import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/utils/constants.dart';
import 'package:message_up/utils/time_format.dart';
import 'package:message_up/widgets/avatar_widget.dart';
import 'package:provider/provider.dart';

/// 24-hour status (stories). Items older than 24h are hidden.
/// Post = text status for now; photo status uploads come with
/// image_picker + Firebase Storage in the next cut.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _posting = false;

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
                  return ListTile(
                    leading: AvatarWidget(
                      photoUrl: (data['photoUrl'] as String?)?.isNotEmpty == true
                          ? data['photoUrl'] as String
                          : null,
                      name: (data['name'] as String?) ?? '',
                    ),
                    title: Text((data['name'] as String?) ?? 'Someone'),
                    subtitle: Text((data['text'] as String?) ?? ''),
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
