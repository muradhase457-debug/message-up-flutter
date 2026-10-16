import 'package:flutter/material.dart';

/// Calls tab — list UI + a call screen placeholder.
///
/// TODO (wiring, does NOT break the build): connect real voice/video calls
/// with flutter_webrtc. Steps when wiring:
///   1. Add `flutter_webrtc` to pubspec.yaml (deliberately NOT included
///      in this first native cut so the project builds as-is).
///   2. Add a signalling collection (e.g. `calls/{callId}` with offer /
///      answer / ICE candidates) in Firestore.
///   3. Replace [_CallPlaceholderSheet] with a real RTCVideoView +
///      RTCPeerConnection flow, and add microphone/camera permission
///      handling (permission_handler) + CallKit/ConnectionService for
///      incoming calls.
/// Until then this screen records call history locally in-memory only.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  final List<_CallEntry> _history = <_CallEntry>[];

  void _startFakeCall(String kind) {
    setState(() => _history.insert(
        0,
        _CallEntry(
            name: 'Demo contact', kind: kind, when: DateTime.now())));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _CallPlaceholderSheet(),
    );
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
                child: ElevatedButton.icon(
                  onPressed: () => _startFakeCall('Voice'),
                  icon: const Icon(Icons.call),
                  label: const Text('Voice call (UI preview)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _startFakeCall('Video'),
                  icon: const Icon(Icons.videocam),
                  label: const Text('Video call (UI preview)'),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Real WebRTC calling is a wiring TODO (see file header). '
              'The buttons above only preview the call UI.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
        Expanded(
          child: _history.isEmpty
              ? const Center(
                  child: Text('No calls yet.',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (context, i) {
                    final entry = _history[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(entry.kind == 'Video'
                            ? Icons.videocam
                            : Icons.call),
                      ),
                      title: Text(entry.name),
                      subtitle: Text('${entry.kind} · UI preview only'),
                      trailing: const Icon(Icons.call_made,
                          size: 16, color: Colors.green),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CallEntry {
  _CallEntry({required this.name, required this.kind, required this.when});

  final String name;
  final String kind;
  final DateTime when;
}

/// Placeholder in-call sheet: mute / speaker / end buttons, no media.
class _CallPlaceholderSheet extends StatelessWidget {
  const _CallPlaceholderSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
                radius: 44, child: Icon(Icons.person, size: 44)),
            const SizedBox(height: 12),
            const Text('Demo contact',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('Call UI preview — WebRTC wiring TODO',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _roundBtn(Icons.mic_off, 'Mute', () {}),
                _roundBtn(Icons.volume_up, 'Speaker', () {}),
                _roundBtn(Icons.call_end, 'End', () {
                  Navigator.pop(context);
                }, bg: Colors.red),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, String label, VoidCallback onTap,
      {Color? bg}) {
    return Column(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: bg ?? Colors.grey[200],
          child: IconButton(
            icon: Icon(icon, color: bg == null ? Colors.black87 : Colors.white),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
