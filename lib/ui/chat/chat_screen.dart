import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app.dart';
import '../../data/models.dart' as models;
import '../../services/auth_service.dart';
import '../../services/chat_repository.dart';
import '../../services/morse_settings_service.dart';
import 'dark_screen_mode.dart';
import 'telegraph_chat_theme.dart';

/// v2: cutoff is latest message [sentAt] from Firestore (not device clock), so
/// server timestamps compare correctly. v1 used DateTime.now() and could hide
/// all recent messages when the phone clock was ahead of the server.
String _broomClearedPrefsKey(String chatId) => 'chat_broom_cleared_ms_v2_$chatId';

/// v3: cutoff in microseconds since epoch (full precision). New brooms store
/// [latestSentAt + 1µs] so `sentAt.isAfter(cutoff)` stays true for the next
/// message after `serverTimestamp()` resolves (avoids strict-equality / ms
/// truncation glitches that made bubbles flash then vanish).
String _broomClearedUsPrefsKey(String chatId) => 'chat_broom_cleared_us_v3_$chatId';

/// Pre-v2 key — migrated once on load so “clear screen” survives app updates.
String _broomClearedLegacyPrefsKey(String chatId) => 'chat_broom_cleared_ms_$chatId';

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
  /// `false`: no broom prefs, no cutoff filter, no app-bar broom — isolates the
  /// vanishing-bubble bug from stale local cutoffs. Set `true` to restore.
  static const bool _kBroomFeatureEnabled = false;

  /// Without broom: show only the latest N bubbles. After broom: no cap — only
  /// post-clear messages, all of them (no rolling backlog).
  static const int _kMaxVisibleMessages = 200;

  final _inputController = TextEditingController();
  /// Reuse one stream per [chatId] so that [StreamBuilder] never resets its
  /// subscription when [build] is called again (e.g. after [setState]).
  Stream<List<models.Message>>? _messagesStream;
  String? _messagesStreamChatId;
  Stream<DocumentSnapshot>? _chatDocStream;
  bool _isDarkScreenActive = false;
  DateTime? _clearedAt;
  /// Message ids we just wrote; always shown until [sentAt] clears the broom cutoff
  /// normally (avoids bubble flashing then vanishing when cutoff vs server time races).
  final Set<String> _broomBypassIds = {};
  final Set<String> _pendingBypassPrune = {};
  bool _broomPruneScheduled = false;

  @override
  void initState() {
    super.initState();
    GlobalReceiveState.activeChatId = widget.chatId;
    if (_kBroomFeatureEnabled) {
      _loadPersistedBroomClear();
    } else {
      _clearBroomPrefsForChat();
    }
  }

  /// Drops any saved broom cutoff for this chat so older installs (e.g. receiver)
  /// cannot hide new messages after [sentAt] resolves.
  Future<void> _clearBroomPrefsForChat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_broomClearedUsPrefsKey(widget.chatId));
    await prefs.remove(_broomClearedPrefsKey(widget.chatId));
    await prefs.remove(_broomClearedLegacyPrefsKey(widget.chatId));
  }

  Future<void> _loadPersistedBroomClear() async {
    final prefs = await SharedPreferences.getInstance();
    final v3Key = _broomClearedUsPrefsKey(widget.chatId);
    final us = prefs.getInt(v3Key);
    if (us != null) {
      if (mounted) {
        setState(() {
          _clearedAt = DateTime.fromMicrosecondsSinceEpoch(us);
        });
      }
      return;
    }

    final v2Key = _broomClearedPrefsKey(widget.chatId);
    int? ms = prefs.getInt(v2Key);
    if (ms == null) {
      final legacyMs = prefs.getInt(_broomClearedLegacyPrefsKey(widget.chatId));
      if (legacyMs != null) {
        ms = legacyMs;
        await prefs.setInt(v2Key, legacyMs);
        await prefs.remove(_broomClearedLegacyPrefsKey(widget.chatId));
      }
    }
    if (ms != null && mounted) {
      setState(() {
        _clearedAt = DateTime.fromMillisecondsSinceEpoch(ms!);
      });
    }
  }

  /// Latest [sentAt] in the thread (server time), for a broom cutoff aligned with [Message.sentAt].
  static Future<DateTime?> _latestMessageSentAt(String chatId) async {
    final snap = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final t = snap.docs.first.data()['sentAt'];
    if (t is! Timestamp) return null;
    return t.toDate();
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _broomBypassIds.clear();
      _pendingBypassPrune.clear();
      _messagesStream = null;
      _messagesStreamChatId = null;
      _chatDocStream = null;
      GlobalReceiveState.activeChatId = widget.chatId;
    }
  }

  Stream<List<models.Message>> _messagesStreamFor(ChatRepository repo) {
    if (_messagesStreamChatId != widget.chatId) {
      _messagesStreamChatId = widget.chatId;
      _messagesStream = repo.observeMessages(widget.chatId);
    }
    return _messagesStream!;
  }

  @override
  void dispose() {
    _inputController.dispose();
    if (GlobalReceiveState.activeChatId == widget.chatId) {
      GlobalReceiveState.activeChatId = null;
    }
    super.dispose();
  }

  void _registerSentMessageId(String id) {
    if (!mounted) return;
    setState(() => _broomBypassIds.add(id));
  }

  void _queueBypassPrune(Iterable<String> ids) {
    final add = ids.where((id) => id.isNotEmpty).toSet();
    if (add.isEmpty) return;
    _pendingBypassPrune.addAll(add);
    if (_broomPruneScheduled) return;
    _broomPruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _broomPruneScheduled = false;
      if (!mounted || _pendingBypassPrune.isEmpty) return;
      final todo = Set<String>.from(_pendingBypassPrune);
      _pendingBypassPrune.clear();
      setState(() => _broomBypassIds.removeAll(todo));
    });
  }

  bool _passesBroomFilter(models.Message m, DateTime? clearedAt) {
    if (_broomBypassIds.contains(m.id)) return true;
    if (clearedAt == null) return true;
    if (m.sentAt == null) return true;
    return m.sentAt!.isAfter(clearedAt);
  }

  /// [observeMessages] uses ascending [sentAt]. Pending [serverTimestamp] docs
  /// often have [sentAt] null and sort *first*, so taking the last N by index
  /// drops the newest outgoing bubbles until [sentAt] resolves — then they
  /// can wrongly disappear if combined with the broom filter.
  List<models.Message> _applyMaxVisibleMessages(
    List<models.Message> messages,
    int maxVisible,
  ) {
    if (messages.length <= maxVisible) return messages;
    final sorted = List<models.Message>.from(messages);
    sorted.sort((a, b) {
      final ta = a.sentAt;
      final tb = b.sentAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
    return sorted.sublist(sorted.length - maxVisible);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ChatRepository>();
    final myUserId = context.read<AuthService>().currentUser?.uid ?? '';
    if (_isDarkScreenActive) {
      final senderName = context.read<MorseSettingsService>().senderDisplayName;
      return DarkScreenMode(
        chatId: widget.chatId,
        repo: repo,
        myUserId: myUserId,
        onSendMessage: (text) {
          repo.sendMessage(
            widget.chatId,
            text,
            inputMode: models.InputMode.tapped,
            senderDisplayName:
                senderName.isNotEmpty ? senderName : null,
            onMessageId: _registerSentMessageId,
          );
        },
        onExit: () => setState(() => _isDarkScreenActive = false),
      );
    }

    return Scaffold(
      backgroundColor: TelegraphChatTheme.screenBackground,
      appBar: AppBar(
        backgroundColor: TelegraphChatTheme.screenBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: TelegraphChatTheme.chromeForeground,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.chatTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: TelegraphChatTheme.chromeForeground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              'Silent Morse',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: TelegraphChatTheme.chromeSubtitle,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
        actions: [
          if (_kBroomFeatureEnabled)
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined),
              tooltip: 'Clear screen — hide older messages on this device',
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final v2Key = _broomClearedPrefsKey(widget.chatId);
                final v3Key = _broomClearedUsPrefsKey(widget.chatId);
                final legacyKey = _broomClearedLegacyPrefsKey(widget.chatId);
                final latest = await _latestMessageSentAt(widget.chatId);
                if (latest == null) {
                  await prefs.remove(v2Key);
                  await prefs.remove(v3Key);
                  await prefs.remove(legacyKey);
                  if (mounted) {
                    setState(() {
                      _clearedAt = null;
                      _broomBypassIds.clear();
                      _pendingBypassPrune.clear();
                    });
                  }
                  return;
                }
                final cutoff = latest.add(const Duration(microseconds: 1));
                await prefs.setInt(v3Key, cutoff.microsecondsSinceEpoch);
                await prefs.remove(v2Key);
                await prefs.remove(legacyKey);
                if (mounted) {
                  setState(() {
                    _clearedAt = cutoff;
                    _broomBypassIds.clear();
                    _pendingBypassPrune.clear();
                  });
                }
              },
            ),
          Tooltip(
            message:
                'Silent mode: tap = dot, long press = dash, swipe up or down = send; back / swipe back = return to chat',
            child: IconButton(
              icon: const Icon(Icons.dark_mode_outlined),
              onPressed: () => setState(() => _isDarkScreenActive = true),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _chatDocStream ??= FirebaseFirestore.instance
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
                  stream: _messagesStreamFor(repo),
                  builder: (context, snapshot) {
                    final clearedAt =
                        _kBroomFeatureEnabled ? _clearedAt : null;
                    final raw = snapshot.data ?? [];
                    final pruneIds = <String>[];
                    for (final m in raw) {
                      if (!_broomBypassIds.contains(m.id)) continue;
                      if (m.sentAt != null &&
                          (clearedAt == null || m.sentAt!.isAfter(clearedAt))) {
                        pruneIds.add(m.id);
                      }
                    }
                    _queueBypassPrune(pruneIds);

                    var messages =
                        raw.where((m) => _passesBroomFilter(m, clearedAt)).toList();
                    if (clearedAt == null &&
                        messages.length > _kMaxVisibleMessages) {
                      messages = _applyMaxVisibleMessages(
                        messages,
                        _kMaxVisibleMessages,
                      );
                    }

                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[messages.length - 1 - index];
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
                    _inputController.clear();
                    repo.sendMessage(
                      widget.chatId,
                      text,
                      senderDisplayName:
                          senderName.isNotEmpty ? senderName : null,
                      onMessageId: _registerSentMessageId,
                    );
                  }
                } : null,
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
                    : TelegraphChatTheme.incomingTape,
                border: isFromMe
                    ? null
                    : Border.all(color: TelegraphChatTheme.incomingTapeBorder),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isFromMe ? 16 : 4),
                  bottomRight: Radius.circular(isFromMe ? 4 : 16),
                ),
              ),
              child: Text(
                message.text,
                style: TelegraphChatTheme.bodyStyle(
                  color: TelegraphChatTheme.ink,
                ),
              ),
            ),
            if (isFromMe)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Icon(
                  message.isRead ? Icons.done_all : (message.isDelivered ? Icons.done_all : Icons.done),
                  size: 14,
                  color: message.isRead
                      ? TelegraphChatTheme.chromeForeground
                      : TelegraphChatTheme.chromeSubtitle,
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
  final bool enabled;

  const _ChatInputBar({
    required this.controller,
    required this.onSend,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TelegraphChatTheme.inputBarSurface,
      elevation: 6,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  style: TelegraphChatTheme.bodyStyle(
                    color: TelegraphChatTheme.ink,
                  ),
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: enabled ? 'Type a message...' : 'Chat not yet approved',
                    hintStyle: TelegraphChatTheme.bodyStyle(
                      color: TelegraphChatTheme.hintText,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(
                        color: TelegraphChatTheme.fieldBorder,
                        width: 1.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(
                        color: TelegraphChatTheme.fieldBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(
                        color: TelegraphChatTheme.chromeForeground,
                        width: 2,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: TelegraphChatTheme.fieldBorder.withValues(alpha: 0.4),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onSubmitted: enabled ? (_) => onSend?.call() : null,
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                onPressed: enabled ? onSend : null,
                backgroundColor: enabled
                    ? TelegraphChatTheme.sendButtonBackground
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
