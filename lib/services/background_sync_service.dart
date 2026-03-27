import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'attendance_service.dart';
import 'storage_service.dart';

class BackgroundSyncService {
  static const _moodleCacheKey = 'moodle_signed_keys';

  /// Check Moodle to see if a slot is already signed.
  /// Updates the shared preferences cache and returns true if signed.
  /// Returns false on any error (fail-safe: prefer showing notification).
  static Future<bool> checkSlotStatus(String slotKey) async {
    try {
      final storage = StorageService();
      final studentId = await storage.getStudentId();
      final password = await storage.getPassword();

      if (studentId == null ||
          password == null ||
          studentId.isEmpty ||
          password.isEmpty) {
        debugPrint('BackgroundSync: Credentials not found');
        return false;
      }

      final service = AttendanceService(studentId, password);
      final loginResult = await service.tryLogin();
      if (loginResult != LoginResult.success) {
        debugPrint('BackgroundSync: Login failed ($loginResult)');
        return false;
      }

      debugPrint('BackgroundSync: Login success. Fetching signed sessions...');
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

  /// AndroidAlarmManager callback: runs ~30 s before a scheduled notification.
  /// Checks Moodle — if the slot is already signed, cancels the scheduled
  /// notifications so they never appear.  On error, does nothing (the native
  /// notification fires normally as a fail-safe).
  @pragma('vm:entry-point')
  static Future<void> preCheckAndCancel(
    int alarmId,
    Map<String, dynamic> params,
  ) async {
    debugPrint('BackgroundSync: preCheckAndCancel alarm=$alarmId');

    try {
      final String slotKey = params['slotKey'] as String;
      final List<int> notifIds =
          (params['notifIds'] as List<dynamic>).cast<int>();

      if (slotKey.isEmpty || notifIds.isEmpty) {
        debugPrint('BackgroundSync: Invalid params slotKey=$slotKey');
        return;
      }

      final alreadySigned = await checkSlotStatus(slotKey);
      if (!alreadySigned) {
        debugPrint(
          'BackgroundSync: Slot "$slotKey" NOT signed. Notifications stay.',
        );
        return;
      }

      // Slot is signed — cancel scheduled notifications.
      // Must initialize the plugin in this background isolate before calling
      // cancel(), otherwise the platform channel is not available.
      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings(
        '@drawable/ic_launcher_monochrome',
      );
      await plugin.initialize(
        const InitializationSettings(android: androidInit),
      );

      for (final notifId in notifIds) {
        await plugin.cancel(notifId);
      }
      debugPrint(
        'BackgroundSync: Slot "$slotKey" already signed — cancelled $notifIds',
      );
    } catch (e) {
      debugPrint('BackgroundSync: preCheckAndCancel error: $e');
    }
  }
}
