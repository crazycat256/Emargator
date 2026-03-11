import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Utility to request battery-optimization exemption on Android so the system
/// does not kill the app process in the background.
class BatteryService {
  static const _channel = MethodChannel('fr.crazycat256.emargator/battery');

  /// Returns `true` if the app is already exempt from battery optimizations.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (e) {
      debugPrint('BatteryService: isIgnoring check failed: $e');
      return false;
    }
  }

  /// Shows the system dialog asking the user to exempt the app from battery
  /// optimizations. This is a one-time request; Android remembers the choice.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('BatteryService: request failed: $e');
    }
  }

  /// Convenience: request exemption if not already granted.
  static Future<void> ensureExempt() async {
    if (!Platform.isAndroid) return;
    final exempt = await isIgnoringBatteryOptimizations();
    if (!exempt) {
      debugPrint('BatteryService: requesting battery optimization exemption');
      await requestIgnoreBatteryOptimizations();
    } else {
      debugPrint('BatteryService: already exempt from battery optimization');
    }
  }
}
