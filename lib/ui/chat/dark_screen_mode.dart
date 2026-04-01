import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../app.dart';
import '../../data/models.dart';
import '../../services/chat_repository.dart';
import '../../services/morse_settings_service.dart';
import '../../util/morse_haptic_engine.dart';
import '../../util/tap_decoder.dart';
import 'dark_decoded_draft.dart';

/// DarkScreenMode — The signature Silent Morse feature.
/// Fills screen with black only; exit via Android back / predictive back.
/// Sets brightness to near-zero; all interaction is haptic/touch Morse.
///
/// Gestures:
///   Short tap        → dot
///   Long press       → dash
///   Horizontal slide → dash
///   Swipe up or down → send current decoded text immediately
///   System back / predictive back → exit to normal chat
///   Two-finger touch → exit
class DarkScreenMode extends StatefulWidget {
  final String chatId;
  final ChatRepository repo;
  final String myUserId;
  final void Function(String text) onSendMessage;
  final VoidCallback onExit;

  const DarkScreenMode({
    super.key,
    required this.chatId,
    required this.repo,
    required this.myUserId,
    required this.onSendMessage,
    required this.onExit,
  });

  @override
  State<DarkScreenMode> createState() => _DarkScreenModeState();
}

class _DarkScreenModeState extends State<DarkScreenMode> {
  late TapDecoder _tapDecoder;
  late MorseSettingsService _settingsSvc;
  late VoidCallback _onSettingsChanged;
  ReceiveMode _priorReceiveMode = ReceiveMode.vibrate;
  int _tapDecoderTimingSig = 0;
  StreamSubscription? _incomingSub;
  Timer? _silenceTimer;

  bool _showTapFeedback = false;
  final List<String> _exchangeTextBacklog = [];

  int _pressStartMs = 0;
  final Set<int> _activePointers = {};
  final Map<int, double> _pointerStartY = {};
  final Map<int, double> _pointerLastY = {};
  final Map<int, double> _pointerStartX = {};
  final Map<int, double> _pointerLastX = {};

  static const double _swipeVerticalThreshold = 20;
  static const double _swipeHorizontalThreshold = 80;
  static const int _kExchangeTextBacklogMax = 10;

  Timer? _longPressExitTimer;
  bool _exiting = false;
  static const int _longPressExitMs = 2000;

  static int _timingSignature(MorseSettings s) =>
      Object.hash(s.dotDurationMs, s.letterGapMs, s.wordGapMs);

