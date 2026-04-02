import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/attendance_service.dart';
import '../services/attendance_notification_service.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/time_slot_service.dart';
import '../services/app_log_service.dart';
import '../models/attendance_log.dart';

enum SSOStatus {
  disconnected(Icons.cancel, 'Déconnecté', Colors.grey),
  connecting(Icons.sync, 'Connexion...', Colors.orange),
  connected(Icons.check_circle, 'Connecté', Colors.green),
  error(Icons.error, 'Erreur de connexion', Colors.red);

  const SSOStatus(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;
}

class AppState extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  // LogService is kept internally to support hasSignedInCurrentSlot().
  final LogService _logService = LogService();

  AttendanceService? _attendanceService;
  SSOStatus _ssoStatus = SSOStatus.disconnected;
  bool _isSigningAttendance = false;
  List<AttendanceLog> _logs = [];
  bool _hasAcceptedWarning = false;
  bool _isInitialized = false;
  Set<String> _moodleSignedKeys = {};
  bool _moodleDataLoaded = false;
  static const _moodleCacheKey = 'moodle_signed_keys';

  SSOStatus get ssoStatus => _ssoStatus;
  bool get isSigningAttendance => _isSigningAttendance;
  bool get hasCredentials => _attendanceService != null;
  bool get hasAcceptedWarning => _hasAcceptedWarning;
  bool get isInitialized => _isInitialized;
  bool get moodleDataLoaded => _moodleDataLoaded;
  Set<String> get moodleSignedKeys => _moodleSignedKeys;

  Future<bool> hasStoredCredentials() async {
    return await _storageService.hasCredentials();
  }

  Future<void> initialize() async {
    await AppLogService.instance.load();
    await _loadAttendanceLogs();
    await _loadMoodleCache();
    _hasAcceptedWarning = await _storageService.hasAcceptedWarning();
    // Populate SharedPreferences credential cache for background isolates
    await _storageService.ensureBackgroundCache();
    _isInitialized = true;
    await AppLogService.info('App', 'Application initialisée');
    if (_hasAcceptedWarning) {
      await _tryAutoConnect();
    }
    notifyListeners();
  }

  Future<void> acceptWarning() async {
    await _storageService.setWarningAccepted();
    _hasAcceptedWarning = true;
    await _tryAutoConnect();
    notifyListeners();
  }

  Future<void> _tryAutoConnect() async {
    if (await _storageService.hasCredentials()) {
      await connectSSO();
    }
  }

  Future<bool> saveCredentials(String studentId, String password) async {
    try {
      String finalPassword = password;
      if (password.isEmpty) {
        final existingPassword = await _storageService.getPassword();
        if (existingPassword == null) {
          return false;
        }
        finalPassword = existingPassword;
      }

      await _storageService.saveCredentials(studentId, finalPassword);
      _attendanceService = AttendanceService(
        studentId,
        finalPassword,
        onError: recordError,
      );
      await AppLogService.info(
        'Settings',
        'Identifiants enregistrés pour $studentId',
      );
      return await connectSSO();
    } catch (e, stackTrace) {
      await recordError('AppState.saveCredentials', e, stackTrace);
      return false;
    }
  }

  Future<bool> connectSSO() async {
    _ssoStatus = SSOStatus.connecting;
    notifyListeners();
    await AppLogService.info('SSO', 'Tentative de connexion SSO...');

    try {
      if (_attendanceService == null) {
        final studentId = await _storageService.getStudentId();
        final password = await _storageService.getPassword();
        if (studentId == null ||
            password == null ||
            studentId.isEmpty ||
            password.isEmpty) {
          _ssoStatus = SSOStatus.disconnected;
          await AppLogService.warning('SSO', 'Identifiants manquants');
          notifyListeners();
          return false;
        }
        _attendanceService = AttendanceService(
          studentId,
          password,
          onError: recordError,
        );
      }

      final loginResult = await _attendanceService!.tryLogin();
      _ssoStatus = loginResult == LoginResult.success
          ? SSOStatus.connected
          : SSOStatus.error;
      if (loginResult == LoginResult.success) {
        await AppLogService.success('SSO', 'Connexion SSO réussie');
        fetchMoodleAttendance(); // fire-and-forget
      } else {
        await AppLogService.error(
          'SSO',
          'Échec de connexion SSO : ${loginResult.name}',
        );
      }
      notifyListeners();
      return loginResult == LoginResult.success;
    } catch (e, stackTrace) {
      _ssoStatus = SSOStatus.error;
      await recordError('AppState.connectSSO', e, stackTrace);
      notifyListeners();
      return false;
    }
  }

