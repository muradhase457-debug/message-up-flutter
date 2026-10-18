import 'package:cloud_firestore/cloud_firestore.dart';

/// One call, stored in the `calls` collection. Signalling (offer / answer /
/// ICE candidates) runs over Firestore — see CallService. The caller and the
/// callee are the ONLY two accounts allowed to read/write this doc (see
/// firestore.rules).
class CallDoc {
  final String id;
  final String callerId;
  final String callerName;
  final String calleeId;
  final String calleeName;
  final String type; // 'voice' | 'video'
  final String status; // 'ringing' | 'active' | 'ended' | 'declined'
  final bool answered;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final DateTime? createdAt;
  final DateTime? endedAt;

  const CallDoc({
    required this.id,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
    required this.calleeName,
    this.type = 'voice',
    this.status = 'ringing',
    this.answered = false,
    this.offer,
    this.answer,
    this.createdAt,
    this.endedAt,
  });

  bool get isVideo => type == 'video';
  bool get isRinging => status == 'ringing';
  bool get isActive => status == 'active';
  bool get isOver => status == 'ended' || status == 'declined';

  /// The other side's name from [myUid]'s point of view.
  String peerName(String myUid) {
    if (myUid == callerId) return calleeName;
    return callerName;
  }

  /// Call length in seconds, 0 while the call is still ringing/active.
  int get durationSeconds {
    if (createdAt == null || endedAt == null) return 0;
    return endedAt!.difference(createdAt!).inSeconds;
  }

  factory CallDoc.fromMap(String id, Map<String, dynamic> map) {
    return CallDoc(
      id: id,
      callerId: (map['callerId'] as String?) ?? '',
      callerName: (map['callerName'] as String?) ?? '',
      calleeId: (map['calleeId'] as String?) ?? '',
      calleeName: (map['calleeName'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'voice',
      status: (map['status'] as String?) ?? 'ringing',
      answered: (map['answered'] as bool?) ?? false,
      offer: map['offer'] is Map
          ? Map<String, dynamic>.from(map['offer'] as Map)
          : null,
      answer: map['answer'] is Map
          ? Map<String, dynamic>.from(map['answer'] as Map)
          : null,
      createdAt: _toDate(map['createdAt']),
      endedAt: _toDate(map['endedAt']),
    );
  }

  factory CallDoc.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return CallDoc.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
