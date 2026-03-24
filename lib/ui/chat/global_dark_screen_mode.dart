import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../app.dart';
import '../../data/models.dart';
import '../../services/chat_repository.dart';
import 'package:vibration/vibration.dart';

import '../../util/morse_haptic_engine.dart';
import '../../util/tap_decoder.dart';

/// Global dark-screen mode — listens to ALL active chats simultaneously.
/// Ilya doesn't need to pick a friend first.
///
/// Receive: whenever any friend sends a message the morse vibrates.
/// Reply:   swipe up sends the current morse to whoever messaged most recently.
/// Unsend:  swipe down deletes Ilya's last sent message (across any chat).
/// Exit:    two-finger touch.
class GlobalDarkScreenMode extends StatefulWidget {
  final MorseSettings settings;
  final VoidCallback onExit;

  const GlobalDarkScreenMode({
    super.key,
    required this.settings,
    required this.onExit,
  });

  @override
  State<GlobalDarkScreenMode> createState() => _GlobalDarkScreenModeState();
}

class _GlobalDarkScreenModeState extends State<GlobalDarkScreenMode> {
  late TapDecoder _tapDecoder;
  StreamSubscription<List<Chat>>? _chatListSub;
  final Map<String, StreamSubscription<List<Message>>> _chatSubs = {};
  final Map<String, bool> _chatFirstEvent = {};
  final Map<String, String?> _chatLastMsgId = {};
  final Map<String, int> _chatPrevCount = {};
  Timer? _silenceTimer;

  // Who to reply to (the last friend who sent a message).
  String? _replyToChatId;
  String _replyToName = '';
  String _lastReceivedText = '';
  bool _showTapFeedback = false;

  int _pressStartMs = 0;
  final Set<int> _activePointers = {};
  final Map<int, double> _pointerStartY = {};
  final Map<int, double> _pointerLastY = {};

  static const double _swipeUpThreshold = 80;
  static const double _swipeDownThreshold = 80;

  // Name cache: chatId → other participant's display name.
  final Map<String, String> _nameCache = {};

