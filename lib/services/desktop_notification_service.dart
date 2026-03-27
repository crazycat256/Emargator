import 'dart:async';
import 'dart:io' show Platform, Process;
import 'package:local_notifier/local_notifier.dart';
import 'package:flutter/foundation.dart';
import 'attendance_notification_service.dart';
import 'background_sync_service.dart';
import 'desktop_service.dart';

class _DesktopScheduledNotification {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledTime;
  final String payload;
  final bool urgent;
  final DateTime slotEnd;

  const _DesktopScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
    required this.payload,
    required this.urgent,
    required this.slotEnd,
  });
}

class DesktopNotificationService {
  static const Duration _watchdogInterval = Duration(seconds: 20);
  static const Duration _watchdogOverdueSlack = Duration(seconds: 2);
  static const Duration _moodleCheckTimeout = Duration(seconds: 20);
  static const Duration _catchUpCoalesceThreshold = Duration(seconds: 15);
  static final Map<int, Timer> _activeTimers = {};
  static final Map<int, DateTime> _scheduledTimes = {};
  static final Map<int, _DesktopScheduledNotification> _scheduledById = {};
  static final Map<String, List<int>> _slotRequests = {};
  static Timer? _watchdogTimer;

  static String _ts(DateTime dt) => dt.toIso8601String();

