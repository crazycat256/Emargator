import 'dart:async';
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
    _slotRequests[payload]!.add(id);
    
    _activeTimers[id] = Timer(delay, () async {
      final fireTime = DateTime.now();
      
      // Nettoyage des timers
      _activeTimers.remove(id);
      _scheduledTimes.remove(id);
      
      // 1. Annulée si le créneau est déjà passé
      if (fireTime.isAfter(slotEnd)) {
        debugPrint('DesktopNotification: Ignored notification $id because slot $payload is already over');
        return;
      }
      
      // 2. Vérifier si c'est la dernière notification (la plus urgente) du créneau
      final reqs = _slotRequests[payload] ?? [];
      if (reqs.isNotEmpty && reqs.last != id) {
        // En cas de réveil de veille, plusieurs timers risquent de se déclencher en même temps.
        // On vérifie le delta : si on s'est déclenché trop tard en même temps que les autres
        // On ne laisse passer que la dernière notification de la pile pour ne pas spammer.
        final expectedTime = scheduledTime;
        final diff = fireTime.difference(expectedTime).abs();
        if (diff.inSeconds > 10) {
           debugPrint('DesktopNotification: Ignored old delayed notification $id, keeping only the final one');
           return;
        }
      }

      // 3. Vérifier si l'étudiant a déjà émargé ailleurs (surtout pour les non-urgentes)
      if (!urgent) {
        final prefs = await SharedPreferences.getInstance();
        final cachedList = prefs.getStringList('moodle_signed_keys');
        final signedKeys = cachedList?.toSet() ?? <String>{};
        if (signedKeys.contains(payload)) {
           debugPrint('DesktopNotification: Ignored $id because slot was signed on another device');
           return;
        }
      }

      _show(title, body, payload);
    });
    
    debugPrint('DesktopNotification: Scheduled $id for $scheduledTime (slotEnd: $slotEnd)');
  }

  static void _show(String title, String body, String payload) {
    LocalNotification notification = LocalNotification(
      title: title,
      body: body,
      actions: [
        LocalNotificationAction(text: 'Émarger'),
        LocalNotificationAction(text: 'Ignorer le créneau'),
      ]
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

    notification.show();
  }

  static void cancel(int id) {
    _activeTimers[id]?.cancel();
    _activeTimers.remove(id);
    _scheduledTimes.remove(id);
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
