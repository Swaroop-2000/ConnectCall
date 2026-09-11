import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../services/calling_service.dart';
import '../../services/user_service.dart';
import '../../widgets/common_button.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String callId;
  final bool isCaller;
  final String callType; // 'audio' | 'video'
  final String callerId;
  final String callerName;
  final String calleeId;
  final String calleeName;

  const CallScreen({
    super.key,
    required this.callId,
    required this.isCaller,
    required this.callType,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
    required this.calleeName,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with SingleTickerProviderStateMixin {
  late CallingService _callingService;

  // Button states
  bool _isMicMuted    = false;
  bool _isCameraOff   = false;
  bool _isSpeakerOn   = false;
  bool _isFrontCamera = true;
  bool _isSwitchingCamera = false;
  bool _isScreenSharing = false;

  String _status        = 'Calling...';
  Timer? _timer;
  int    _secondsElapsed = 0;
  int    _networkQuality = 0;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _callingService = ref.read(callingServiceProvider);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _initCall();
  }

  // ─── WebRTC setup ───────────────────────────────────────────────────────────
  void _initCall() async {
    _callingService.onNetworkQualityChanged = (quality) {
      if (mounted) setState(() => _networkQuality = quality);
    };

    _callingService.onScreenShareStateChanged = (isSharing) {
      if (mounted) setState(() => _isScreenSharing = isSharing);
    };

    _callingService.onCallStateChanged = (state) {
      if (!mounted) return;

      void showPremiumError(String msg) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
              ],
            ),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      if (state == 'rejected') {
        showPremiumError('User rejected the call');
      } else if (state == 'failed' || state == RTCPeerConnectionState.RTCPeerConnectionStateFailed.name || state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected.name) {
        showPremiumError('Call connection fails');
      }

      setState(() {
        if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected.name) {
          _status = 'Connected';
          _startTimer();
          _pulseController.stop();
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && _status == 'Connected') {
              setState(() => _status = 'In Call');
            }
          });
        } else if (state == 'ended' ||
            state == 'rejected' ||
            state == 'missed' ||
            state == 'failed' ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected
                    .name ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed.name) {
          _status = 'Ended';
          _timer?.cancel();
        } else {
          _status = 'Ringing...';
        }
      });
    };

    _callingService.onCallEnded = () {
      if (mounted) Navigator.pop(context);
    };

    _callingService.onRemoteStream = (stream) {
      if (mounted) setState(() {});
    };

    try {
      if (widget.isCaller) {
        await _callingService.createCall(
          widget.callId,
          widget.callType,
          callerId:   widget.callerId,
          callerName: widget.callerName,
          calleeId:   widget.calleeId,
          calleeName: widget.calleeName,
        );
      } else {
        await _callingService.joinCall(widget.callId,
            calleeName: widget.calleeName);
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.contains('Camera or Microphone permission is denied')) {
          errorMsg = 'Camera permission is denied / Microphone permission is denied';
        } else if (errorMsg.contains('Internet connection is unavailable')) {
          errorMsg = 'Internet connection is unavailable';
        } else {
          errorMsg = 'Call connection fails';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(errorMsg, style: const TextStyle(color: Colors.white))),
              ],
            ),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  // ─── Timer ──────────────────────────────────────────────────────────────────
  void _startTimer() {
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  String get _formattedTime {
    final m = _secondsElapsed ~/ 60;
    final s = _secondsElapsed % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ─── Controls ───────────────────────────────────────────────────────────────

  void _toggleMic() {
    // Use actual track state returned by service to stay in sync
    final nowMuted = _callingService.toggleMute();
    setState(() => _isMicMuted = nowMuted);
  }

  void _toggleCamera() {
    setState(() => _isCameraOff = !_isCameraOff);
    _callingService.toggleCamera();
  }

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera) return;
    setState(() => _isSwitchingCamera = true);

    try {
      if (kIsWeb) {
        // On web, enumerate video input devices and pick the other one
        final devices = await navigator.mediaDevices.enumerateDevices();
        final videoDevices =
            devices.where((d) => d.kind == 'videoinput').toList();

        if (videoDevices.length < 2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No second camera found')),
            );
          }
          return;
        }

        // Find current device id
        final currentTracks =
            _callingService.localStream?.getVideoTracks() ?? [];
        String? currentDeviceId;
        if (currentTracks.isNotEmpty) {
          final settings = currentTracks[0].getSettings();
          currentDeviceId = settings['deviceId'] as String?;
        }

        // Pick the other device
        final nextDevice = videoDevices.firstWhere(
          (d) => d.deviceId != currentDeviceId,
          orElse: () => videoDevices[0],
        );

        // Get new stream with that device
        final newStream = await navigator.mediaDevices.getUserMedia({
          'video': {'deviceId': nextDevice.deviceId},
          'audio': false,
        });

        final newVideoTrack = newStream.getVideoTracks().first;

        // Replace track in peer connection
        if (_callingService.peerConnection != null) {
          final senders =
              await _callingService.peerConnection!.getSenders();
          for (final sender in senders) {
            if (sender.track?.kind == 'video') {
              await sender.replaceTrack(newVideoTrack);
            }
          }
        }

        // Update local stream & renderer
        final oldTracks =
            _callingService.localStream?.getVideoTracks() ?? [];
        for (final t in oldTracks) {
          _callingService.localStream?.removeTrack(t);
          await t.stop();
        }
        await _callingService.localStream?.addTrack(newVideoTrack);
        _callingService.localRenderer.srcObject =
            _callingService.localStream;

        setState(() => _isFrontCamera = !_isFrontCamera);
      } else {
        // On mobile use Helper
        await _callingService.switchCamera();
        setState(() => _isFrontCamera = !_isFrontCamera);
      }
    } catch (e) {
      debugPrint('switchCamera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera switch failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSwitchingCamera = false);
    }
  }

  Future<void> _toggleScreenShare() async {
    await _callingService.toggleScreenShare();
    setState(() {
      _isScreenSharing = _callingService.isScreenSharing;
    });
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    if (!kIsWeb) {
      _callingService.toggleSpeaker(_isSpeakerOn);
    }
    // On web: audio output routing is browser-controlled; we show the toggle
    // as a visual preference indicator but can't force audio output device
    // without getUserMedia / setSinkId on the HTMLAudioElement (not exposed).
  }

  Future<void> _hangUp() async {
    _timer?.cancel();
    // endCall() will now handle popping the UI safely and waiting for the animation
    await _callingService.endCall();
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    
    // If the user hit the hardware back button, ensure the call still ends.
    // We run it asynchronously to avoid modifying state during the dispose phase.
    if (_callingService.currentCallId != null) {
      Future.microtask(() => _callingService.endCall());
    }
    
    super.dispose();
  }

  // ─── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isVideo   = widget.callType == 'video';
    final otherName = widget.isCaller ? widget.calleeName : widget.callerName;
    
    final allUsersAsync = ref.watch(allUsersProvider);
    final otherUserList = allUsersAsync.value?.where((u) => u.name == otherName).toList();
    final otherPhotoUrl = (otherUserList != null && otherUserList.isNotEmpty) ? otherUserList.first.photoUrl : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Video / Audio background ──────────────────────────────────
            if (isVideo) ...[
              Positioned.fill(
                child: RTCVideoView(
                  _callingService.remoteRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
              // Local PiP
              Positioned(
                top: 20,
                right: 20,
                width: 110,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RTCVideoView(
                        _callingService.localRenderer,
                        mirror: _isFrontCamera,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                      // Camera-off overlay
                      if (_isCameraOff)
                        Container(
                          color: Colors.black,
                          child: Center(
                            child: Icon(Icons.videocam_off,
                                color: Colors.white54, size: 28),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Audio: render full size but invisible to ensure browser plays it
              Positioned.fill(
                child: Opacity(
                  opacity: 0.0,
                  child: RTCVideoView(_callingService.remoteRenderer),
                ),
              ),

              // Full gradient background
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF1A1A2E),
                        Color(0xFF16213E),
                        Color(0xFF0F3460),
                      ],
                    ),
                  ),
                ),
              ),

              // Avatar + name + status
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Pulsing glow ring (only while ringing)
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, child) => Container(
                        padding: EdgeInsets.all(
                            (_status == 'Ringing...' || _status == 'Calling...')
                                ? 14 + 8 * _pulseController.value
                                : 14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.deepPurple.withValues(
                              alpha: (_status == 'Ringing...' ||
                                      _status == 'Calling...')
                                  ? 0.15 + 0.15 * _pulseController.value
                                  : 0.2),
                        ),
                        child: child,
                      ),
                      child: AvatarCircle(
                        radius: 58,
                        name: otherName,
                        photoUrl: otherPhotoUrl,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      otherName,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 8),
                    // Mic muted indicator badge
                    if (_isMicMuted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mic_off, color: Colors.red, size: 14),
                            SizedBox(width: 6),
                            Text('Microphone Off',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],

            // ── Status / Timer chip ───────────────────────────────────────
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_status,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (_status == 'In Call' || _status == 'Connected') ...[
                      const SizedBox(width: 8),
                      Text('•',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 14)),
                      const SizedBox(width: 8),
                      Text(_formattedTime,
                          style: TextStyle(
                              color: Colors.white70, fontSize: 14)),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: _networkQuality == 2
                            ? Colors.red
                            : _networkQuality == 1
                                ? Colors.yellow
                                : Colors.green,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Control Bar ───────────────────────────────────────────────
            Positioned(
              bottom: 28,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // ── Mic ──────────────────────────────────────────────
                    _ControlButton(
                      icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                      label: _isMicMuted ? 'Unmute' : 'Mute',
                      active: _isMicMuted,
                      activeColor: Colors.red,
                      onTap: _toggleMic,
                    ),

                    // ── Camera (video only) or Speaker (audio only) ───────
                    if (isVideo) ...[
                      _ControlButton(
                        icon: _isCameraOff
                            ? Icons.videocam_off
                            : Icons.videocam,
                        label: _isCameraOff ? 'Cam Off' : 'Cam On',
                        active: _isCameraOff,
                        activeColor: Colors.red,
                        onTap: _toggleCamera,
                      ),
                      _ControlButton(
                        icon: _isSwitchingCamera
                            ? Icons.sync
                            : (_isFrontCamera
                                ? Icons.camera_front
                                : Icons.camera_rear),
                        label: _isFrontCamera ? 'Front' : 'Rear',
                        loading: _isSwitchingCamera,
                        onTap: _switchCamera,
                      ),
                      _ControlButton(
                        icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
                        label: _isScreenSharing ? 'Stop' : 'Share',
                        active: _isScreenSharing,
                        activeColor: Colors.deepPurpleAccent,
                        onTap: _toggleScreenShare,
                      ),
                    ] else ...[
                      _ControlButton(
                        icon: _isSpeakerOn
                            ? Icons.volume_up
                            : Icons.volume_down,
                        label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                        active: _isSpeakerOn,
                        activeColor: Colors.deepPurpleAccent,
                        onTap: _toggleSpeaker,
                      ),
                    ],

                    // ── End Call ─────────────────────────────────────────
                    _ControlButton(
                      icon: Icons.call_end,
                      label: 'End',
                      activeColor: Colors.red,
                      active: true,
                      size: 56,
                      onTap: _hangUp,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reusable Control Button ─────────────────────────────────────────────────
class _ControlButton extends StatelessWidget {
  final IconData    icon;
  final String      label;
  final bool        active;
  final Color       activeColor;
  final bool        loading;
  final double      size;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    this.active      = false,
    this.activeColor  = Colors.white,
    this.loading     = false,
    this.size        = 48,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? activeColor.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.1);
    final iconColor = active ? activeColor : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width:  size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: active
                  ? Border.all(color: activeColor.withValues(alpha: 0.6), width: 1.5)
                  : null,
            ),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: iconColor,
                    ),
                  )
                : Icon(icon, color: iconColor, size: size * 0.46),
          ),
          const SizedBox(height: 5),
          Text(label,
              style: TextStyle(
                  color: active ? activeColor : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