  @override
  void initState() {
    super.initState();
    _tapDecoder = TapDecoder(widget.settings);
    _initBrightness();
    // Prevent the per-chat foreground FCM listener from double-vibrating.
    GlobalReceiveState.activeDarkModeChatId = '__global__';
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _startListeningToAllChats());
  }

  Future<void> _initBrightness() async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(0.01);
    } catch (_) {}
  }

  void _startListeningToAllChats() {
    final repo = context.read<ChatRepository>();
    final myUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    _chatListSub = repo.observeChats().listen((chats) async {
      final active = chats.where((c) => c.isActive).toList();
      final activeIds = active.map((c) => c.id).toSet();

      // Cancel subs for chats no longer active.
      for (final id in _chatSubs.keys.toList()) {
        if (!activeIds.contains(id)) {
          _chatSubs[id]?.cancel();
          _chatSubs.remove(id);
          _chatFirstEvent.remove(id);
          _chatLastMsgId.remove(id);
          _chatPrevCount.remove(id);
        }
      }

      // Subscribe to new active chats.
      for (final chat in active) {
        if (_chatSubs.containsKey(chat.id)) continue;
        _chatFirstEvent[chat.id] = true;

        // Resolve other participant's name upfront.
        final otherId = chat.otherParticipant(myUserId);
        if (!_nameCache.containsKey(chat.id) && otherId.isNotEmpty) {
          final user = await repo.getUserById(otherId);
          if (mounted) {
            _nameCache[chat.id] = chat.isGroup
                ? (chat.name.isNotEmpty ? chat.name : 'Group')
                : (user?.displayName ?? user?.username ?? 'Friend');
          }
        }

        _chatSubs[chat.id] =
            repo.observeMessages(chat.id).listen((messages) async {
          if (messages.isEmpty) {
            _chatPrevCount[chat.id] = 0;
            return;
          }
          final last = messages.last;

          // Skip the initial snapshot.
          if (_chatFirstEvent[chat.id] == true) {
            _chatFirstEvent[chat.id] = false;
            _chatLastMsgId[chat.id] = last.id;
            _chatPrevCount[chat.id] = messages.length;
            return;
          }

          if (last.id == _chatLastMsgId[chat.id]) {
            _chatPrevCount[chat.id] = messages.length;
            return;
          }

          final prevLen = _chatPrevCount[chat.id] ?? 0;
          if (messages.length < prevLen &&
              last.id != _chatLastMsgId[chat.id]) {
            _chatLastMsgId[chat.id] = last.id;
            _chatPrevCount[chat.id] = messages.length;
            return;
          }

          _chatPrevCount[chat.id] = messages.length;

          if (last.senderId == myUserId) return;
          if (last.morse.isEmpty) return;

          _chatLastMsgId[chat.id] = last.id;

          // Update reply target to the chat that just spoke.
          if (mounted) {
            setState(() {
              _replyToChatId = chat.id;
              _replyToName = _nameCache[chat.id] ?? 'Friend';
              _lastReceivedText =
                  widget.settings.receiveMode == ReceiveMode.text
                      ? last.text
                      : '';
            });
          }

          if (widget.settings.receiveMode == ReceiveMode.vibrate) {
            // Group messages get a short alert buzz first so Ilya can
            // feel the difference between a 1-on-1 and a group message.
            if (chat.isGroup) {
              await Vibration.vibrate(duration: 80);
              await Future.delayed(const Duration(milliseconds: 120));
            }
            MorseHapticEngine.playMorseString(last.morse, widget.settings);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _tapDecoder.dispose();
    _chatListSub?.cancel();
    for (final sub in _chatSubs.values) {
      sub.cancel();
    }
    _silenceTimer?.cancel();
    _resetBrightness();
    GlobalReceiveState.activeDarkModeChatId = null;
    super.dispose();
  }

  Future<void> _resetBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  // ── Silence timer ────────────────────────────────────────────────────────

  void _resetSilenceTimer() {
    final delayMs = widget.settings.autoSendDelayMs;
    if (delayMs <= 0) return;
    _silenceTimer?.cancel();
    _silenceTimer = Timer(Duration(milliseconds: delayMs), _autoSend);
  }

  void _autoSend() {
    final text = _tapDecoder.consumeText();
    if (text.isNotEmpty && _replyToChatId != null) {
      _sendMessage(text);
    }
  }

  void _sendMessage(String text) {
    final chatId = _replyToChatId;
    if (chatId == null) return;
    final repo = context.read<ChatRepository>();
    repo.sendMessage(chatId, text);
  }

  // ── Pointer handling ─────────────────────────────────────────────────────

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length >= 2) {
      _tapDecoder.reset();
      _silenceTimer?.cancel();
      _pointerStartY.clear();
      _pointerLastY.clear();
      widget.onExit();
      return;
    }
    _pressStartMs = DateTime.now().millisecondsSinceEpoch;
    _pointerStartY[event.pointer] = event.localPosition.dy;
    _pointerLastY[event.pointer] = event.localPosition.dy;
    _tapDecoder.onPressDown();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerLastY.containsKey(event.pointer)) {
      _pointerLastY[event.pointer] = event.localPosition.dy;
    }
  }

  Future<void> _handlePointerUp(PointerUpEvent event) async {
    final startY = _pointerStartY[event.pointer];
    final lastY = _pointerLastY[event.pointer];
    _pointerStartY.remove(event.pointer);
    _pointerLastY.remove(event.pointer);
    _activePointers.remove(event.pointer);

    if (_activePointers.isNotEmpty) return;

    final duration = DateTime.now().millisecondsSinceEpoch - _pressStartMs;
    final dy = (startY != null && lastY != null) ? lastY - startY : 0.0;

    if (dy < -_swipeUpThreshold) {
      // Swipe up → send immediately.
      _silenceTimer?.cancel();
      final text = _tapDecoder.consumeText();
      if (text.isNotEmpty && _replyToChatId != null) {
        _sendMessage(text);
      }
    } else if (dy > _swipeDownThreshold) {
      // Swipe down → unsend last sent message across all chats.
      _tapDecoder.reset();
      _silenceTimer?.cancel();
      await _unsendLast();
    } else {
      _tapDecoder.onPressUp();
      setState(() => _showTapFeedback = true);
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) setState(() => _showTapFeedback = false);
      });
      if (duration < widget.settings.dotDurationMs * 2) {
        await MorseHapticEngine.dot(widget.settings);
      } else {
        await MorseHapticEngine.dash(widget.settings);
      }
      _resetSilenceTimer();
    }
  }

  Future<void> _unsendLast() async {
    final repo = context.read<ChatRepository>();
    // Try the active reply chat first, then fall back to any chat.
    final chatIds = _replyToChatId != null
        ? [_replyToChatId!, ..._chatSubs.keys.where((id) => id != _replyToChatId)]
        : _chatSubs.keys.toList();
    for (final chatId in chatIds) {
      final msg = await repo.getLastMyMessage(chatId);
      if (msg != null) {
        await repo.deleteMessage(chatId, msg.id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasReplyTarget = _replyToChatId != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black,
          child: StreamBuilder<String>(
            stream: _tapDecoder.decodedText,
            initialData: '',
            builder: (context, decodedSnapshot) {
              final decodedText = decodedSnapshot.data ?? '';
              final sendMode = widget.settings.sendMode;
              final showText =
                  sendMode == SendMode.text && decodedText.isNotEmpty;

              return Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_lastReceivedText.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32),
                            child: Text(
                              _lastReceivedText,
                              style: const TextStyle(
                                  color: Color(0xFF222222),
                                  fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _showTapFeedback
                                ? const Color(0xFF222222)
                                : Colors.black,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (showText)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32),
                            child: Text(
                              decodedText,
                              style: const TextStyle(
                                  color: Color(0xFF0A0A0A),
                                  fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                        left: 16,
                        right: 16,
                        bottom: 24,
                        child: SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasReplyTarget)
                                Text(
                                  'Replying to $_replyToName',
                                  style: const TextStyle(
                                      color: Color(0xFF2A2A2A),
                                      fontSize: 11),
                                  textAlign: TextAlign.center,
                                )
                              else
                                const Text(
                                  'Waiting for any friend…',
                                  style: TextStyle(
                                      color: Color(0xFF2A2A2A),
                                      fontSize: 11),
                                  textAlign: TextAlign.center,
                                ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tap • Hold = dash • Swipe ↑ = send • Swipe ↓ = unsend',
                                style: TextStyle(
                                    color: Color(0xFF222222),
                                    fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Two fingers = exit',
                                style: TextStyle(
                                    color: Color(0xFF222222),
                                    fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
            },
          ),
        ),
      ),
    );
  }
}
