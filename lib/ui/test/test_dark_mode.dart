import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/morse_settings_service.dart';
import '../../util/morse_haptic_engine.dart';
import '../../util/tap_decoder.dart';

/// Standalone dark practice pad — tap to send morse, no chat.
/// Same gestures as DarkScreenMode: short tap = dot, long press or horizontal slide = dash.
/// Swipe up/down to "send" (echo back what you tapped).
/// Two-finger touch to exit.
class TestDarkMode extends StatefulWidget {
  final VoidCallback onExit;

  const TestDarkMode({
    super.key,
    required this.onExit,
  });

  @override
  State<TestDarkMode> createState() => _TestDarkModeState();
}

class _TestDarkModeState extends State<TestDarkMode> {
  late TapDecoder _tapDecoder;
  late MorseSettingsService _settingsSvc;
  late VoidCallback _onSettingsChanged;
  int _tapDecoderTimingSig = 0;
  bool _showTapFeedback = false;
  int _pressStartMs = 0;
  final Set<int> _activePointers = {};
  final Map<int, double> _pointerStartY = {};
  final Map<int, double> _pointerLastY = {};
  final Map<int, double> _pointerStartX = {};
  final Map<int, double> _pointerLastX = {};
  static const double _swipeVerticalThreshold = 80;
  static const double _swipeHorizontalThreshold = 80;

  final List<int> _tapUpTimestamps = [];
  static const int _tripleTapWindowMs = 600;

  String _sentText = '';
  Timer? _sentTextTimer;
  Timer? _silenceTimer;
  static const Duration _sentTextDisplayDuration = Duration(seconds: 4);

  static int _timingSignature(MorseSettings s) =>
      Object.hash(s.dotDurationMs, s.letterGapMs, s.wordGapMs);

  @override
  void initState() {
    super.initState();
    _settingsSvc = context.read<MorseSettingsService>();
    final initial = _settingsSvc.settings;
    _tapDecoder = TapDecoder(initial);
    _tapDecoderTimingSig = _timingSignature(initial);
    _onSettingsChanged = () {
      final s = _settingsSvc.settings;
      final sig = _timingSignature(s);
      if (sig != _tapDecoderTimingSig && mounted) {
        setState(() {
          _tapDecoder.dispose();
          _tapDecoder = TapDecoder(s);
          _tapDecoderTimingSig = sig;
        });
      } else if (mounted) {
        setState(() {});
      }
    };
    _settingsSvc.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _sentTextTimer?.cancel();
    _settingsSvc.removeListener(_onSettingsChanged);
    _tapDecoder.dispose();
    super.dispose();
  }

  void _resetSilenceTimer() {
    final delayMs = _settingsSvc.settings.autoSendDelayMs;
    if (delayMs <= 0) return;
    _silenceTimer?.cancel();
    _silenceTimer = Timer(Duration(milliseconds: delayMs), _finishInput);
  }

  void _finishInput() {
    final text = _tapDecoder.consumeText();
    if (text.isNotEmpty) {
      _showSentText(text);
      MorseHapticEngine.playMorseString(
        MorseHapticEngine.textToMorse(text),
        _settingsSvc.settings,
      );
    }
  }

  void _showSentText(String text) {
    _sentTextTimer?.cancel();
    setState(() => _sentText = text);
    _sentTextTimer = Timer(_sentTextDisplayDuration, () {
      if (mounted) setState(() => _sentText = '');
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length >= 2) {
      _tapDecoder.reset();
      _pointerStartY.clear();
      _pointerLastY.clear();
      _pointerStartX.clear();
      _pointerLastX.clear();
      widget.onExit();
      return;
    }
    _pressStartMs = DateTime.now().millisecondsSinceEpoch;
    _pointerStartY[event.pointer] = event.localPosition.dy;
    _pointerLastY[event.pointer] = event.localPosition.dy;
    _pointerStartX[event.pointer] = event.localPosition.dx;
    _pointerLastX[event.pointer] = event.localPosition.dx;
    _tapDecoder.onPressDown();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerLastY.containsKey(event.pointer)) {
      _pointerLastY[event.pointer] = event.localPosition.dy;
      _pointerLastX[event.pointer] = event.localPosition.dx;
    }
  }

  void _handlePointerUp(PointerUpEvent event) async {
    final startY = _pointerStartY[event.pointer];
    final lastY = _pointerLastY[event.pointer];
    final startX = _pointerStartX[event.pointer];
    final lastX = _pointerLastX[event.pointer];
    _pointerStartY.remove(event.pointer);
    _pointerLastY.remove(event.pointer);
    _pointerStartX.remove(event.pointer);
    _pointerLastX.remove(event.pointer);
    _activePointers.remove(event.pointer);

    if (_activePointers.isNotEmpty) return;

    final duration = DateTime.now().millisecondsSinceEpoch - _pressStartMs;
    final dy = (startY != null && lastY != null) ? lastY - startY : 0.0;
    final dx = (startX != null && lastX != null) ? lastX - startX : 0.0;
    final settings = _settingsSvc.settings;

    if (dy.abs() >= _swipeVerticalThreshold) {
      _silenceTimer?.cancel();
      _tapUpTimestamps.clear();
      _finishInput();
    } else if (dx.abs() >= _swipeHorizontalThreshold) {
      _tapUpTimestamps.clear();
      _tapDecoder.appendSymbol('-');
      setState(() => _showTapFeedback = true);
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) setState(() => _showTapFeedback = false);
      });
      await MorseHapticEngine.dash(settings);
      _resetSilenceTimer();
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      _tapUpTimestamps.add(now);
      if (_tapUpTimestamps.length > 3) _tapUpTimestamps.removeAt(0);
      if (_tapUpTimestamps.length == 3 &&
          now - _tapUpTimestamps.first <= _tripleTapWindowMs) {
        _tapUpTimestamps.clear();
        _tapDecoder.reset();
        _silenceTimer?.cancel();
        widget.onExit();
        return;
      }

      _tapDecoder.onPressUp();
      setState(() => _showTapFeedback = true);
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) setState(() => _showTapFeedback = false);
      });
      if (duration < settings.dotDurationMs * 2) {
        await MorseHapticEngine.dot(settings);
      } else {
        await MorseHapticEngine.dash(settings);
      }
      _resetSilenceTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<MorseSettingsService>();
    final settings = _settingsSvc.settings;

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
                  final showMorseText = settings.sendMode == SendMode.text;
                  final showDecoded =
                      showMorseText && decodedText.isNotEmpty;

                  return Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
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
                            if (showMorseText && currentMorse.isNotEmpty)
                              Text(
                                currentMorse,
                                style: const TextStyle(
                                  color: Color(0xFF111111),
                                  fontSize: 24,
                                  fontFamily: 'monospace',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            if (showMorseText && currentMorse.isNotEmpty)
                              const SizedBox(height: 16),
                            if (showDecoded)
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
                      if (_sentText.isNotEmpty)
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 60,
                          child: AnimatedOpacity(
                            opacity: _sentText.isNotEmpty ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              _sentText,
                              style: const TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 24,
                        child: Column(
                          children: const [
                            Text(
                              'Short tap = dot • Long press = dash',
                              style: TextStyle(
                                  color: Color(0xFF222222), fontSize: 12),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Swipe up/down = send • Triple-tap = exit',
                              style: TextStyle(
                                  color: Color(0xFF222222), fontSize: 12),
                            ),
                          ],
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
