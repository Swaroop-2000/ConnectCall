import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../widgets/common_button.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authServiceProvider).currentUser;
    
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return Scaffold(
      appBar: AppBar(
        title: Text('Call History'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('call_history')
            .where(Filter.or(
              Filter('callerId', isEqualTo: user.uid),
              Filter('calleeId', isEqualTo: user.uid),
            ))
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView.builder(
              itemCount: 5,
              itemBuilder: (context, index) => ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.grey),
                title: Container(height: 15, color: Colors.grey),
                subtitle: Container(height: 10, color: Colors.grey),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No call history yet', style: TextStyle(fontSize: 18)));
          }

          var docs = snapshot.data!.docs.toList();
          docs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['createdAt'] as Timestamp?;
            final bTime = bData['createdAt'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime); // descending
          });

          return Consumer(
            builder: (context, ref, child) {
              final allUsersAsync = ref.watch(allUsersProvider);
              final allUsers = allUsersAsync.value ?? [];

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var doc = docs[index];
                  var data = doc.data() as Map<String, dynamic>;
                  bool isOutgoing = data['callerId'] == user.uid;
                  
                  String otherId = isOutgoing ? (data['calleeId'] as String? ?? '') : (data['callerId'] as String? ?? '');
                  // Find the live user data
                  final liveUser = allUsers.where((u) => u.uid == otherId).firstOrNull;
                  
                  String otherPartyName = liveUser?.name ?? (isOutgoing 
                      ? (data['calleeName'] as String? ?? 'Unknown') 
                      : (data['callerName'] as String? ?? 'Unknown'));
                      
                  String type = (data['type'] as String? ?? 'audio').capitalize();
                  String status = data['status'] ?? 'ended';
                  
                  String direction = isOutgoing ? 'Outgoing' : 'Incoming';
              
              String durationText = '';
              if (status == 'ended' || status == 'completed') {
                int secs = data['durationSeconds'] ?? 0;
                if (secs >= 60) {
                  durationText = '${secs ~/ 60}m ${secs % 60}s';
                } else {
                  durationText = '${secs}s';
                }
              } else {
                durationText = status.capitalize();
              }

              Color statusColor;
              if (status == 'missed' || status == 'rejected') {
                statusColor = Colors.red;
              } else if (isOutgoing) {
                statusColor = Colors.green;
              } else {
                statusColor = Colors.blue;
              }

              IconData callTypeIcon = (data['type'] == 'video') ? Icons.videocam : Icons.phone;
              IconData directionIcon;
              if (status == 'missed' || status == 'rejected') {
                directionIcon = Icons.call_missed;
              } else if (isOutgoing) {
                directionIcon = Icons.call_made;
              } else {
                directionIcon = Icons.call_received;
              }

              return ListTile(
                leading: liveUser != null
                    ? AvatarCircle(name: liveUser.name, photoUrl: liveUser.photoUrl, radius: 20)
                    : CircleAvatar(
                        backgroundColor: Colors.deepPurple.shade100,
                        foregroundColor: Colors.deepPurple,
                        child: Text(otherPartyName.isNotEmpty ? otherPartyName[0].toUpperCase() : '?'),
                      ),
                title: Text(otherPartyName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    children: [
                      Icon(directionIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Icon(callTypeIcon, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        '$type • $direction • $durationText',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                trailing: Text(
                  data['createdAt'] != null 
                    ? _formatDate((data['createdAt'] as Timestamp).toDate()) 
                    : '',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              );
            },
          );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
