import 'package:cloud_firestore/cloud_firestore.dart';

/// A Message Up user profile, stored in the `users` collection.
class ChatUser {
  final String uid;
  final String displayName;
  final String email;
  final String photoUrl;
  final String about;
  final bool online;
  final DateTime? lastSeen;
  final bool blocked;

  const ChatUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl = '',
    this.about = '',
    this.online = false,
    this.lastSeen,
    this.blocked = false,
  });

  String get initials {
    final parts =
        displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  factory ChatUser.fromMap(String uid, Map<String, dynamic> map) {
    return ChatUser(
      uid: uid,
      displayName: (map['displayName'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      photoUrl: (map['photoUrl'] as String?) ?? '',
      about: (map['about'] as String?) ?? '',
      online: (map['online'] as bool?) ?? false,
      lastSeen: _toDate(map['lastSeen']),
      blocked: (map['blocked'] as bool?) ?? false,
    );
  }

  factory ChatUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ChatUser.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'about': about,
      'online': online,
      'lastSeen': lastSeen == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(lastSeen!),
      'blocked': blocked,
    };
  }

  ChatUser copyWith({
    String? displayName,
    String? photoUrl,
    String? about,
    bool? online,
    DateTime? lastSeen,
    bool? blocked,
  }) {
    return ChatUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email,
      photoUrl: photoUrl ?? this.photoUrl,
      about: about ?? this.about,
      online: online ?? this.online,
      lastSeen: lastSeen ?? this.lastSeen,
      blocked: blocked ?? this.blocked,
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
