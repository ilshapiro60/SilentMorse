/// MorseHapticEngine
///
/// Handles all Morse code encoding, decoding, and haptic playback.
/// Pure utility — no state, fully testable.
library silentmorse_messenger.util.morse_haptic_engine;

import 'dart:async';

import 'package:vibration/vibration.dart';

import '../data/models.dart';

class MorseHapticEngine {
  MorseHapticEngine._();

  // ─────────────────────────────────────────────
  // MORSE ALPHABET
  // ─────────────────────────────────────────────

  static const Map<String, String> _charToMorse = {
    'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.',
    'G': '--.', 'H': '....', 'I': '..', 'J': '.---', 'K': '-.-', 'L': '.-..',
    'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-', 'R': '.-.',
    'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-',
    'Y': '-.--', 'Z': '--..',
    '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
    '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
    '.': '.-.-.-', ',': '--..--', '?': '..--..', '!': '-.-.--', "'": '.----.',
    '/': '-..-.', '(': '-.--.', ')': '-.--.-', '&': '.-...', ':': '---...',
    ';': '-.-.-.', '=': '-...-', '+': '.-.-.', '-': '-....-', '_': '..__.-',
    '"': '.-..-.', '\$': '...-..-', '@': '.--.-.',
    ' ': '/',
  };

  static final Map<String, String> _morseToChar = {
    for (var e in _charToMorse.entries) e.value: e.key,
  };

  /// Characters available for learning (letters A–Z, digits 0–9).
  static List<String> get learnableCharacters =>
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.split('');

  /// Get morse pattern for a single character.
  static String? charToMorse(String char) =>
      _charToMorse[char.toUpperCase()];

  // ─────────────────────────────────────────────
  // TEXT → MORSE STRING
  // ─────────────────────────────────────────────

  /// Convert plain text to a morse string.
  /// Example: "HI" → ".... .."
  static String textToMorse(String text) {
    return text.toUpperCase().split('').map((c) => _charToMorse[c]).whereType<String>().join(' ');
  }

  // ─────────────────────────────────────────────
  // MORSE STRING → HAPTIC SEQUENCE
  // ─────────────────────────────────────────────

  /// Convert a morse string into a list of HapticPulse objects.
  /// Timing ratios follow ITU standard.
  static List<HapticPulse> morseToHapticSequence(String morse, MorseSettings settings) {
    final dot = settings.dotDurationMs;
    final dash = settings.dashDurationMs;
    final symbolGap = dot;
    final letterGap = settings.letterGapMs;
    final wordGap = settings.wordGapMs;

    final pulses = <HapticPulse>[];
    final letters = morse.split(' ');

    for (var letterIndex = 0; letterIndex < letters.length; letterIndex++) {
      final letter = letters[letterIndex];
      if (letter == '/') {
        if (pulses.isNotEmpty && !pulses.last.isOn) {
          pulses[pulses.length - 1] = HapticPulse(wordGap, false);
        } else {
          pulses.add(HapticPulse(wordGap, false));
        }
      } else {
        for (var symbolIndex = 0; symbolIndex < letter.length; symbolIndex++) {
          final symbol = letter[symbolIndex];
          if (symbol == '.') {
            pulses.add(HapticPulse(dot, true));
          } else if (symbol == '-') {
            pulses.add(HapticPulse(dash, true));
          }
          if (symbolIndex < letter.length - 1) {
            pulses.add(HapticPulse(symbolGap, false));
          }
        }
        if (letterIndex < letters.length - 1 && letters[letterIndex + 1] != '/') {
          pulses.add(HapticPulse(letterGap, false));
        }
      }
    }
    return pulses;
  }

  // ─────────────────────────────────────────────
  // PLAY HAPTIC SEQUENCE
  // ─────────────────────────────────────────────

  /// Play a morse string as haptic vibration.
  static Future<void> playMorseString(String morse, MorseSettings settings) async {
    if (settings.vibrationIntensity.amplitude == 0) return;
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;

    final pulses = morseToHapticSequence(morse, settings);
    if (pulses.isEmpty) return;

    // Play each pulse sequentially (vibration is fire-and-forget, so we await delays)
    for (final p in pulses) {
      if (p.isOn) {
        Vibration.vibrate(
          duration: p.durationMs,
          amplitude: settings.vibrationIntensity.amplitude,
        );
        await Future.delayed(Duration(milliseconds: p.durationMs));
      } else {
        await Future.delayed(Duration(milliseconds: p.durationMs));
      }
    }
  }

  /// Play a single dot — used for tap feedback
  static Future<void> dot(MorseSettings settings) async {
    if (settings.vibrationIntensity.amplitude == 0) return;
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;
    Vibration.vibrate(
      duration: settings.dotDurationMs,
      amplitude: settings.vibrationIntensity.amplitude,
    );
  }

  /// Play a single dash — used for tap feedback
  static Future<void> dash(MorseSettings settings) async {
    if (settings.vibrationIntensity.amplitude == 0) return;
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;
    Vibration.vibrate(
      duration: settings.dashDurationMs,
      amplitude: settings.vibrationIntensity.amplitude,
    );
  }

  // ─────────────────────────────────────────────
  // MORSE → TEXT (Decoding)
  // ─────────────────────────────────────────────

  static String morseToText(String morse) {
    return morse.split(' / ').map((word) {
      return word.split(' ').map((s) => _morseToChar[s]).whereType<String>().join();
    }).join(' ');
  }

  // ─────────────────────────────────────────────
  // VALIDATION
  // ─────────────────────────────────────────────

  static bool isValidMorse(String morse) {
    const validChars = {'.', '-', ' ', '/'};
    return morse.split('').every((c) => validChars.contains(c));
  }
}
