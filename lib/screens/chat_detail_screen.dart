import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:message_up/models/chat_model.dart';
import 'package:message_up/models/message_model.dart';
import 'package:message_up/models/user_model.dart';
import 'package:message_up/screens/call_screen.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/services/call_service.dart';
import 'package:message_up/services/chat_service.dart';
import 'package:message_up/utils/constants.dart';
import 'package:message_up/utils/validators.dart';
import 'package:message_up/widgets/message_bubble.dart';
import 'package:message_up/widgets/three_dot_menu.dart';
import 'package:provider/provider.dart';

/// One conversation: bubbles, ticks, composer, reply, forward, star,
/// disappearing-messages menu, and a chat ⋮ menu.
class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.chatId,
    required this.title,
  });

  final String chatId;
  final String title;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Message? _replyTo;
  bool _sending = false;
  bool _sendingImage = false;
  int? _disappearingSeconds;
  Chat? _chat;
  StreamSubscription<Chat?>? _chatSub;

  @override
  void initState() {
    super.initState();
    // The chat doc itself: members (for the call button) + lastRead
    // (for ticks + unread detection). One small subscription.
    _chatSub = context
        .read<ChatService>()
        .chatStream(widget.chatId)
        .listen((chat) {
      if (mounted) setState(() => _chat = chat);
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text;
    if (!isValidMessageText(text) || _sending) return;
    final auth = context.read<AuthService>();
    final uid = auth.currentUid;
    final user = auth.currentUser;
    if (uid == null) return;
    setState(() => _sending = true);
    try {
      await context.read<ChatService>().sendMessage(
            chatId: widget.chatId,
            senderId: uid,
            senderName: user?.displayName ?? '',
            text: text,
            replyToId: _replyTo?.id,
            replyToText: _replyTo?.text,
            disappearingSeconds: _disappearingSeconds,
          );
      _composer.clear();
      if (mounted) setState(() => _replyTo = null);
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Pick a photo from the gallery, upload it to Firebase Storage
  /// (no Cloudinary account needed) and send it as an image message.
  Future<void> _sendImage() async {
    if (_sendingImage) return;
    final auth = context.read<AuthService>();
    final uid = auth.currentUid;
    if (uid == null) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() => _sendingImage = true);
    try {
      final url = await context.read<ChatService>().uploadChatImage(
            chatId: widget.chatId,
            file: File(picked.path),
            myUid: uid,
          );
      await context.read<ChatService>().sendMessage(
            chatId: widget.chatId,
            senderId: uid,
            senderName: auth.currentUser?.displayName ?? '',
            text: '',
            type: 'image',
            imageUrl: url,
            disappearingSeconds: _disappearingSeconds,
          );
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo could not be sent.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  /// Start a real 1:1 voice call with the other member of this chat.
  Future<void> _startCall() async {
    final chat = _chat;
    final auth = context.read<AuthService>();
    final myUid = auth.currentUid;
    if (chat == null || myUid == null) return;
    if (chat.isGroup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Group calls are not in this build — 1:1 only.')),
      );
      return;
    }
    final otherId = chat.members.firstWhere(
      (m) => m != myUid,
      orElse: () => '',
    );
    if (otherId.isEmpty) return;
    try {
      final callId = await CallService().startCall(
        callerId: myUid,
        callerName: auth.currentUser?.displayName ?? '',
        calleeId: otherId,
        calleeName: widget.title,
        type: 'voice',
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            callId: callId,
            isCaller: true,
            peerName: widget.title,
            peerPhoto: '',
            isVideo: false,
            myUid: myUid,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the call.')),
        );
      }
    }
  }

  /// Ticks from the chat doc's `lastRead` map (the website's seen-state):
  /// delivered = the other side has opened this chat at least once,
  /// read = their lastRead is at/after this message. Falls back to the
  /// per-message fields when the map is missing (older chats).
  /// (delivered, read) for one of MY messages.
  (bool, bool) _tickState(Message m, String myUid) {
    final chat = _chat;
    if (chat == null) return (m.delivered, m.read);
    final others =
        chat.members.where((member) => member != myUid).toList();
    if (others.isEmpty) return (m.delivered, m.read);
    final created = m.createdAt;
    if (created == null) return (m.delivered, m.read);
    var anyOpened = false;
    var allRead = true;
    for (final other in others) {
      final lastRead = chat.lastRead[other];
      if (lastRead != null) anyOpened = true;
      if (lastRead == null || lastRead.isBefore(created)) {
        allRead = false;
      }
    }
    return (anyOpened || m.delivered, allRead || m.read);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final myUid = auth.currentUid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Voice call',
            onPressed: _startCall,
          ),
          ThreeDotMenu(
            title: widget.title,
            items: [
              ThreeDotMenuItem(
                label: 'Disappearing messages: ${_disappearingLabel()}',
                icon: Icons.timer,
                onTap: () => _pickDisappearing(context),
              ),
              ThreeDotMenuItem(
                label: 'Mute chat',
                icon: Icons.volume_off,
                onTap: () async {
                  await chatService.setChatFlag(widget.chatId, muted: true);
                },
              ),
              ThreeDotMenuItem(
                label: 'Block',
                icon: Icons.block,
                danger: true,
                onTap: () async {
                  await chatService.setChatFlag(widget.chatId,
                      blocked: true);
                },
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: chatService.messagesStream(widget.chatId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Could not load messages.'));
                }
                final messages = snapshot.data ?? <Message>[];
                // Mark others' messages read now that the chat is open —
                // compared against MY lastRead stamp, so an already-read
                // chat costs no writes at all.
                final myLastRead = _chat?.lastRead[myUid];
                final hasUnread = messages.any((m) =>
                    m.senderId != myUid &&
                    (myLastRead == null ||
                        (m.createdAt != null &&
                            m.createdAt!.isAfter(myLastRead))));
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && hasUnread) {
                    chatService.markRead(widget.chatId, myUid);
                  }
                  if (mounted) {
                    chatService.sweepExpired(widget.chatId);
                  }
                });
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No messages yet. Say hi 👋',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final isMine = m.senderId == myUid;
                    // Ticks for my messages come from the lastRead map.
                    final shown = isMine
                        ? m.copyWith(
                            delivered: _tickState(m, myUid).$1,
                            read: _tickState(m, myUid).$2,
                          )
                        : m;
                    return MessageBubble(
                      message: shown,
                      isMine: isMine,
                      onReply: () => setState(() => _replyTo = m),
                      onForward: () => _forward(context, m),
                      onStar: () => chatService.setStarred(
                          widget.chatId, m.id, !m.starred),
                      onDelete: () => chatService.deleteMessage(
                          widget.chatId, m.id),
                    );
                  },
                );
              },
            ),
          ),
          if (_replyTo != null)
            Container(
              width: double.infinity,
              color: Colors.grey[200],
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying to: ${_replyTo!.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _replyTo = null),
                  ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: _sendingImage
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image),
                    tooltip: 'Send photo',
                    onPressed: _sendingImage ? null : _sendImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF25D366),
                    child: IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed: _sending ? null : _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _disappearingLabel() {
    final s = _disappearingSeconds;
    if (s == null) return 'Off';
    if (s < 60) return '$s sec';
    if (s < 3600) return '${s ~/ 60} min';
    if (s < 86400) return '${s ~/ 3600} hours';
    return '${s ~/ 86400} days';
  }

  void _pickDisappearing(BuildContext context) {
    final options = <int?, String>{
      null: 'Off',
      60: '1 minute',
      3600: '1 hour',
      86400: '24 hours',
      604800: '7 days',
    };
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Disappearing messages',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...options.entries.map((e) => RadioListTile<int?>(
                  title: Text(e.value),
                  value: e.key,
                  groupValue: _disappearingSeconds,
                  onChanged: (v) async {
                    Navigator.pop(ctx);
                    setState(() => _disappearingSeconds = v);
                    await context
                        .read<ChatService>()
                        .setDisappearingTimer(widget.chatId, v);
                  },
                )),
          ],
        ),
      ),
    );
  }

  /// Forward [m] into another chat: pick the target chat, then send a
  /// copy there with forwarded=true (text or photo, same as the original).
  void _forward(BuildContext context, Message m) async {
    final auth = context.read<AuthService>();
    final myUid = auth.currentUid;
    if (myUid == null) return;
    final service = context.read<ChatService>();
    final target = await showDialog<Chat>(
      context: context,
      builder: (ctx) => const _ForwardPicker(),
    );
    if (target == null || !context.mounted) return;
    await service.sendMessage(
      chatId: target.id,
      senderId: myUid,
      senderName: auth.currentUser?.displayName ?? '',
      text: m.text,
      type: m.type,
      imageUrl: m.imageUrl,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Forwarded')),
      );
    }
  }
}

