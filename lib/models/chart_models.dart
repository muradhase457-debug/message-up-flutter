import 'package:cloud_firestore/cloud_firestore.dart';

/// A 1:1 or group chat, stored in the `chats` collection.
/// Sub-collection `messages` holds the [Message] documents.
class Chat {
  final String id;
  final List<String> members;
  final bool isGroup;
  final String title;
  final String photoUrl;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String lastSenderId;
  final Map<String, int> unreadCounts;
  final bool archived;
  final bool muted;
  final bool blocked;
  final int? disappearingSeconds;
  final DateTime? createdAt;

  const Chat({
    required this.id,
    required this.members,
    this.isGroup = false,
    this.title = '',
    this.photoUrl = '',
    this.lastMessage = '',
    this.lastMessageAt,
    this.lastSenderId = '',
    this.unreadCounts = const <String, int>{},
    this.archived = false,
    this.muted = false,
    this.blocked = false,
    this.disappearingSeconds,
    this.createdAt,
  });

  int unreadFor(String uid) => unreadCounts[uid] ?? 0;

  /// Title shown in the list: group title, or the other member's name
  /// (resolved by the UI from the users map).
  String displayTitle(String myUid, Map<String, String> namesByUid) {
    if (isGroup && title.isNotEmpty) return title;
    final other = members.firstWhere(
      (m) => m != myUid,
      orElse: () => members.isNotEmpty ? members.first : '',
    );
    return namesByUid[other] ?? (title.isNotEmpty ? title : 'Chat');
  }

  factory Chat.fromMap(String id, Map<String, dynamic> map) {
    final rawMembers = map['members'];
    final members = rawMembers is List
        ? rawMembers.map((e) => e.toString()).toList()
        : <String>[];
    final rawUnread = map['unreadCounts'];
    final unread = <String, int>{};
    if (rawUnread is Map) {
      rawUnread.forEach((k, v) {
        unread[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }
    return Chat(
      id: id,
      members: members,
      isGroup: (map['isGroup'] as bool?) ?? false,
      title: (map['title'] as String?) ?? '',
      photoUrl: (map['photoUrl'] as String?) ?? '',
      lastMessage: (map['lastMessage'] as String?) ?? '',
      lastMessageAt: _toDate(map['lastMessageAt']),
      lastSenderId: (map['lastSenderId'] as String?) ?? '',
      unreadCounts: unread,
      archived: (map['archived'] as bool?) ?? false,
      muted: (map['muted'] as bool?) ?? false,
      blocked: (map['blocked'] as bool?) ?? false,
      disappearingSeconds: (map['disappearingSeconds'] as num?)?.toInt(),
      createdAt: _toDate(map['createdAt']),
    );
  }

  factory Chat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Chat.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'members': members,
      'isGroup': isGroup,
      'title': title,
      'photoUrl': photoUrl,
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(lastMessageAt!),
      'lastSenderId': lastSenderId,
      'unreadCounts': unreadCounts,
      'archived': archived,
      'muted': muted,
      'blocked': blocked,
      'disappearingSeconds': disappearingSeconds,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }

  Chat copyWith({
    bool? archived,
    bool? muted,
    bool? blocked,
    int? disappearingSeconds,
    bool clearDisappearing = false,
  }) {
    return Chat(
      id: id,
      members: members,
      isGroup: isGroup,
      title: title,
      photoUrl: photoUrl,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      lastSenderId: lastSenderId,
      unreadCounts: unreadCounts,
      archived: archived ?? this.archived,
      muted: muted ?? this.muted,
      blocked: blocked ?? this.blocked,
      disappearingSeconds: clearDisappearing
          ? null
          : (disappearingSeconds ?? this.disappearingSeconds),
      createdAt: createdAt,
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
