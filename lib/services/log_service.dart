import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_log.dart';

class LogService {
  static const _keyLogs = 'attendance_logs';

  Future<void> addLog(AttendanceLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final logs = await getLogs();
    logs.insert(0, log);

    if (logs.length > 1024) {
      logs.removeRange(1024, logs.length);
    }

    final jsonList = logs.map((l) => l.toJson()).toList();
    await prefs.setString(_keyLogs, jsonEncode(jsonList));
  }

  Future<List<AttendanceLog>> getLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyLogs);
    if (jsonString == null) return [];

    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => AttendanceLog.fromJson(json)).toList();
  }

  Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLogs);
  }
}
