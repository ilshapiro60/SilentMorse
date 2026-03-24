import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'ui/watch/watch_app.dart';
import 'services/ad_service.dart';
import 'services/auth_service.dart';
import 'services/chat_repository.dart' show ChatRepository, FirestoreChatRepository;
import 'services/morse_settings_service.dart';
import 'services/purchase_service.dart';

/// Initialise Firebase.  On iOS the native SDK auto-configures from
/// GoogleService-Info.plist during plugin registration, so we must NOT pass
/// explicit [FirebaseOptions] (that triggers a second native configure →
/// uncatchable NSException → SIGABRT).  Android needs the Dart-side options.
Future<void> _initFirebase() async {
  try {
    if (Platform.isIOS) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e) {
    debugPrint('Firebase init: $e');
  }
}

/// Top-level background message handler — runs in a separate isolate.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Platform.isIOS) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (_) {}
  if (message.data['type'] == 'message') {
    try {
      await Vibration.vibrate(duration: 400);
    } catch (_) {}
  }
}

late final Future<void> _firebaseReady;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start Firebase init but do NOT await — runApp must be called immediately
  // so the user sees UI.  A 10-second timeout prevents an infinite hang on iOS
  // if the method-channel call never returns.
  _firebaseReady = _initFirebase().timeout(
    const Duration(seconds: 10),
    onTimeout: () => debugPrint('Firebase init timed out after 10 s'),
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const _SilentMorseAppLoader());
}

class _SilentMorseAppLoader extends StatelessWidget {
  const _SilentMorseAppLoader();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: FutureBuilder<void>(
        future: _firebaseReady,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.amber),
                    SizedBox(height: 16),
                    Text(
                      'Starting Silent Morse…',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final isWatch =
                  constraints.maxWidth < 500 && constraints.maxHeight < 500;
              if (isWatch) return const WatchApp();
              return const _PhoneAppWithAdMob(child: SilentMorseApp());
            },
          );
        },
      ),
    );
  }
}

/// Initializes AdMob only on phone (Wear OS lacks WebView and crashes).
class _PhoneAppWithAdMob extends StatefulWidget {
  final Widget child;

  const _PhoneAppWithAdMob({required this.child});

  @override
  State<_PhoneAppWithAdMob> createState() => _PhoneAppWithAdMobState();
}

class _PhoneAppWithAdMobState extends State<_PhoneAppWithAdMob> {
  @override
  void initState() {
    super.initState();
    initAdMob().catchError((e) => debugPrint('AdMob init: $e'));
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    // Request permission after the app is visible — never block runApp.
    await FirebaseMessaging.instance.requestPermission();
    await AuthService().refreshFcmToken();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SilentMorseApp extends StatelessWidget {
  const SilentMorseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => AuthService()),
        Provider<ChatRepository>(create: (_) => FirestoreChatRepository()),
        ChangeNotifierProvider(create: (_) => MorseSettingsService()),
        ChangeNotifierProvider(create: (_) => PurchaseService()),
      ],
      child: MaterialApp(
        title: 'Silent Morse',
        debugShowCheckedModeBanner: false,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: ThemeMode.dark,
        home: const AppRouter(),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7B5800),
        brightness: Brightness.light,
        primary: const Color(0xFF7B5800),
      ),
      fontFamily: 'monospace',
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFFC107),
        brightness: Brightness.dark,
        primary: const Color(0xFFFFC107),
        surface: const Color(0xFF121212),
      ),
      fontFamily: 'monospace',
    );
  }
}
