import 'desktop_notification_service.dart';
import 'dart:async';
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
  static const _syncLeadTime = Duration(seconds: 30);
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// IDs of notifications we've scheduled (so we can cancel them individually).
  static final List<int> _scheduledIds = [];
  static final Map<int, String> _scheduledSlotByNotifId = {};
  static final Map<int, int> _scheduledAlarmByNotifId = {};

  /// Callbacks set from outside (main.dart) to handle notification actions.
  static OnSignAttendance? onSignAttendance;
  static OnIgnoreSlot? onIgnoreSlot;

  static int _alarmIdForNotification(int notificationId) =>
      100000 + notificationId;

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
      await DesktopNotificationService.init();
      _initialized = true;
      return;
    }

    const android = AndroidInitializationSettings(
      '@drawable/ic_launcher_foreground',
    );
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

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return true;
    }

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
      final List<DateTime> slotNotifTimes = [];

      for (final timing in notifTimings) {
        final notifTime = timing.timingMode == NotificationTimingMode.afterStart
            ? slotStart.add(timing.offset)
            : slotEnd.subtract(timing.offset);

        // Don't schedule if: in the past, or after slot end, or before slot start
        if (!notifTime.isAfter(now)) continue;
        if (notifTime.isAfter(slotEnd) || notifTime.isBefore(slotStart)) {
          continue;
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
            slotEnd: slotEnd,
          );
          _scheduledIds.add(id);
          _scheduledSlotByNotifId[id] = slotKey;
          slotNotifIds.add(id);
          slotNotifTimes.add(notifTime);
          id++;
        } catch (e) {
          debugPrint('AttendanceNotif: failed to schedule id=$id: $e');
          id++;
        }
      }

      // Schedule one background sync check 30s before each notification.
      // If the slot is already signed on Moodle, that check cancels all remaining slot notifs.
      for (int index = 0; index < slotNotifIds.length; index++) {
        final notifId = slotNotifIds[index];
        final notifTime = slotNotifTimes[index];
        final alarmTime = notifTime.subtract(_syncLeadTime);
        final finalAlarmTime = alarmTime.isAfter(now)
            ? alarmTime
            : now.add(const Duration(seconds: 1));
        final alarmId = _alarmIdForNotification(notifId);

        debugPrint(
          'AttendanceNotif: Scheduling pre-notif sync alarm $alarmId at $finalAlarmTime for notif $notifId ($slotKey)',
        );

        if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
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
        } else {
          // On Desktop, just schedule a Timer to trigger sync.
          Timer(finalAlarmTime.difference(DateTime.now()), () {
            BackgroundSyncService.syncAttendanceStatus(alarmId, {
              'slotKey': slotKey,
              'notifIds': slotNotifIds,
            });
          });
        }
      }
    }
    debugPrint(
      'AttendanceNotif: scheduled ${_scheduledIds.length} notifications',
    );
  }

  /// Cancel all previously scheduled notifications.
  static Future<void> _cancelPrevious() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      DesktopNotificationService.cancelAll();
    }

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
      if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
        try {
          await AndroidAlarmManager.cancel(slotKey.hashCode.abs());
        } catch (_) {}
      }
    }

    _scheduledIds.clear();
    _scheduledSlotByNotifId.clear();
    _scheduledAlarmByNotifId.clear();
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
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        DesktopNotificationService.cancel(id);
      }
      try {
        await _plugin.cancel(id);
      } catch (_) {}

      final alarmId = _scheduledAlarmByNotifId[id];
      if (alarmId != null) {
        try {
          await AndroidAlarmManager.cancel(alarmId);
        } catch (_) {}
      }

      _scheduledIds.remove(id);
      _scheduledSlotByNotifId.remove(id);
      _scheduledAlarmByNotifId.remove(id);
    }

    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      try {
        await AndroidAlarmManager.cancel(slotKey.hashCode.abs());
      } catch (_) {}
    }

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
    required DateTime slotEnd,
    bool urgent = false,
  }) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      DesktopNotificationService.scheduleNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        payload: payload,
        urgent: urgent,
        slotEnd: slotEnd,
      );
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      playSound ? 'emargator_sound' : 'emargator_silent',
      playSound ? 'Rappels d\'émargement urgents' : 'Rappels d\'émargement',
      channelDescription: playSound
          ? 'Notifications avec son et vibration'
          : 'Notifications vibration seule (sans son)',
      icon: '@drawable/ic_launcher_foreground',
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
