import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/ad_service.dart';
import 'services/auth_service.dart';
import 'services/chat_repository.dart' show ChatRepository, FirestoreChatRepository;
import 'services/morse_settings_service.dart';
import 'services/purchase_service.dart';

Future<void> _initFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e, st) {
    // Android auto-initializes from google-services.json before Dart runs.
    // Treat duplicate-app as success.
    if (e.toString().contains('duplicate-app') || e.toString().contains('already exists')) {
      return;
    }
    debugPrint('Firebase init error: $e');
    debugPrint('Stack trace: $st');
    rethrow;
  }
}

final _firebaseInitFuture = _initFirebase();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAdMob();
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
        future: _firebaseInitFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasError) {
              return _FirebaseErrorScreen(error: snapshot.error);
            }
            return const SilentMorseApp();
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}

class _FirebaseErrorScreen extends StatelessWidget {
  final Object? error;

  const _FirebaseErrorScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.amber),
              const SizedBox(height: 24),
              Text(
                'Firebase Setup Required',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Silent Morse needs Firebase to be configured.\n\n'
                '1. Create a project at console.firebase.google.com\n'
                '2. Add Android app (bundle: com.silentmorse.messenger) and iOS app\n'
                '3. Download google-services.json and GoogleService-Info.plist\n'
                '4. Or run: flutterfire configure',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (error != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Error: $error',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
