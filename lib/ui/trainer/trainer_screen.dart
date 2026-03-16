import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/morse_settings_service.dart';
import '../../util/morse_haptic_engine.dart';
import '../theme/silentmorse_theme.dart';

/// Trainer mode — learn morse code.
/// Browse characters, hear/feel haptic patterns, practice tapping.
class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key});

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  String? _selectedChar;
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<MorseSettingsService>().settings;
    final chars = MorseHapticEngine.learnableCharacters;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Learn Morse', style: TextStyle(fontFamily: 'monospace')),
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
                'Tap a character to hear its pattern.\nShort tap = dot •  Long press = dash −',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_selectedChar != null) ...[
                _buildSelectedCharCard(settings),
                const SizedBox(height: 24),
              ],
              const Text(
                'Alphabet',
                style: TextStyle(
                  color: dotAmber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: chars.map((c) => _CharChip(
                  char: c,
                  isSelected: _selectedChar == c,
                  onTap: () => _selectAndPlay(c, settings),
                )).toList(),
              ),
              const SizedBox(height: 24),
              const Text(
                'Digits',
                style: TextStyle(
                  color: dotAmber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: '0123456789'.split('').map((c) => _CharChip(
                  char: c,
                  isSelected: _selectedChar == c,
                  onTap: () => _selectAndPlay(c, settings),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedCharCard(MorseSettings settings) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: inkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dotAmber.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(
            _selectedChar!,
            style: const TextStyle(
              color: dotAmber,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            MorseHapticEngine.charToMorse(_selectedChar!) ?? '',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 24,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isPlaying ? null : () => _playSelected(settings),
            icon: _isPlaying
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow),
            label: Text(_isPlaying ? 'Playing...' : 'Play haptic'),
            style: FilledButton.styleFrom(
              backgroundColor: dotAmber,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  void _selectAndPlay(String char, MorseSettings settings) {
    setState(() => _selectedChar = char);
    _playSelected(settings);
  }

  Future<void> _playSelected(MorseSettings settings) async {
    if (_selectedChar == null || _isPlaying) return;
    setState(() => _isPlaying = true);
    final morse = MorseHapticEngine.charToMorse(_selectedChar!);
    if (morse != null && morse.isNotEmpty) {
      await MorseHapticEngine.playMorseString(morse, settings);
    }
    if (mounted) setState(() => _isPlaying = false);
  }
}

class _CharChip extends StatelessWidget {
  final String char;
  final bool isSelected;
  final VoidCallback onTap;

  const _CharChip({required this.char, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? dotAmber.withValues(alpha: 0.3) : inkSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            char,
            style: TextStyle(
              color: isSelected ? dotAmber : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
