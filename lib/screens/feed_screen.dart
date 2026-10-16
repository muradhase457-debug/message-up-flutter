import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/utils/constants.dart';
import 'package:message_up/utils/time_format.dart';
import 'package:message_up/widgets/avatar_widget.dart';
import 'package:provider/provider.dart';

/// Facebook-style Feed, wired to Firestore `posts`:
/// create post, like/unlike, comment. Posts are newest first.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _posts =>
      FirebaseFirestore.instance.collection(AppConstants.postsCollection);

  Future<void> _createPost() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _posting) return;
    final auth = context.read<AuthService>();
    final uid = auth.currentUid;
    if (uid == null) return;
    setState(() => _posting = true);
    try {
      await _posts.add(<String, dynamic>{
        'authorId': uid,
        'authorName': auth.currentUser?.displayName ?? '',
        'authorPhoto': auth.currentUser?.photoURL ?? '',
        'text': text,
        'likes': <String>[],
        'commentCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _composer.clear();
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _toggleLike(
      String postId, List<String> likes, String myUid) async {
    final ref = _posts.doc(postId);
    if (likes.contains(myUid)) {
      await ref.update(<String, dynamic>{
        'likes': FieldValue.arrayRemove(<String>[myUid])
      });
    } else {
      await ref.update(<String, dynamic>{
        'likes': FieldValue.arrayUnion(<String>[myUid])
      });
    }
  }

  Future<void> _addComment(String postId) async {
    final controller = TextEditingController();
    try {
      final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a comment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Write a comment…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    final auth = context.read<AuthService>();
    final uid = auth.currentUid;
    if (uid == null) return;
    await _posts.doc(postId).collection('comments').add(<String, dynamic>{
      'authorId': uid,
      'authorName': auth.currentUser?.displayName ?? '',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _posts.doc(postId).update(<String, dynamic>{
      'commentCount': FieldValue.increment(1),
    });
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = context.read<AuthService>().currentUid ?? '';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  decoration: InputDecoration(
                    hintText: "What's on your mind?",
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _posting ? null : _createPost,
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
            stream: _posts
                .orderBy('createdAt', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text('Could not load feed.'));
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No posts yet. Be the first to post!',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data();
                  final rawLikes = data['likes'];
                  final likes = rawLikes is List
                      ? rawLikes.map((e) => e.toString()).toList()
                      : <String>[];
                  final liked = likes.contains(myUid);
                  final created =
                      (data['createdAt'] as Timestamp?)?.toDate();
                  return Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AvatarWidget(
                                photoUrl: (data['authorPhoto'] as String?)
                                            ?.isNotEmpty ==
                                        true
                                    ? data['authorPhoto'] as String
                                    : null,
                                name: (data['authorName'] as String?) ?? '',
                                radius: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (data['authorName'] as String?) ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      timeAgo(created),
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text((data['text'] as String?) ?? ''),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _toggleLike(
                                    doc.id, likes, myUid),
                                icon: Icon(
                                  liked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: liked ? Colors.red : null,
                                  size: 20,
                                ),
                                label: Text('${likes.length}'),
                              ),
                              TextButton.icon(
                                onPressed: () => _addComment(doc.id),
                                icon: const Icon(Icons.comment_outlined,
                                    size: 20),
                                label: Text(
                                    '${(data['commentCount'] as num?)?.toInt() ?? 0}'),
                              ),
                            ],
                          ),
                        ],
                      ),
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
