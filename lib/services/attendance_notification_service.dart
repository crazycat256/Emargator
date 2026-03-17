import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import '../services/time_slot_service.dart';
import '../services/background_sync_service.dart';
import 'planning_prefs_service.dart';

/// Action identifiers for notification buttons.
const _actionSign = 'sign_attendance';
const _actionIgnore = 'ignore_slot';

/// Notification timing offsets relative to a slot.
class _SlotNotif {
  final Duration offset;
  final NotificationTimingMode timingMode;

  /// If true, use maximum visibility (fullScreenIntent, ticker, etc.)
  final bool urgent;

  const _SlotNotif(this.offset, this.timingMode, {this.urgent = false});
}

/// Callback types for notification actions.
typedef OnSignAttendance = Future<void> Function();
typedef OnIgnoreSlot = Future<void> Function(String slotKey);

/// Schedules attendance reminder notifications for time slots.
class AttendanceNotificationService {
  static const _slotDurationSeconds = 90 * 60;
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// IDs of notifications we've scheduled (so we can cancel them individually).
  static final List<int> _scheduledIds = [];
  static final Map<int, String> _scheduledSlotByNotifId = {};

  /// Callbacks set from outside (main.dart) to handle notification actions.
  static OnSignAttendance? onSignAttendance;
  static OnIgnoreSlot? onIgnoreSlot;

  static List<_SlotNotif> _buildNotifTimings(
    List<PlanningNotificationRule> rules,
  ) {
    final normalized = rules.where((r) => r.offsetSeconds > 0).toList()
      ..sort((a, b) => a.offsetSeconds.compareTo(b.offsetSeconds));

    final source = normalized.isEmpty
        ? PlanningPrefsService.defaultNotificationRules
        : normalized;

    return source
        .map(
          (r) => _SlotNotif(
            Duration(seconds: r.offsetSeconds),
            r.timingMode,
            urgent: r.urgent,
          ),
        )
        .toList()
      ..sort((a, b) {
        final ea = a.timingMode == NotificationTimingMode.afterStart
            ? a.offset.inSeconds
            : _slotDurationSeconds - a.offset.inSeconds;
        final eb = b.timingMode == NotificationTimingMode.afterStart
            ? b.offset.inSeconds
            : _slotDurationSeconds - b.offset.inSeconds;
        return ea.compareTo(eb);
      });
  }

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
        // Tapped the notification body — just open the app (home screen)
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
    required List<PlanningNotificationRule> notificationRules,
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

    final notifTimings = _buildNotifTimings(notificationRules);

    for (final entry in slotsToAttend) {
      final date = entry.date;
      final slot = entry.slot;
      final slotKey = slot.keyForDate(date);

      // Skip already signed slots
      if (signedSlotKeys.contains(slotKey)) continue;

      final slotStart = slot.getStartTime(date);
      final slotEnd = slot.getEndTime(date);

      final List<int> slotNotifIds = [];
      DateTime? firstNotifTime;

      for (final timing in notifTimings) {
        final notifTime = timing.timingMode == NotificationTimingMode.afterStart
            ? slotStart.add(timing.offset)
            : slotEnd.subtract(timing.offset);

        // Don't schedule if: in the past, or after slot end, or before slot start
        if (!notifTime.isAfter(now)) continue;
        if (notifTime.isAfter(slotEnd) || notifTime.isBefore(slotStart)) {
          continue;
        }

        if (firstNotifTime == null || notifTime.isBefore(firstNotifTime)) {
          firstNotifTime = notifTime;
        }

        String body;
        if (timing.urgent) {
          final remaining = slotEnd.difference(notifTime);
          final remainStr = _formatRemaining(remaining);
          body = '${slot.getTimeRange()} — $remainStr restantes';
        } else {
          body = '${slot.getTimeRange()} — Rappel d\'émargement';
        }

        try {
          await _scheduleNotification(
            id: id,
            title: timing.urgent ? '🚨 Émargement URGENT' : 'Émargement requis',
            body: body,
            scheduledTime: notifTime,
            playSound: timing.urgent,
            urgent: timing.urgent,
            payload: slotKey,
          );
          _scheduledIds.add(id);
          _scheduledSlotByNotifId[id] = slotKey;
          slotNotifIds.add(id);
          id++;
        } catch (e) {
          debugPrint('AttendanceNotif: failed to schedule id=$id: $e');
          id++;
        }
      }

      // If we scheduled at least one notification for this slot, setup the background sync alarm
      if (slotNotifIds.isNotEmpty && firstNotifTime != null) {
        final alarmTime = firstNotifTime.subtract(const Duration(minutes: 2));
        // Make sure alarm isn't scheduled in the past. If it is, schedule it for almost immediately
        final finalAlarmTime = alarmTime.isAfter(now)
            ? alarmTime
            : now.add(const Duration(seconds: 10));

        final alarmId = slotKey.hashCode.abs(); // Need unique ID for the alarm
        debugPrint(
          'AttendanceNotif: Scheduling background sync alarm $alarmId at $finalAlarmTime for slot $slotKey',
        );

        await AndroidAlarmManager.oneShotAt(
          finalAlarmTime,
          alarmId,
          BackgroundSyncService.syncAttendanceStatus,
          exact: true,
          wakeup: true,
          alarmClock:
              true, // Requires SCHEDULE_EXACT_ALARM permission, which we already have
          params: {'slotKey': slotKey, 'notifIds': slotNotifIds},
        );
      }
    }
    debugPrint(
      'AttendanceNotif: scheduled ${_scheduledIds.length} notifications',
    );
  }

  /// Cancel all previously scheduled notifications.
  static Future<void> _cancelPrevious() async {
    final slotKeys = _scheduledSlotByNotifId.values.toSet();
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

    for (final slotKey in slotKeys) {
      try {
        await AndroidAlarmManager.cancel(slotKey.hashCode.abs());
      } catch (_) {}
    }

    _scheduledIds.clear();
    _scheduledSlotByNotifId.clear();
  }

  static String? _currentSlotKeyNow() {
    final slotInfo = TimeSlotService.getCurrentSlotInfo();
    if (!slotInfo.isInSlot || slotInfo.currentSlot == null) return null;
    return slotInfo.currentSlot!.keyForDate(DateTime.now());
  }

  static Future<void> cancelNotificationsForSlot(String slotKey) async {
    if (!_initialized) return;

    final idsToCancel = _scheduledSlotByNotifId.entries
        .where((e) => e.value == slotKey)
        .map((e) => e.key)
        .toList();

    if (idsToCancel.isEmpty) return;

    for (final id in idsToCancel) {
      try {
        await _plugin.cancel(id);
      } catch (_) {}
      _scheduledIds.remove(id);
      _scheduledSlotByNotifId.remove(id);
    }

    try {
      await AndroidAlarmManager.cancel(slotKey.hashCode.abs());
    } catch (_) {}

    debugPrint(
      'AttendanceNotif: cancelled ${idsToCancel.length} notifications for slot $slotKey',
    );
  }

  static Future<void> cancelCurrentSlotNotifications() async {
    final slotKey = _currentSlotKeyNow();
    if (slotKey == null) return;
    await cancelNotificationsForSlot(slotKey);
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
