/// Entry point for screenshot capture. Uses mocks, no Firebase.
/// Run: flutter run -t lib/main_screenshot.dart
/// Or: flutter drive --driver=test_driver/integration_test.dart --target=lib/main_screenshot.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'services/chat_repository.dart';
import 'services/morse_settings_service.dart';
import 'screenshot/mock_services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final mockUser = MockUser(
    uid: 'screenshot-user',
    email: 'demo@silentmorse.app',
    displayName: 'Demo User',
    photoURL: null,
  );
  final mockAuth = MockFirebaseAuth(mockUser: mockUser);

  runApp(MultiProvider(
    providers: [
      Provider<AuthService>(create: (_) => AuthService(auth: mockAuth)),
      Provider<ChatRepository>(create: (_) => MockChatRepository()),
      ChangeNotifierProvider(create: (_) => MorseSettingsService()),
    ],
    child: MaterialApp(
      title: 'Silent Morse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFC107),
          brightness: Brightness.dark,
          primary: const Color(0xFFFFC107),
          surface: const Color(0xFF121212),
        ),
        fontFamily: 'monospace',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFC107),
          brightness: Brightness.dark,
          primary: const Color(0xFFFFC107),
          surface: const Color(0xFF121212),
        ),
        fontFamily: 'monospace',
      ),
      themeMode: ThemeMode.dark,
      home: const AppRouter(),
    ),
  ));
}
