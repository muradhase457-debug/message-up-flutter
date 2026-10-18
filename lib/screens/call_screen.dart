import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:message_up/models/call_model.dart';
import 'package:message_up/services/call_service.dart';

/// Full-screen 1:1 call: remote video (or avatar for voice calls),
/// local preview, Mute / Speaker / Camera / End. Driven by [CallEngine];
/// the Firestore call doc is the single source of truth for ending —
/// when either side ends, the other side's doc listener closes too.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.callId,
    required this.isCaller,
    required this.peerName,
    required this.peerPhoto,
    required this.isVideo,
    required this.myUid,
  });

  final String callId;
  final bool isCaller;
  final String peerName;
  final String peerPhoto;
  final bool isVideo;
  final String myUid;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallService _callService;
  late final CallEngine _engine;
  StreamSubscription<CallDoc?>? _docSub;
  Timer? _noAnswerTimer;
  String _status = 'Connecting…';
  bool _muted = false;
  bool _speaker = false;
  bool _cameraOn = true;
  bool _remoteAnswerApplied = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _callService = CallService();
    _engine = CallEngine(
      firestore: FirebaseFirestore.instance,
      callId: widget.callId,
      myUid: widget.myUid,
    );
    _start();
  }

  Future<void> _start() async {
    // Watch the call doc: answer (caller) / ended / declined.
    _docSub = _callService.callStream(widget.callId).listen((doc) {
      if (doc == null || !mounted) return;
      if (doc.isOver) {
        _leave(showDeclined: doc.status == 'declined');
        return;
      }
      if (widget.isCaller &&
          !_remoteAnswerApplied &&
          doc.answer != null) {
        _remoteAnswerApplied = true;
        _engine.setRemoteAnswer(doc.answer!);
      }
    });
    try {
      if (widget.isCaller) {
        await _engine.start(
          isCaller: true,
          video: widget.isVideo,
          onState: _setStatus,
        );
        // No answer in 60s -> end the call, don't ring forever.
        _noAnswerTimer = Timer(const Duration(seconds: 60), () {
          if (mounted && _status != 'Connected') {
            _endCall();
          }
        });
      } else {
        // Callee: the offer is on the doc already.
        final snap = await FirebaseFirestore.instance
            .collection('calls')
            .doc(widget.callId)
            .get();
        final doc = snap.exists
            ? CallDoc.fromDoc(
                snap as DocumentSnapshot<Map<String, dynamic>>)
            : null;
        await _engine.start(
          isCaller: false,
          video: widget.isVideo,
          offer: doc?.offer,
          onState: _setStatus,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not start the call — mic/camera unavailable.')),
        );
        _leave();
      }
    }
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  Future<void> _endCall() async {
    await _callService.endCall(widget.callId);
    await _leave();
  }

  Future<void> _leave({bool showDeclined = false}) async {
    if (_leaving) return;
    _leaving = true;
    _noAnswerTimer?.cancel();
    await _docSub?.cancel();
    await _engine.dispose();
    if (!mounted) return;
    if (showDeclined) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call declined')),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _noAnswerTimer?.cancel();
    _docSub?.cancel();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peerLabel =
        widget.peerName.isNotEmpty ? widget.peerName : 'User';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _endCall(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        body: SafeArea(
          child: Stack(
            children: [
              // Remote video, or avatar while waiting / on voice calls.
              Positioned.fill(
                child: widget.isVideo
                    ? RTCVideoView(
                        _engine.remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 64,
                              backgroundImage:
                                  widget.peerPhoto.isNotEmpty
                                      ? NetworkImage(widget.peerPhoto)
                                      : null,
                              child: widget.peerPhoto.isEmpty
                                  ? Text(
                                      peerLabel.isNotEmpty
                                          ? peerLabel[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(fontSize: 40),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              peerLabel,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.isVideo
                                  ? _status
                                  : 'Voice call · $_status',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
              ),
              // Name + status on video calls.
              if (widget.isVideo)
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        peerLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                  blurRadius: 8, color: Colors.black54),
                            ]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _status,
                        style: const TextStyle(
                            color: Colors.white70,
                            shadows: [
                              Shadow(
                                  blurRadius: 8, color: Colors.black54),
                            ]),
                      ),
                    ],
                  ),
                ),
              // Local preview (video calls).
              if (widget.isVideo)
                Positioned(
                  right: 16,
                  bottom: 140,
                  child: Container(
                    width: 110,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: RTCVideoView(
                        _engine.localRenderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              // Controls.
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundBtn(
                      _muted ? Icons.mic_off : Icons.mic,
                      'Mute',
                      _muted,
                      () {
                        setState(() => _muted = !_muted);
                        _engine.setMuted(_muted);
                      },
                    ),
                    _roundBtn(
                      Icons.volume_up,
                      'Speaker',
                      _speaker,
                      () async {
                        setState(() => _speaker = !_speaker);
                        await _engine.setSpeaker(_speaker);
                      },
                    ),
                    if (widget.isVideo) ...[
                      _roundBtn(
                        _cameraOn ? Icons.videocam : Icons.videocam_off,
                        'Camera',
                        !_cameraOn,
                        () {
                          setState(() => _cameraOn = !_cameraOn);
                          _engine.setVideoEnabled(_cameraOn);
                        },
                      ),
                      _roundBtn(
                        Icons.switch_camera,
                        'Flip',
                        false,
                        () => _engine.switchCamera(),
                      ),
                    ],
                    _roundBtn(
                      Icons.call_end,
                      'End',
                      false,
                      _endCall,
                      bg: Colors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundBtn(
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap, {
    Color? bg,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor:
              bg ?? (active ? Colors.white : Colors.white24),
          child: IconButton(
            icon: Icon(icon,
                color: bg == null && active
                    ? Colors.black87
                    : Colors.white),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
