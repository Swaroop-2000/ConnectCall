import 'package:cloud_firestore/cloud_firestore.dart';

class CallModel {
  final String callId;
  final String callerId;
  final String callerName;
  final String calleeId;
  final String calleeName;
  final String type; 
  final String status; 
  final DateTime createdAt;
  final int? durationSeconds;

  CallModel({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
    required this.calleeName,
    required this.type,
    required this.status,
    required this.createdAt,
    this.durationSeconds,
  });

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'calleeId': calleeId,
      'calleeName': calleeName,
      'type': type,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'durationSeconds': durationSeconds,
    };
  }

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      callId: map['callId'] as String,
      callerId: map['callerId'] as String,
      callerName: map['callerName'] as String,
      calleeId: map['calleeId'] as String,
      calleeName: map['calleeName'] as String,
      type: map['type'] as String,
      status: map['status'] as String,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      durationSeconds: map['durationSeconds'] as int?,
    );
  }
}
