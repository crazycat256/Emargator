import 'dart:async';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'attendance_service.dart';
import 'storage_service.dart';
import 'app_log_service.dart';
import '../models/app_log.dart';

class BackgroundSyncService {
  static const _moodleCacheKey = 'moodle_signed_keys';
  static const _httpCheckTimeout = Duration(seconds: 20);

  static Future<bool> _isSignedInLocalCache(String slotKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList(_moodleCacheKey);
      if (cached != null && cached.contains(slotKey)) {
        await AppLogService.writeFromBackground(
          LogLevel.debug,
          'BackgroundSync',
          'Créneau "$slotKey" déjà émargé (cache local)',
        );
        return true;
      }
    } catch (e) {
      await AppLogService.writeFromBackground(
        LogLevel.warning,
        'BackgroundSync',
        'Erreur lecture cache local : $e',
      );
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
        await AppLogService.writeFromBackground(
          LogLevel.debug,
          'BackgroundSync',
          'SecureStorage vide, tentative via le cache background',
        );
        final cached = await StorageService.getBackgroundCredentials();
        studentId = cached.studentId;
        password = cached.password;
      }

      if (studentId == null ||
          studentId.isEmpty ||
          password == null ||
          password.isEmpty) {
        await AppLogService.writeFromBackground(
          LogLevel.warning,
          'BackgroundSync',
          'Identifiants introuvables, impossible de vérifier Moodle',
        );
        return false;
      }

      await AppLogService.writeFromBackground(
        LogLevel.debug,
        'BackgroundSync',
        'Vérification Moodle pour le créneau "$slotKey"...',
      );
      final service = AttendanceService(studentId, password);
      final loginResult = await service.tryLogin();
      if (loginResult != LoginResult.success) {
        await AppLogService.writeFromBackground(
          LogLevel.warning,
          'BackgroundSync',
          'Échec connexion SSO (${loginResult.name}), notifications maintenues',
        );
        return false;
      }

      final sessions = await service.fetchSignedSessions();
      final signedKeys = sessions.map((s) => s.key).toSet();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_moodleCacheKey, signedKeys.toList());

      final signed = signedKeys.contains(slotKey);
      await AppLogService.writeFromBackground(
        signed ? LogLevel.info : LogLevel.debug,
        'BackgroundSync',
        signed
            ? 'Créneau "$slotKey" déjà émargé sur Moodle'
            : 'Créneau "$slotKey" non émargé, notifications maintenues',
      );
      return signed;
    } catch (e) {
      await AppLogService.writeFromBackground(
        LogLevel.error,
        'BackgroundSync',
        'Erreur vérification Moodle : $e',
      );
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
    await AppLogService.writeFromBackground(
      LogLevel.debug,
      'BackgroundSync',
      'Alarme pré-notif déclenchée (id=$alarmId)',
    );
    try {
      final String slotKey = params['slotKey'] as String;
      final List<int> notifIds = (params['notifIds'] as List<dynamic>)
          .cast<int>();

      if (slotKey.isEmpty || notifIds.isEmpty) {
        await AppLogService.writeFromBackground(
          LogLevel.warning,
          'BackgroundSync',
          'Paramètres invalides pour l\'alarme $alarmId',
        );
        return;
      }

      final alreadySigned = await checkSlotStatus(slotKey).timeout(
        _httpCheckTimeout,
        onTimeout: () async {
          await AppLogService.writeFromBackground(
            LogLevel.warning,
            'BackgroundSync',
            'Vérification Moodle expirée, notifications maintenues',
          );
          return false;
        },
      );

      if (!alreadySigned) return;

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
      await AppLogService.writeFromBackground(
        LogLevel.info,
        'BackgroundSync',
        'Notifications $notifIds annulées (créneau "$slotKey" déjà émargé)',
      );
    } catch (e) {
      await AppLogService.writeFromBackground(
        LogLevel.error,
        'BackgroundSync',
        'Erreur alarme pré-notif : $e',
      );
    }
  }
}
