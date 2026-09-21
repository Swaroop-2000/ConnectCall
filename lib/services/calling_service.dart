import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_model.dart';

final callingServiceProvider = Provider<CallingService>((ref) {
  final service = CallingService();
  ref.onDispose(() => service.dispose());
  return service;
});

class CallingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? currentCallId;
  DateTime? _callStartTime;
  Timer? _missedCallTimer;
  Timer? _statsTimer;
  final List<StreamSubscription> _subscriptions = [];

  bool isScreenSharing = false;
  bool isAwaitingScreenCapture = false; // suppresses disconnect during permission dialog
  MediaStream? _cameraStream;
  int networkQuality = 0; // 0: Good, 1: Fair, 2: Poor
  Function(int quality)? onNetworkQualityChanged;
  Function(bool isSharing)? onScreenShareStateChanged;

  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;
  
  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _remoteCandidatesQueue = [];

  Function(MediaStream stream)? onLocalStream;
  Function(MediaStream stream)? onRemoteStream;
  Function()? onCallEnded;
  Function(String state)? onCallStateChanged;

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  Future<void> _initRenderers() async {
    if (!_renderersInitialized) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
    }
  }

  void _addCandidate(RTCIceCandidate candidate) {
    if (_isRemoteDescriptionSet) {
      peerConnection?.addCandidate(candidate);
    } else {
      _remoteCandidatesQueue.add(candidate);
    }
  }

  void _processCandidateQueue() {
    _isRemoteDescriptionSet = true;
    for (var candidate in _remoteCandidatesQueue) {
      peerConnection?.addCandidate(candidate);
    }
    _remoteCandidatesQueue.clear();
  }

  Future<void> _initLocalStream(String type) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
    };
    if (type == 'video') {
      mediaConstraints['video'] = {
        'facingMode': 'user',
      };
    }

    try {
      localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      if (type == 'video') {
        localRenderer.srcObject = localStream;
      }
      onLocalStream?.call(localStream!);
    } catch (e) {
      debugPrint('getUserMedia error: $e');
      if (e.toString().toLowerCase().contains('notallowed') || 
          e.toString().toLowerCase().contains('denied') || 
          e.toString().toLowerCase().contains('notreadable')) {
        throw Exception('Camera or Microphone permission is denied.');
      }
      throw Exception('Hardware initialization failed: $e');
    }
  }

  Future<void> _createPeerConnection() async {
    peerConnection = await createPeerConnection(_configuration);

    peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        remoteRenderer.srcObject = remoteStream;
        onRemoteStream?.call(remoteStream!);
      }
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      if (!isAwaitingScreenCapture ||
          (state != RTCPeerConnectionState.RTCPeerConnectionStateDisconnected &&
           state != RTCPeerConnectionState.RTCPeerConnectionStateFailed)) {
        onCallStateChanged?.call(state.name);
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _callStartTime = DateTime.now();
        _startStatsTimer();
        if (currentCallId != null) {
          _firestore
              .collection('calls')
              .doc(currentCallId)
              .update({'status': 'connected'});
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!isAwaitingScreenCapture) {
          endCall();
        }
      }
    };

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });
  }

  /// Create a call as the caller. [callId] is a pre-generated Firestore doc ID.
  /// [callType] is 'audio' or 'video'.
  Future<void> createCall(String callId, String callType,
      {String callerId = '',
      String callerName = '',
      String calleeId = '',
      String calleeName = ''}) async {
    _isRemoteDescriptionSet = false;
    _remoteCandidatesQueue.clear();
    
    await _initRenderers();
    await _initLocalStream(callType);
    await _createPeerConnection();

    currentCallId = callId;
    _callStartTime = DateTime.now();

    final callDoc = _firestore.collection('calls').doc(callId);
    
    // Start missed call timer (45 seconds)
    _missedCallTimer?.cancel();
    _missedCallTimer = Timer(const Duration(seconds: 45), () {
      if (currentCallId == callId) {
        callDoc.get().then((snap) {
          if (snap.exists && (snap.data()?['status'] == 'calling' || snap.data()?['status'] == 'ringing')) {
            endCall(callId); // Automatically marks as missed
          }
        });
      }
    });

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        callDoc.collection('callerCandidates').add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    final offer = await peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': callType == 'video' ? 1 : 0,
    });
    await peerConnection!.setLocalDescription(offer);

    final call = CallModel(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      calleeId: calleeId,
      calleeName: calleeName,
      type: callType,
      status: 'calling',
      createdAt: DateTime.now(),
    );
    try {
      await callDoc.set(call.toMap()).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Internet connection is unavailable')
      );

      await callDoc.update({
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Internet connection is unavailable')
      );
    } catch (e) {
      if (e.toString().contains('unavailable')) {
        throw Exception('Internet connection is unavailable');
      }
      rethrow;
    }

    // Listen for answer and status changes
    _subscriptions.add(callDoc.snapshots().listen((snapshot) async {
      if (currentCallId != callId) return; // Prevent ghost events
      if (!snapshot.exists) {
        endCall();
        return;
      }
      final data = snapshot.data();
      if (data != null) {
        final status = data['status'];
        if (status != null && status != 'calling' && status != 'ringing' && status != 'connected') {
          onCallStateChanged?.call(status);
          endCall();
          return;
        }
      }
      if (data != null && data['answer'] != null) {
        final currentRemote = await peerConnection?.getRemoteDescription();
        if (currentRemote == null) {
          await peerConnection?.setRemoteDescription(
            RTCSessionDescription(data['answer']['sdp'], data['answer']['type']),
          );
          _processCandidateQueue();
        }
      }
    }));

    // Listen for callee ICE candidates
    _subscriptions.add(callDoc.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          _addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      }
    }));
  }

  /// Join an existing call as the callee.
  Future<void> joinCall(String callId,
      {String calleeId = '', String calleeName = ''}) async {
    _isRemoteDescriptionSet = false;
    _remoteCandidatesQueue.clear();
    
    await _initRenderers();
    currentCallId = callId;

    final callDoc = _firestore.collection('calls').doc(callId);
    DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await callDoc.get().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Internet connection is unavailable')
      );
    } catch (e) {
      if (e.toString().contains('unavailable')) {
        throw Exception('Internet connection is unavailable');
      }
      rethrow;
    }
    if (!snapshot.exists) return;

    final data = snapshot.data()!;
    final type = (data['type'] as String?) ?? 'video';

    await _initLocalStream(type);
    await _createPeerConnection();

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        callDoc.collection('calleeCandidates').add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    final offer = data['offer'];
    await peerConnection?.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );
    
    _processCandidateQueue(); // Sets flag to true and processes any early birds

    final answer = await peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': type == 'video' ? 1 : 0,
    });
    await peerConnection!.setLocalDescription(answer);

    try {
      await callDoc.update({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Internet connection is unavailable')
      );
    } catch (e) {
      if (e.toString().contains('unavailable')) {
        throw Exception('Internet connection is unavailable');
      }
      rethrow;
    }

    // Listen for status changes
    _subscriptions.add(callDoc.snapshots().listen((snapshot) {
      if (currentCallId != callId) return; // Prevent ghost events
      if (!snapshot.exists) {
        endCall();
        return;
      }
      final data = snapshot.data();
      if (data != null) {
        final status = data['status'];
        if (status != null && status != 'calling' && status != 'ringing' && status != 'connected') {
          onCallStateChanged?.call(status);
          endCall();
        }
      }
    }));

    // Listen for caller ICE candidates
    _subscriptions.add(callDoc.collection('callerCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          _addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      }
    }));
  }

  /// End the current call, saves history to Firestore.
  bool _isEnding = false;
  Future<void> endCall([String? callId]) async {
    if (_isEnding) return;
    _isEnding = true;

    try {
      final id = callId ?? currentCallId;

      // Step 1: Immediately notify UI to pop the screen (starts 300ms route transition)
      try {
        onCallEnded?.call();
      } catch (e) {
        debugPrint('onCallEnded error: $e');
      }

      // Step 2: Wait for the route transition to fully complete so RTCVideoView unmounts
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 3: Now it's safe to release all hardware (mic/camera)
      await _cleanUp();

      // Step 4: Notify the other device and save history in background
      if (id != null) {
        final duration = _callStartTime != null
            ? DateTime.now().difference(_callStartTime!).inSeconds
            : 0;

        final callDoc = _firestore.collection('calls').doc(id);
        callDoc.get().then((snapshot) {
          if (snapshot.exists) {
            final data = Map<String, dynamic>.from(snapshot.data()!);
            
            final currentStatus = data['status'] as String?;
            String finalStatus = 'ended';
            if (currentStatus == 'rejected' || currentStatus == 'busy' || currentStatus == 'missed' || currentStatus == 'failed' || currentStatus == 'disconnected') {
              finalStatus = currentStatus!;
            } else if (currentStatus == 'calling' || currentStatus == 'ringing') {
              finalStatus = 'missed'; // Unanswered
            }

            // Write status first so the other device detects it
            data['status'] = finalStatus;
            data['durationSeconds'] = duration;
            data.putIfAbsent('createdAt', () => FieldValue.serverTimestamp());
            // Save to history, then delete
            _firestore.collection('call_history').doc(id).set(data).then((_) {
              callDoc.delete();
            });
          }
        }).catchError((e) {
          debugPrint('endCall Firestore error: $e');
        });
      }
    } finally {
      currentCallId = null;
      _callStartTime = null;
      _isEnding = false;
    }
  }

  Future<void> _cleanUp() async {
    _missedCallTimer?.cancel();
    _statsTimer?.cancel();
    
    // 1. Detach streams and completely destroy renderers
    // We MUST await dispose() so the CanvasKit video elements are fully destroyed
    // in the browser before we abruptly power down the hardware tracks.
    try {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
      await localRenderer.dispose();
      await remoteRenderer.dispose();
      
      // Re-initialize fresh objects for the next call
      localRenderer = RTCVideoRenderer();
      remoteRenderer = RTCVideoRenderer();
      _renderersInitialized = false;
    } catch (e) {}

    // 2. Stop all media tracks to release mic/camera hardware
    try {
      localStream?.getAudioTracks().forEach((t) => t.stop());
      localStream?.getVideoTracks().forEach((t) => t.stop());
    } catch (e) {}
    try {
      remoteStream?.getAudioTracks().forEach((t) => t.stop());
      remoteStream?.getVideoTracks().forEach((t) => t.stop());
    } catch (e) {}

    // 3. Dispose streams (REMOVED: causes CanvasKit crash if UI is still mounted)
    // try { localStream?.dispose(); } catch (e) {}
    // try { remoteStream?.dispose(); } catch (e) {}

    // 4. Null out all peer connection callbacks BEFORE closing
    //    to prevent ghost onConnectionState events after cleanup
    try {
      peerConnection?.onConnectionState = null;
      peerConnection?.onTrack = null;
      peerConnection?.onIceCandidate = null;
      peerConnection?.onIceConnectionState = null;
    } catch (e) {}

    // 5. Close peer connection
    try {
      peerConnection?.close();
      peerConnection?.dispose();
    } catch (e) {}

    // 6. Cancel Firestore subscriptions last
    try {
      for (var sub in _subscriptions) {
        try { sub.cancel(); } catch (e) {}
      }
      _subscriptions.clear();
    } catch (e) {}

    peerConnection = null;
    localStream = null;
    remoteStream = null;
    _missedCallTimer?.cancel();
    // Do NOT reset _renderersInitialized here, as we keep the renderers alive
  }

  /// Toggle microphone. Returns true if now muted, false if unmuted.
  bool toggleMute() {
    if (localStream != null) {
      final tracks = localStream!.getAudioTracks();
      if (tracks.isNotEmpty) {
        final newEnabled = !tracks[0].enabled;
        tracks[0].enabled = newEnabled;
        debugPrint('Mic ${newEnabled ? "unmuted" : "muted"}');
        return !newEnabled; // isMuted = !enabled
      }
    }
    return false;
  }

  void toggleCamera() {
    if (localStream != null) {
      final tracks = localStream!.getVideoTracks();
      if (tracks.isNotEmpty) {
        tracks[0].enabled = !tracks[0].enabled;
        debugPrint('Camera ${tracks[0].enabled ? "on" : "off"}');
      }
    }
  }

  Future<void> switchCamera() async {
    if (isScreenSharing) return; // Disallow switching camera while sharing screen
    if (localStream != null) {
      final tracks = localStream!.getVideoTracks();
      if (tracks.isNotEmpty) {
        await Helper.switchCamera(tracks[0]);
      }
    }
  }

  Future<void> toggleScreenShare() async {
    if (peerConnection == null) return;

    if (!isScreenSharing) {
      try {
        // Set flag BEFORE showing the system permission dialog.
        // This prevents the brief AppLifecycleState.paused from triggering call end.
        isAwaitingScreenCapture = true;

        final displayMedia = await navigator.mediaDevices.getDisplayMedia({
          'video': true,
          'audio': false,
        });

        isAwaitingScreenCapture = false;
        _cameraStream = localStream;

        final screenTrack = displayMedia.getVideoTracks().first;
        final senders = await peerConnection!.getSenders();
        final sender = senders.firstWhere((s) => s.track?.kind == 'video');
        await sender.replaceTrack(screenTrack);

        localStream = displayMedia;
        localRenderer.srcObject = displayMedia;
        isScreenSharing = true;
        onScreenShareStateChanged?.call(true);
        onLocalStream?.call(localStream!);

        screenTrack.onEnded = () {
          _revertToCamera();
        };
      } catch (e) {
        isAwaitingScreenCapture = false;
        debugPrint('Screen share error: $e');
      }
    } else {
      await _revertToCamera();
    }
  }

  Future<void> _revertToCamera() async {
    if (_cameraStream == null || peerConnection == null) return;

    final cameraTrack = _cameraStream!.getVideoTracks().first;
    final senders = await peerConnection!.getSenders();
    final sender = senders.firstWhere((s) => s.track?.kind == 'video');
    await sender.replaceTrack(cameraTrack);

    localStream = _cameraStream;
    localRenderer.srcObject = _cameraStream;
    isScreenSharing = false;
    onScreenShareStateChanged?.call(false);
    onLocalStream?.call(localStream!);
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (peerConnection == null || peerConnection!.connectionState != RTCPeerConnectionState.RTCPeerConnectionStateConnected) return;
      try {
        final stats = await peerConnection!.getStats();
        int newQuality = 0; // 0=Good, 1=Fair, 2=Poor
        
        for (var report in stats) {
          if (report.type == 'candidate-pair' && report.values['state'] == 'succeeded') {
            final rttVal = report.values['currentRoundTripTime'];
            double rtt = rttVal != null ? (double.tryParse(rttVal.toString()) ?? 0) : 0;
            if (rtt > 0.4) {
              newQuality = 2; // Poor > 400ms
            } else if (rtt > 0.15) {
              newQuality = (newQuality < 1) ? 1 : newQuality; // Fair > 150ms
            }
          }
          if (report.type == 'inbound-rtp') {
            final plVal = report.values['packetsLost'];
            final prVal = report.values['packetsReceived'];
            double packetsLost = plVal != null ? (double.tryParse(plVal.toString()) ?? 0) : 0;
            double packetsReceived = prVal != null ? (double.tryParse(prVal.toString()) ?? 0) : 0;
            
            if (packetsReceived > 0) {
              double lossRate = packetsLost / packetsReceived;
              if (lossRate > 0.05) newQuality = 2; // Poor > 5% loss
              else if (lossRate > 0.01) newQuality = (newQuality < 1) ? 1 : newQuality; // Fair > 1% loss
            }
          }
        }
        
        if (networkQuality != newQuality) {
          networkQuality = newQuality;
          onNetworkQualityChanged?.call(networkQuality);
        }
      } catch (e) {
        debugPrint('Stats error: $e');
      }
    });
  }

  void toggleSpeaker([bool? enabled]) {
    if (!kIsWeb) {
      final on = enabled ?? true;
      Helper.setSpeakerphoneOn(on);
      debugPrint('Speaker ${on ? "on" : "off"}');
    }
    // On web, the browser routes audio output automatically.
    // The button shows a visual state only; actual output routing
    // requires HTMLMediaElement.setSinkId() which is not exposed in flutter_webrtc.
  }

  Future<void> dispose() async {
    _cleanUp();
    if (_renderersInitialized) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
      _renderersInitialized = false;
    }
  }
}
