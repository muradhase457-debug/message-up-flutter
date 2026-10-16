import 'package:flutter/material.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:provider/provider.dart';

/// Sign-in screen. Google only — no passwords anywhere in this app.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().signInWithGoogle();
      // AuthGate switches to Home automatically on authStateChanges.
    } catch (e) {
      // DIAGNOSTIC (temporary): show the REAL failure reason on screen
      // (e.g. ApiException 10 = signature/fingerprint mismatch) instead
      // of a generic message, so the exact cause can be identified.
      if (mounted) {
        setState(() => _error = 'Sign-in failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF075E54),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.chat_bubble,
                  size: 88, color: Color(0xFF25D366)),
              const SizedBox(height: 16),
              const Text(
                'Message Up',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'WhatsApp + Messenger + Facebook — one app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.login, color: Colors.white),
                label: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Continue with Google',
                        style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                SelectableText(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white)),
              ],
              const SizedBox(height: 32),
              const Text(
                'By continuing you agree to the Terms and Privacy Policy.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
