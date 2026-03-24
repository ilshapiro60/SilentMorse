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

/// Tracks which chat is currently shown in DarkScreenMode so the global
/// foreground listener skips double-vibration for that chat.
class GlobalReceiveState {
  static String? activeDarkModeChatId;
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

    // Dark-screen UIs handle incoming via Firestore; skip FCM to avoid double
    // vibrate. Global mode uses activeDarkModeChatId == '__global__'.
    final active = GlobalReceiveState.activeDarkModeChatId;
    if (chatId != null &&
        active != null &&
        (active == '__global__' || chatId == active)) {
      return;
    }

    final settings = context.read<MorseSettingsService>().settings;
    if (settings.receiveMode == ReceiveMode.vibrate) {
      if (morse.isEmpty) return;
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
