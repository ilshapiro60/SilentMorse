import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart' as models;
import '../../services/auth_service.dart';
import '../../services/chat_repository.dart';
import '../../services/morse_settings_service.dart';
import 'dark_screen_mode.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final bool isGroup;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
    this.isGroup = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  bool _isDarkScreenActive = false;
  DateTime? _clearedAt;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ChatRepository>();
    final myUserId = context.read<AuthService>().currentUser?.uid ?? '';
    final settings = context.read<MorseSettingsService>().settings;

    if (_isDarkScreenActive) {
      final senderName = context.read<MorseSettingsService>().senderDisplayName;
      return DarkScreenMode(
        chatId: widget.chatId,
        settings: settings,
        onSendMessage: (text) {
          repo.sendMessage(widget.chatId, text,
              senderDisplayName:
                  senderName.isNotEmpty ? senderName : null);
        },
        onUnsend: () async {
          final msg = await repo.getLastMyMessage(widget.chatId);
          if (msg != null) {
            await repo.deleteMessage(widget.chatId, msg.id);
          }
        },
        onExit: () => setState(() => _isDarkScreenActive = false),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chatTitle, style: Theme.of(context).textTheme.titleMedium),
            Text('Silent Morse', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: 'Clear screen',
            onPressed: () => setState(() => _clearedAt = DateTime.now()),
          ),
          Tooltip(
            message: 'Dark mode: tap = dot, long press = dash, swipe up = send, two fingers = exit',
            child: IconButton(
              icon: Icon(Icons.dark_mode, color: Theme.of(context).colorScheme.primary),
              onPressed: () => setState(() => _isDarkScreenActive = true),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .snapshots(),
        builder: (context, chatSnap) {
          final chatData = chatSnap.data?.data() as Map<String, dynamic>? ?? {};
          final status = models.ChatStatus.fromString(chatData['status'] as String?);
          final requesterId = chatData['requesterId'] as String? ?? '';
          final isPending = status == models.ChatStatus.pending;
          final iAmRequester = requesterId == myUserId;
          final canSend = !isPending;

          return Column(
            children: [
              if (isPending)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_top, size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          iAmRequester
                              ? 'Waiting for ${widget.chatTitle} to accept your chat request…'
                              : '${widget.chatTitle} wants to chat with you',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (!iAmRequester) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => repo.approveChat(widget.chatId),
                          child: const Text('Accept'),
                        ),
                        TextButton(
                          onPressed: () {
                            repo.declineChat(widget.chatId);
                            Navigator.of(context).pop();
                          },
                          child: Text('Decline',
                              style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: StreamBuilder<List<models.Message>>(
                  stream: repo.observeMessages(widget.chatId),
                  builder: (context, snapshot) {
                    final clearedAt = _clearedAt;
                    final messages = (snapshot.data ?? [])
                        .where((m) => clearedAt == null ||
                            (m.sentAt != null && m.sentAt!.isAfter(clearedAt)))
                        .toList();

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: messages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == messages.length) {
                          return const SizedBox(height: 8);
                        }
                        final message = messages[index];
                        final isFromMe = message.senderId == myUserId;

                        return _MessageBubble(
                          message: message,
                          isFromMe: isFromMe,
                          showSenderName: widget.isGroup && !isFromMe,
                          repo: repo,
                        );
                      },
                    );
                  },
                ),
              ),
              _ChatInputBar(
                controller: _inputController,
                enabled: canSend,
                onSend: canSend ? () {
                  final text = _inputController.text.trim();
                  if (text.isNotEmpty) {
                    final senderName = context.read<MorseSettingsService>().senderDisplayName;
                    repo.sendMessage(widget.chatId, text, senderDisplayName: senderName.isNotEmpty ? senderName : null);
                    _inputController.clear();
                  }
                } : null,
                onDarkMode: canSend ? () => setState(() => _isDarkScreenActive = true) : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SenderNameLabel extends StatelessWidget {
  final String senderDisplayName;
  final String senderId;
  final ChatRepository? repo;

  const _SenderNameLabel({
    required this.senderDisplayName,
    required this.senderId,
    this.repo,
  });

  @override
  Widget build(BuildContext context) {
    if (senderDisplayName.isNotEmpty) {
      return Text(
        senderDisplayName,
        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
      );
    }
    if (repo == null) return const SizedBox.shrink();
    return FutureBuilder<models.User?>(
      future: repo!.getUserById(senderId),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final name = user?.displayName ?? user?.username ?? 'Unknown';
        return Text(
          name,
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final models.Message message;
  final bool isFromMe;
  final bool showSenderName;
  final ChatRepository? repo;

  const _MessageBubble({
    required this.message,
    required this.isFromMe,
    this.showSenderName = false,
    this.repo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: isFromMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showSenderName)
              Padding(
                padding: const EdgeInsets.only(bottom: 2, left: 4),
                child: _SenderNameLabel(
                  senderDisplayName: message.senderDisplayName,
                  senderId: message.senderId,
                  repo: repo,
                ),
              ),
            Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isFromMe
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isFromMe ? 16 : 4),
                  bottomRight: Radius.circular(isFromMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isFromMe ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (message.morse.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      message.morse,
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: (isFromMe ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant).withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isFromMe)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Icon(
                  message.isRead ? Icons.done_all : (message.isDelivered ? Icons.done_all : Icons.done),
                  size: 14,
                  color: message.isRead ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSend;
  final VoidCallback? onDarkMode;
  final bool enabled;

  const _ChatInputBar({
    required this.controller,
    required this.onSend,
    required this.onDarkMode,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Tooltip(
                message: 'Dark mode: tap = dot, long press = dash, swipe up = send, two fingers = exit',
                child: IconButton(
                  icon: Icon(Icons.dark_mode, color: Theme.of(context).colorScheme.primary),
                  onPressed: onDarkMode,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: enabled ? 'Type a message...' : 'Chat not yet approved',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onSubmitted: enabled ? (_) => onSend?.call() : null,
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                onPressed: enabled ? onSend : null,
                backgroundColor: enabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(Icons.send,
                    color: enabled ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
