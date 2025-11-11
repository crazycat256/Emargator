import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();
  static const _keyStudentId = 'student_id';
  static const _keyPassword = 'password';
  static const _keyWarningAccepted = 'warning_accepted';

  Future<void> saveCredentials(String studentId, String password) async {
    await _storage.write(key: _keyStudentId, value: studentId);
    await _storage.write(key: _keyPassword, value: password);
  }

  Future<String?> getStudentId() async {
    return await _storage.read(key: _keyStudentId);
  }

  Future<String?> getPassword() async {
    return await _storage.read(key: _keyPassword);
  }

  Future<bool> hasCredentials() async {
    final studentId = await getStudentId();
    final password = await getPassword();
    return studentId != null && password != null;
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyStudentId);
    await _storage.delete(key: _keyPassword);
  }

  Future<bool> hasAcceptedWarning() async {
    final value = await _storage.read(key: _keyWarningAccepted);
    return value == 'true';
  }

  Future<void> setWarningAccepted() async {
    await _storage.write(key: _keyWarningAccepted, value: 'true');
  }
}
