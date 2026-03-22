import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/morse_settings_service.dart';
import '../../services/chat_repository.dart';
import '../../util/morse_haptic_engine.dart';
import '../../util/tap_decoder.dart';
import '../theme/silentmorse_theme.dart';

/// Morse tap interface for Wear OS.
/// Tap = dot, long press = dash, swipe up = send now,
/// swipe down = unsend last, two fingers = exit.
class WatchChatScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;

  const WatchChatScreen(
      {super.key, required this.chatId, required this.chatTitle});

  @override
  State<WatchChatScreen> createState() => _WatchChatScreenState();
}

class _WatchChatScreenState extends State<WatchChatScreen> {
  late TapDecoder _tapDecoder;
  StreamSubscription? _incomingSub;
  Timer? _silenceTimer;

  String _lastReceivedText = '';
  String? _lastIncomingMsgId;

  int _pressStartMs = 0;
  final Set<int> _activePointers = {};
  final Map<int, double> _pointerStartY = {};
  final Map<int, double> _pointerLastY = {};

  static const double _swipeUpThreshold = 60;
  static const double _swipeDownThreshold = 60;

  @override
  void initState() {
    super.initState();
    final settings = context.read<MorseSettingsService>().settings;
    _tapDecoder = TapDecoder(settings);
    _observeIncomingMessages();
  }

  void _observeIncomingMessages() {
    final repo = context.read<ChatRepository>();
    final myUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    bool firstEvent = true;

    _incomingSub = repo.observeMessages(widget.chatId).listen((messages) {
      if (messages.isEmpty) return;
      final last = messages.last;

      if (firstEvent) {
        firstEvent = false;
        _lastIncomingMsgId = last.id;
        return;
      }

      if (last.id == _lastIncomingMsgId) return;
      if (last.senderId == myUserId) return;
      if (last.morse.isEmpty) return;

      _lastIncomingMsgId = last.id;

      if (!mounted) return;
      final settings = context.read<MorseSettingsService>().settings;
      switch (settings.receiveMode) {
        case ReceiveMode.vibrate:
          MorseHapticEngine.playMorseString(last.morse, settings);
          if (mounted) setState(() => _lastReceivedText = '');
        case ReceiveMode.text:
          if (last.text.isNotEmpty && mounted) {
            setState(() => _lastReceivedText = last.text);
          }
      }
    });
  }

  @override
  void dispose() {
    _tapDecoder.dispose();
    _incomingSub?.cancel();
    _silenceTimer?.cancel();
    super.dispose();
  }

  // --- Silence timer ---

  void _resetSilenceTimer() {
    final settings = context.read<MorseSettingsService>().settings;
    final delayMs = settings.autoSendDelayMs;
    if (delayMs <= 0) return;
    _silenceTimer?.cancel();
    _silenceTimer = Timer(Duration(milliseconds: delayMs), _autoSend);
  }

  void _autoSend() {
    final text = _tapDecoder.consumeText();
    if (text.isNotEmpty) {
      final senderName =
          context.read<MorseSettingsService>().senderDisplayName;
      context.read<ChatRepository>().sendMessage(
            widget.chatId,
            text,
            senderDisplayName: senderName.isNotEmpty ? senderName : null,
          );
    }
  }

  // --- Unsend ---

  Future<void> _unsendLast() async {
    final repo = context.read<ChatRepository>();
    final msg = await repo.getLastMyMessage(widget.chatId);
    if (msg != null) {
      await repo.deleteMessage(widget.chatId, msg.id);
    }
  }

  // --- Pointer handling ---

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length >= 2) {
      _tapDecoder.reset();
      _silenceTimer?.cancel();
      _pointerStartY.clear();
      _pointerLastY.clear();
      Navigator.of(context).pop();
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

    final settings = context.read<MorseSettingsService>().settings;
    final senderName = context.read<MorseSettingsService>().senderDisplayName;

    if (dy < -_swipeUpThreshold) {
      // Swipe up → send immediately.
      _silenceTimer?.cancel();
      final text = _tapDecoder.consumeText();
      if (text.isNotEmpty) {
        context.read<ChatRepository>().sendMessage(
              widget.chatId,
              text,
              senderDisplayName: senderName.isNotEmpty ? senderName : null,
            );
      }
    } else if (dy > _swipeDownThreshold) {
      // Swipe down → unsend last message.
      _tapDecoder.reset();
      _silenceTimer?.cancel();
      await _unsendLast();
    } else {
      // Normal tap/press.
      _tapDecoder.onPressUp();
      if (duration < settings.dotDurationMs * 2) {
        await MorseHapticEngine.dot(settings);
      } else {
        await MorseHapticEngine.dash(settings);
      }
      _resetSilenceTimer();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.chatTitle,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: inkDark,
        foregroundColor: Colors.white,
      ),
      backgroundColor: inkBlack,
      body: Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        behavior: HitTestBehavior.opaque,
        child: StreamBuilder<String>(
          stream: _tapDecoder.decodedText,
          initialData: '',
          builder: (context, decodedSnapshot) {
            return StreamBuilder<String>(
              stream: _tapDecoder.currentMorse,
              initialData: '',
              builder: (context, morseSnapshot) {
                final decodedText = decodedSnapshot.data ?? '';
                final currentMorse = morseSnapshot.data ?? '';

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_lastReceivedText.isNotEmpty) ...[
                      const Text(
                        'Incoming',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _lastReceivedText,
                          style: const TextStyle(
                              color: dotAmber, fontSize: 12),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (currentMorse.isNotEmpty)
                      Text(
                        currentMorse,
                        style: const TextStyle(
                            color: dotAmber,
                            fontSize: 18,
                            fontFamily: 'monospace'),
                        textAlign: TextAlign.center,
                      ),
                    if (decodedText.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          decodedText,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Tap • Hold = dash • Swipe ↑ = send • Swipe ↓ = unsend',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