  Future<AttendanceResult> signAttendance() async {
    if (_attendanceService == null) {
      return AttendanceResult.loginError;
    }

    _isSigningAttendance = true;
    notifyListeners();

    await AppLogService.info('Émargement', 'Tentative d\'émargement...');
    try {
      final result = await _attendanceService!.signAttendance();

      // Keep AttendanceLog for hasSignedInCurrentSlot() logic.
      final log = AttendanceLog(
        timestamp: DateTime.now(),
        result: result.name,
        message: result.message,
      );
      await _logService.addLog(log);
      await _loadAttendanceLogs();

      if (result == AttendanceResult.success ||
          result == AttendanceResult.alreadySignedIn) {
        await AppLogService.success('Émargement', result.message);
        await AttendanceNotificationService.cancelCurrentSlotNotifications();
        fetchMoodleAttendance(); // fire-and-forget
      } else {
        await AppLogService.error('Émargement', result.message);
      }

      return result;
    } catch (e, stackTrace) {
      final log = AttendanceLog(
        timestamp: DateTime.now(),
        result: 'error',
        message: 'Erreur: $e',
      );
      await _logService.addLog(log);
      await recordError('AppState.signAttendance', e, stackTrace);
      await _loadAttendanceLogs();
      return AttendanceResult.unknownError;
    } finally {
      _isSigningAttendance = false;
      notifyListeners();
    }
  }

  Future<void> _loadAttendanceLogs() async {
    _logs = await _logService.getLogs();
    notifyListeners();
  }

  Future<void> recordError(
    String contextName,
    Object error,
    StackTrace? stackTrace,
  ) async {
    await AppLogService.error(
      contextName,
      error.toString(),
      details: stackTrace?.toString(),
    );
  }

  Future<void> clearLogs() async {
    await _logService.clearLogs();
    await AppLogService.instance.clear();
    await _loadAttendanceLogs();
  }

  bool hasSignedInCurrentSlot() {
    final slotInfo = TimeSlotService.getCurrentSlotInfo();
    if (!slotInfo.isInSlot || slotInfo.currentSlot == null) {
      return false;
    }

    final slot = slotInfo.currentSlot!;
    final slotStart = slot.getStartTime(DateTime.now());
    final slotEnd = slot.getEndTime(DateTime.now());

    return _logs.any((log) {
      final isInTimeRange =
          log.timestamp.isAfter(slotStart) && log.timestamp.isBefore(slotEnd);
      final isSuccess =
          log.result == 'success' || log.result == 'alreadySignedIn';
      return isInTimeRange && isSuccess;
    });
  }

  bool isSlotSignedLocally(DateTime day, TimeSlot slot) {
    final slotStart = slot.getStartTime(day);
    final slotEnd = slot.getEndTime(day);
    return _logs.any((log) {
      final inRange =
          !log.timestamp.isBefore(slotStart) && !log.timestamp.isAfter(slotEnd);
      return inRange &&
          (log.result == 'success' || log.result == 'alreadySignedIn');
    });
  }

  bool isSlotSignedOnMoodle(DateTime date, TimeSlot slot) {
    final key =
        '${date.year}-${date.month}-${date.day}_${slot.startHour}:${slot.startMinute}';
    return _moodleSignedKeys.contains(key);
  }

  Future<void> fetchMoodleAttendance() async {
    if (_attendanceService == null) return;
    await AppLogService.info(
      'Moodle',
      'Récupération des émargements Moodle...',
    );
    try {
      final sessions = await _attendanceService!.fetchSignedSessions();
      _moodleSignedKeys = sessions.map((s) => s.key).toSet();
      final slotInfo = TimeSlotService.getCurrentSlotInfo();
      if (slotInfo.isInSlot && slotInfo.currentSlot != null) {
        final currentSlotKey = slotInfo.currentSlot!.keyForDate(DateTime.now());
        if (_moodleSignedKeys.contains(currentSlotKey)) {
          await AttendanceNotificationService.cancelNotificationsForSlot(
            currentSlotKey,
          );
        }
      }
      _moodleDataLoaded = true;
      await _saveMoodleCache();
      await AppLogService.success(
        'Moodle',
        '${sessions.length} émargement(s) récupéré(s)',
      );
      notifyListeners();
    } catch (e, stackTrace) {
      await recordError('AppState.fetchMoodleAttendance', e, stackTrace);
    }
  }

  Future<void> _loadMoodleCache() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_moodleCacheKey);
    if (list != null) {
      _moodleSignedKeys = list.toSet();
      _moodleDataLoaded = true;
    }
  }

  Future<void> _saveMoodleCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_moodleCacheKey, _moodleSignedKeys.toList());
  }

  Future<String?> getStudentId() async {
    return await _storageService.getStudentId();
  }

  Future<void> clearCredentials() async {
    await _storageService.clearCredentials();
    _attendanceService = null;
    _ssoStatus = SSOStatus.disconnected;
    await AppLogService.info('Settings', 'Identifiants supprimés');
    notifyListeners();
  }

  Future<void> logout() async {
    await clearCredentials();
  }
}
