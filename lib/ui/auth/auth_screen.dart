import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../legal/legal_screen.dart';
import '../theme/silentmorse_theme.dart';

enum AuthStep { chooseMethod, setUsername }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthStep _step = AuthStep.chooseMethod;
  bool _isLoading = false;
  String? _error;

  void _setLoading(bool loading) {
    setState(() {
      _isLoading = loading;
      _error = null;
    });
  }

  void _setError(String message) {
    setState(() {
      _isLoading = false;
      _error = message;
    });
  }

  Future<void> _signInWithGoogle() async {
    _setLoading(true);
    try {
      await context.read<AuthService>().signInWithGoogle();
      if (!mounted) return;
      final needsUsername = await context.read<AuthService>().needsUsername();
      if (!mounted) return;
      if (needsUsername) {
        setState(() {
          _step = AuthStep.setUsername;
          _isLoading = false;
        });
      }
    } catch (e) {
      _setError('Google sign-in failed: $e');
    }
  }

  Future<void> _signInWithApple() async {
    _setLoading(true);
    try {
      await context.read<AuthService>().signInWithApple();
      if (!mounted) return;
      final needsUsername = await context.read<AuthService>().needsUsername();
      if (!mounted) return;
      if (needsUsername) {
        setState(() {
          _step = AuthStep.setUsername;
          _isLoading = false;
        });
      }
    } catch (e) {
      _setError('Apple sign-in failed: $e');
    }
  }

  Future<void> _claimUsername(String username) async {
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username)) {
      _setError('Username must be 3-20 chars, lowercase letters, numbers, underscores only');
      return;
    }
    _setLoading(true);
    try {
      await context.read<AuthService>().claimUsername(username);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('already-exists')) {
        _setError('Username @$username is taken');
      } else if (msg.contains('invalid-argument')) {
        _setError('Invalid username format');
      } else {
        _setError('Failed to claim username: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _MorseLogoHeader(),
                const SizedBox(height: 48),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildStepContent(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case AuthStep.chooseMethod:
        return _ChooseMethodStep(
          key: const ValueKey('choose'),
          isLoading: _isLoading,
          onGoogleSignIn: _signInWithGoogle,
          onAppleSignIn: _signInWithApple,
        );
      case AuthStep.setUsername:
        return _SetUsernameStep(
          key: const ValueKey('username'),
          isLoading: _isLoading,
          onClaim: _claimUsername,
        );
    }
  }
}

class _MorseLogoHeader extends StatelessWidget {
  const _MorseLogoHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildMorseBar(true),
            _buildMorseBar(false),
            _buildMorseBar(false),
            const SizedBox(width: 6),
            _buildMorseBar(true),
            _buildMorseBar(false),
            _buildMorseBar(false),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Silent Morse',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Communicate in silence',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildMorseBar(bool isLong) {
    return Container(
      height: 8,
      width: isLong ? 24 : 8,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: dotAmber,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ChooseMethodStep extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onAppleSignIn;

  const _ChooseMethodStep({
    super.key,
    required this.isLoading,
    required this.onGoogleSignIn,
    required this.onAppleSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: isLoading ? null : onGoogleSignIn,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('G', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[700], fontSize: 18)),
                      const SizedBox(width: 12),
                      const Text('Continue with Google'),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: isLoading ? null : onAppleSignIn,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.apple, color: Colors.white, size: 22),
                SizedBox(width: 12),
                Text('Continue with Apple'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LegalScreen()),
          ),
          child: Text(
            'By continuing you agree to our Terms of Service and Privacy Policy.',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              decoration: TextDecoration.underline,
              decorationColor: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _SetUsernameStep extends StatefulWidget {
  final bool isLoading;
  final void Function(String) onClaim;

  const _SetUsernameStep({
    super.key,
    required this.isLoading,
    required this.onClaim,
  });

  @override
  State<_SetUsernameStep> createState() => _SetUsernameStepState();
}

class _SetUsernameStepState extends State<_SetUsernameStep> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final username = _controller.text.toLowerCase().replaceAll(' ', '_');
    final isValid = RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choose a username', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Others will find you by this name. Lowercase letters, numbers, and underscores only.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Username',
            hintText: 'e.g. jane_doe',
            prefixText: '@',
            errorText: username.isNotEmpty && !isValid ? '3–20 chars, lowercase letters, numbers, _ only' : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: isValid && !widget.isLoading ? () => widget.onClaim(username) : null,
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: widget.isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Claim @$username'),
          ),
        ),
      ],
    );
  }
}
