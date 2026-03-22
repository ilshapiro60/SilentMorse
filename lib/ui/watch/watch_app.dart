import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wear/wear.dart';

import '../../services/auth_service.dart';
import '../../services/chat_repository.dart';
import '../../services/morse_settings_service.dart';
import 'watch_contacts_screen.dart';

/// Watch-optimized app for Wear OS.
/// Compact UI, morse tap to send, haptic receive.
class WatchApp extends StatelessWidget {
  const WatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => AuthService()),
        Provider<ChatRepository>(create: (_) => FirestoreChatRepository()),
        ChangeNotifierProvider(create: (_) => MorseSettingsService()),
      ],
      child: WatchShape(
        builder: (context, shape, child) {
          return AmbientMode(
            builder: (context, mode, child) {
              return MaterialApp(
                title: 'Silent Morse',
                debugShowCheckedModeBanner: false,
                theme: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFFFFC107),
                    surface: Color(0xFF121212),
                  ),
                  textTheme: Typography.whiteMountainView.apply(fontFamily: 'monospace'),
                ),
                home: mode == WearMode.active
                    ? const _WatchRouter()
                    : const _WatchAmbientScreen(),
              );
            },
          );
        },
      ),
    );
  }
}

class _WatchRouter extends StatelessWidget {
  const _WatchRouter();

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
        if (snapshot.data == null) {
          return const _WatchAuthScreen();
        }
        return const WatchContactsScreen();
      },
    );
  }
}

class _WatchAmbientScreen extends StatelessWidget {
  const _WatchAmbientScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          '··· −−− ···',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 14,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// Compact sign-in screen sized for a small round watch display.
class _WatchAuthScreen extends StatefulWidget {
  const _WatchAuthScreen();

  @override
  State<_WatchAuthScreen> createState() => _WatchAuthScreenState();
}

class _WatchAuthScreenState extends State<_WatchAuthScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().signInWithGoogle();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign-in failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              '·−· −·· ·−·',
              style: TextStyle(
                color: Color(0xFFFFC107),
                fontSize: 13,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Silent Morse',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton(
                onPressed: _loading ? null : _signIn,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Sign in with Google',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
