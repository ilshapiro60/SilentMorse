/// TapDecoder
///
/// Converts raw press/release events into Morse symbols, then letters, then words.
/// Timing-based: short press = dot, long press = dash.
/// Silence after a symbol = letter boundary. Longer silence = word boundary.
library silentmorse_messenger.util.tap_decoder;

import 'dart:async';

import '../data/models.dart';
import 'morse_haptic_engine.dart';

class TapDecoder {
  final MorseSettings settings;

  TapDecoder(this.settings);

  final _decodedTextController = StreamController<String>.broadcast();
  final _currentMorseController = StreamController<String>.broadcast();
  final _lastSymbolController = StreamController<String?>.broadcast();

  Stream<String> get decodedText => _decodedTextController.stream;
  Stream<String> get currentMorse => _currentMorseController.stream;
  Stream<String?> get lastSymbol => _lastSymbolController.stream;

  String _currentMorse = '';
  int _pressStartMs = 0;
  final _currentLetterSymbols = StringBuffer();
  final _fullText = StringBuffer();
  final _currentWord = StringBuffer();

  Timer? _letterGapTimer;
  Timer? _wordGapTimer;

  void onPressDown() {
    _pressStartMs = DateTime.now().millisecondsSinceEpoch;
    _letterGapTimer?.cancel();
    _wordGapTimer?.cancel();
  }

  void onPressUp() {
    final pressDurationMs = DateTime.now().millisecondsSinceEpoch - _pressStartMs;
    final symbol = pressDurationMs < settings.dotDurationMs * 2 ? '.' : '-';

    _currentLetterSymbols.write(symbol);
    _currentMorse = _currentLetterSymbols.toString();
    _currentMorseController.add(_currentMorse);
    _lastSymbolController.add(symbol);

    _letterGapTimer?.cancel();
    _letterGapTimer = Timer(Duration(milliseconds: settings.letterGapMs), () {
      _commitLetter();
      _wordGapTimer?.cancel();
      _wordGapTimer = Timer(
        Duration(milliseconds: settings.wordGapMs - settings.letterGapMs),
        _commitWord,
      );
    });
  }

  void _commitLetter() {
    final morseSymbols = _currentLetterSymbols.toString();
    _currentLetterSymbols.clear();
    _currentMorse = '';
    _currentMorseController.add('');

    final decoded = MorseHapticEngine.morseToText(morseSymbols);
    final char = decoded.isNotEmpty ? decoded[0] : null;
    if (char != null) {
      _currentWord.write(char);
    }
    _updateDecodedText();
  }

  void _commitWord() {
    if (_currentWord.isNotEmpty) {
      if (_fullText.isNotEmpty) _fullText.write(' ');
      _fullText.write(_currentWord);
      _currentWord.clear();
      _updateDecodedText();
    }
  }

  void _updateDecodedText() {
    final preview = _currentWord.isNotEmpty
        ? '$_fullText${_fullText.isNotEmpty ? ' ' : ''}$_currentWord'
        : _fullText.toString();
    _decodedTextController.add(preview);
  }

  void deleteLastChar() {
    if (_currentLetterSymbols.isNotEmpty) {
      final s = _currentLetterSymbols.toString();
      _currentLetterSymbols.clear();
      _currentLetterSymbols.write(s.substring(0, s.length - 1));
      _currentMorse = _currentLetterSymbols.toString();
      _currentMorseController.add(_currentMorse);
    } else if (_currentWord.isNotEmpty) {
      final s = _currentWord.toString();
      _currentWord.clear();
      _currentWord.write(s.substring(0, s.length - 1));
    } else if (_fullText.isNotEmpty) {
      final s = _fullText.toString();
      _fullText.clear();
      _fullText.write(s.substring(0, s.length - 1));
    }
    _updateDecodedText();
  }

  String consumeText() {
    _letterGapTimer?.cancel();
    _wordGapTimer?.cancel();
    _commitLetter();
    _commitWord();
    final result = _fullText.toString();
    reset();
    return result;
  }

  void reset() {
    _letterGapTimer?.cancel();
    _wordGapTimer?.cancel();
    _currentLetterSymbols.clear();
    _currentWord.clear();
    _fullText.clear();
    _currentMorse = '';
    _decodedTextController.add('');
    _currentMorseController.add('');
    _lastSymbolController.add(null);
  }

  void dispose() {
    _letterGapTimer?.cancel();
    _wordGapTimer?.cancel();
    _decodedTextController.close();
    _currentMorseController.close();
    _lastSymbolController.close();
  }
}
