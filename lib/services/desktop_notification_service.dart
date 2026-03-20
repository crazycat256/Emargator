import 'dart:async';
import 'dart:io' show Platform, Process;
import 'package:local_notifier/local_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_notification_service.dart';

class DesktopNotificationService {
  static final Map<int, Timer> _activeTimers = {};
  static final Map<int, DateTime> _scheduledTimes = {};
  static final Map<String, List<int>> _slotRequests = {};

  static Future<void> init() async {
    await localNotifier.setup(
      appName: 'Emargator',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
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

    if (delay.isNegative) return;

    _activeTimers[id]?.cancel();
    _scheduledTimes[id] = scheduledTime;

    if (!_slotRequests.containsKey(payload)) {
      _slotRequests[payload] = [];
    }
    if (!_slotRequests[payload]!.contains(id)) {
      _slotRequests[payload]!.add(id);
    }

    _activeTimers[id] = Timer(delay, () async {
      final fireTime = DateTime.now();

      _activeTimers.remove(id);
      _scheduledTimes.remove(id);

      final reqsForPayload = _slotRequests[payload];
      reqsForPayload?.remove(id);

      if (fireTime.isAfter(slotEnd)) {
        debugPrint(
          'DesktopNotification: Ignored notification $id because slot $payload is already over',
        );
        return;
      }

      final reqs = reqsForPayload ?? [];
      if (reqs.isNotEmpty && reqs.last != id) {
        final expectedTime = scheduledTime;
        final diff = fireTime.difference(expectedTime).abs();
        if (diff.inSeconds > 10) {
          debugPrint(
            'DesktopNotification: Ignored old delayed notification $id, keeping only the final one',
          );
          return;
        }
      }

      if (!urgent) {
        final prefs = await SharedPreferences.getInstance();
        final cachedList = prefs.getStringList('moodle_signed_keys');
        final signedKeys = cachedList?.toSet() ?? <String>{};
        if (signedKeys.contains(payload)) {
          debugPrint(
            'DesktopNotification: Ignored $id because slot was signed on another device',
          );
          return;
        }
      }

      await _show(title, body, payload, urgent: urgent);
    });

    debugPrint(
      'DesktopNotification: Scheduled $id for $scheduledTime (slotEnd: $slotEnd)',
    );
  }

  static Future<void> _show(
    String title,
    String body,
    String payload, {
    required bool urgent,
  }) async {
    if (Platform.isLinux) {
      final sent = await _showLinuxNotifySend(title, body, urgent: urgent);
      if (sent) return;
    }

    LocalNotification notification = LocalNotification(
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
      // Bring window to front
    };

    try {
      await notification.show();
    } catch (e) {
      debugPrint('DesktopNotification: local_notifier show failed: $e');
    }
  }

  static Future<bool> _showLinuxNotifySend(
    String title,
    String body, {
    required bool urgent,
  }) async {
    try {
      final args = <String>['-a', 'Emargator'];
      if (urgent) {
        args.addAll(['-u', 'critical']);
      }
      args.addAll([title, body]);

      final result = await Process.run('notify-send', args);
      if (result.exitCode == 0) {
        return true;
      }
      debugPrint(
        'DesktopNotification: notify-send failed (${result.exitCode}): ${result.stderr}',
      );
      return false;
    } catch (e) {
      debugPrint('DesktopNotification: notify-send exception: $e');
      return false;
    }
  }

  static void cancel(int id) {
    _activeTimers[id]?.cancel();
    _activeTimers.remove(id);
    _scheduledTimes.remove(id);

    for (final entry in _slotRequests.entries.toList()) {
      entry.value.remove(id);
      if (entry.value.isEmpty) {
        _slotRequests.remove(entry.key);
      }
    }
  }

  static void cancelAll() {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    _scheduledTimes.clear();
    _slotRequests.clear();
  }
}
