import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'ui/auth/auth_screen.dart';
import 'ui/contacts/contacts_screen.dart';
import 'ui/chat/chat_screen.dart';

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

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

void navigateToChat(BuildContext context, String chatId, String chatTitle, {bool isGroup = false}) {
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
