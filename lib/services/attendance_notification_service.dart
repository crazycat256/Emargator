import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../services/time_slot_service.dart';

/// Action identifiers for notification buttons.
const _actionSign = 'sign_attendance';
const _actionIgnore = 'ignore_slot';

/// Notification timing offsets relative to a slot.
class _SlotNotif {
  final Duration offsetFromStart;
  final String label;
  final bool playSound;

  const _SlotNotif(this.offsetFromStart, this.label, {this.playSound = false});
}

/// Callback types for notification actions.
typedef OnSignAttendance = Future<void> Function();
typedef OnIgnoreSlot = Future<void> Function(String slotKey);

/// Schedules attendance reminder notifications for time slots.
class AttendanceNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Callbacks set from outside (main.dart) to handle notification actions.
  static OnSignAttendance? onSignAttendance;
  static OnIgnoreSlot? onIgnoreSlot;

  /// The 4 notification timings per slot.
  static const _notifTimings = [
    // 5 min after start
    _SlotNotif(Duration(minutes: 5), 'Créneau commencé'),
    // 30 min before end  (offset computed from start based on slot duration)
    _SlotNotif(Duration(minutes: -30), '30 min restantes'),
    // 5 min before end
    _SlotNotif(Duration(minutes: -5), '5 min restantes', playSound: true),
    // 1min30 before end
    _SlotNotif(
      Duration(minutes: -1, seconds: -30),
      '1 min 30 restantes',
      playSound: true,
    ),
  ];

  static Future<void> init() async {
    if (_initialized) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create notification channels on Android
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'emargator_silent',
          'Rappels d\'émargement',
          description: 'Notifications vibration seule (sans son)',
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'emargator_sound',
          'Rappels d\'émargement urgents',
          description: 'Notifications avec son et vibration',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    _initialized = true;
  }

  /// Handle notification tap / action button tap.
  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    switch (response.actionId) {
      case _actionSign:
        onSignAttendance?.call();
        break;
      case _actionIgnore:
        if (payload.isNotEmpty) {
          onIgnoreSlot?.call(payload);
        }
        break;
      default:
        // Tapped the notification body itself — treat as sign
        onSignAttendance?.call();
        break;
    }
  }

  /// Request notification permissions (Android 13+, iOS).
  static Future<bool> requestPermission() async {
    if (!_initialized) return false;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return false;
  }

  /// Schedule reminder notifications for time slots that need attendance.
  ///
  /// [slotsToAttend] is a list of (date, slot) pairs the student must attend.
  /// [signedSlotKeys] is the set of slot keys already signed (local + Moodle).
  static Future<void> scheduleForSlots({
    required List<({DateTime date, TimeSlot slot})> slotsToAttend,
    required Set<String> signedSlotKeys,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('cancelAll failed (continuing): $e');
    }

    int id = 0;
    final now = DateTime.now();

    for (final entry in slotsToAttend) {
      final date = entry.date;
      final slot = entry.slot;

      // Skip already signed slots
      if (signedSlotKeys.contains(slot.keyForDate(date))) continue;

      final slotStart = slot.getStartTime(date);
      final slotEnd = slot.getEndTime(date);

      for (final timing in _notifTimings) {
        DateTime notifTime;
        if (timing.offsetFromStart.isNegative) {
          // Negative = offset from end
          notifTime = slotEnd.add(timing.offsetFromStart);
        } else {
          notifTime = slotStart.add(timing.offsetFromStart);
        }

        // Don't schedule if: in the past, or after slot end, or before slot start
        if (!notifTime.isAfter(now)) continue;
        if (notifTime.isAfter(slotEnd) || notifTime.isBefore(slotStart)) {
          continue;
        }

        final remaining = slotEnd.difference(notifTime);
        final remainStr = _formatRemaining(remaining);

        await _scheduleNotification(
          id: id++,
          title: '⚠️ Émargement requis',
          body:
              '${slot.getTimeRange()} — ${timing.label}${remainStr.isNotEmpty ? ' ($remainStr)' : ''}',
          scheduledTime: notifTime,
          playSound: timing.playSound,
          payload: slot.keyForDate(date),
        );
      }
    }
  }

  /// Cancel all scheduled notifications.
  static Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  static String _formatRemaining(Duration d) {
    if (d.inMinutes <= 0) return '';
    if (d.inMinutes < 2) return '${d.inSeconds}s';
    return '${d.inMinutes} min';
  }

  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required bool playSound,
    required String payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      playSound ? 'emargator_sound' : 'emargator_silent',
      playSound ? 'Rappels d\'émargement urgents' : 'Rappels d\'émargement',
      channelDescription: playSound
          ? 'Notifications avec son et vibration'
          : 'Notifications vibration seule (sans son)',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: playSound,
      channelShowBadge: true,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          _actionSign,
          'Émarger',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          _actionIgnore,
          'Ignorer ce créneau',
          cancelNotification: true,
        ),
      ],
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
      ),
    );

    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      details,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );
  }
}
