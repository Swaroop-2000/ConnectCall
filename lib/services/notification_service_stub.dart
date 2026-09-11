import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  Future<void> init() async {}
  Future<void> requestPermissions() async {}
  Future<void> disableNotifications() async {}
  Future<bool> isEnabled() async => false;
  Future<void> showIncomingCallNotification(String callerName) async {}
}
