import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'attendance_service.dart';
import 'storage_service.dart';

class BackgroundSyncService {
  static const _moodleCacheKey = 'moodle_signed_keys';

  @pragma('vm:entry-point')
  static Future<void> syncAttendanceStatus(int id, Map<String, dynamic> params) async {
    debugPrint('BackgroundSync: Starting background check for slot alarm=$id');
    
    try {
      final String slotKey = params['slotKey'] as String;
      final List<dynamic> notifIdsDyn = params['notifIds'] ?? [];
      final List<int> notifIds = notifIdsDyn.cast<int>();

      if (slotKey.isEmpty || notifIds.isEmpty) {
         debugPrint('BackgroundSync: Invalid params for slotKey=$slotKey');
         return;
      }

      final storage = StorageService();
      final studentId = await storage.getStudentId();
      final password = await storage.getPassword();

      if (studentId == null || password == null || studentId.isEmpty || password.isEmpty) {
        debugPrint('BackgroundSync: Credentials not found, stopping sync.');
        return;
      }

      // Initialize AttendanceService strictly for background fetch
      final service = AttendanceService(studentId, password);
      
      // We don't necessarily need to "tryLogin", fetchSignedSessions handles CSRF tokens if needed, 
      // but tryLogin guarantees we have a Moodle session.
      final loginResult = await service.tryLogin();
      if (loginResult != LoginResult.success) {
         debugPrint('BackgroundSync: Login failed, cannot sync.');
         return;
      }

      debugPrint('BackgroundSync: Login success. Fetching Moodle signed sessions...');
      final sessions = await service.fetchSignedSessions();
      
      final signedKeys = sessions.map((s) => s.key).toSet();
      
      // Update the cache so the app can use it when opened
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_moodleCacheKey, signedKeys.toList());

      // If the targeted slotKey is present in Moodle, cancel all scheduled notifications for it
      if (signedKeys.contains(slotKey)) {
         debugPrint('BackgroundSync: Student already signed "$slotKey". Cancelling notifications: $notifIds');
         final plugin = FlutterLocalNotificationsPlugin();
         for (final notifId in notifIds) {
             await plugin.cancel(notifId);
         }
      } else {
         debugPrint('BackgroundSync: Slot "$slotKey" NOT signed yet. Notifications will ring normally.');
      }

    } catch (e) {
      debugPrint('BackgroundSync: Error during background sync: $e');
    }
  }
}
