import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:message_up/firebase_options.dart';
import 'package:message_up/screens/home_screen.dart';
import 'package:message_up/screens/login_screen.dart';
import 'package:message_up/services/admin_service.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/services/chat_service.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // If Firebase was never configured (template firebase_options.dart),
  // do NOT crash with a red screen: show the setup screen instead,
  // with the exact steps to finish setup.
  String? firebaseInitError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    firebaseInitError = e.toString();
  }
  runApp(MessageUpApp(firebaseInitError: firebaseInitError));
}

class MessageUpApp extends StatelessWidget {
  const MessageUpApp({super.key, this.firebaseInitError});

  /// Non-null when Firebase could not initialise (setup not finished).
  final String? firebaseInitError;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<ChatService>(create: (_) => ChatService()),
        Provider<AdminService>(create: (_) => AdminService()),
      ],
      child: MaterialApp(
        title: 'Message Up',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF075E54),
            primary: const Color(0xFF075E54),
            secondary: const Color(0xFF25D366),
          ),
          primaryColor: const Color(0xFF075E54),
          scaffoldBackgroundColor: const Color(0xFFECE5DD),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF075E54),
            foregroundColor: Colors.white,
            elevation: 2,
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Colors.white,
            selectedItemColor: Color(0xFF075E54),
            unselectedItemColor: Colors.grey,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF25D366),
            foregroundColor: Colors.white,
          ),
        ),
        darkTheme: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF075E54),
            brightness: Brightness.dark,
            primary: const Color(0xFF25D366),
            secondary: const Color(0xFF25D366),
          ),
          scaffoldBackgroundColor: const Color(0xFF0B141A),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0B141A),
            foregroundColor: Colors.white,
          ),
        ),
        themeMode: ThemeMode.system,
        home: firebaseInitError != null
            ? SetupNeededScreen(error: firebaseInitError!)
            : const AuthGate(),
      ),
    );
  }
}

/// Shown instead of a crash when Firebase is not configured yet.
/// Lists the exact setup steps — no red screen, no stack trace.
class SetupNeededScreen extends StatelessWidget {
  const SetupNeededScreen({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF075E54),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.build, size: 64, color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                'Setup baki ache',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '1. Firebase Console theke google-services.json namiye repo root-e rakho.\n'
                '2. lib/firebase_options.dart-e Firebase Console-er asol value boshao.\n'
                '3. Codemagic-e rebuild dao, tarpor APK install koro.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text(
                'Technical detail: $error',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Routes to Home when signed in, Login when signed out.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: context.read<AuthService>().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
