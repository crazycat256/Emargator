import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/error_report.dart';

class ErrorService {
  static const _keyErrors = 'error_reports';
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<void> logError(String contextName, Object error, StackTrace? stackTrace) async {
    final prefs = await SharedPreferences.getInstance();
    final errors = await getErrors();

    String deviceModel = 'Unknown';
    try {
      if (kIsWeb) {
         deviceModel = 'Web Browser';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceModel = '${androidInfo.brand} ${androidInfo.model} (SDK ${androidInfo.version.sdkInt})';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceModel = '${iosInfo.name} ${iosInfo.systemName} ${iosInfo.systemVersion}';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfo.linuxInfo;
        deviceModel = '${linuxInfo.name} ${linuxInfo.versionId}';
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        deviceModel = '${macInfo.model} ${macInfo.osRelease}';
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        deviceModel = '${windowsInfo.productName}';
      }
    } catch (e) {
      deviceModel = 'Unknown ($e)';
    }

    final report = ErrorReport(
      timestamp: DateTime.now(),
      deviceModel: deviceModel,
      error: error.toString(),
      stackTrace: stackTrace?.toString() ?? 'No stacktrace',
      contextName: contextName,
    );

    errors.insert(0, report);

    // Keep only last 50 errors to save space
    if (errors.length > 50) {
      errors.removeRange(50, errors.length);
    }

    final jsonList = errors.map((e) => e.toJson()).toList();
    await prefs.setString(_keyErrors, jsonEncode(jsonList));
  }

  Future<List<ErrorReport>> getErrors() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyErrors);
    if (jsonString == null) return [];

    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList.map((json) => ErrorReport.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> clearErrors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyErrors);
  }
}

