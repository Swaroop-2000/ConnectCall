import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _isEnabled = false;

  Future<void> init() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      _isEnabled = settings.authorizationStatus == AuthorizationStatus.authorized;
      
      // Listen for foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');
      });
    } catch (e) {
      debugPrint('FCM Mobile init error: $e');
    }
  }

  Future<void> requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _isEnabled = settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint('FCM request permission error: $e');
    }
  }

  Future<void> disableNotifications() async {
    _isEnabled = false;
  }

  Future<bool> isEnabled() async => _isEnabled;

  Future<void> showIncomingCallNotification(String callerName) async {
    // On mobile, FCM data messages normally trigger local notifications.
    // For now, this is a placeholder unless we add flutter_local_notifications.
    debugPrint('Show incoming call notification for: $callerName');
  }
}
