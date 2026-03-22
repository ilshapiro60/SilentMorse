import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../services/chat_repository.dart';
import '../theme/silentmorse_theme.dart';
import 'watch_chat_screen.dart';

/// Compact contacts list for Wear OS.
class WatchContactsScreen extends StatefulWidget {
  const WatchContactsScreen({super.key});

  @override
  State<WatchContactsScreen> createState() => _WatchContactsScreenState();
}

class _WatchContactsScreenState extends State<WatchContactsScreen> {
  final _nameCache = <String, String>{};

  Future<void> _ensureName(Chat chat, String myUserId, ChatRepository repo) async {
    final otherId = chat.otherParticipant(myUserId);
    if (otherId.isEmpty || _nameCache.containsKey(otherId)) return;
    final user = await repo.getUserById(otherId);
    if (mounted) {
      setState(() {
        _nameCache[otherId] = user?.displayName ?? user?.username ?? 'Contact';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ChatRepository>();
    final myUserId = context.read<AuthService>().currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Silent Morse', style: TextStyle(fontFamily: 'monospace', fontSize: 14)),
        backgroundColor: inkDark,
        foregroundColor: Colors.white,
      ),
      backgroundColor: inkBlack,
      body: StreamBuilder<List<Chat>>(
        stream: repo.observeChats(),
        builder: (context, snapshot) {
          final chats = snapshot.data ?? [];
          if (chats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Add contacts on your phone',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              final otherId = chat.otherParticipant(myUserId);
              final contactName = _nameCache[otherId] ?? '...';
              _ensureName(chat, myUserId, repo);

              final chatTitle = chat.isGroup
                  ? (chat.name.isNotEmpty ? chat.name : 'Group')
                  : (_nameCache[otherId] ?? contactName);

              return ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: dotAmber.withValues(alpha: 0.5),
                  child: Text(
                    chatTitle.isNotEmpty ? chatTitle[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                title: Text(
                  chatTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: chat.lastMessage.isNotEmpty
                    ? Text(
                        chat.lastMessage,
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WatchChatScreen(
                        chatId: chat.id,
                        chatTitle: chatTitle,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
