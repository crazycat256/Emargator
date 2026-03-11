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
  final bool showRemaining;

  /// If true, use maximum visibility (fullScreenIntent, ticker, etc.)
  final bool urgent;

  const _SlotNotif(
    this.offsetFromStart,
    this.label, {
    this.playSound = false,
    this.showRemaining = false,
    this.urgent = false,
  });
}

/// Callback types for notification actions.
typedef OnSignAttendance = Future<void> Function();
typedef OnIgnoreSlot = Future<void> Function(String slotKey);

/// Schedules attendance reminder notifications for time slots.
class AttendanceNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// IDs of notifications we've scheduled (so we can cancel them individually).
  static final List<int> _scheduledIds = [];

  /// Callbacks set from outside (main.dart) to handle notification actions.
  static OnSignAttendance? onSignAttendance;
  static OnIgnoreSlot? onIgnoreSlot;

  /// The 5 notification timings per slot (offsets from start).
  /// Slots are 90 min, so 75 min = 15 min before end, etc.
  static const _notifTimings = [
    // 1 min after start
    _SlotNotif(Duration(minutes: 1), 'Créneau commencé'),
    // 5 min after start
    _SlotNotif(Duration(minutes: 5), 'Créneau en cours'),
    // 75 min after start (15 min before end)
    _SlotNotif(Duration(minutes: 75), '15 min restantes', showRemaining: true),
    // 85 min after start (5 min before end)
    _SlotNotif(
      Duration(minutes: 85),
      '5 min restantes',
      playSound: true,
      showRemaining: true,
      urgent: true,
    ),
    // 88 min after start (2 min before end)
    _SlotNotif(
      Duration(minutes: 88),
      '2 min restantes',
      playSound: true,
      showRemaining: true,
      urgent: true,
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

      // Request notification permission (Android 13+)
      await androidPlugin.requestNotificationsPermission();

      // Request exact alarm permission
      await androidPlugin.requestExactAlarmsPermission();
    }

    _initialized = true;
    debugPrint('AttendanceNotif: initialized');
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
    if (!_initialized) {
      debugPrint('AttendanceNotif: not initialized, skipping');
      return;
    }

    // Cancel previous notifications — try cancelAll first, fall back to individual cancel
    await _cancelPrevious();

    // Clear tracked IDs
    _scheduledIds.clear();

    int id = 0;
    final now = DateTime.now();
    debugPrint(
      'AttendanceNotif: scheduling for ${slotsToAttend.length} slots '
      '(${signedSlotKeys.length} signed)',
    );

    for (final entry in slotsToAttend) {
      final date = entry.date;
      final slot = entry.slot;

      // Skip already signed slots
      if (signedSlotKeys.contains(slot.keyForDate(date))) continue;

      final slotStart = slot.getStartTime(date);
      final slotEnd = slot.getEndTime(date);

      for (final timing in _notifTimings) {
        // All timings are offsets from start
        final notifTime = slotStart.add(timing.offsetFromStart);

        // Don't schedule if: in the past, or after slot end, or before slot start
        if (!notifTime.isAfter(now)) continue;
        if (notifTime.isAfter(slotEnd) || notifTime.isBefore(slotStart)) {
          continue;
        }

        String body;
        if (timing.showRemaining) {
          final remaining = slotEnd.difference(notifTime);
          final remainStr = _formatRemaining(remaining);
          body = '${slot.getTimeRange()} — $remainStr';
        } else {
          body = '${slot.getTimeRange()} — ${timing.label}';
        }

        try {
          await _scheduleNotification(
            id: id,
            title: timing.urgent
                ? '🚨 Émargement URGENT'
                : 'Émargement requis',
            body: body,
            scheduledTime: notifTime,
            playSound: timing.playSound,
            urgent: timing.urgent,
            payload: slot.keyForDate(date),
          );
          _scheduledIds.add(id);
          id++;
        } catch (e) {
          debugPrint('AttendanceNotif: failed to schedule id=$id: $e');
          id++;
        }
      }
    }
    debugPrint(
      'AttendanceNotif: scheduled ${_scheduledIds.length} notifications',
    );
  }

  /// Cancel all previously scheduled notifications.
  static Future<void> _cancelPrevious() async {
    try {
      await _plugin.cancelAll();
      debugPrint('AttendanceNotif: cancelAll succeeded');
    } catch (e) {
      debugPrint(
        'AttendanceNotif: cancelAll failed, cancelling individually: $e',
      );
      for (final id in _scheduledIds) {
        try {
          await _plugin.cancel(id);
        } catch (_) {}
      }
    }
    _scheduledIds.clear();
  }

  /// Cancel all scheduled notifications (public).
  static Future<void> cancelAll() async {
    if (!_initialized) return;
    await _cancelPrevious();
  }

  static String _formatRemaining(Duration d) {
    if (d.inMinutes <= 0) return '';
    if (d.inMinutes < 2) return '${d.inSeconds}s';
    return '${d.inMinutes} min';
  }

  /// Schedule a notification via zonedSchedule (AlarmManager on Android).
  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required bool playSound,
    required String payload,
    bool urgent = false,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      playSound ? 'emargator_sound' : 'emargator_silent',
      playSound ? 'Rappels d\'émargement urgents' : 'Rappels d\'émargement',
      channelDescription: playSound
          ? 'Notifications avec son et vibration'
          : 'Notifications vibration seule (sans son)',
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: true,
      playSound: playSound,
      channelShowBadge: true,
      fullScreenIntent: urgent,
      ticker: urgent ? title : null,
      category: urgent
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
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
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    debugPrint(
      'AttendanceNotif: scheduled #$id at $scheduledTime (tz=$tzTime)',
    );
  }
}
