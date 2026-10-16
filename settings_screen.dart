import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:message_up/utils/constants.dart';
import 'package:message_up/utils/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings: theme, speed mode, ghost mode, vault PIN, app lock.
/// All persisted with SharedPreferences. The vault PIN is stored ONLY
/// as a SHA-256 hash — never the PIN itself.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SharedPreferences? _prefs;
  bool _dark = false;
  bool _speedMode = false;
  bool _ghostMode = false;
  bool _appLock = false;
  bool _hasVaultPin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _dark = prefs.getBool(AppConstants.keyThemeDark) ?? false;
      _speedMode = prefs.getBool(AppConstants.keySpeedMode) ?? false;
      _ghostMode = prefs.getBool(AppConstants.keyGhostMode) ?? false;
      _appLock = prefs.getBool(AppConstants.keyAppLockEnabled) ?? false;
      _hasVaultPin =
          (prefs.getString(AppConstants.keyVaultPinHash) ?? '').isNotEmpty;
    });
  }

  Future<void> _setPin() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Vault PIN (4–6 digits)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
          decoration:
              const InputDecoration(hintText: 'Enter PIN'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (pin == null) return;
    if (!isValidPin(pin)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('PIN must be 4–6 digits.')),
        );
      }
      return;
    }
    final hash = sha256.convert(utf8.encode('mu-vault:$pin')).toString();
    await _prefs?.setString(AppConstants.keyVaultPinHash, hash);
    if (mounted) {
      setState(() => _hasVaultPin = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vault PIN saved (as a hash).')),
      );
    }
  }

  Future<void> _removePin() async {
    await _prefs?.remove(AppConstants.keyVaultPinHash);
    if (mounted) {
      setState(() => _hasVaultPin = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vault PIN removed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _prefs == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Dark theme'),
                  subtitle: const Text('Midnight look for night chats'),
                  value: _dark,
                  onChanged: (v) async {
                    await _prefs!
                        .setBool(AppConstants.keyThemeDark, v);
                    if (!mounted) return;
                    setState(() => _dark = v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Speed mode'),
                  subtitle: const Text(
                      'Tap-to-load images, lighter feed — saves data'),
                  value: _speedMode,
                  onChanged: (v) async {
                    await _prefs!
                        .setBool(AppConstants.keySpeedMode, v);
                    if (!mounted) return;
                    setState(() => _speedMode = v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Ghost mode'),
                  subtitle: const Text(
                      'Hide online status and read receipts from others'),
                  value: _ghostMode,
                  onChanged: (v) async {
                    await _prefs!
                        .setBool(AppConstants.keyGhostMode, v);
                    if (!mounted) return;
                    setState(() => _ghostMode = v);
                  },
                ),
                SwitchListTile(
                  title: const Text('App lock'),
                  subtitle: const Text(
                      'Ask for the Vault PIN when the app opens'),
                  value: _appLock,
                  onChanged: (v) async {
                    if (v && !_hasVaultPin) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Set a Vault PIN first, then enable App lock.')),
                      );
                      return;
                    }
                    await _prefs!.setBool(
                        AppConstants.keyAppLockEnabled, v);
                    if (!mounted) return;
                    setState(() => _appLock = v);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: Text(_hasVaultPin
                      ? 'Vault PIN is set'
                      : 'Set Vault PIN'),
                  subtitle: const Text(
                      'Stored only as a SHA-256 hash, never as the PIN itself'),
                  trailing: _hasVaultPin
                      ? TextButton(
                          onPressed: _removePin,
                          child: const Text('Remove'),
                        )
                      : null,
                  onTap: _setPin,
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                  subtitle: Text('Message Up 1.0.0 — native Flutter build.\n'
                      'Sign-in is Google only. No passwords anywhere.'),
                ),
              ],
            ),
    );
  }
}
