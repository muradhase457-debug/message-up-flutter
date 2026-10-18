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
    // The WEBSITE (index.html) and this app share `users` docs but write
    // different field names. Read EVERY variant so a name/photo set on
    // the website shows up here (and vice versa) instead of '?':
    //   name:  displayName (app) | name (website) | username
    //   photo: photoUrl (app)    | photoURL (website) | photo | avatar
    //   about: about (app)       | bio | status
    //   online: online | isOnline ; lastSeen: lastSeen | lastActive
    return ChatUser(
      uid: uid,
      displayName: _firstString(map, const [
        'displayName',
        'name',
        'username',
      ]),
      email: (map['email'] as String?) ?? '',
      photoUrl: _firstString(map, const [
        'photoUrl',
        'photoURL',
        'photo',
        'avatar',
      ]),
      about: _firstString(map, const ['about', 'bio', 'status']),
      online: (map['online'] as bool?) ?? (map['isOnline'] as bool?) ?? false,
      lastSeen: _toDate(map['lastSeen']) ?? _toDate(map['lastActive']),
      blocked: (map['blocked'] as bool?) ?? false,
    );
  }

  /// First non-empty string among [keys], or '' when none is set.
  static String _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
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
