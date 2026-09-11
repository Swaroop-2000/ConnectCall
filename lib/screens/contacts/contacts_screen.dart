import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../models/user_model.dart';
import '../../widgets/common_button.dart';
import '../call/call_screen.dart';
import 'dart:async';

final _recentContactsProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final auth = ref.watch(authServiceProvider);
  final uid = auth.currentUser?.uid ?? '';
  if (uid.isEmpty) return Stream.value([]);

  final controller = StreamController<List<Map<String, dynamic>>>();
  
  List<QueryDocumentSnapshot> callerDocs = [];
  List<QueryDocumentSnapshot> calleeDocs = [];

  void emit() {
    final allDocs = [...callerDocs, ...calleeDocs];
    allDocs.sort((a, b) {
      final aTime = (a.data() as dynamic)['createdAt']?.seconds ?? 0;
      final bTime = (b.data() as dynamic)['createdAt']?.seconds ?? 0;
      return (bTime as int).compareTo(aTime as int);
    });

    final seen = <String>{};
    final results = <Map<String, dynamic>>[];
    for (final doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final otherId = data['callerId'] == uid
          ? (data['calleeId'] as String? ?? '')
          : (data['callerId'] as String? ?? '');
      final otherName = data['callerId'] == uid
          ? (data['calleeName'] as String? ?? 'Unknown')
          : (data['callerName'] as String? ?? 'Unknown');
      if (otherId.isNotEmpty && seen.add(otherId)) {
        results.add({'uid': otherId, 'name': otherName});
      }
      if (results.length >= 10) break;
    }
    controller.add(results);
  }

  final sub1 = FirebaseFirestore.instance
      .collection('call_history')
      .where('callerId', isEqualTo: uid)
      .limit(30)
      .snapshots()
      .listen((snap) {
    callerDocs = snap.docs;
    emit();
  });

  final sub2 = FirebaseFirestore.instance
      .collection('call_history')
      .where('calleeId', isEqualTo: uid)
      .limit(30)
      .snapshots()
      .listen((snap) {
    calleeDocs = snap.docs;
    emit();
  });

  ref.onDispose(() {
    sub1.cancel();
    sub2.cancel();
    controller.close();
  });

  return controller.stream;
});

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});
  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initiateCall(BuildContext context, UserModel calleeUser,
      String callType, String currentUserId, String currentUserName) async {
    
    // Fetch real-time status just before calling to ensure accuracy
    bool isOnline = calleeUser.isOnline;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(calleeUser.uid).get();
      if (doc.exists) {
        isOnline = doc.data()?['isOnline'] == true;
      }
    } catch (_) {}

    if (!isOnline && context.mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.orange),
          title: const Text('User Offline'),
          content: Text('${calleeUser.name} appears to be offline right now and may not answer. Do you still want to call them?'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade900,
              ),
              child: const Text('Call Anyway'),
            ),
          ],
        ),
      );
      
      // If user dismissed dialog or clicked Cancel, stop the call
      if (proceed != true) return;
    }
    
    if (!context.mounted) return;
    
    final callId = FirebaseFirestore.instance.collection('calls').doc().id;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: callId,
          isCaller: true,
          callType: callType,
          callerId: currentUserId,
          callerName: currentUserName,
          calleeId: calleeUser.uid,
          calleeName: calleeUser.name,
        ),
      ),
    );
  }

  void _toggleBlock(String currentUid, String targetUid, bool isBlocked) {
    ref.read(userServiceProvider).toggleBlockUser(currentUid, targetUid, isBlocked);
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authServiceProvider).currentUser;
    if (authUser == null) {
      return const Scaffold(body: Center(child: Text('Please log in.')));
    }
    
    final liveUserAsync = ref.watch(currentUserProvider);
    final currentUserName = liveUserAsync.value?.name ?? 'Unknown';
    final currentUserId = authUser.uid;
    
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        elevation: 0,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
          const _RecentContactsCarousel(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'ALL CONTACTS',
              style: textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUserId)
                  .snapshots(),
              builder: (context, meSnap) {
                final blockedList = meSnap.hasData && meSnap.data!.exists
                    ? List<String>.from(
                        (meSnap.data!.data() as Map<String, dynamic>?)?['blockedUsers'] ?? [])
                    : <String>[];

                return StreamBuilder<List<UserModel>>(
                  stream: ref.watch(userServiceProvider).getUsersStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    var users = (snapshot.data ?? [])
                        .where((u) => u.uid != currentUserId)
                        .toList();
                    if (_searchQuery.isNotEmpty) {
                      users = users
                          .where((u) => u.name.toLowerCase().contains(_searchQuery))
                          .toList();
                    }
                    if (users.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.group_off_outlined,
                                size: 64, color: colorScheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text('No contacts found.',
                                style: textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final isBlocked = blockedList.contains(user.uid);
                        return _ContactTile(
                          user: user,
                          isBlocked: isBlocked,
                          currentUserId: currentUserId,
                          currentUserName: currentUserName,
                          onBlock: () => _toggleBlock(currentUserId, user.uid, isBlocked),
                          onAudioCall: () => _initiateCall(
                              context, user, 'audio', currentUserId, currentUserName),
                          onVideoCall: () => _initiateCall(
                              context, user, 'video', currentUserId, currentUserName),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentContactsCarousel extends ConsumerStatefulWidget {
  const _RecentContactsCarousel();
  @override
  ConsumerState<_RecentContactsCarousel> createState() =>
      _RecentContactsCarouselState();
}

class _RecentContactsCarouselState
    extends ConsumerState<_RecentContactsCarousel> {
  @override
  Widget build(BuildContext context) {
    final recentAsync = ref.watch(_recentContactsProvider);
    final allUsersAsync = ref.watch(allUsersProvider);
    final allUsers = allUsersAsync.value ?? [];
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return recentAsync.when(
      data: (contacts) {
        // Strict Filter: Only show recent users if they still exist and are valid in allUsers
        final filteredContacts = contacts.where((c) {
          final uid = c['uid'] as String? ?? '';
          return allUsers.any((u) => u.uid == uid);
        }).toList();

        if (filteredContacts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text('RECENT',
                  style: textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant)),
            ),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: filteredContacts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final contact = filteredContacts[i];
                  final uid = contact['uid'] as String? ?? '';
                  final liveUser = allUsers.where((u) => u.uid == uid).firstOrNull;
                  
                  final name = liveUser?.name ?? contact['name'] as String? ?? '?';
                  final parts = name.trim().split(' ');
                  final initials = parts.length >= 2
                      ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                      : name.isNotEmpty
                          ? name[0].toUpperCase()
                          : '?';
                  final bgColors = [
                    const Color(0xFF6C63FF),
                    const Color(0xFF00BCD4),
                    const Color(0xFF4CAF50),
                    const Color(0xFFFF5722),
                    const Color(0xFF9C27B0),
                    const Color(0xFF2196F3),
                  ];
                  final bgColor = bgColors[
                      name.isNotEmpty ? name.codeUnitAt(0) % bgColors.length : 0];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: colorScheme.primary, width: 2.5),
                        ),
                        child: liveUser != null
                            ? AvatarCircle(name: liveUser.name, photoUrl: liveUser.photoUrl, radius: 28)
                            : Container(
                                decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
                                alignment: Alignment.center,
                                child: Text(initials,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20)),
                              ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 60,
                        child: Text(
                          name.split(' ').first,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(fontSize: 11),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final UserModel user;
  final bool isBlocked;
  final String currentUserId;
  final String currentUserName;
  final VoidCallback onBlock;
  final VoidCallback onAudioCall;
  final VoidCallback onVideoCall;

  const _ContactTile({
    required this.user,
    required this.isBlocked,
    required this.currentUserId,
    required this.currentUserName,
    required this.onBlock,
    required this.onAudioCall,
    required this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          AvatarCircle(name: user.name, radius: 24, photoUrl: user.photoUrl),
          if (user.isOnline)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isBlocked ? Colors.red : Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(user.name,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isBlocked ? Colors.red : null)),
      subtitle: Text(
        isBlocked ? 'Blocked' : user.email,
        style: TextStyle(
            color: isBlocked ? Colors.red.withValues(alpha: 0.7) : null),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isBlocked) ...[
            IconButton(
                icon: const Icon(Icons.phone, color: Colors.green),
                tooltip: 'Audio Call',
                onPressed: onAudioCall),
            IconButton(
                icon: Icon(Icons.videocam, color: colorScheme.primary),
                tooltip: 'Video Call',
                onPressed: onVideoCall),
          ],
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
            onSelected: (value) {
              if (value == 'block') onBlock();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'block',
                child: Row(children: [
                  Icon(
                    isBlocked ? Icons.lock_open : Icons.block,
                    color: isBlocked ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(isBlocked ? 'Unblock User' : 'Block User'),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
