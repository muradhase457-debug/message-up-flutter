import 'package:flutter/material.dart';
import 'package:message_up/models/message_model.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/services/chat_service.dart';
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
  int? _disappearingSeconds;

  @override
  void dispose() {
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
            tooltip: 'Voice call (coming soon)',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Voice calls arrive with the WebRTC wiring (see Calls screen).')),
            ),
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
                // only when there is actually something unread, so the
                // write does not retrigger this builder in a loop.
                final hasUnread = messages.any(
                    (m) => m.senderId != myUid && !m.read);
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
                    return MessageBubble(
                      message: m,
                      isMine: m.senderId == myUid,
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

  void _forward(BuildContext context, Message m) {
    // Forwarding target picker: for this first native cut, forward into
    // any existing chat is done by picking from the user's chat list.
    // Kept intentionally simple: copy the text into the composer of
    // this chat is NOT what forward means, so we show a picker instead.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Forward: pick a chat from Chats, long-press, '
              'then choose Forward (target picker ships in the next cut).')),
    );
  }
}
