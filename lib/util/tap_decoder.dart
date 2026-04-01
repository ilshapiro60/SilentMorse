/// TapDecoder
///
/// Converts raw press/release events into Morse symbols, then letters, then words.
/// Timing-based: short press = dot, long press = dash.
/// Callers may also append a dash after a horizontal slide (dark mode).
///
/// Letter boundaries are detected at press-down time: if enough silence has
/// elapsed since the last symbol was appended, the accumulated symbols are
/// committed as a letter before the new press begins.
library silentmorse_messenger.util.tap_decoder;

import 'dart:async';

import 'package:flutter/foundation.dart';

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
  int _lastAppendMs = 0;
  final _currentLetterSymbols = StringBuffer();
  final _fullText = StringBuffer();
  final _currentWord = StringBuffer();

  void onPressDown() {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_lastAppendMs > 0 && _currentLetterSymbols.isNotEmpty) {
      final gap = now - _lastAppendMs;
      if (gap >= settings.letterGapMs) {
        debugPrint('[TapDecoder] letter boundary: gap=${gap}ms');
        _commitLetter();
        if (gap >= settings.wordGapMs) {
          debugPrint('[TapDecoder] word boundary: gap=${gap}ms');
          _commitWord();
        }
      }
    }

    _pressStartMs = now;
  }

  void onPressUp() {
    final pressDurationMs = DateTime.now().millisecondsSinceEpoch - _pressStartMs;
    final symbol = pressDurationMs < settings.dotDurationMs * 2 ? '.' : '-';
    appendSymbol(symbol);
  }

  /// Record a dot or dash (e.g. horizontal slide → dash in dark mode).
  void appendSymbol(String symbol) {
    if (symbol != '.' && symbol != '-') return;

    _lastAppendMs = DateTime.now().millisecondsSinceEpoch;
    _currentLetterSymbols.write(symbol);
    _currentMorse = _currentLetterSymbols.toString();
    _currentMorseController.add(_currentMorse);
    _lastSymbolController.add(symbol);
    _updateDecodedText();
  }

  void _commitLetter() {
    final morseSymbols = _currentLetterSymbols.toString();
    _currentLetterSymbols.clear();
    _currentMorse = '';
    _currentMorseController.add('');

    if (morseSymbols.isEmpty) return;

    final decoded = MorseHapticEngine.morseToText(morseSymbols);
    if (decoded.isNotEmpty) {
      _currentWord.write(decoded[0]);
    } else {
      _greedySplit(morseSymbols);
    }
    _updateDecodedText();
  }

  void _greedySplit(String symbols) {
    var remaining = symbols;
    while (remaining.isNotEmpty) {
      String? bestChar;
      int bestLen = 0;
      for (int len = remaining.length; len >= 1; len--) {
        final prefix = remaining.substring(0, len);
        final decoded = MorseHapticEngine.morseToText(prefix);
        if (decoded.isNotEmpty) {
          bestChar = decoded[0];
          bestLen = len;
          break;
        }
      }
      if (bestChar != null) {
        _currentWord.write(bestChar);
        remaining = remaining.substring(bestLen);
      } else {
        remaining = remaining.substring(1);
      }
    }
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
    _commitLetter();
    _commitWord();
    final result = _fullText.toString();
    reset();
    return result;
  }

  void reset() {
    _currentLetterSymbols.clear();
    _currentWord.clear();
    _fullText.clear();
    _currentMorse = '';
    _lastAppendMs = 0;
    _decodedTextController.add('');
    _currentMorseController.add('');
    _lastSymbolController.add(null);
  }

  void dispose() {
    _decodedTextController.close();
    _currentMorseController.close();
    _lastSymbolController.close();
  }
}
