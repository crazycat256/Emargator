import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'attendance_service.dart';
import 'storage_service.dart';

class BackgroundSyncService {
  static const _moodleCacheKey = 'moodle_signed_keys';
  static const _androidNotificationIcon = '@drawable/ic_launcher_monochrome';

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

  /// AndroidAlarmManager callback: checks Moodle, then shows notification if
  /// the slot has not been signed yet, and the slot has not ended.
  @pragma('vm:entry-point')
  static Future<void> checkAndNotify(
    int alarmId,
    Map<String, dynamic> params,
  ) async {
    debugPrint('BackgroundSync: checkAndNotify alarm=$alarmId');

    try {
      final String slotKey = params['slotKey'] as String;
      final int notifId = params['notifId'] as int;
      final String title = params['title'] as String;
      final String body = params['body'] as String;
      final bool playSound = params['playSound'] as bool;
      final String payload = params['payload'] as String;
      final DateTime slotEnd = DateTime.parse(params['slotEndIso'] as String);

      // If slot has ended, don't notify
      if (DateTime.now().isAfter(slotEnd)) {
        debugPrint(
          'BackgroundSync: Slot "$slotKey" is over, skipping notification',
        );
        return;
      }

      // Check Moodle — on error, we still notify (fail-safe)
      final alreadySigned = await checkSlotStatus(slotKey);
      if (alreadySigned) {
        debugPrint(
          'BackgroundSync: Slot "$slotKey" already signed, skipping notification',
        );
        return;
      }

      // Show notification immediately
      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit =
          AndroidInitializationSettings(_androidNotificationIcon);
      await plugin.initialize(
        const InitializationSettings(android: androidInit),
      );

      final androidDetails = AndroidNotificationDetails(
        playSound ? 'emargator_sound' : 'emargator_silent',
        playSound
            ? 'Rappels d\'émargement urgents'
            : 'Rappels d\'émargement',
        channelDescription: playSound
            ? 'Notifications avec son et vibration'
            : 'Notifications vibration seule (sans son)',
        icon: _androidNotificationIcon,
        importance: Importance.max,
        priority: Priority.max,
        enableVibration: true,
        playSound: playSound,
        channelShowBadge: true,
        fullScreenIntent: false,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'sign_attendance',
            'Émarger',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'ignore_slot',
            'Ignorer ce créneau',
            cancelNotification: true,
          ),
        ],
      );

      await plugin.show(
        notifId,
        title,
        body,
        NotificationDetails(android: androidDetails),
        payload: payload,
      );

      debugPrint(
        'BackgroundSync: Showed notification #$notifId for "$slotKey"',
      );
    } catch (e) {
      debugPrint('BackgroundSync: checkAndNotify error: $e');
    }
  }
}
