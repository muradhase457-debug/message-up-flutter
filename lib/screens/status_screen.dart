import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/services/chat_service.dart';
import 'package:message_up/utils/constants.dart';
import 'package:message_up/utils/time_format.dart';
import 'package:message_up/widgets/avatar_widget.dart';
import 'package:provider/provider.dart';

/// 24-hour status (stories). Items older than 24h are hidden.
/// Post = text status, or a photo status (gallery -> Firebase Storage).
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _posting = false;

  /// First non-empty string among [keys], or '' when none is set.
  static String _firstString(
      Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _statusCol =>
      FirebaseFirestore.instance.collection(AppConstants.statusCollection);

  Future<void> _postStatus() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _posting) return;
    final auth = context.read<AuthService>();
    final uid = auth.currentUid;
    if (uid == null) return;
    setState(() => _posting = true);
    try {
      await _statusCol.add(<String, dynamic>{
        'uid': uid,
        'name': auth.currentUser?.displayName ?? '',
        'photoUrl': auth.currentUser?.photoURL ?? '',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
      });
      _controller.clear();
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  /// Post a photo status: gallery -> Firebase Storage -> status doc.
  Future<void> _postPhotoStatus() async {
    if (_posting) return;
    final auth = context.read<AuthService>();
    final uid = auth.currentUid;
    if (uid == null) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() => _posting = true);
    try {
      final url = await ChatService().uploadStatusImage(
        file: File(picked.path),
        myUid: uid,
      );
      await _statusCol.add(<String, dynamic>{
        'uid': uid,
        'name': auth.currentUser?.displayName ?? '',
        'photoUrl': auth.currentUser?.photoURL ?? '',
        'text': _controller.text.trim(),
        'imageUrl': url,
        'type': 'image',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
      });
      _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo status could not be posted.')),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Share a 24h status…',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.image),
                tooltip: 'Photo status',
                onPressed: _posting ? null : _postPhotoStatus,
              ),
              ElevatedButton(
                onPressed: _posting ? null : _postStatus,
                child: _posting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Post'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _statusCol
                // No server-side expiry filter: filtering client-side
                // avoids needing a composite Firestore index.
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(
                    child: Text('Could not load status.'));
              }
              final now = DateTime.now();
              final docs = (snapshot.data?.docs ?? []).where((d) {
                final exp = (d.data()['expiresAt'] as Timestamp?)?.toDate();
                return exp == null || exp.isAfter(now);
              }).toList();
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No active status. Be the first to post one!',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final data = docs[i].data();
                  final created =
                      (data['createdAt'] as Timestamp?)?.toDate();
                  final authorName = _firstString(data, const [
                    'name',
                    'displayName',
                    'username',
                  ]);
                  final authorPhoto = _firstString(data, const [
                    'photoUrl',
                    'photoURL',
                    'photo',
                    'avatar',
                  ]);
                  final imageUrl =
                      (data['imageUrl'] as String?) ?? '';
                  return ListTile(
                    leading: AvatarWidget(
                      photoUrl:
                          authorPhoto.isEmpty ? null : authorPhoto,
                      name: authorName,
                    ),
                    title: Text(
                        authorName.isNotEmpty ? authorName : 'Someone'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (((data['text'] as String?) ?? '').isNotEmpty)
                          Text((data['text'] as String?) ?? ''),
                        if (imageUrl.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imageUrl,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image,
                                      color: Colors.grey),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Text(
                      statusRemaining(created),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
