import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/morse_settings_service.dart';
import '../../util/morse_haptic_engine.dart';
import '../theme/silentmorse_theme.dart';
import 'test_dark_mode.dart';

/// Test mode — practice sending and receiving haptic morse.
/// No chat required. Send by tapping, receive by listening to patterns.
class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  bool _isDarkMode = false;

  static const _practiceWords = [
    'SOS', 'HI', 'OK', 'YES', 'NO', 'HELP', 'E', 'T', 'A',
  ];

  static const _practiceSentences = [
    'HI THERE',
    'I AM OK',
    'SEND HELP',
    'YES I CAN',
    'NO PROBLEM',
    'OK THANKS',
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.read<MorseSettingsService>().settings;
    if (_isDarkMode) {
      return TestDarkMode(
        onExit: () => setState(() => _isDarkMode = false),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Practice Morse', style: TextStyle(fontFamily: 'monospace')),
        backgroundColor: inkDark,
        foregroundColor: Colors.white,
      ),
      backgroundColor: inkBlack,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Practice sending and receiving morse code.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _SectionCard(
                title: 'Send',
                subtitle: 'Short tap = dot, long press = dash. Swipe up to send, two fingers to exit.',
                child: FilledButton.icon(
                  onPressed: () => setState(() => _isDarkMode = true),
                  icon: const Icon(Icons.touch_app),
                  label: const Text('Open practice pad'),
                  style: FilledButton.styleFrom(
                    backgroundColor: dotAmber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _SectionCard(
                title: 'Receive',
                subtitle: 'Tap a word or sentence to feel its haptic pattern.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Words', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _practiceWords.map((word) => _WordChip(
                        word: word,
                        settings: settings,
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Sentences', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _practiceSentences.map((sentence) => _WordChip(
                        word: sentence,
                        settings: settings,
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: inkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: inkSurfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: dotAmber,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _WordChip extends StatefulWidget {
  final String word;
  final MorseSettings settings;

  const _WordChip({required this.word, required this.settings});

  @override
  State<_WordChip> createState() => _WordChipState();
}

class _WordChipState extends State<_WordChip> {
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _isPlaying ? dotAmber.withValues(alpha: 0.2) : inkSurfaceVariant,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _isPlaying ? null : _playWord,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            widget.word,
            style: TextStyle(
              color: _isPlaying ? dotAmber : Colors.white,
              fontSize: 16,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playWord() async {
    setState(() => _isPlaying = true);
    final morse = MorseHapticEngine.textToMorse(widget.word);
    await MorseHapticEngine.playMorseString(morse, widget.settings);
    if (mounted) setState(() => _isPlaying = false);
  }
}
