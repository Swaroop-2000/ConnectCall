import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final bool isOnline;
  final String? photoUrl;
  final DateTime? lastSeen;
  final List<String> blockedUsers;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.isOnline = false,
    this.photoUrl,
    this.lastSeen,
    this.blockedUsers = const [],
  });

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    bool? isOnline,
    String? photoUrl,
    DateTime? lastSeen,
    List<String>? blockedUsers,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      isOnline: isOnline ?? this.isOnline,
      photoUrl: photoUrl ?? this.photoUrl,
      lastSeen: lastSeen ?? this.lastSeen,
      blockedUsers: blockedUsers ?? this.blockedUsers,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'isOnline': isOnline,
      'photoUrl': photoUrl,
      'lastSeen': lastSeen != null ? Timestamp.fromDate(lastSeen!) : null,
      'blockedUsers': blockedUsers,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, [String? docId]) {
    return UserModel(
      uid: map['uid'] as String? ?? docId ?? '',
      name: map['name'] as String? ?? 'Unknown',
      email: map['email'] as String? ?? 'No email',
      isOnline: map['isOnline'] as bool? ?? false,
      photoUrl: map['photoUrl'] as String?,
      lastSeen: map['lastSeen'] != null 
          ? (map['lastSeen'] as Timestamp).toDate() 
          : null,
      blockedUsers: List<String>.from(map['blockedUsers'] ?? []),
    );
  }
}
