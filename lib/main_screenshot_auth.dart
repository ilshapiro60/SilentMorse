/// Entry point for Auth screen screenshot. No user signed in.
/// Run: flutter drive --driver=test_driver/integration_test.dart --target=lib/main_screenshot_auth.dart -d <device>

import 'package:flutter/material.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'services/chat_repository.dart';
import 'services/morse_settings_service.dart';
import 'screenshot/mock_services.dart';
import 'ui/auth/auth_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final mockAuth = MockFirebaseAuth(signedIn: false);

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
      home: const AuthScreen(),
    ),
  ));
}
