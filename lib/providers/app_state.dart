import 'package:flutter/material.dart';
import '../services/attendance_service.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/time_slot_service.dart';
import '../models/attendance_log.dart';
import '../services/error_service.dart';
import '../models/error_report.dart';

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
  final LogService _logService = LogService();
  final ErrorService _errorService = ErrorService();

  AttendanceService? _attendanceService;
  SSOStatus _ssoStatus = SSOStatus.disconnected;
  bool _isSigningAttendance = false;
  List<AttendanceLog> _logs = [];
  List<ErrorReport> _errors = [];
  bool _hasAcceptedWarning = false;
  bool _isInitialized = false;

  SSOStatus get ssoStatus => _ssoStatus;
  bool get isSigningAttendance => _isSigningAttendance;
  List<AttendanceLog> get logs => _logs;
  List<ErrorReport> get errors => _errors;
  bool get hasCredentials => _attendanceService != null;
  bool get hasAcceptedWarning => _hasAcceptedWarning;
  bool get isInitialized => _isInitialized;

  Future<bool> hasStoredCredentials() async {
    return await _storageService.hasCredentials();
  }

  Future<void> initialize() async {
    await loadLogs();
    await loadErrors();
    _hasAcceptedWarning = await _storageService.hasAcceptedWarning();
    _isInitialized = true;
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
      _attendanceService = AttendanceService(studentId, finalPassword, onError: recordError);
      return await connectSSO();
    } catch (e, stackTrace) {
      await recordError('AppState.saveCredentials', e, stackTrace);
      return false;
    }
  }

  Future<bool> connectSSO() async {
    _ssoStatus = SSOStatus.connecting;
    notifyListeners();

    try {
      if (_attendanceService == null) {
        final studentId = await _storageService.getStudentId();
        final password = await _storageService.getPassword();
        if (studentId == null ||
            password == null ||
            studentId.isEmpty ||
            password.isEmpty) {
          _ssoStatus = SSOStatus.disconnected;
          notifyListeners();
          return false;
        }
        _attendanceService = AttendanceService(studentId, password, onError: recordError);
      }

      final loginResult = await _attendanceService!.tryLogin();
      _ssoStatus = loginResult == LoginResult.success
          ? SSOStatus.connected
          : SSOStatus.error;
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

    try {
      final result = await _attendanceService!.signAttendance();

      final log = AttendanceLog(
        timestamp: DateTime.now(),
        result: result.name,
        message: result.message,
      );
      await _logService.addLog(log);
      await loadLogs();

      return result;
    } catch (e, stackTrace) {
      final log = AttendanceLog(
        timestamp: DateTime.now(),
        result: 'error',
        message: 'Erreur: $e',
      );
      await _logService.addLog(log);
      await recordError('AppState.signAttendance', e, stackTrace);
      await loadLogs();
      return AttendanceResult.unknownError;
    } finally {
      _isSigningAttendance = false;
      notifyListeners();
    }
  }

  Future<void> loadLogs() async {
    _logs = await _logService.getLogs();
    notifyListeners();
  }

  Future<void> loadErrors() async {
    _errors = await _errorService.getErrors();
    notifyListeners();
  }

  Future<void> recordError(String contextName, Object error, StackTrace? stackTrace) async {
    await _errorService.logError(contextName, error, stackTrace);
    await loadErrors();
  }

  Future<void> clearErrors() async {
    await _errorService.clearErrors();
    await loadErrors();
  }

  Future<void> clearLogs() async {
    await _logService.clearLogs();
    await loadLogs();
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

  Future<String?> getStudentId() async {
    return await _storageService.getStudentId();
  }

  Future<void> clearCredentials() async {
    await _storageService.clearCredentials();
    _attendanceService = null;
    _ssoStatus = SSOStatus.disconnected;
    notifyListeners();
  }

  Future<void> logout() async {
    await clearCredentials();
  }
}
