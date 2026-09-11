import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime time;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    this.isRead = false,
  });
}

final appNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  
  return FirebaseFirestore.instance
      .collection('call_history')
      .where('calleeId', isEqualTo: uid)
      .snapshots()
      .map((snapshot) {
        final notifications = <AppNotification>[];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final status = data['status'];
          final cleared = data['clearedFromNotifications'] == true;
          
          if (!cleared && (status == 'missed' || status == 'rejected' || status == 'timeout' || status == 'busy')) {
            String title = 'Missed Call';
            String body = 'You missed a ${data['type'] ?? 'audio'} call from ${data['callerName'] ?? 'Unknown'}';
            
            if (status == 'busy') {
              title = 'User Busy';
              body = '${data['callerName'] ?? 'Unknown'} was busy on another call.';
            } else if (status == 'rejected') {
              title = 'Call Declined';
              body = 'You declined a call from ${data['callerName'] ?? 'Unknown'}.';
            }

            notifications.add(
              AppNotification(
                id: doc.id,
                title: title,
                body: body,
                time: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                isRead: data['readInNotifications'] == true,
              )
            );
          }
        }
        notifications.sort((a, b) => b.time.compareTo(a.time));
        return notifications;
      });
});

class NotificationActionService {
  final _firestore = FirebaseFirestore.instance;
  
  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> markAllAsRead() async {
    if (uid == null) return;
    final snapshot = await _firestore.collection('call_history')
        .where('calleeId', isEqualTo: uid)
        .get();
    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'];
      final read = data['readInNotifications'] == true;
      if (!read && (status == 'missed' || status == 'rejected' || status == 'timeout' || status == 'busy')) {
        batch.update(doc.reference, {'readInNotifications': true});
      }
    }
    await batch.commit();
  }

  Future<void> removeNotification(String id) async {
    await _firestore.collection('call_history').doc(id).update({'clearedFromNotifications': true});
  }

  Future<void> clearAll() async {
    if (uid == null) return;
    final snapshot = await _firestore.collection('call_history')
        .where('calleeId', isEqualTo: uid)
        .get();
    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'];
      final cleared = data['clearedFromNotifications'] == true;
      if (!cleared && (status == 'missed' || status == 'rejected' || status == 'timeout' || status == 'busy')) {
        batch.update(doc.reference, {'clearedFromNotifications': true});
      }
    }
    await batch.commit();
  }
}

final notificationActionProvider = Provider((ref) => NotificationActionService());