  static Future<void> init() async {
    await localNotifier.setup(
      appName: 'Emargator',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    _ensureWatchdog();
  }

  static void scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String payload,
    required bool urgent,
    required DateTime slotEnd,
  }) {
    final now = DateTime.now();
    final delay = scheduledTime.difference(now);

    if (delay.isNegative) {
      debugPrint(
        'DesktopNotification: Skip id=$id payload=$payload because scheduled time is in the past '
        '(now=${_ts(now)} scheduled=${_ts(scheduledTime)} delayMs=${delay.inMilliseconds})',
      );
      return;
    }

    if (_activeTimers.containsKey(id)) {
      debugPrint(
        'DesktopNotification: Replacing existing timer id=$id '
        '(oldScheduled=${_scheduledTimes[id] != null ? _ts(_scheduledTimes[id]!) : 'unknown'} '
        'newScheduled=${_ts(scheduledTime)})',
      );
    }

    _activeTimers[id]?.cancel();
    _scheduledTimes[id] = scheduledTime;
    _scheduledById[id] = _DesktopScheduledNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      payload: payload,
      urgent: urgent,
      slotEnd: slotEnd,
    );

    _ensureWatchdog();

    if (!_slotRequests.containsKey(payload)) {
      _slotRequests[payload] = [];
    }
    if (!_slotRequests[payload]!.contains(id)) {
      _slotRequests[payload]!.add(id);
    }

    _activeTimers[id] = Timer(delay, () async {
      await _triggerScheduledNotification(id, source: 'timer');
    });

    debugPrint(
      'DesktopNotification: Scheduled id=$id payload=$payload '
      '(now=${_ts(now)} scheduled=${_ts(scheduledTime)} delaySec=${delay.inSeconds} slotEnd=${_ts(slotEnd)} urgent=$urgent)',
    );
  }

  static void _ensureWatchdog() {
    if (_watchdogTimer != null) return;
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      unawaited(_runWatchdog());
    });
    debugPrint(
      'DesktopNotification: Watchdog started (interval=${_watchdogInterval.inSeconds}s)',
    );
  }

  static Future<void> _runWatchdog() async {
    final now = DateTime.now();
    final dueNotificationIds = <int>[];

    for (final entry in _scheduledById.entries) {
      final data = entry.value;
      if (!data.scheduledTime.isAfter(now.add(_watchdogOverdueSlack))) {
        dueNotificationIds.add(entry.key);
      }
    }

    if (dueNotificationIds.isEmpty) return;

    dueNotificationIds.sort((a, b) {
      final ta = _scheduledById[a]?.scheduledTime;
      final tb = _scheduledById[b]?.scheduledTime;
      if (ta == null && tb == null) return 0;
      if (ta == null) return -1;
      if (tb == null) return 1;
      return ta.compareTo(tb);
    });

    debugPrint(
      'DesktopNotification: Watchdog due scan '
      '(now=${_ts(now)} notifIds=$dueNotificationIds)',
    );

    for (final id in dueNotificationIds) {
      await _triggerScheduledNotification(id, source: 'watchdog');
    }
  }

  static Future<void> _triggerScheduledNotification(
    int id, {
    required String source,
  }) async {
    final data = _scheduledById[id];
    if (data == null) {
      debugPrint(
        'DesktopNotification: Trigger source=$source id=$id skipped (already handled)',
      );
      return;
    }

    final fireTime = DateTime.now();
    final driftMs = fireTime.difference(data.scheduledTime).inMilliseconds;

    debugPrint(
      'DesktopNotification: Trigger source=$source id=$id payload=${data.payload} '
      '(scheduled=${_ts(data.scheduledTime)} fired=${_ts(fireTime)} driftMs=$driftMs urgent=${data.urgent})',
    );

    final isCatchUpMode =
        source == 'watchdog' ||
        fireTime.difference(data.scheduledTime) > _catchUpCoalesceThreshold;
    if (isCatchUpMode &&
        _hasNewerDueNotification(
          id: id,
          scheduledTime: data.scheduledTime,
          now: fireTime,
        )) {
      _activeTimers[id]?.cancel();
      _activeTimers.remove(id);
      _scheduledTimes.remove(id);
      _scheduledById.remove(id);

      final reqsForPayload = _slotRequests[data.payload];
      reqsForPayload?.remove(id);

      debugPrint(
        'DesktopNotification: Skipped stale catch-up id=$id payload=${data.payload} '
        'because a newer due notification exists (source=$source)',
      );
      return;
    }

    _activeTimers[id]?.cancel();
    _activeTimers.remove(id);
    _scheduledTimes.remove(id);
    _scheduledById.remove(id);

    final reqsForPayload = _slotRequests[data.payload];
    reqsForPayload?.remove(id);

    if (fireTime.isAfter(data.slotEnd)) {
      debugPrint(
        'DesktopNotification: Ignored id=$id payload=${data.payload} because slot is over '
        '(fire=${_ts(fireTime)} slotEnd=${_ts(data.slotEnd)} source=$source)',
      );
      return;
    }

    final reqs = reqsForPayload ?? [];
    if (reqs.isNotEmpty && reqs.last != id) {
      final diff = fireTime.difference(data.scheduledTime).abs();
      if (diff.inSeconds > 10) {
        debugPrint(
          'DesktopNotification: Ignored delayed duplicate id=$id payload=${data.payload} '
          '(expected=${_ts(data.scheduledTime)} fired=${_ts(fireTime)} diffSec=${diff.inSeconds} source=$source)',
        );
        return;
      }
    }

    // Live Moodle check at notification time (replaces pre-notification sync)
    bool alreadySigned = false;
    try {
      alreadySigned = await BackgroundSyncService.checkSlotStatus(data.payload)
          .timeout(_moodleCheckTimeout);
    } catch (e) {
      debugPrint(
        'DesktopNotification: Live Moodle check failed id=$id payload=${data.payload}: $e (will notify anyway)',
      );
    }

    if (alreadySigned) {
      debugPrint(
        'DesktopNotification: Ignored id=$id payload=${data.payload} because slot already signed on Moodle (source=$source)',
      );
      return;
    }

    await _show(id, data.title, data.body, data.payload, urgent: data.urgent);
  }

  static bool _hasNewerDueNotification({
    required int id,
    required DateTime scheduledTime,
    required DateTime now,
  }) {
    final dueUpperBound = now.add(_watchdogOverdueSlack);
    for (final entry in _scheduledById.entries) {
      if (entry.key == id) continue;
      final candidate = entry.value;
      final isNewer = candidate.scheduledTime.isAfter(scheduledTime);
      final isDue = !candidate.scheduledTime.isAfter(dueUpperBound);
      if (isNewer && isDue) {
        return true;
      }
    }
    return false;
  }

  static Future<void> _show(
    int id,
    String title,
    String body,
    String payload, {
    required bool urgent,
  }) async {
    if (urgent) {
      await _bringToFrontForUrgent(id, payload);
    }

    final notification = _buildLocalNotification(
      title: title,
      body: body,
      payload: payload,
    );

    if (Platform.isLinux) {
      debugPrint(
        'DesktopNotification: Deliver id=$id payload=$payload via notify-send (Linux primary)',
      );
      final sentByNotifySend = await _showLinuxNotifySend(
        id,
        title,
        body,
        urgent: urgent,
      );
      if (sentByNotifySend) {
        debugPrint(
          'DesktopNotification: Delivered id=$id payload=$payload via notify-send',
        );
        return;
      }

      debugPrint(
        'DesktopNotification: Fallback id=$id payload=$payload to local_notifier',
      );
      final shownByLocal = await _showWithLocalNotifier(notification);
      if (shownByLocal) {
        debugPrint(
          'DesktopNotification: Delivered id=$id payload=$payload via local_notifier',
        );
        return;
      }

      debugPrint(
        'DesktopNotification: Linux delivery failed id=$id payload=$payload for both local_notifier and notify-send',
      );
      return;
    }

    debugPrint(
      'DesktopNotification: Deliver id=$id payload=$payload via local_notifier',
    );
    final shownByLocal = await _showWithLocalNotifier(notification);
    if (shownByLocal) {
      debugPrint(
        'DesktopNotification: Delivered id=$id payload=$payload via local_notifier',
      );
    } else {
      debugPrint(
        'DesktopNotification: Delivery failed id=$id payload=$payload via local_notifier',
      );
    }
  }

  static LocalNotification _buildLocalNotification({
    required String title,
    required String body,
    required String payload,
  }) {
    final notification = LocalNotification(
      title: title,
      body: body,
      actions: [
        LocalNotificationAction(text: 'Émarger'),
        LocalNotificationAction(text: 'Ignorer le créneau'),
      ],
    );

    notification.onClickAction = (index) {
      if (index == 0) {
        AttendanceNotificationService.onSignAttendance?.call();
      } else if (index == 1) {
        AttendanceNotificationService.onIgnoreSlot?.call(payload);
      }
    };

    notification.onClick = () {
      DesktopService.bringToFront();
    };

    return notification;
  }

  static Future<bool> _showWithLocalNotifier(
    LocalNotification notification,
  ) async {
    try {
      await notification.show();
      return true;
    } catch (e) {
      debugPrint('DesktopNotification: local_notifier show failed: $e');
      return false;
    }
  }

  static Future<bool> _showLinuxNotifySend(
    int id,
    String title,
    String body, {
    required bool urgent,
  }) async {
    try {
      final args = <String>['-a', 'Emargator'];
      args.addAll(['-r', id.toString()]);

      if (urgent) {
        args.addAll(['-u', 'critical', '-t', '60000']);
      } else {
        args.addAll(['-u', 'normal', '-t', '30000']);
      }

      args.addAll([title, body]);

      final result = await Process.run('notify-send', args);
      if (result.exitCode == 0) {
        final stdoutText = (result.stdout?.toString() ?? '').trim();
        if (stdoutText.isNotEmpty) {
          debugPrint(
            'DesktopNotification: notify-send stdout id=$id: $stdoutText',
          );
        }
        return true;
      }
      debugPrint(
        'DesktopNotification: notify-send failed id=$id (${result.exitCode}) '
        'stderr=${result.stderr} stdout=${result.stdout}',
      );
      return false;
    } catch (e) {
      debugPrint('DesktopNotification: notify-send exception id=$id: $e');
      return false;
    }
  }

  static Future<void> _bringToFrontForUrgent(int id, String payload) async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await DesktopService.bringToFront();
      debugPrint(
        'DesktopNotification: Urgent id=$id payload=$payload forced app to foreground',
      );
    } catch (e) {
      debugPrint(
        'DesktopNotification: Urgent id=$id payload=$payload failed to bring app to foreground: $e',
      );
    }
  }

  static void cancel(int id) {
    final hadTimer = _activeTimers.containsKey(id);
    _activeTimers[id]?.cancel();
    _activeTimers.remove(id);
    _scheduledTimes.remove(id);
    _scheduledById.remove(id);

    for (final entry in _slotRequests.entries.toList()) {
      entry.value.remove(id);
      if (entry.value.isEmpty) {
        _slotRequests.remove(entry.key);
      }
    }

    if (hadTimer) {
      debugPrint('DesktopNotification: Cancelled timer id=$id');
    }
  }

  static void cancelAll() {
    final notifCount = _activeTimers.length;
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    _scheduledTimes.clear();
    _scheduledById.clear();
    _slotRequests.clear();
    debugPrint(
      'DesktopNotification: Cancelled all timers notifCount=$notifCount',
    );
  }
}
