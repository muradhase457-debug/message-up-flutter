import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:message_up/models/chat_model.dart';
import 'package:message_up/models/message_model.dart';
import 'package:message_up/utils/constants.dart';

/// Firestore chat operations: chats, messages, ticks, flags.
///
/// Collection layout:
///   chats/{chatId}              -> Chat
///   chats/{chatId}/messages/{id} -> Message
class ChatService {
  ChatService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection(AppConstants.chatsCollection);

  CollectionReference<Map<String, dynamic>> _messagesOf(String chatId) =>
      _chats.doc(chatId).collection(AppConstants.messagesCollection);

  /// All chats the user belongs to, newest first.
  /// NOTE: sorted client-side on purpose — `arrayContains` + server-side
  /// `orderBy` on another field would need a composite Firestore index.
  Stream<List<Chat>> chatsStream(String myUid) {
    return _chats
        .where('members', arrayContains: myUid)
        .snapshots()
        .map((snap) {
          final chats = snap.docs.map(Chat.fromDoc).toList();
          chats.sort((a, b) {
            final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bt.compareTo(at);
          });
          return chats;
        });
  }

  /// Single chat document stream.
  Stream<Chat?> chatStream(String chatId) {
    return _chats.doc(chatId).snapshots().map(
        (doc) => doc.exists ? Chat.fromDoc(doc) : null);
  }

