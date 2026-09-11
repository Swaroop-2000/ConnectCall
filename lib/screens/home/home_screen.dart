import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common_button.dart';
import '../call/incoming_call_screen.dart';
import '../call/call_screen.dart';
import '../contacts/contacts_screen.dart';
import '../history/history_screen.dart';
import '../profile/profile_screen.dart';
import '../../providers/app_notifications_provider.dart';
import 'dart:async';
import '../../services/calling_service.dart';
import '../../services/notification_service.dart';
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  late final List<Widget> _pages = [
    _HomePage(onGoToContacts: () => setState(() => _currentIndex = 1)),
    const ContactsScreen(),
    const HistoryScreen(),
    const ProfileScreen(),
  ];

  StreamSubscription? _incomingCallSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = ref.read(authServiceProvider).currentUser?.uid;
    if (uid != null) {
      ref.read(userServiceProvider).updateOnlineStatus(uid, true).catchError((_) {});

      // Listen for incoming calls
      _incomingCallSub = FirebaseFirestore.instance
          .collection('calls')
          .where('calleeId', isEqualTo: uid)
          .snapshots()
          .listen((snapshot) async {
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final data = change.doc.data();
                if (data != null && data['status'] == 'calling') {
                  // Ignore stale ghost calls from Firestore local cache when waking up
                  if (data['createdAt'] != null) {
                    final createdAt = (data['createdAt'] as Timestamp).toDate();
                    if (DateTime.now().difference(createdAt).inSeconds > 60) {
                      continue; 
                    }
                  }
                  
                  // Silent rejection if caller is blocked
                  final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                  final blockedList = List<String>.from(userDoc.data()?['blockedUsers'] ?? []);
                  if (blockedList.contains(data['callerId'] ?? '')) {
                    await change.doc.reference.update({'status': 'rejected'});
                    continue;
                  }

                  // Check if we are already in a call
                  final callingService = ref.read(callingServiceProvider);
                  if (callingService.currentCallId != null) {
                    // We are busy, decline the call
                    change.doc.reference.update({'status': 'busy'});
                    continue;
                  }

                  if (!mounted) return;
                  
                  ref.read(notificationServiceProvider).showIncomingCallNotification(
                    data['callerName'] ?? 'Unknown'
                  );

                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => IncomingCallScreen(
                        callId: change.doc.id,
                        callerName: data['callerName'] ?? 'Unknown',
                        callType: data['type'] ?? 'audio',
                      ),
                      opaque: false,
                    ),
                  );
                }
              }
            }
          });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingCallSub?.cancel();
    final uid = ref.read(authServiceProvider).currentUser?.uid;
    if (uid != null) {
      ref.read(userServiceProvider).updateOnlineStatus(uid, false).catchError((_) {});
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = ref.read(authServiceProvider).currentUser?.uid;
    if (uid != null) {
      if (state == AppLifecycleState.resumed) {
        ref.read(userServiceProvider).updateOnlineStatus(uid, true).catchError((_) {});
      } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.hidden) {
        ref.read(userServiceProvider).updateOnlineStatus(uid, false).catchError((_) {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.contacts_outlined),
            activeIcon: Icon(Icons.contacts),
            label: 'Contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomePage extends ConsumerWidget {
  final VoidCallback onGoToContacts;
  const _HomePage({required this.onGoToContacts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveUserAsync = ref.watch(currentUserProvider);
    final usersAsync = ref.watch(allUsersProvider);
    
    // STRICTLY fetch from database (currentUserProvider)
    final liveUser = liveUserAsync.value;
    final name = liveUser?.name ?? 'Loading...';
    final photoUrl = liveUser?.photoUrl;

    final notificationsAsync = ref.watch(appNotificationsProvider);
    final notificationsList = notificationsAsync.value ?? [];
    final unreadCount = notificationsList.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ConnectCall'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {
                  final unreadIds = notificationsList.where((n) => !n.isRead).map((n) => n.id).toSet();
                  ref.read(notificationActionProvider).markAllAsRead();
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (context) {
                      return NotificationsSheet(unreadIds: unreadIds);
                    },
                  );
                },
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unreadCount.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Greeting
                  Row(
                    children: [
                      AvatarCircle(
                          name: name,
                          radius: 26,
                          photoUrl: photoUrl),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Good day,',
                              style: TextStyle(
                                  color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey), fontSize: 13)),
                          Text(
                            name,
                            style: TextStyle(
                              color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.callGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.callGreen.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                                radius: 4, backgroundColor: AppColors.callGreen),
                            SizedBox(width: 5),
                            Text('Online',
                                style: TextStyle(
                                    color: AppColors.callGreen, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                  // Quick Action Cards
                  Row(
                    children: [
                      _QuickActionCard(
                        icon: Icons.phone,
                        label: 'Audio Call',
                        color: AppColors.callGreen,
                        onTap: onGoToContacts,
                      ),
                      SizedBox(width: 12),
                      _QuickActionCard(
                        icon: Icons.videocam,
                        label: 'Video Call',
                        color: Theme.of(context).colorScheme.primary,
                        onTap: onGoToContacts,
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                  Text(
                    'People',
                    style: TextStyle(
                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                ],
              ),
            ),
          ),
          // Users list
          usersAsync.when(
            loading: () => SliverToBoxAdapter(
              child: Center(
                  child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
              )),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(
                  child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('Error: $e',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              )),
            ),
            data: (users) {
              if (users.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(Icons.people_outline,
                              size: 60, color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey)),
                          SizedBox(height: 12),
                          Text('No other users yet.',
                              style: TextStyle(color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey))),
                          Text('Invite friends to ConnectCall!',
                              style: TextStyle(
                                  color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey), fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final u = users[i];
                      return _UserTile(user: u);
                    },
                    childCount: users.length,
                  ),
                ),
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  final dynamic user;

  const _UserTile({required this.user});

  Future<void> _initiateCall(BuildContext context, String calleeId, String calleeName, String callType, String currentUserId, String currentUserName) async {
    
    // Fetch real-time status just before calling to ensure accuracy
    bool isOnline = user.isOnline;
    try {
      final doc = await FirebaseFirestore.instance.collection("users").doc(calleeId).get();
      if (doc.exists) {
        isOnline = doc.data()?["isOnline"] == true;
      }
    } catch (_) {}

    if (!isOnline && context.mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.orange),
          title: const Text("User Offline"),
          content: Text("$calleeName appears to be offline right now and may not answer. Do you still want to call them?"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade900,
              ),
              child: const Text("Call Anyway"),
            ),
          ],
        ),
      );
      
      // If user dismissed dialog or clicked Cancel, stop the call
      if (proceed != true) return;
    }
    
    if (!context.mounted) return;

    final callId = FirebaseFirestore.instance.collection("calls").doc().id;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: callId,
          isCaller: true,
          callType: callType,
          callerId: currentUserId,
          callerName: currentUserName,
          calleeId: calleeId,
          calleeName: calleeName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveUserAsync = ref.watch(currentUserProvider);
    final authUser = ref.watch(authServiceProvider).currentUser;
    final currentUserName = liveUserAsync.value?.name ?? "Unknown";
    final currentUserId = authUser?.uid ?? "";
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          children: [
            AvatarCircle(
                name: user.name,
                radius: 22,
                photoUrl: user.photoUrl),
            if (user.isOnline)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.callGreen,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          user.name,
          style: TextStyle(
              color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black), fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          user.isOnline ? 'Online' : 'Offline',
          style: TextStyle(
            color: user.isOnline ? AppColors.callGreen : (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey),
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CallIconBtn(
              icon: Icons.phone,
              color: AppColors.callGreen,
              onTap: () => _initiateCall(context, user.uid, user.name, 'audio', currentUserId, currentUserName),
            ),
            SizedBox(width: 4),
            _CallIconBtn(
              icon: Icons.videocam,
              color: Theme.of(context).colorScheme.primary,
              onTap: () => _initiateCall(context, user.uid, user.name, 'video', currentUserId, currentUserName),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CallIconBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class NotificationsSheet extends ConsumerWidget {
  final Set<String> unreadIds;
  const NotificationsSheet({super.key, this.unreadIds = const {}});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(appNotificationsProvider);
    final notifications = notificationsAsync.value ?? [];
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final secondaryTextColor = Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                if (notifications.isNotEmpty)
                  TextButton(
                    onPressed: () => ref.read(notificationActionProvider).clearAll(),
                    child: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
          ),
          if (notifications.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('← Swipe left to delete', style: TextStyle(color: secondaryTextColor, fontSize: 12, fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 10),
          if (notificationsAsync.isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (notifications.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text('No new notifications', style: TextStyle(color: secondaryTextColor))),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final notif = notifications[index];
                  final isNew = unreadIds.contains(notif.id);
                  return Dismissible(
                    key: Key(notif.id),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => ref.read(notificationActionProvider).removeNotification(notif.id),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red.withOpacity(0.8),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.withOpacity(0.2),
                        child: const Icon(Icons.call_missed, color: Colors.red),
                      ),
                      title: Text(notif.title, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                      subtitle: Text(notif.body, style: TextStyle(color: secondaryTextColor)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isNew)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Text(
                            '${notif.time.day}/${notif.time.month}/${notif.time.year}\n${notif.time.hour.toString().padLeft(2, '0')}:${notif.time.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