/// Chat picker for forwarding: titles resolved from the users docs,
/// like the main chat list does.
class _ForwardPicker extends StatefulWidget {
  const _ForwardPicker();

  @override
  State<_ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<_ForwardPicker> {
  Map<String, String> _namesByUid = {};

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final myUid = auth.currentUid ?? '';
    final service = context.read<ChatService>();
    return AlertDialog(
      title: const Text('Forward to…'),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<List<Chat>>(
          stream: service.chatsStream(myUid),
          builder: (context, snapshot) {
            final chats = snapshot.data ?? <Chat>[];
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadNames(chats);
            });
            if (chats.isEmpty) {
              return const Text('No chats yet.');
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: chats.length,
              itemBuilder: (_, i) {
                final chat = chats[i];
                return ListTile(
                  title: Text(chat.displayTitle(myUid, _namesByUid)),
                  subtitle: Text(
                    chat.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(context, chat),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _loadNames(List<Chat> chats) async {
    final ids = <String>{};
    for (final c in chats) {
      ids.addAll(c.members);
    }
    final missing = ids.where((id) => !_namesByUid.containsKey(id));
    if (missing.isEmpty) return;
    final db = FirebaseFirestore.instance;
    final names = Map<String, String>.from(_namesByUid);
    for (final id in missing) {
      try {
        final doc = await db
            .collection(AppConstants.usersCollection)
            .doc(id)
            .get();
        if (doc.exists) {
          names[id] = ChatUser.fromDoc(doc).displayName;
        }
      } catch (_) {
        // Best-effort: the row still shows with a fallback title.
      }
    }
    if (mounted) setState(() => _namesByUid = names);
  }
}