  /// Messages of a chat, oldest → newest.
  Stream<List<Message>> messagesStream(String chatId) {
    return _messagesOf(chatId)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Message.fromDoc(chatId, d)).toList());
  }

  /// Send a text (or image) message. Updates the chat preview, bumps the
  /// other members' unread counters, and stamps ticks fields.
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String text,
    String type = 'text',
    String? imageUrl,
    String? replyToId,
    String? replyToText,
    int? disappearingSeconds,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && imageUrl == null) return;
    final now = DateTime.now();
    final message = Message(
      id: '',
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      text: trimmed,
      type: type,
      imageUrl: imageUrl,
      replyToId: replyToId,
      replyToText: replyToText,
      createdAt: now,
      expiresAt: disappearingSeconds == null
          ? null
          : now.add(Duration(seconds: disappearingSeconds)),
      delivered: false,
      read: false,
    );
    final chatRef = _chats.doc(chatId);
    final chatSnap = await chatRef.get();
    final members = chatSnap.data()?['members'];
    final memberList = members is List
        ? members.map((e) => e.toString()).toList()
        : <String>[];
    // Nested map (NOT dotted keys): set(merge:true) treats dotted keys as
    // literal field names, which silently broke the unread counters.
    final unread = <String, dynamic>{};
    for (final m in memberList) {
      if (m != senderId) unread[m] = FieldValue.increment(1);
    }
    await _messagesOf(chatId).add(message.toMap());
    // set(merge:true) — NOT update: update() throws if the chat document
    // does not exist yet, set(merge:true) creates it instead. No crash
    // for a stale / deleted chatId.
    // Written in the website-compatible format: lastMessage = {text, senderId},
    // unread = {uid: n}, updatedAt = time.
    final preview = trimmed.isEmpty ? '📷 Photo' : trimmed;
    await chatRef.set(<String, dynamic>{
      'lastMessage': <String, dynamic>{'text': preview, 'senderId': senderId},
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSenderId': senderId,
      if (unread.isNotEmpty) 'unread': unread,
    }, SetOptions(merge: true));
  }

  /// Mark every message in a chat as delivered+read for [myUid], and
  /// reset my unread counter. Call when opening a chat / on new messages
  /// while the chat is open.
  ///
  /// Seen-state is written in BOTH formats so the app and the website
  /// agree: the website reads `lastRead.{uid}` on the chat doc, the app
  /// also reads per-message `read`/`readBy`. Only messages newer than my
  /// last `lastRead` stamp are rewritten, so an already-read chat costs
  /// no writes at all.
  Future<void> markRead(String chatId, String myUid) async {
    final chatSnap = await _chats.doc(chatId).get();
    final chatData = chatSnap.data() ?? <String, dynamic>{};
    final rawLastRead = chatData['lastRead'];
    DateTime? myLastRead;
    if (rawLastRead is Map) {
      myLastRead = _toDate(rawLastRead[myUid]);
    }
    // Single-field query + client-side filter: combining `!=` with `==`
    // on another field would need a composite Firestore index.
    final snap = await _messagesOf(chatId)
        .where('senderId', isNotEqualTo: myUid)
        .limit(100)
        .get();
    final toMark = snap.docs.where((d) {
      if ((d.data()['read'] as bool?) == true) return false;
      final created = _toDate(d.data()['createdAt']);
      if (created == null) return true;
      return myLastRead == null || created.isAfter(myLastRead);
    }).toList();
    if (toMark.isEmpty && myLastRead != null) {
      return; // nothing new — no write, no snapshot loop
    }
    final batch = _firestore.batch();
    for (final doc in toMark) {
      batch.update(doc.reference, <String, dynamic>{
        'delivered': true,
        'read': true,
        'readBy': FieldValue.arrayUnion(<String>[myUid]),
      });
    }
    batch.update(_chats.doc(chatId), <String, dynamic>{
      'unread.$myUid': 0,
      'lastRead.$myUid': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Mark messages as delivered (recipient online) without marking read.
  Future<void> markDelivered(String chatId, String myUid) async {
    final snap = await _messagesOf(chatId)
        .where('senderId', isNotEqualTo: myUid)
        .limit(100)
        .get();
    final undelivered = snap.docs
        .where((d) => (d.data()['delivered'] as bool?) != true)
        .toList();
    if (undelivered.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in undelivered) {
      batch.update(doc.reference, <String, dynamic>{'delivered': true});
    }
    await batch.commit();
  }

  /// Create a 1:1 chat between two users, or return the existing one.
  Future<String> createChat({
    required String myUid,
    required String otherUid,
  }) async {
    // Single-field query + client-side filter: `arrayContains` + `==`
    // on another field would need a composite Firestore index.
    final existing = await _chats
        .where('members', arrayContains: myUid)
        .get();
    for (final doc in existing.docs) {
      final data = doc.data();
      if (data['isGroup'] == true) continue;
      final members = (doc.data()['members'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[];
      if (members.length == 2 && members.contains(otherUid)) {
        return doc.id;
      }
    }
    // Same id scheme as the website: both uids sorted and joined by "_".
    final ids = <String>[myUid, otherUid]..sort();
    final ref = _chats.doc(ids.join('_'));
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set(<String, dynamic>{
        'members': ids,
        'isGroup': false,
        'lastMessage': null,
        'unread': <String, dynamic>{myUid: 0, otherUid: 0},
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return ref.id;
  }

  /// Create a group chat.
  Future<String> createGroupChat({
    required String myUid,
    required List<String> memberUids,
    required String title,
  }) async {
    final members = <String>{myUid, ...memberUids}.toList();
    final ref = await _chats.add(<String, dynamic>{
      'members': members,
      'isGroup': true,
      'title': title,
      'name': title,
      'createdBy': myUid,
      'lastMessage': null,
      'unread': <String, dynamic>{},
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Toggle archive / mute / block flags on a chat.
  Future<void> setChatFlag(
    String chatId, {
    bool? archived,
    bool? muted,
    bool? blocked,
  }) async {
    final updates = <String, dynamic>{};
    if (archived != null) updates['archived'] = archived;
    if (muted != null) updates['muted'] = muted;
    if (blocked != null) updates['blocked'] = blocked;
    if (updates.isEmpty) return;
    await _chats.doc(chatId).update(updates);
  }

  /// Set the disappearing-messages timer (seconds). Null = off.
  Future<void> setDisappearingTimer(String chatId, int? seconds) async {
    await _chats.doc(chatId).update(
        <String, dynamic>{'disappearingSeconds': seconds});
  }

  /// Star / unstar a message.
  Future<void> setStarred(String chatId, String messageId, bool starred) async {
    await _messagesOf(chatId)
        .doc(messageId)
        .update(<String, dynamic>{'starred': starred});
  }

  /// Soft-delete a message (text replaced with a tombstone).
  Future<void> deleteMessage(String chatId, String messageId) async {
    await _messagesOf(chatId).doc(messageId).update(<String, dynamic>{
      'deleted': true,
      'text': '',
      'imageUrl': null,
    });
  }

  /// Upload a chat photo to Firebase Storage (NO Cloudinary account
  /// needed — Storage is part of the same Firebase project) and return
  /// its download URL. The caller then sends it with [sendMessage].
  Future<String> uploadChatImage({
    required String chatId,
    required File file,
    required String myUid,
  }) async {
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_$myUid.jpg';
    final ref = FirebaseStorage.instance.ref('chat_images/$chatId/$name');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  /// Upload a profile photo to Firebase Storage and return its URL.
  Future<String> uploadProfilePhoto({
    required File file,
    required String myUid,
  }) async {
    final ref =
        FirebaseStorage.instance.ref('profile_photos/$myUid.jpg');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  /// Upload a status photo to Firebase Storage and return its URL.
  Future<String> uploadStatusImage({
    required File file,
    required String myUid,
  }) async {
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_$myUid.jpg';
    final ref =
        FirebaseStorage.instance.ref('status_images/$myUid/$name');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  /// Delete messages whose [expiresAt] has passed (disappearing messages).
  /// Call on chat open; a Cloud Function / cron is the robust long-term
  /// home for this sweep.
  Future<void> sweepExpired(String chatId) async {
    final snap = await _messagesOf(chatId)
        .where('expiresAt', isLessThan: Timestamp.now())
        .limit(50)
        .get();
    if (snap.docs.isEmpty) return; // nothing expired — no empty batch write
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
