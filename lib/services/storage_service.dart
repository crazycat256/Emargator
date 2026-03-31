import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();
  static const _keyStudentId = 'student_id';
  static const _keyPassword = 'password';
  static const _keyWarningAccepted = 'warning_accepted';

  // FlutterSecureStorage (Android KeyStore) can fail in background isolates.
  // Credentials are also cached in SharedPreferences so background alarms can
  // read them reliably.
  static const _bgCacheKey = 'bg_credentials_cache';

  Future<String?> _readOrReset(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (error) {
      debugPrint(
        'StorageService: secure storage read failed for "$key": ${error.message}',
      );
      // Do NOT wipe credentials — the error is likely transient (no Activity).
      return null;
    }
  }

  Future<void> saveCredentials(String studentId, String password) async {
    await _storage.write(key: _keyStudentId, value: studentId);
    await _storage.write(key: _keyPassword, value: password);
    await _updateBackgroundCache(studentId, password);
  }

  Future<String?> getStudentId() async {
    return await _readOrReset(_keyStudentId);
  }

  Future<String?> getPassword() async {
    return await _readOrReset(_keyPassword);
  }

  Future<bool> hasCredentials() async {
    final studentId = await getStudentId();
    final password = await getPassword();
    return studentId != null && password != null;
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyStudentId);
    await _storage.delete(key: _keyPassword);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bgCacheKey);
  }

  Future<bool> hasAcceptedWarning() async {
    final value = await _readOrReset(_keyWarningAccepted);
    return value == 'true';
  }

  Future<void> setWarningAccepted() async {
    await _storage.write(key: _keyWarningAccepted, value: 'true');
  }

  static Future<void> _updateBackgroundCache(
    String studentId,
    String password,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = base64Encode(
      utf8.encode(jsonEncode({'s': studentId, 'p': password})),
    );
    await prefs.setString(_bgCacheKey, payload);
  }

  /// Warm up the background credential cache from SecureStorage.
  /// Call once on foreground startup.
  Future<void> ensureBackgroundCache() async {
    final studentId = await getStudentId();
    final password = await getPassword();
    if (studentId != null &&
        studentId.isNotEmpty &&
        password != null &&
        password.isNotEmpty) {
      await _updateBackgroundCache(studentId, password);
    }
  }

  static Future<({String? studentId, String? password})>
  getBackgroundCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bgCacheKey);
      if (raw == null) return (studentId: null, password: null);
      final decoded =
          jsonDecode(utf8.decode(base64Decode(raw))) as Map<String, dynamic>;
      return (
        studentId: decoded['s'] as String?,
        password: decoded['p'] as String?,
      );
    } catch (e) {
      debugPrint('StorageService: background cache read failed: $e');
      return (studentId: null, password: null);
    }
  }
}
