import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:message_up/models/call_model.dart';
import 'package:message_up/models/user_model.dart';
import 'package:message_up/screens/call_screen.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/services/call_service.dart';
import 'package:message_up/utils/constants.dart';
import 'package:message_up/utils/time_format.dart';
import 'package:message_up/widgets/avatar_widget.dart';
import 'package:provider/provider.dart';

/// Calls tab: real 1:1 voice/video call history (from Firestore `calls`),
/// plus New call -> pick a contact -> voice/video.
///
/// History merges two single-field queries (outgoing + incoming) and
/// sorts client-side — two `where` filters on different fields would
/// need a composite Firestore index.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  /// Start a call to [peer]: create the ringing doc, then open the
  /// call screen (caller side — it writes the offer).
  Future<void> _startCall(ChatUser peer, String type) async {
    final auth = context.read<AuthService>();
    final myUid = auth.currentUid;
    if (myUid == null) return;
    final myName = auth.currentUser?.displayName ?? '';
    final callService = CallService();
    try {
      final callId = await callService.startCall(
        callerId: myUid,
        callerName: myName,
        calleeId: peer.uid,
        calleeName: peer.displayName,
        type: type,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            callId: callId,
            isCaller: true,
            peerName: peer.displayName,
            peerPhoto: peer.photoUrl,
            isVideo: type == 'video',
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

  /// Contact picker: everyone in `users` except me.
  Future<void> _pickContact() async {
    final auth = context.read<AuthService>();
    final myUid = auth.currentUid ?? '';
    final snap = await FirebaseFirestore.instance
        .collection(AppConstants.usersCollection)
        .limit(100)
        .get();
    final users = snap.docs
        .map(ChatUser.fromDoc)
        .where((u) => u.uid != myUid)
        .toList();
    if (!mounted) return;
    if (users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No contacts yet — ask a friend to sign in.')),
      );
      return;
    }
    final picked = await showDialog<ChatUser>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New call'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: users.length,
            itemBuilder: (_, i) {
              final user = users[i];
              return ListTile(
                leading: AvatarWidget(
                  photoUrl:
                      user.photoUrl.isEmpty ? null : user.photoUrl,
                  name: user.displayName,
                  radius: 20,
                ),
                title: Text(
                  user.displayName.isNotEmpty
                      ? user.displayName
                      : 'User',
                ),
                subtitle: Text(user.email),
                onTap: () => Navigator.pop(ctx, user),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Call ${picked.displayName}'),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'voice'),
              icon: const Icon(Icons.call),
              label: const Text('Voice'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'video'),
              icon: const Icon(Icons.videocam),
              label: const Text('Video'),
            ),
          ],
        ),
      ),
    );
    if (type != null) {
      await _startCall(picked, type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = context.read<AuthService>().currentUid ?? '';
    final callService = CallService();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pickContact,
              icon: const Icon(Icons.add_call),
              label: const Text('New call'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<CallDoc>>(
            stream: callService.outgoingHistory(myUid),
            builder: (context, outSnap) {
              return StreamBuilder<List<CallDoc>>(
                stream: callService.incomingHistory(myUid),
                builder: (context, inSnap) {
                  final calls = <CallDoc>[
                    ...(outSnap.data ?? <CallDoc>[]),
                    ...(inSnap.data ?? <CallDoc>[]),
                  ];
                  calls.sort((a, b) {
                    final at =
                        a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bt =
                        b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return bt.compareTo(at);
                  });
                  if (calls.isEmpty) {
                    return const Center(
                      child: Text('No calls yet.',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return ListView.builder(
                    itemCount: calls.length,
                    itemBuilder: (context, i) {
                      final call = calls[i];
                      final outgoing = call.callerId == myUid;
                      final peer = call.peerName(myUid);
                      final missed = !outgoing &&
                          !call.answered &&
                          call.isOver;
                      final subtitle = _subtitle(call, outgoing, missed);
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(call.isVideo
                              ? Icons.videocam
                              : Icons.call),
                        ),
                        title: Text(
                            peer.isNotEmpty ? peer : 'User'),
                        subtitle: Text(subtitle),
                        trailing: Icon(
                          outgoing
                              ? Icons.call_made
                              : Icons.call_received,
                          size: 16,
                          color: missed
                              ? Colors.red
                              : const Color(0xFF25D366),
                        ),
                        onTap: () {
                          // Re-call this person (name may be stale in the
                          // old doc, so look the contact up fresh).
                          _recall(call, outgoing, myUid);
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _subtitle(CallDoc call, bool outgoing, bool missed) {
    final when = timeAgo(call.createdAt);
    if (missed) return 'Missed · $when';
    if (call.isRinging) return 'Ringing… · $when';
    if (call.status == 'declined') return 'Declined · $when';
    final dur = call.durationSeconds;
    final durText = dur >= 60
        ? '${dur ~/ 60}m ${dur % 60}s'
        : '${dur}s';
    final dir = outgoing ? 'Outgoing' : 'Incoming';
    return '$dir · $durText · $when';
  }

  /// Re-call: find the peer's current profile, then start a fresh call.
  Future<void> _recall(CallDoc call, bool outgoing, String myUid) async {
    final peerId = outgoing ? call.calleeId : call.callerId;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(peerId)
          .get();
      if (!doc.exists || !mounted) return;
      final peer = ChatUser.fromDoc(doc);
      await _startCall(peer, call.type);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reach this contact.')),
        );
      }
    }
  }
}
