import 'package:flutter/foundation.dart';
import '../services/attendance_service.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../models/attendance_log.dart';

enum SSOStatus { disconnected, connecting, connected, error }

class AppState extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final LogService _logService = LogService();

  AttendanceService? _attendanceService;
  SSOStatus _ssoStatus = SSOStatus.disconnected;
  bool _isSigningAttendance = false;
  List<AttendanceLog> _logs = [];

  SSOStatus get ssoStatus => _ssoStatus;
  bool get isSigningAttendance => _isSigningAttendance;
  List<AttendanceLog> get logs => _logs;

  Future<void> initialize() async {
    await loadLogs();
    await _tryAutoConnect();
  }

  Future<void> _tryAutoConnect() async {
    if (await _storageService.hasCredentials()) {
      await connectSSO();
    }
  }

  Future<bool> saveCredentials(String studentId, String password) async {
    await _storageService.saveCredentials(studentId, password);
    _attendanceService = AttendanceService(studentId, password);
    return await connectSSO();
  }

  Future<bool> connectSSO() async {
    _ssoStatus = SSOStatus.connecting;
    notifyListeners();

    try {
      if (_attendanceService == null) {
        final studentId = await _storageService.getStudentId();
        final password = await _storageService.getPassword();
        if (studentId == null || password == null) {
          _ssoStatus = SSOStatus.error;
          notifyListeners();
          return false;
        }
        _attendanceService = AttendanceService(studentId, password);
      }

      final success = await _attendanceService!.tryLogin();
      _ssoStatus = success ? SSOStatus.connected : SSOStatus.error;
      notifyListeners();
      return success;
    } catch (e) {
      _ssoStatus = SSOStatus.error;
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
        message: _getResultMessage(result),
      );
      await _logService.addLog(log);
      await loadLogs();

      return result;
    } catch (e) {
      final log = AttendanceLog(
        timestamp: DateTime.now(),
        result: 'error',
        message: 'Erreur: $e',
      );
      await _logService.addLog(log);
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

  Future<void> clearLogs() async {
    await _logService.clearLogs();
    await loadLogs();
  }

  Future<void> logout() async {
    await _storageService.clearCredentials();
    _attendanceService = null;
    _ssoStatus = SSOStatus.disconnected;
    notifyListeners();
  }

  String _getResultMessage(AttendanceResult result) {
    switch (result) {
      case AttendanceResult.success:
        return 'Émargement réussi';
      case AttendanceResult.alreadySignedIn:
        return 'Déjà émargé';
      case AttendanceResult.attendanceIdError:
        return 'Erreur: ID d\'émargement introuvable';
      case AttendanceResult.loginError:
        return 'Erreur de connexion';
      case AttendanceResult.unknownError:
        return 'Erreur inconnue';
    }
  }
}
