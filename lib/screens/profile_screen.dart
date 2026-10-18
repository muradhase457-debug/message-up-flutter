import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:message_up/models/user_model.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/services/chat_service.dart';
import 'package:message_up/utils/time_format.dart';
import 'package:message_up/utils/validators.dart';
import 'package:message_up/widgets/avatar_widget.dart';
import 'package:provider/provider.dart';

/// Own profile: photo, name, email, about. Name/about are editable and
/// saved to the `users` document.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _editing = false;
  bool _saving = false;
  bool _photoSaving = false;
  late TextEditingController _nameController;
  late TextEditingController _aboutController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _aboutController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  void _startEdit(ChatUser user) {
    _nameController.text = user.displayName;
    _aboutController.text = user.about;
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    final nameError = validateDisplayName(_nameController.text);
    if (nameError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(nameError)));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AuthService>().updateProfile(
            displayName: _nameController.text.trim(),
            about: _aboutController.text.trim(),
          );
      if (mounted) setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Change profile photo: gallery -> Firebase Storage -> users doc.
  Future<void> _changePhoto() async {
    if (_photoSaving) return;
    final auth = context.read<AuthService>();
    final uid = auth.currentUid;
    if (uid == null) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _photoSaving = true);
    try {
      final url = await ChatService().uploadProfilePhoto(
        file: File(picked.path),
        myUid: uid,
      );
      await auth.updateProfile(photoUrl: url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo could not be updated.')),
        );
      }
    } finally {
      if (mounted) setState(() => _photoSaving = false);
    }
  }

  /// Display name with fallbacks: profile doc -> Google account ->
  /// email prefix. Never a blank name line.
  String _displayName(ChatUser shown, AuthService auth) {
    if (shown.displayName.isNotEmpty) return shown.displayName;
    final googleName = (auth.currentUser?.displayName ?? '').trim();
    if (googleName.isNotEmpty) return googleName;
    if (shown.email.isNotEmpty) return shown.email.split('@').first;
    return 'Message Up user';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<ChatUser?>(
      stream: auth.currentProfileStream(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final fallback = ChatUser(
          uid: auth.currentUid ?? '',
          displayName: auth.currentUser?.displayName ?? 'Message Up user',
          email: auth.currentUser?.email ?? '',
          photoUrl: auth.currentUser?.photoURL ?? '',
        );
        final shown = user ?? fallback;
        final displayName = _displayName(shown, auth);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AvatarWidget(
                    photoUrl:
                        shown.photoUrl.isEmpty ? null : shown.photoUrl,
                    name: displayName,
                    radius: 52,
                    online: shown.online,
                    showOnlineDot: true,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF075E54),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: _photoSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt,
                                size: 16, color: Colors.white),
                        tooltip: 'Change photo',
                        onPressed: _photoSaving ? null : _changePhoto,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!_editing) ...[
              Text(
                displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                shown.about.isEmpty ? 'Hey there! I am using Message Up.' : shown.about,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                shown.email,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _startEdit(shown),
                icon: const Icon(Icons.edit),
                label: const Text('Edit profile'),
              ),
            ] else ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _aboutController,
                decoration: const InputDecoration(
                    labelText: 'About', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => setState(() => _editing = false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            ListTile(
              leading: Icon(
                Icons.circle,
                color: shown.online
                    ? const Color(0xFF25D366)
                    : Colors.grey,
              ),
              title: Text(shown.online ? 'Online' : 'Offline'),
              subtitle: shown.lastSeen == null || shown.online
                  ? null
                  : Text('Last seen ${timeAgo(shown.lastSeen)}'),
            ),
          ],
        );
      },
    );
  }
}
