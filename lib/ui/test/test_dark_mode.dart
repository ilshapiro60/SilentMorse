import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../util/morse_haptic_engine.dart';
import '../../util/tap_decoder.dart';

/// Standalone dark practice pad — tap to send morse, no chat.
/// Same gestures as DarkScreenMode: short tap = dot, long press = dash.
/// Swipe up to "send" (echo back what you tapped).
/// Two-finger touch to exit.
class TestDarkMode extends StatefulWidget {
  final MorseSettings settings;
  final VoidCallback onExit;

  const TestDarkMode({
    super.key,
    required this.settings,
    required this.onExit,
  });

  @override
  State<TestDarkMode> createState() => _TestDarkModeState();
}

class _TestDarkModeState extends State<TestDarkMode> {
  late TapDecoder _tapDecoder;
  bool _showTapFeedback = false;
  int _pressStartMs = 0;
  final Set<int> _activePointers = {};
  final Map<int, double> _pointerStartY = {};
  final Map<int, double> _pointerLastY = {};
  static const double _swipeUpThreshold = 80;

  @override
  void initState() {
    super.initState();
    _tapDecoder = TapDecoder(widget.settings);
  }

  @override
  void dispose() {
    _tapDecoder.dispose();
    super.dispose();
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
        await MorseHapticEngine.playMorseString(
          MorseHapticEngine.textToMorse(text),
          widget.settings,
        );
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

                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _showTapFeedback ? const Color(0xFF222222) : Colors.black,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (currentMorse.isNotEmpty)
                          Text(
                            currentMorse,
                            style: const TextStyle(
                              color: Color(0xFF111111),
                              fontSize: 24,
                              fontFamily: 'monospace',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        if (currentMorse.isNotEmpty) const SizedBox(height: 16),
                        if (decodedText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              decodedText,
                              style: const TextStyle(color: Color(0xFF0A0A0A), fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 48),
                        const Text(
                          'Short tap = dot • Long press = dash',
                          style: TextStyle(color: Color(0xFF222222), fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Swipe up to send & hear back • Two fingers to exit',
                          style: TextStyle(color: Color(0xFF222222), fontSize: 12),
                        ),
                      ],
                    ),
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
