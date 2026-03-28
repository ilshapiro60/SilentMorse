import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../app.dart';
import '../../data/models.dart';
import '../../services/chat_repository.dart';
import '../../services/morse_settings_service.dart';
import 'package:vibration/vibration.dart';

import '../../util/morse_haptic_engine.dart';
import '../../util/tap_decoder.dart';
import 'dark_decoded_draft.dart';

/// Global dark-screen mode — listens to ALL active chats simultaneously.
///
/// Receive: whenever any friend sends a message the morse vibrates.
/// Reply:   swipe up or down sends the current morse to whoever messaged most recently.
/// Exit:    system back / predictive back, or two-finger touch.
class GlobalDarkScreenMode extends StatefulWidget {
  final VoidCallback onExit;

  const GlobalDarkScreenMode({
    super.key,
    required this.onExit,
  });

  @override
  State<GlobalDarkScreenMode> createState() => _GlobalDarkScreenModeState();
}

class _GlobalDarkScreenModeState extends State<GlobalDarkScreenMode> {
  late TapDecoder _tapDecoder;
  late MorseSettingsService _settingsSvc;
  late VoidCallback _onSettingsChanged;
  ReceiveMode _priorReceiveMode = ReceiveMode.vibrate;
  int _tapDecoderTimingSig = 0;
  StreamSubscription<List<Chat>>? _chatListSub;
  final Map<String, StreamSubscription<List<Message>>> _chatSubs = {};
  final Map<String, Set<String>> _chatSeenIds = {};
  Timer? _silenceTimer;

  String? _replyToChatId;
  final List<String> _exchangeTextBacklog = [];
  bool _showTapFeedback = false;

  int _pressStartMs = 0;
  final Set<int> _activePointers = {};
  final Map<int, double> _pointerStartY = {};
  final Map<int, double> _pointerLastY = {};
  final Map<int, double> _pointerStartX = {};
  final Map<int, double> _pointerLastX = {};

  static const double _swipeVerticalThreshold = 80;
  static const double _swipeHorizontalThreshold = 80;
  static const int _kExchangeTextBacklogMax = 10;

  final List<int> _tapUpTimestamps = [];
  static const int _tripleTapWindowMs = 600;

  final Map<String, String> _nameCache = {};

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

      for (final id in _chatSubs.keys.toList()) {
        if (!activeIds.contains(id)) {
          _chatSubs[id]?.cancel();
          _chatSubs.remove(id);
          _chatSeenIds.remove(id);
        }
      }

      for (final chat in active) {
        if (_chatSubs.containsKey(chat.id)) continue;

        final otherId = chat.otherParticipant(myUserId);
        if (!_nameCache.containsKey(chat.id) && otherId.isNotEmpty) {
          final user = await repo.getUserById(otherId);
          if (mounted) {
            _nameCache[chat.id] = chat.isGroup
                ? (chat.name.isNotEmpty ? chat.name : 'Group')
                : (user?.displayName ?? user?.username ?? 'Friend');
          }
        }

        final seen = <String>{};
        _chatSeenIds[chat.id] = seen;
        bool firstSnapshot = true;

        _chatSubs[chat.id] =
            repo.observeMessages(chat.id).listen(
          (messages) async {
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
              if (m.senderId == myUserId) continue;
              if (!mounted) return;

              setState(() => _replyToChatId = chat.id);

              final settings = _settingsSvc.settings;
              if (settings.receiveMode == ReceiveMode.text) {
                final t = m.text.trim();
                if (t.isNotEmpty && mounted) {
                  final from = _nameCache[chat.id] ?? 'Friend';
                  _appendExchangeLine('$from: $t');
                }
              }

              // Dark mode is tactile — always vibrate regardless of
              // receiveMode setting.
              if (chat.isGroup) {
                await Vibration.vibrate(duration: 80);
                await Future.delayed(
                    const Duration(milliseconds: 120));
              }
              if (m.morse.isNotEmpty) {
                MorseHapticEngine.playMorseString(
                    m.morse, settings);
              }
            }
          },
          onError: (e) =>
              debugPrint('Global dark listener error ($chat.id): $e'),
        );
      }
    });
  }

  @override
  void dispose() {
    _settingsSvc.removeListener(_onSettingsChanged);
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

  void _resetSilenceTimer() {
    final delayMs = _settingsSvc.settings.autoSendDelayMs;
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

  void _sendMessage(String text) {
    final chatId = _replyToChatId;
    if (chatId == null) return;
    final t = text.trim();
    if (t.isEmpty) return;
    _appendExchangeLine('You: $t');
    context.read<ChatRepository>().sendMessage(
          chatId,
          t,
          inputMode: InputMode.tapped,
        );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length >= 2) {
      _tapDecoder.reset();
      _silenceTimer?.cancel();
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

  Future<void> _handlePointerUp(PointerUpEvent event) async {
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
      final text = _tapDecoder.consumeText();
      if (text.isNotEmpty && _replyToChatId != null) {
        _sendMessage(text);
      }
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
                                  color: Color(0xFF333333),
                                  fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
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
                                    color: Color(0xFF0A0A0A),
                                    fontSize: 16),
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
