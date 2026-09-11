import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_notifications_provider.dart';
import '../../services/user_service.dart';
import '../../widgets/common_button.dart';
import 'dart:async';
import 'call_screen.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  final String callId;
  final String callerName;
  final String callType;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.callType,
  });

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  StreamSubscription? _callSubscription;
  bool _isResuming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // Automatically close the screen if the caller hangs up
    _callSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final data = snapshot.data() as Map<String, dynamic>;
      final status = data['status'];
      if (status != 'calling' && status != 'ringing') {
        if (mounted) {
          Navigator.pop(context);
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Hide the UI temporarily while Firestore reconnects to check if the call is still active
      setState(() => _isResuming = true);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _isResuming = false);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _callSubscription?.cancel();
    super.dispose();
  }

  void _acceptCall() {
    // Cancel the listener so it doesn't pop the new CallScreen!
    _callSubscription?.cancel();
    
    FirebaseFirestore.instance.collection('calls').doc(widget.callId).update({'status': 'connected'});
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: widget.callId,
          isCaller: false,
          callType: widget.callType,
          callerName: widget.callerName,
          calleeName: 'Me',
          callerId: '',
          calleeId: '',
        ),
      ),
    );
  }

  void _declineCall() {
    // Update status to rejected. The snapshot listener will pop the screen.
    FirebaseFirestore.instance.collection('calls').doc(widget.callId).update({
      'status': 'rejected',
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isResuming) {
      // Return a blank screen matching the background color to hide the flash
      return Scaffold(backgroundColor: Colors.black.withValues(alpha: 0.96));
    }

    final allUsersAsync = ref.watch(allUsersProvider);
    final otherUserList = allUsersAsync.value?.where((u) => u.name == widget.callerName).toList();
    final otherPhotoUrl = (otherUserList != null && otherUserList.isNotEmpty) ? otherUserList.first.photoUrl : null;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.96),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                const SizedBox(height: 50),
                FadeTransition(
                  opacity: _pulseController,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.deepPurple.withValues(alpha: 0.3),
                    ),
                    child: AvatarCircle(
                      radius: 60,
                      name: widget.callerName,
                      photoUrl: otherPhotoUrl,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  'Incoming ${widget.callType == 'video' ? 'Video' : 'Audio'} Call',
                  style: const TextStyle(fontSize: 20, color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.callerName,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.red,
                      child: IconButton(
                        iconSize: 35,
                        icon: const Icon(Icons.call_end, color: Colors.white),
                        onPressed: _declineCall,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Decline', style: TextStyle(color: Colors.white)),
                  ],
                ),
                Column(
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.green,
                      child: IconButton(
                        iconSize: 35,
                        icon: const Icon(Icons.phone, color: Colors.white),
                        onPressed: _acceptCall,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Accept', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
