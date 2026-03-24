import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../app.dart';
import '../../data/models.dart';
import '../../services/chat_repository.dart';
import '../../util/morse_haptic_engine.dart';
import '../../util/tap_decoder.dart';

/// DarkScreenMode — The signature Silent Morse feature.
/// Fills screen with pure black, sets brightness to near-zero,
/// converts all interaction to haptic/touch Morse.
///
/// Gestures:
///   Short tap        → dot
///   Long press       → dash
///   Swipe up         → send current decoded text immediately
///   Swipe down       → unsend your last sent message
///   Two-finger touch → exit
class DarkScreenMode extends StatefulWidget {
  final String chatId;
  final MorseSettings settings;
  final void Function(String text) onSendMessage;
  final VoidCallback onUnsend;
  final VoidCallback onExit;

  const DarkScreenMode({
    super.key,
    required this.chatId,
    required this.settings,
    required this.onSendMessage,
    required this.onUnsend,
    required this.onExit,
  });

  @override
  State<DarkScreenMode> createState() => _DarkScreenModeState();
}

class _DarkScreenModeState extends State<DarkScreenMode> {
  late TapDecoder _tapDecoder;
  StreamSubscription? _incomingSub;
  Timer? _silenceTimer;

  bool _showTapFeedback = false;
  String _lastReceivedText = '';
  String? _lastIncomingMsgId;
  int _prevMessageCount = 0;

  int _pressStartMs = 0;
  final Set<int> _activePointers = {};
  final Map<int, double> _pointerStartY = {};
  final Map<int, double> _pointerLastY = {};

  static const double _swipeUpThreshold = 80;
  static const double _swipeDownThreshold = 80;

  @override
  void initState() {
    super.initState();
    _tapDecoder = TapDecoder(widget.settings);
    _initBrightness();
    // Mark this chat as the one currently in dark-screen mode so the global
    // foreground FCM listener skips it (avoid double-vibrate).
    GlobalReceiveState.activeDarkModeChatId = widget.chatId;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _observeIncomingMessages());
  }

  Future<void> _initBrightness() async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(0.01);
    } catch (_) {}
  }

  void _observeIncomingMessages() {
    final repo = context.read<ChatRepository>();
    final myUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    bool firstEvent = true;

    _incomingSub = repo.observeMessages(widget.chatId).listen((messages) {
      if (messages.isEmpty) {
        _prevMessageCount = 0;
        return;
      }
      final last = messages.last;

      // Skip the initial snapshot — we don't want to replay old messages.
      if (firstEvent) {
        firstEvent = false;
        _lastIncomingMsgId = last.id;
        _prevMessageCount = messages.length;
        return;
      }

      if (last.id == _lastIncomingMsgId) {
        _prevMessageCount = messages.length;
        return;
      }

      // Ephemeral delete: list shrank and the tip reverted to an older message.
      if (messages.length < _prevMessageCount &&
          last.id != _lastIncomingMsgId) {
        _lastIncomingMsgId = last.id;
        _prevMessageCount = messages.length;
        return;
      }

      _prevMessageCount = messages.length;

      if (last.senderId == myUserId) return;
      if (last.morse.isEmpty) return;

      _lastIncomingMsgId = last.id;

      switch (widget.settings.receiveMode) {
        case ReceiveMode.vibrate:
          MorseHapticEngine.playMorseString(last.morse, widget.settings);
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
    _resetBrightness();
    GlobalReceiveState.activeDarkModeChatId = null;
    super.dispose();
  }

  Future<void> _resetBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  // --- Silence timer ---

  void _resetSilenceTimer() {
    final delayMs = widget.settings.autoSendDelayMs;
    if (delayMs <= 0) return;
    _silenceTimer?.cancel();
    _silenceTimer = Timer(Duration(milliseconds: delayMs), _autoSend);
  }

  void _autoSend() {
    final text = _tapDecoder.consumeText();
    if (text.isNotEmpty) {
      widget.onSendMessage(text);
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
      if (text.isNotEmpty) {
        widget.onSendMessage(text);
      }
    } else if (dy > _swipeDownThreshold) {
      // Swipe down → unsend last message.
      _tapDecoder.reset();
      _silenceTimer?.cancel();
      widget.onUnsend();
    } else {
      // Normal tap/press → record as dot or dash, then reset silence timer.
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

  @override
  Widget build(BuildContext context) {
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
                          const Text(
                            'Incoming',
                            style: TextStyle(
                                color: Color(0xFF333333), fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32),
                            child: Text(
                              _lastReceivedText,
                              style: const TextStyle(
                                  color: Color(0xFF222222), fontSize: 12),
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
                                  color: Color(0xFF0A0A0A), fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Tap = dot • Hold = dash • Swipe ↑ = send • Swipe ↓ = unsend',
                            style: TextStyle(
                                color: Color(0xFF333333), fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Two fingers = exit',
                            style: TextStyle(
                                color: Color(0xFF333333), fontSize: 11),
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
