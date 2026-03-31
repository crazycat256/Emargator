import 'dart:async';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'attendance_service.dart';
import 'storage_service.dart';

class BackgroundSyncService {
  static const _moodleCacheKey = 'moodle_signed_keys';
  static const _httpCheckTimeout = Duration(seconds: 20);

  static Future<bool> _isSignedInLocalCache(String slotKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList(_moodleCacheKey);
      if (cached != null && cached.contains(slotKey)) {
        debugPrint('BackgroundSync: slot "$slotKey" found in local cache');
        return true;
      }
    } catch (e) {
      debugPrint('BackgroundSync: local cache read error: $e');
    }
    return false;
  }

  /// Returns true if [slotKey] is already signed on Moodle.
  /// Checks local cache first, then falls back to a live HTTP check.
  /// Returns false on any error (fail-safe: prefer showing the notification).
  static Future<bool> checkSlotStatus(String slotKey) async {
    if (await _isSignedInLocalCache(slotKey)) return true;

    try {
      // FlutterSecureStorage can fail in background isolates; fall back to
      // the SharedPreferences credential cache written on each foreground login.
      final storage = StorageService();
      String? studentId = await storage.getStudentId();
      String? password = await storage.getPassword();

      if (studentId == null ||
          studentId.isEmpty ||
          password == null ||
          password.isEmpty) {
        debugPrint(
          'BackgroundSync: SecureStorage empty, trying background cache',
        );
        final cached = await StorageService.getBackgroundCredentials();
        studentId = cached.studentId;
        password = cached.password;
      }

      if (studentId == null ||
          studentId.isEmpty ||
          password == null ||
          password.isEmpty) {
        debugPrint('BackgroundSync: credentials not found');
        return false;
      }

      final service = AttendanceService(studentId, password);
      final loginResult = await service.tryLogin();
      if (loginResult != LoginResult.success) {
        debugPrint('BackgroundSync: login failed ($loginResult)');
        return false;
      }

      final sessions = await service.fetchSignedSessions();
      final signedKeys = sessions.map((s) => s.key).toSet();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_moodleCacheKey, signedKeys.toList());

      return signedKeys.contains(slotKey);
    } catch (e) {
      debugPrint('BackgroundSync: checkSlotStatus error: $e');
      return false;
    }
  }

  /// AndroidAlarmManager callback — runs ~30 s before each scheduled notification.
  ///
  /// Must be `void` (not `Future<void>`): android_alarm_manager_plus does not
  /// await async callbacks, so we use a [ReceivePort] to keep the isolate alive
  /// until the async work finishes before the WakeLock is released.
  @pragma('vm:entry-point')
  static void preCheckAndCancel(int alarmId, Map<String, dynamic> params) {
    WidgetsFlutterBinding.ensureInitialized();

    final keepAlive = ReceivePort();
    _doPreCheck(alarmId, params).whenComplete(keepAlive.close);
  }

  static Future<void> _doPreCheck(
    int alarmId,
    Map<String, dynamic> params,
  ) async {
    debugPrint('BackgroundSync: preCheckAndCancel alarm=$alarmId');
    try {
      final String slotKey = params['slotKey'] as String;
      final List<int> notifIds = (params['notifIds'] as List<dynamic>)
          .cast<int>();

      if (slotKey.isEmpty || notifIds.isEmpty) {
        debugPrint('BackgroundSync: invalid params');
        return;
      }

      final alreadySigned = await checkSlotStatus(slotKey).timeout(
        _httpCheckTimeout,
        onTimeout: () {
          debugPrint('BackgroundSync: check timed out');
          return false;
        },
      );

      if (!alreadySigned) {
        debugPrint('BackgroundSync: "$slotKey" not signed, notifications stay');
        return;
      }

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings(
            '@drawable/ic_launcher_monochrome',
          ),
        ),
      );
      for (final notifId in notifIds) {
        await plugin.cancel(notifId);
      }
      debugPrint(
        'BackgroundSync: "$slotKey" already signed — cancelled $notifIds',
      );
    } catch (e) {
      debugPrint('BackgroundSync: _doPreCheck error: $e');
    }
  }
}
