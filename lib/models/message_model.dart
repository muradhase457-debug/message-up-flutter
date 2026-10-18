import 'package:cloud_firestore/cloud_firestore.dart';

/// A single chat message, stored in `chats/{chatId}/messages`.
class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String text;
  final String type; // 'text' | 'image' | 'system'
  final String? imageUrl;
  final String? replyToId;
  final String? replyToText;
  final bool starred;
  final bool forwarded;
  final bool deleted;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// Delivery ticks: sent → delivered → read.
  final bool delivered;
  final bool read;
  final List<String> readBy;

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.senderName = '',
    this.text = '',
    this.type = 'text',
    this.imageUrl,
    this.replyToId,
    this.replyToText,
    this.starred = false,
    this.forwarded = false,
    this.deleted = false,
    this.createdAt,
    this.expiresAt,
    this.delivered = false,
    this.read = false,
    this.readBy = const <String>[],
  });

  String get displayText => deleted ? 'This message was deleted' : text;

  factory Message.fromMap(
      String id, String chatId, Map<String, dynamic> map) {
    final rawReadBy = map['readBy'];
    final readBy = rawReadBy is List
        ? rawReadBy.map((e) => e.toString()).toList()
        : <String>[];
    return Message(
      id: id,
      chatId: chatId,
      senderId: (map['senderId'] as String?) ?? '',
      senderName: (map['senderName'] as String?) ?? '',
      text: (map['text'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'text',
      imageUrl: map['imageUrl'] as String?,
      replyToId: map['replyToId'] as String?,
      replyToText: map['replyToText'] as String?,
      starred: (map['starred'] as bool?) ?? false,
      forwarded: (map['forwarded'] as bool?) ?? false,
      deleted: (map['deleted'] as bool?) ?? false,
      createdAt: _toDate(map['createdAt']),
      expiresAt: _toDate(map['expiresAt']),
      delivered: (map['delivered'] as bool?) ?? false,
      read: (map['read'] as bool?) ?? false,
      readBy: readBy,
    );
  }

  factory Message.fromDoc(
      String chatId, DocumentSnapshot<Map<String, dynamic>> doc) {
    return Message.fromMap(doc.id, chatId, doc.data() ?? <String, dynamic>{});
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'type': type,
      'imageUrl': imageUrl,
      'replyToId': replyToId,
      'replyToText': replyToText,
      'starred': starred,
      'forwarded': forwarded,
      'deleted': deleted,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'expiresAt':
          expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
      'delivered': delivered,
      'read': read,
      'readBy': readBy,
    };
  }

  Message copyWith({
    bool? starred,
    bool? deleted,
    bool? delivered,
    bool? read,
  }) {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      type: type,
      imageUrl: imageUrl,
      replyToId: replyToId,
      replyToText: replyToText,
      starred: starred ?? this.starred,
      forwarded: forwarded,
      deleted: deleted ?? this.deleted,
      createdAt: createdAt,
      expiresAt: expiresAt,
      delivered: delivered ?? this.delivered,
      read: read ?? this.read,
      readBy: readBy,
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
