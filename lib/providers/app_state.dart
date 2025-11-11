import 'package:flutter/material.dart';
import '../services/attendance_service.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';
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
  final LogService _logService = LogService();

  AttendanceService? _attendanceService;
  SSOStatus _ssoStatus = SSOStatus.disconnected;
  bool _isSigningAttendance = false;
  List<AttendanceLog> _logs = [];
  bool _hasAcceptedWarning = false;

  SSOStatus get ssoStatus => _ssoStatus;
  bool get isSigningAttendance => _isSigningAttendance;
  List<AttendanceLog> get logs => _logs;
  bool get hasCredentials => _attendanceService != null;
  bool get hasAcceptedWarning => _hasAcceptedWarning;

  Future<void> initialize() async {
    await loadLogs();
    _hasAcceptedWarning = await _storageService.hasAcceptedWarning();
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
    String finalPassword = password;
    if (password.isEmpty) {
      final existingPassword = await _storageService.getPassword();
      if (existingPassword == null) {
        return false;
      }
      finalPassword = existingPassword;
    }

    await _storageService.saveCredentials(studentId, finalPassword);
    _attendanceService = AttendanceService(studentId, finalPassword);
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

      final loginResult = await _attendanceService!.tryLogin();
      _ssoStatus = loginResult == LoginResult.success
          ? SSOStatus.connected
          : SSOStatus.error;
      notifyListeners();
      return loginResult == LoginResult.success;
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
        message: result.message,
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
