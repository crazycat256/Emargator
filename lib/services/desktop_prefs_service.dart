import 'package:shared_preferences/shared_preferences.dart';

class DesktopPrefsService {
  static const _keyKeepRunningInBackgroundOnClose =
      'desktop_keep_running_in_background_on_close';

  static Future<bool> getKeepRunningInBackgroundOnClose() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyKeepRunningInBackgroundOnClose) ?? true;
  }

  static Future<void> setKeepRunningInBackgroundOnClose(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeepRunningInBackgroundOnClose, enabled);
  }
}
