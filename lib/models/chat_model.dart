import 'package:cloud_firestore/cloud_firestore.dart';

/// A 1:1 or group chat, stored in the `chats` collection.
/// Sub-collection `messages` holds the [Message] documents.
///
/// The website (index.html) and this app share the same Firestore data.
/// The website stores `lastMessage` as a Map {text, senderId}, unread counts
/// in `unread`, the group name in `name` and the time in `updatedAt`.
/// This model reads BOTH that format and the older app format.
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

  /// When each member last opened this chat (the website's seen-state).
  /// The website writes `lastRead.{uid} = serverTimestamp()`; ticks are
  /// computed from this map, NOT from per-message fields.
  final Map<String, DateTime> lastRead;

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
    this.lastRead = const <String, DateTime>{},
  });

  int unreadFor(String uid) => unreadCounts[uid] ?? 0;

  /// Title shown in the list: group title, or the other member's name
  /// (resolved by the UI from the users map). An empty resolved name
  /// falls back to 'Chat' — never a blank row.
  String displayTitle(String myUid, Map<String, String> namesByUid) {
    if (isGroup && title.isNotEmpty) return title;
    final other = members.firstWhere(
      (m) => m != myUid,
      orElse: () => members.isNotEmpty ? members.first : '',
    );
    final name = namesByUid[other] ?? '';
    if (name.isNotEmpty) return name;
    return title.isNotEmpty ? title : 'Chat';
  }

  // ---- safe readers: never throw, whatever type Firestore returns ----
  static String _str(dynamic v) => v is String ? v : '';
  static bool _bool(dynamic v) => v is bool ? v : false;
  static int? _int(dynamic v) => v is num ? v.toInt() : null;

  static void _readCounts(dynamic raw, Map<String, int> into) {
    if (raw is Map) {
      raw.forEach((k, v) {
        into[k.toString()] = _int(v) ?? 0;
      });
    }
  }

  factory Chat.fromMap(String id, Map<String, dynamic> map) {
    final rawMembers = map['members'];
    final members = rawMembers is List
        ? rawMembers.map((e) => e.toString()).toList()
        : <String>[];

    // unread: old app format `unreadCounts`, website format `unread`.
    final unread = <String, int>{};
    _readCounts(map['unreadCounts'], unread);
    _readCounts(map['unread'], unread);

    // lastMessage: website = Map {text, senderId}, old app = String.
    final rawLast = map['lastMessage'];
    var lastText = '';
    var lastSender = _str(map['lastSenderId']);
    if (rawLast is String) {
      lastText = rawLast;
    } else if (rawLast is Map) {
      lastText = _str(rawLast['text']);
      final s = _str(rawLast['senderId']);
      if (s.isNotEmpty) lastSender = s;
    }

    var title = _str(map['title']);
    if (title.isEmpty) title = _str(map['name']);

    // lastRead: {uid: Timestamp} — the website's seen-state.
    final lastRead = <String, DateTime>{};
    final rawLastRead = map['lastRead'];
    if (rawLastRead is Map) {
      rawLastRead.forEach((k, v) {
        final dt = _toDate(v);
        if (dt != null) lastRead[k.toString()] = dt;
      });
    }

    return Chat(
      id: id,
      members: members,
      isGroup: _bool(map['isGroup']),
      title: title,
      photoUrl: _str(map['photoUrl']),
      lastMessage: lastText,
      lastMessageAt: _toDate(map['lastMessageAt']) ?? _toDate(map['updatedAt']),
      lastSenderId: lastSender,
      unreadCounts: unread,
      archived: _bool(map['archived']),
      muted: _bool(map['muted']),
      blocked: _bool(map['blocked']),
      disappearingSeconds: _int(map['disappearingSeconds']),
      createdAt: _toDate(map['createdAt']) ?? _toDate(map['updatedAt']),
      lastRead: lastRead,
    );
  }

  factory Chat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Chat.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
  }

  /// Written in the website-compatible format so both apps understand it.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'members': members,
      'isGroup': isGroup,
      'title': title,
      if (isGroup) 'name': title,
      'photoUrl': photoUrl,
      'lastMessage': lastMessage.isEmpty
          ? null
          : <String, dynamic>{'text': lastMessage, 'senderId': lastSenderId},
      'lastMessageAt': lastMessageAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(lastMessageAt!),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSenderId': lastSenderId,
      'unread': unreadCounts,
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
