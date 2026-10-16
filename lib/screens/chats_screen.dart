import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:message_up/models/chat_model.dart';
import 'package:message_up/models/user_model.dart';
import 'package:message_up/screens/chat_detail_screen.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/services/chat_service.dart';
import 'package:message_up/utils/constants.dart';
import 'package:message_up/utils/time_format.dart';
import 'package:message_up/widgets/avatar_widget.dart';
import 'package:message_up/widgets/tick_widget.dart';
import 'package:provider/provider.dart';

/// Chat list: unread badges, ticks on own last message, search, and a
/// per-chat ⋮ menu (archive / mute / block) via long-press.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  String _query = '';
  bool _showArchived = false;
  Map<String, String> _namesByUid = {};
  Map<String, String> _photosByUid = {};

  Future<void> _loadNames(List<Chat> chats) async {
    final ids = <String>{};
    for (final c in chats) {
      ids.addAll(c.members);
    }
    final missing = ids.where((id) => !_namesByUid.containsKey(id));
    if (missing.isEmpty) return;
    final db = FirebaseFirestore.instance;
    for (final id in missing) {
      try {
        final doc = await db
            .collection(AppConstants.usersCollection)
            .doc(id)
            .get();
        if (doc.exists) {
          final user = ChatUser.fromDoc(doc);
          _namesByUid[id] = user.displayName;
          _photosByUid[id] = user.photoUrl;
        }
      } catch (_) {
        // Name resolution is best-effort; the chat still renders.
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final myUid = auth.currentUid;
    if (myUid == null) {
      return const Center(child: Text('Not signed in'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search chats',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Archived'),
                selected: _showArchived,
                onSelected: (v) => setState(() => _showArchived = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Chat>>(
            stream: chatService.chatsStream(myUid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('Could not load chats: ${snapshot.error}'));
              }
              var chats = snapshot.data ?? <Chat>[];
              // Name resolution runs AFTER this build frame finishes —
              // calling it synchronously here would setState during build.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _loadNames(chats);
              });
              chats = chats
                  .where((c) => c.archived == _showArchived)
                  .where((c) {
                    if (_query.isEmpty) return true;
                    final title =
                        c.displayTitle(myUid, _namesByUid).toLowerCase();
                    return title.contains(_query) ||
                        c.lastMessage.toLowerCase().contains(_query);
                  })
                  .toList();
              if (chats.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _showArchived
                          ? 'No archived chats.'
                          : 'No chats yet. Start one from a profile or the Feed.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              return ListView.separated(
                itemCount: chats.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) {
                  final chat = chats[i];
                  final unread = chat.unreadFor(myUid);
                  final title = chat.displayTitle(myUid, _namesByUid);
                  final otherId = chat.members.firstWhere(
                    (m) => m != myUid,
                    orElse: () => '',
                  );
                  final photo = chat.isGroup
                      ? chat.photoUrl
                      : (_photosByUid[otherId] ?? chat.photoUrl);
                  return ListTile(
                    leading: AvatarWidget(
                        photoUrl: photo.isEmpty ? null : photo,
                        name: title),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread > 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Text(
                          formatChatTime(chat.lastMessageAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread > 0
                                ? const Color(0xFF25D366)
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        if (chat.lastSenderId == myUid)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: TickWidget(delivered: true, read: false),
                          ),
                        Expanded(
                          child: Text(
                            chat.lastMessage.isEmpty
                                ? 'Say hi 👋'
                                : chat.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unread > 0
                                  ? Colors.black87
                                  : Colors.grey[600],
                              fontWeight: unread > 0
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (chat.muted)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.volume_off,
                                size: 15, color: Colors.grey),
                          ),
                      ],
                    ),
                    trailing: unread > 0
                        ? CircleAvatar(
                            radius: 11,
                            backgroundColor: const Color(0xFF25D366),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          )
                        : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(
                            chatId: chat.id, title: title),
                      ),
                    ),
                    onLongPress: () => _showChatMenu(context, chat),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showChatMenu(BuildContext context, Chat chat) {
    final service = context.read<ChatService>();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(chat.archived
                  ? Icons.unarchive
                  : Icons.archive),
              title: Text(chat.archived ? 'Unarchive' : 'Archive'),
              onTap: () async {
                Navigator.pop(ctx);
                await service.setChatFlag(chat.id,
                    archived: !chat.archived);
              },
            ),
            ListTile(
              leading: Icon(
                  chat.muted ? Icons.volume_up : Icons.volume_off),
              title: Text(chat.muted ? 'Unmute' : 'Mute'),
              onTap: () async {
                Navigator.pop(ctx);
                await service.setChatFlag(chat.id, muted: !chat.muted);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: Text(chat.blocked ? 'Unblock' : 'Block',
                  style: const TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                await service.setChatFlag(chat.id,
                    blocked: !chat.blocked);
              },
            ),
          ],
        ),
      ),
    );
  }
}
