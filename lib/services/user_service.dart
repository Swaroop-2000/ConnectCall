import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import 'auth_service.dart';

final userServiceProvider = Provider<UserService>((ref) {
  return UserService();
});

final allUsersProvider = StreamProvider<List<UserModel>>((ref) {
  final authUser = ref.watch(authStateProvider).value;
  return FirebaseFirestore.instance.collection('users').snapshots().map((snapshot) {
    return snapshot.docs
        .map((doc) => UserModel.fromMap(doc.data(), doc.id))
        .where((user) => 
            user.uid != authUser?.uid &&
            user.name.trim().isNotEmpty && 
            user.name.trim().toLowerCase() != 'unknown' &&
            user.email.trim().isNotEmpty)
        .toList();
  });
});

final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authUser = ref.watch(authStateProvider).value;
  if (authUser == null) return Stream.value(null);
  
  return FirebaseFirestore.instance.collection('users').doc(authUser.uid).snapshots().map((doc) {
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data()!, doc.id);
  });
});

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveUserToFirestore(String uid, String name, String email) async {
    final user = UserModel(
      uid: uid,
      name: name,
      email: email,
      isOnline: true,
      lastSeen: DateTime.now(),
    );
    await _firestore.collection('users').doc(uid).set(user.toMap(), SetOptions(merge: true));
  }

  Future<void> updateOnlineStatus(String uid, bool isOnline) async {
    await _firestore.collection('users').doc(uid).set({
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<UserModel?> getUserById(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      return UserModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  Future<List<UserModel>> searchUsers(String query) async {
    if (query.isEmpty) return [];
    
    final snapshot = await _firestore
        .collection('users')
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uf8ff')
        .get();
        
    return snapshot.docs
        .map((doc) => UserModel.fromMap(doc.data(), doc.id))
        .where((user) => 
            user.name.trim().isNotEmpty && 
            user.name.trim().toLowerCase() != 'unknown' &&
            user.email.trim().isNotEmpty)
        .toList();
  }

  Stream<List<UserModel>> getUsersStream() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .where((user) => 
              user.name.trim().isNotEmpty && 
              user.name.trim().toLowerCase() != 'unknown' &&
              user.email.trim().isNotEmpty)
          .toList();
    });
  }

  Future<void> toggleBlockUser(String currentUid, String uidToToggle, bool isBlocked) async {
    if (isBlocked) {
      await _firestore.collection('users').doc(currentUid).update({
        'blockedUsers': FieldValue.arrayRemove([uidToToggle])
      });
    } else {
      await _firestore.collection('users').doc(currentUid).update({
        'blockedUsers': FieldValue.arrayUnion([uidToToggle])
      });
    }
  }
}
