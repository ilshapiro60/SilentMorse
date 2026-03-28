import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/models.dart' hide User;
import 'services/auth_service.dart';
import 'services/morse_settings_service.dart';
import 'ui/auth/auth_screen.dart';
import 'ui/contacts/contacts_screen.dart';
import 'ui/chat/chat_screen.dart';
import 'util/morse_haptic_engine.dart';

/// Tracks which chat is currently open so the foreground FCM listener can skip
/// duplicate SnackBars / vibrations for that chat.
class GlobalReceiveState {
  static String? activeDarkModeChatId;
  /// Set while a normal (text-mode) chat screen is open.
  static String? activeChatId;
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  void initState() {
    super.initState();
    // Listen to FCM messages while the app is in the foreground.
    _fcmSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM] received: type=${message.data['type']}');
    final type = message.data['type'] as String?;

    if (type == 'chat_request') {
      // App is open — show a banner. The contacts Firestore stream will
      // already update the request list automatically.
      if (!mounted) return;
      final senderName =
          message.data['senderName'] as String? ?? 'Someone';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$senderName wants to chat with you'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => Navigator.of(context)
                .popUntil((route) => route.isFirst),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    if (type != 'message') return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.data()?['receiveIncoming'] == false) return;
      } catch (_) {}
    }

    if (!mounted) return;

    final chatId = message.data['chatId'] as String?;
    final morse = message.data['morse'] as String? ?? '';
    final text = message.data['text'] as String? ?? '';

    final settings = context.read<MorseSettingsService>().settings;

    final darkActive = GlobalReceiveState.activeDarkModeChatId;
    debugPrint('[FCM] chatId=$chatId darkActive=$darkActive '
        'activeChatId=${GlobalReceiveState.activeChatId} '
        'receiveMode=${settings.receiveMode} morse=${morse.isNotEmpty}');

    // Dark mode is tactile-only — ALWAYS vibrate regardless of receiveMode.
    if (chatId != null &&
        darkActive != null &&
        (darkActive == '__global__' || chatId == darkActive)) {
      if (morse.isNotEmpty) {
        debugPrint('[FCM] dark-mode vibrate!');
        MorseHapticEngine.playMorseString(morse, settings);
      }
      return;
    }

    // Normal text-mode chat is open — messages already visible via Firestore
    // StreamBuilder, so skip the SnackBar / vibration.
    if (chatId != null && chatId == GlobalReceiveState.activeChatId) {
      debugPrint('[FCM] text-mode chat open, suppressing');
      return;
    }

    if (settings.receiveMode == ReceiveMode.vibrate) {
      if (morse.isEmpty) return;
      debugPrint('[FCM] default vibrate');
      MorseHapticEngine.playMorseString(morse, settings);
    } else {
      if (text.isEmpty) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

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

        final user = snapshot.data;
        if (user == null) {
          return const AuthScreen();
        }

        return const ContactsScreen();
      },
    );
  }
}

void navigateToChat(BuildContext context, String chatId, String chatTitle,
    {bool isGroup = false}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => ChatScreen(
        chatId: chatId,
        chatTitle: chatTitle,
        isGroup: isGroup,
      ),
    ),
  );
}
