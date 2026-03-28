import 'package:flutter/material.dart';

/// Normal chat (“text mode”) — light gray chrome + monospace teleprinter text.
abstract final class TelegraphChatTheme {
  static const Color screenBackground = Color(0xFFDBD9D3);
  static const Color inputBarSurface = Color(0xFFD2D0CA);
  static const Color incomingTape = Color(0xFFEDE5D6);
  static const Color incomingTapeBorder = Color(0xFFC4BAA5);
  static const Color ink = Color(0xFF1A1510);
  /// Icons, chat title, and other chrome on [screenBackground] (high contrast).
  static const Color chromeForeground = Color(0xFF1A1916);
  /// Subtitle under the contact name (not theme primary yellow).
  static const Color chromeSubtitle = Color(0xFF4A4740);
  static const Color fieldBorder = Color(0xFF6E6A63);
  static const Color hintText = Color(0xFF5E5A54);
  /// Send control on the input bar (dark, not yellow on gray).
  static const Color sendButtonBackground = Color(0xFF2A2824);

  static TextStyle bodyStyle({
    required Color color,
    double fontSize = 15,
    FontStyle fontStyle = FontStyle.normal,
  }) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.38,
      letterSpacing: 0.75,
      fontWeight: FontWeight.w500,
      color: color,
      fontStyle: fontStyle,
    );
  }

  static TextStyle morseStyle({
    required Color color,
    double fontSize = 10,
  }) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.2,
      letterSpacing: 0.5,
      color: color,
    );
  }
}
