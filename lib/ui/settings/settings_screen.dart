import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../services/chat_repository.dart';
import '../../services/morse_settings_service.dart';
import '../../services/purchase_service.dart';
import '../theme/silentmorse_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _senderController;
  bool _hasSyncedSender = false;

  @override
  void initState() {
    super.initState();
    _senderController = TextEditingController();
  }

  @override
  void dispose() {
    _senderController.dispose();
    super.dispose();
  }

  void _syncSenderFromService(MorseSettingsService service) {
    if (!_hasSyncedSender) {
      _hasSyncedSender = true;
      _senderController.text = service.senderDisplayName;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Settings', style: TextStyle(fontFamily: 'monospace')),
        backgroundColor: inkDark,
        foregroundColor: Colors.white,
      ),
      backgroundColor: inkBlack,
      body: Consumer3<MorseSettingsService, PurchaseService, AuthService>(
        builder: (context, service, purchase, auth, _) {
          _syncSenderFromService(service);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildAccountSection(context, auth),
              const SizedBox(height: 32),
              _buildRemoveAdsSection(purchase),
              const SizedBox(height: 32),
              _buildIncomingPushSection(auth),
              const SizedBox(height: 32),
              const Text(
                'Group chats',
                style: TextStyle(
                  color: dotAmber,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Name shown when you send from dark mode',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _senderController,
                decoration: InputDecoration(
                  labelText: 'Sender name',
                  hintText: 'Name shown in group chats',
                  hintStyle: const TextStyle(color: Colors.white38),
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: inkSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: inkSurfaceVariant)),
                ),
                style: const TextStyle(color: Colors.white),
                onSubmitted: (v) => service.setSenderDisplayName(v),
                onTapOutside: (_) => service.setSenderDisplayName(_senderController.text),
              ),
              const SizedBox(height: 32),
              const Text(
                'Vibration Volumes',
                style: TextStyle(
                  color: dotAmber,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Vibration when tapping to send',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ...VibrationIntensity.values.map((intensity) => RadioListTile<VibrationIntensity>(
                title: Text(
                  _labelFor(intensity),
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                ),
                subtitle: Text(
                  _subtitleFor(intensity),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: intensity,
                groupValue: service.vibrationIntensity,
                onChanged: (v) => service.setVibrationIntensity(v!),
                activeColor: dotAmber,
              )),
              const SizedBox(height: 32),
              const Text(
                'Auto-send delay',
                style: TextStyle(
                  color: dotAmber,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Seconds of silence before the message is sent automatically.'
                ' Set to 0 to disable auto-send.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('0 s', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: service.autoSendDelayMs / 1000,
                      min: 0,
                      max: 10,
                      divisions: 10,
                      activeColor: dotAmber,
                      inactiveColor: inkSurfaceVariant,
                      label: service.autoSendDelayMs == 0
                          ? 'off'
                          : '${(service.autoSendDelayMs / 1000).toStringAsFixed(0)} s',
                      onChanged: (v) =>
                          service.setAutoSendDelayMs((v * 1000).round()),
                    ),
                  ),
                  Text(
                    service.autoSendDelayMs == 0
                        ? 'off'
                        : '${(service.autoSendDelayMs / 1000).toStringAsFixed(0)} s',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Text(
                'Dark mode gestures',
                style: TextStyle(
                  color: dotAmber,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Short tap = dot • Long press = dash'
                ' • Swipe up or down = send now'
                ' • Two fingers = exit',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIncomingPushSection(AuthService auth) {
    final user = fa.FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Incoming pushes',
          style: TextStyle(
            color: dotAmber,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'When off, new messages are not delivered to this device (no vibration or banner).',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox.shrink();
            }
            final data = snap.data!.data();
            final receiveIncoming = data?['receiveIncoming'] != false;
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Allow incoming messages',
                style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
              ),
              subtitle: const Text(
                'Disabling stops server push for new chat messages',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              value: receiveIncoming,
              activeThumbColor: dotAmber,
              onChanged: (v) {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .set({'receiveIncoming': v}, SetOptions(merge: true));
              },
            );
          },
        ),
      ],
    );
  }

  String _labelFor(VibrationIntensity i) {
    switch (i) {
      case VibrationIntensity.none:
        return 'None';
      case VibrationIntensity.silent:
        return 'Silent';
      case VibrationIntensity.low:
        return 'Low';
      case VibrationIntensity.medium:
        return 'Medium';
      case VibrationIntensity.high:
        return 'High';
    }
  }

  String _subtitleFor(VibrationIntensity i) {
    switch (i) {
      case VibrationIntensity.none:
        return 'Complete silence — no vibration when typing';
      case VibrationIntensity.silent:
        return 'Quietest — minimal buzz';
      case VibrationIntensity.low:
        return 'Quiet';
      case VibrationIntensity.medium:
        return 'Standard';
      case VibrationIntensity.high:
        return 'Strong';
    }
  }

  Widget _buildAccountSection(BuildContext context, AuthService auth) {
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final repo = context.read<ChatRepository>();
    final displayName = user.displayName ?? user.email?.split('@').first ?? 'Morser';

    return FutureBuilder<User?>(
      future: repo.getUserById(user.uid),
      builder: (context, snapshot) {
        final firestoreUser = snapshot.data;
        final username = firestoreUser?.username ?? '';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: inkSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inkSurfaceVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: dotAmber.withValues(alpha: 0.3),
                    foregroundColor: dotAmber,
                    backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                    child: user.photoURL == null
                        ? Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (username.isNotEmpty)
                          Text(
                            '@$username',
                            style: const TextStyle(
                              color: dotAmber,
                              fontSize: 14,
                              fontFamily: 'monospace',
                            ),
                          )
                        else if (user.email != null && user.email!.isNotEmpty)
                          Text(
                            user.email!,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: inkDark,
                        title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
                        content: const Text(
                          'You will need to sign in again to use Silent Morse.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(backgroundColor: dotAmber, foregroundColor: Colors.black),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await auth.signOut();
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.logout, size: 18, color: Colors.white70),
                  label: const Text('Sign out', style: TextStyle(color: Colors.white70)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white38),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDeleteAccount(context, auth),
                  icon: const Icon(Icons.delete_forever, size: 18, color: Colors.redAccent),
                  label: const Text('Delete Account', style: TextStyle(color: Colors.redAccent)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context, AuthService auth) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: inkDark,
        title: const Text('Delete Account?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete your account and all associated data. '
          'This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await auth.deleteAccount();
      if (context.mounted) Navigator.of(context).pop();
    } on fa.FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign out and sign back in, then try again.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: ${e.message}')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account: $e')),
      );
    }
  }

  Widget _buildRemoveAdsSection(PurchaseService purchase) {
    if (purchase.hasRemovedAds) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dotAmber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dotAmber.withValues(alpha: 0.5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: dotAmber, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ad-free • Thanks for your support!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Support Silent Morse',
          style: TextStyle(
            color: dotAmber,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Remove ads forever for \$1.99',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (purchase.error != null) ...[
          Text(
            purchase.error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          onPressed: purchase.isLoading || !purchase.isAvailable
              ? null
              : () => purchase.purchaseRemoveAds(),
          icon: purchase.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Icon(Icons.remove_circle_outline, size: 20),
          label: Text(purchase.isLoading ? 'Processing...' : 'Remove ads — \$1.99'),
          style: FilledButton.styleFrom(
            backgroundColor: dotAmber,
            foregroundColor: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: purchase.isLoading || !purchase.isAvailable
              ? null
              : () => purchase.restorePurchases(),
          child: const Text('Restore purchase', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}
