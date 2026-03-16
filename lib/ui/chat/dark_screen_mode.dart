import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../data/models.dart';
import '../../services/chat_repository.dart';
import '../../util/morse_haptic_engine.dart';
import '../../util/tap_decoder.dart';

/// DarkScreenMode — The signature Silent Morse feature.
/// Fills screen with pure black, sets brightness to near-zero,
/// converts all interaction to haptic/touch Morse.
///
/// Gestures:
///   Short tap       → dot
///   Long press      → dash
///   Swipe up        → send current decoded text
///   Two-finger touch → exit
class DarkScreenMode extends StatefulWidget {
  final String chatId;
  final MorseSettings settings;
  final void Function(String) onSendMessage;
  final VoidCallback onExit;

  const DarkScreenMode({
    super.key,
    required this.chatId,
    required this.settings,
    required this.onSendMessage,
    required this.onExit,
  });

  @override
  State<DarkScreenMode> createState() => _DarkScreenModeState();
}

class _DarkScreenModeState extends State<DarkScreenMode> {
  late TapDecoder _tapDecoder;
  StreamSubscription? _incomingSub;
  bool _showTapFeedback = false;
  String _lastReceivedText = '';
  int _pressStartMs = 0;
  final Set<int> _activePointers = {};
  final Map<int, double> _pointerStartY = {};
  final Map<int, double> _pointerLastY = {};
  static const double _swipeUpThreshold = 80;

  @override
  void initState() {
    super.initState();
    _tapDecoder = TapDecoder(widget.settings);
    _initBrightness();
    WidgetsBinding.instance.addPostFrameCallback((_) => _observeIncomingMessages());
  }

  Future<void> _initBrightness() async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(0.01);
    } catch (_) {}
  }

  void _observeIncomingMessages() {
    final repo = context.read<ChatRepository>();
    final myUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    _incomingSub = repo.observeMessages(widget.chatId).listen((messages) {
      if (messages.isEmpty) return;
      final last = messages.last;
      if (last.senderId != myUserId && last.morse.isNotEmpty) {
        switch (widget.settings.receiveMode) {
          case ReceiveMode.vibrate:
            MorseHapticEngine.playMorseString(last.morse, widget.settings);
            if (mounted) setState(() => _lastReceivedText = '');
            break;
          case ReceiveMode.text:
            if (last.text.isNotEmpty && mounted) {
              setState(() => _lastReceivedText = last.text);
            }
            break;
        }
      }
    });
  }

  @override
  void dispose() {
    _tapDecoder.dispose();
    _incomingSub?.cancel();
    _resetBrightness();
    super.dispose();
  }

  Future<void> _resetBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length >= 2) {
      _tapDecoder.reset();
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

  void _handlePointerUp(PointerUpEvent event) async {
    final startY = _pointerStartY[event.pointer];
    final lastY = _pointerLastY[event.pointer];
    _pointerStartY.remove(event.pointer);
    _pointerLastY.remove(event.pointer);
    _activePointers.remove(event.pointer);

    if (_activePointers.isNotEmpty) return;

    final duration = DateTime.now().millisecondsSinceEpoch - _pressStartMs;
    final movedUp = startY != null && lastY != null && startY - lastY > _swipeUpThreshold;

    if (movedUp) {
      final text = _tapDecoder.consumeText();
      if (text.isNotEmpty) {
        widget.onSendMessage(text);
        await MorseHapticEngine.playMorseString('.. .', widget.settings);
      }
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
              return StreamBuilder<String>(
                stream: _tapDecoder.currentMorse,
                initialData: '',
                builder: (context, morseSnapshot) {
                  final decodedText = decodedSnapshot.data ?? '';
                  final currentMorse = morseSnapshot.data ?? '';

                  final sendMode = widget.settings.sendMode;
                  final showMorse = sendMode == SendMode.touchWithText && currentMorse.isNotEmpty;
                  final showText = (sendMode == SendMode.text || sendMode == SendMode.touchWithText) && decodedText.isNotEmpty;

                  return Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_lastReceivedText.isNotEmpty) ...[
                              const Text('Incoming', style: TextStyle(color: Color(0xFF333333), fontSize: 11)),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  _lastReceivedText,
                                  style: const TextStyle(color: Color(0xFF222222), fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _showTapFeedback ? const Color(0xFF222222) : Colors.black,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (showMorse)
                              Text(
                                currentMorse,
                                style: const TextStyle(
                                  color: Color(0xFF111111),
                                  fontSize: 24,
                                  fontFamily: 'monospace',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            if (showMorse) const SizedBox(height: 16),
                            if (showText)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  decodedText,
                                  style: const TextStyle(color: Color(0xFF0A0A0A), fontSize: 16),
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
                              Text(
                                'Short tap = dot • Long press = dash • Swipe up = send',
                                style: const TextStyle(color: Color(0xFF333333), fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Two fingers = exit',
                                style: const TextStyle(color: Color(0xFF333333), fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
