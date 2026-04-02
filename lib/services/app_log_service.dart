import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_log.dart';

class AppLogService extends ChangeNotifier {
  AppLogService._();

  static final AppLogService instance = AppLogService._();

  static const _prefsKey = 'app_logs';
  // Logs written from background isolates land here; merged into _prefsKey on load().
  static const _bgKey = 'app_logs_bg';
  static const _maxLogs = 2048;
  static const _retention = Duration(days: 7);

  List<AppLog> _logs = [];

  List<AppLog> get logs => List.unmodifiable(_logs);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Merge any logs written by background isolates.
    final bgRaw = prefs.getString(_bgKey);
    List<AppLog> bgLogs = [];
    if (bgRaw != null) {
      try {
        bgLogs = (jsonDecode(bgRaw) as List<dynamic>)
            .map((j) => AppLog.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {}
      await prefs.remove(_bgKey);
    }

    final raw = prefs.getString(_prefsKey);
    List<AppLog> main = [];
    if (raw != null) {
      try {
        main = (jsonDecode(raw) as List<dynamic>)
            .map((j) => AppLog.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // Corrupted data – start fresh.
      }
    }

    if (bgLogs.isNotEmpty) {
      main = [...main, ...bgLogs]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    main = _purgeOld(main);
    if (main.length > _maxLogs) main = main.sublist(0, _maxLogs);

    _logs = main;
    notifyListeners();
    if (bgLogs.isNotEmpty) await _persist();
  }

  static List<AppLog> _purgeOld(List<AppLog> logs) {
    final cutoff = DateTime.now().subtract(_retention);
    return logs.where((l) => l.timestamp.isAfter(cutoff)).toList();
  }

  Future<void> clear() async {
    _logs = [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.remove(_bgKey);
  }

  String exportAsText() {
    return _logs.reversed.map((l) => l.toString()).join('\n');
  }

  Future<void> _add(AppLog log) async {
    _logs.insert(0, log);
    _logs = _purgeOld(_logs);
    if (_logs.length > _maxLogs) {
      _logs.removeRange(_maxLogs, _logs.length);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_logs.map((l) => l.toJson()).toList()),
    );
  }

  // Callable from any isolate: appends directly to SharedPreferences without
  // touching the singleton (which lives only in the main isolate's heap).
  static Future<void> writeFromBackground(
    LogLevel level,
    String context,
    String message, {
    String? details,
  }) async {
    final log = AppLog(
      timestamp: DateTime.now(),
      level: level,
      context: context,
      message: message,
      details: details,
    );
    final prefs = await SharedPreferences.getInstance();
    List<AppLog> existing = [];
    final raw = prefs.getString(_bgKey);
    if (raw != null) {
      try {
        existing = (jsonDecode(raw) as List<dynamic>)
            .map((j) => AppLog.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    existing.insert(0, log);
    existing = _purgeOld(existing);
    if (existing.length > 256) existing = existing.sublist(0, 256);
    await prefs.setString(
      _bgKey,
      jsonEncode(existing.map((l) => l.toJson()).toList()),
    );
  }

  static Future<void> debug(
    String context,
    String message, {
    String? details,
  }) => instance._add(
    AppLog(
      timestamp: DateTime.now(),
      level: LogLevel.debug,
      context: context,
      message: message,
      details: details,
    ),
  );

  static Future<void> info(String context, String message, {String? details}) =>
      instance._add(
        AppLog(
          timestamp: DateTime.now(),
          level: LogLevel.info,
          context: context,
          message: message,
          details: details,
        ),
      );

  static Future<void> success(
    String context,
    String message, {
    String? details,
  }) => instance._add(
    AppLog(
      timestamp: DateTime.now(),
      level: LogLevel.success,
      context: context,
      message: message,
      details: details,
    ),
  );

  static Future<void> warning(
    String context,
    String message, {
    String? details,
  }) => instance._add(
    AppLog(
      timestamp: DateTime.now(),
      level: LogLevel.warning,
      context: context,
      message: message,
      details: details,
    ),
  );

  static Future<void> error(
    String context,
    String message, {
    String? details,
  }) => instance._add(
    AppLog(
      timestamp: DateTime.now(),
      level: LogLevel.error,
      context: context,
      message: message,
      details: details,
    ),
  );
}
