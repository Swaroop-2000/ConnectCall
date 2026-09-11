import 'dart:html' as html;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final String _vapidKey = 'BEqsomDp0hA_nLtPusCkduX-CCa3r-GaDs8GUkmfiPhR7dh386EPQjEwL5h4ne9RBueHfqPiDhWyIDXFaPGDmFM';

  Future<void> init() async {
    // Handle foreground messages if the user happens to have the app open
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      // STRICT FILTER: If the user toggled off, but a delayed message arrives, throw it in the trash
      final enabled = await isEnabled();
      if (!enabled) return;

      if (message.notification != null) {
        if (html.Notification.permission == 'granted') {
          try {
            html.Notification(
              message.notification!.title ?? 'Incoming Call', 
              body: message.notification!.body ?? 'You have an incoming call!'
            );
          } catch (e) {
            print('Notification error: $e');
          }
        }
      }
    });
  }

  Future<void> requestPermissions() async {
    try {
      // 1. Request FCM permissions
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final isGranted = settings.authorizationStatus == AuthorizationStatus.authorized;
        
        if (isGranted) {
          // 2. Get the FCM Token with VAPID key
          final fcmToken = await _messaging.getToken(vapidKey: _vapidKey);
          
          // 3. Save to Firestore
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {
              'notificationsEnabled': true,
              'fcmToken': fcmToken
            },
            SetOptions(merge: true)
          );
        } else {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {'notificationsEnabled': false},
            SetOptions(merge: true)
          );
          html.window.alert('Notifications were blocked by your browser. Please click the lock icon in the URL bar to allow them.');
        }
      }
    } catch (e) {
      print('Notification error: $e');
    }
  }

  Future<void> disableNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'notificationsEnabled': false, 'fcmToken': FieldValue.delete()},
        SetOptions(merge: true)
      );
    }
  }

  Future<bool> isEnabled() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return doc.data()?['notificationsEnabled'] ?? false;
  }

  Future<void> showIncomingCallNotification(String callerName) async {
    // Now handled by Firebase Cloud Functions and Service Worker!
    // We leave this empty because the server does the push.
  }
}