  @override
  void initState() {
    super.initState();
    _settingsSvc = context.read<MorseSettingsService>();
    final initial = _settingsSvc.settings;
    _priorReceiveMode = initial.receiveMode;
    _tapDecoder = TapDecoder(initial);
    _tapDecoderTimingSig = _timingSignature(initial);

    _onSettingsChanged = () {
      final s = _settingsSvc.settings;
      final nextReceive = s.receiveMode;
      if (_priorReceiveMode == ReceiveMode.text &&
          nextReceive == ReceiveMode.vibrate &&
          mounted) {
        setState(() => _exchangeTextBacklog.clear());
      }
      _priorReceiveMode = nextReceive;

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

    _initBrightness();
    GlobalReceiveState.activeDarkModeChatId = widget.chatId;
    _observeIncomingMessages();
  }

  Future<void> _initBrightness() async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(0.01);
    } catch (_) {}
  }

  void _observeIncomingMessages() {
    final seen = <String>{};
    bool firstSnapshot = true;

    debugPrint('[DarkMode] subscribing to messages for ${widget.chatId}');

    _incomingSub = widget.repo.observeMessages(widget.chatId).listen(
      (messages) {
        debugPrint('[DarkMode] snapshot: ${messages.length} msgs, '
            'firstSnapshot=$firstSnapshot, seen=${seen.length}');
        if (firstSnapshot) {
          firstSnapshot = false;
          for (final m in messages) {
            seen.add(m.id);
          }
          return;
        }

        for (final m in messages) {
          if (seen.contains(m.id)) continue;
          seen.add(m.id);
          if (m.senderId == widget.myUserId) continue;
          if (!mounted) return;

          debugPrint('[DarkMode] NEW incoming: "${m.text}"');

          final settings = _settingsSvc.settings;
          // Dark mode is tactile — always vibrate, regardless of receiveMode.
          if (m.morse.isNotEmpty) {
            debugPrint('[DarkMode] vibrating morse...');
            MorseHapticEngine.playMorseString(m.morse, settings);
          }
          // Also update the text backlog for when receiveMode is text.
          if (settings.receiveMode == ReceiveMode.text) {
            final t = m.text.trim();
            if (t.isNotEmpty && mounted) {
              _appendExchangeLine(t);
            }
          }
        }
      },
      onError: (e) => debugPrint('[DarkMode] listener error: $e'),
    );
  }

  @override
  void dispose() {
    _settingsSvc.removeListener(_onSettingsChanged);
    _tapDecoder.dispose();
    _incomingSub?.cancel();
    _silenceTimer?.cancel();
    _longPressExitTimer?.cancel();
    _resetBrightness();
    GlobalReceiveState.activeDarkModeChatId = null;
    super.dispose();
  }

  Future<void> _resetBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  void _resetSilenceTimer() {
    final delayMs = _settingsSvc.settings.autoSendDelayMs;
    if (delayMs <= 0) return;
    _silenceTimer?.cancel();
    _silenceTimer = Timer(Duration(milliseconds: delayMs), _autoSend);
  }

  void _appendExchangeLine(String line) {
    final t = line.trim();
    if (t.isEmpty || !mounted) return;
    setState(() {
      _exchangeTextBacklog.add(t);
      while (_exchangeTextBacklog.length > _kExchangeTextBacklogMax) {
        _exchangeTextBacklog.removeAt(0);
      }
    });
  }

  void _sendOutgoing(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _appendExchangeLine('You: $t');
    widget.onSendMessage(t);
  }

  void _autoSend() {
    final text = _tapDecoder.consumeText();
    if (text.isNotEmpty) {
      _sendOutgoing(text);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length >= 2) {
      _exiting = true;
      _tapDecoder.reset();
      _silenceTimer?.cancel();
      _longPressExitTimer?.cancel();
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
    _longPressExitTimer?.cancel();
    _longPressExitTimer = Timer(
      const Duration(milliseconds: _longPressExitMs),
      () {
        if (!mounted) return;
        _exiting = true;
        _tapDecoder.reset();
        _silenceTimer?.cancel();
        widget.onExit();
      },
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerLastY.containsKey(event.pointer)) {
      _pointerLastY[event.pointer] = event.localPosition.dy;
      _pointerLastX[event.pointer] = event.localPosition.dx;
    }
    // Cancel exit timer if finger is clearly moving (it's a swipe, not a hold)
    if (_longPressExitTimer != null) {
      final startY = _pointerStartY[event.pointer];
      final startX = _pointerStartX[event.pointer];
      if (startY != null && startX != null) {
        final dy = (event.localPosition.dy - startY).abs();
        final dx = (event.localPosition.dx - startX).abs();
        if (dy > 15 || dx > 15) {
          _longPressExitTimer?.cancel();
          _longPressExitTimer = null;
        }
      }
    }
  }

  Future<void> _handlePointerUp(PointerUpEvent event) async {
    _longPressExitTimer?.cancel();
    if (_exiting) return;
    final startY = _pointerStartY[event.pointer];
    final startX = _pointerStartX[event.pointer];
    final endY = event.localPosition.dy;
    final endX = event.localPosition.dx;
    _pointerStartY.remove(event.pointer);
    _pointerLastY.remove(event.pointer);
    _pointerStartX.remove(event.pointer);
    _pointerLastX.remove(event.pointer);
    _activePointers.remove(event.pointer);

    if (_activePointers.isNotEmpty) return;

    final duration = DateTime.now().millisecondsSinceEpoch - _pressStartMs;
    final dy = startY != null ? endY - startY : 0.0;
    final dx = startX != null ? endX - startX : 0.0;
    final settings = _settingsSvc.settings;

    if (dy.abs() >= _swipeVerticalThreshold) {
      debugPrint('[DarkMode] swipe detected dy=$dy, sending...');
      _silenceTimer?.cancel();
      final text = _tapDecoder.consumeText();
      debugPrint('[DarkMode] consumeText="$text"');
      if (text.isNotEmpty) {
        _sendOutgoing(text);
        await MorseHapticEngine.dot(settings);
        await Future.delayed(const Duration(milliseconds: 80));
        await MorseHapticEngine.dot(settings);
      } else {
        debugPrint('[DarkMode] nothing to send (auto-send may have fired already)');
      }
      return;
    } else if (dx.abs() >= _swipeHorizontalThreshold) {
      _tapDecoder.appendSymbol('-');
      setState(() => _showTapFeedback = true);
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) setState(() => _showTapFeedback = false);
      });
      await MorseHapticEngine.dash(settings);
      _resetSilenceTimer();
    } else {
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onExit();
      },
      child: Scaffold(
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
                final sendMode = settings.sendMode;
                final showDecodedDraft = sendMode == SendMode.text &&
                    shouldShowTapDecoderDraft(
                        decodedText, _exchangeTextBacklog);

                return Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_exchangeTextBacklog.isNotEmpty) ...[
                            const Text(
                              'Messages',
                              style: TextStyle(
                                  color: Color(0xFF333333), fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 140),
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const ClampingScrollPhysics(),
                                itemCount: _exchangeTextBacklog.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final line = _exchangeTextBacklog[i];
                                  final isYou = line.startsWith('You: ');
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24),
                                    child: Text(
                                      line,
                                      style: TextStyle(
                                        color: isYou
                                            ? const Color(0xFF1A3A1A)
                                            : const Color(0xFF222222),
                                        fontSize: 12,
                                        height: 1.25,
                                        fontStyle: isYou
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                },
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
                          if (showDecodedDraft)
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
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
