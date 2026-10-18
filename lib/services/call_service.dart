import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:message_up/models/call_model.dart';

/// Real 1:1 voice/video calls (WebRTC) with Firestore signalling.
///
/// Flow:
///   Caller:  startCall() creates `calls/{id}` (status 'ringing'), then
///            CallEngine creates the offer and writes it to the doc.
///   Callee:  HomeScreen listens for ringing docs addressed to me and shows
///            an incoming-call sheet. Accept -> engine joins with the offer
///            and writes the answer + status 'active'.
///   Both:    ICE candidates go to `calls/{id}/candidates` (each side only
///            applies the other side's). Either side ending writes
///            status 'ended' — the other side's doc listener closes too.
///
/// Queries use ONE `where` field + client-side filtering on purpose:
/// two `where` filters on different fields would need a composite
/// Firestore index.
class CallService {
  CallService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection('calls');

  /// Create a ringing call doc. Returns the call id.
  Future<String> startCall({
    required String callerId,
    required String callerName,
    required String calleeId,
    required String calleeName,
    required String type, // 'voice' | 'video'
  }) async {
    final ref = await _calls.add(<String, dynamic>{
      'callerId': callerId,
      'callerName': callerName,
      'calleeId': calleeId,
      'calleeName': calleeName,
      'type': type,
      'status': 'ringing',
      'answered': false,
      'offer': null,
      'answer': null,
      'createdAt': FieldValue.serverTimestamp(),
      'endedAt': null,
    });
    return ref.id;
  }

  /// Live updates of one call doc (offer / answer / ended).
  Stream<CallDoc?> callStream(String callId) {
    return _calls.doc(callId).snapshots().map(
        (doc) => doc.exists ? CallDoc.fromDoc(doc) : null);
  }

  /// Ringing calls addressed to me (incoming). Client-side filter keeps
  /// this a single-field query — no composite index needed.
  Stream<List<CallDoc>> incomingCallsStream(String myUid) {
    return _calls
        .where('calleeId', isEqualTo: myUid)
        .snapshots()
        .map((snap) {
      final calls = snap.docs
          .map(CallDoc.fromDoc)
          .where((c) => c.isRinging)
          .toList();
      calls.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return calls;
    });
  }

  /// My outgoing calls, newest first (single-field query + client sort).
  Stream<List<CallDoc>> outgoingHistory(String myUid) {
    return _calls.where('callerId', isEqualTo: myUid).snapshots().map(
        (snap) {
      final calls = snap.docs.map(CallDoc.fromDoc).toList();
      calls.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return calls;
    });
  }

  /// Calls made TO me, newest first (single-field query + client sort).
  Stream<List<CallDoc>> incomingHistory(String myUid) {
    return _calls.where('calleeId', isEqualTo: myUid).snapshots().map(
        (snap) {
      final calls = snap.docs.map(CallDoc.fromDoc).toList();
      calls.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return calls;
    });
  }

  /// End a call (either side). The other side sees status 'ended'.
  Future<void> endCall(String callId) async {
    try {
      await _calls.doc(callId).update(<String, dynamic>{
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // The doc may already be gone — ending locally is enough.
    }
  }

  /// Decline an incoming call.
  Future<void> declineCall(String callId) async {
    try {
      await _calls.doc(callId).update(<String, dynamic>{
        'status': 'declined',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // The doc may already be gone — declining locally is enough.
    }
  }
}

/// Owns ONE live WebRTC peer connection: local media, remote video,
/// ICE exchange, mute / speaker / camera. Created by CallScreen and
/// disposed when the call ends. Never reused across calls.
class CallEngine {
  CallEngine({
    required FirebaseFirestore firestore,
    required this.callId,
    required this.myUid,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;
  final String callId;
  final String myUid;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidateSub;
  final Set<String> _seenCandidates = <String>{};
  bool _disposed = false;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  static const Map<String, dynamic> _config = <String, dynamic>{
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  /// Start as caller (creates + writes the offer) or callee (answers the
  /// [offer] from the call doc). [onState] gets connection updates like
  /// 'Calling…', 'Ringing…', 'Connected'.
  Future<void> start({
    required bool isCaller,
    required bool video,
    Map<String, dynamic>? offer,
    required void Function(String) onState,
  }) async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': true,
        'video': video,
      });
    } catch (_) {
      // Mic/camera denied or unavailable — the screen shows this and
      // ends the call instead of crashing.
      onState('Mic/camera unavailable');
      rethrow;
    }
    localRenderer.srcObject = _localStream;

    _pc = await createPeerConnection(_config);
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
      }
    };
    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      _firestore
          .collection('calls')
          .doc(callId)
          .collection('candidates')
          .add(<String, dynamic>{
        'from': myUid,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onState('Connected');
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
        onState('Connecting…');
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onState('Connection lost…');
      }
    };

    _candidateSub = _firestore
        .collection('calls')
        .doc(callId)
        .collection('candidates')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        if (_seenCandidates.contains(change.doc.id)) continue;
        _seenCandidates.add(change.doc.id);
        final data = change.doc.data();
        if (data == null) continue;
        if (data['from'] == myUid) continue;
        final candidate = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        _pc?.addCandidate(candidate);
      }
    });

    if (isCaller) {
      onState('Calling…');
      final offerDesc = await _pc!.createOffer();
      await _pc!.setLocalDescription(offerDesc);
      await _firestore.collection('calls').doc(callId).update(
          <String, dynamic>{
        'offer': <String, dynamic>{
          'sdp': offerDesc.sdp,
          'type': offerDesc.type,
        },
      });
    } else {
      onState('Connecting…');
      final o = offer ?? <String, dynamic>{};
      await _pc!.setRemoteDescription(RTCSessionDescription(
        o['sdp'] as String? ?? '',
        o['type'] as String? ?? 'offer',
      ));
      final answerDesc = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answerDesc);
      await _firestore.collection('calls').doc(callId).update(
          <String, dynamic>{
        'answer': <String, dynamic>{
          'sdp': answerDesc.sdp,
          'type': answerDesc.type,
        },
        'status': 'active',
        'answered': true,
      });
    }
  }

  /// Caller: apply the callee's answer.
  Future<void> setRemoteAnswer(Map<String, dynamic> answer) async {
    await _pc?.setRemoteDescription(RTCSessionDescription(
      answer['sdp'] as String? ?? '',
      answer['type'] as String? ?? 'answer',
    ));
  }

  /// Mute / unmute the mic.
  void setMuted(bool muted) {
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  /// Turn the camera on / off (video calls).
  void setVideoEnabled(bool enabled) {
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  /// Flip front / back camera.
  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  /// Speaker on / off.
  Future<void> setSpeaker(bool on) async {
    await Helper.setSpeakerphoneOn(on);
  }

  /// Stop everything. Safe to call twice.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _candidateSub?.cancel();
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      await _localStream?.dispose();
    } catch (_) {}
    try {
      await localRenderer.dispose();
    } catch (_) {}
    try {
      await remoteRenderer.dispose();
    } catch (_) {}
  }
}
