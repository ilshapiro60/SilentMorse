import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../firebase_options.dart';

String _sha256ofString(String input) {
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

class AuthService {
  AuthService({firebase_auth.FirebaseAuth? auth})
      : _auth = auth ?? firebase_auth.FirebaseAuth.instance;
  final firebase_auth.FirebaseAuth _auth;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: DefaultFirebaseOptions.ios.iosClientId,
  );

  firebase_auth.User? get currentUser => _auth.currentUser;
  Stream<firebase_auth.User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return;

    final googleAuth = await googleUser.authentication;
    final credential = firebase_auth.GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    await _handleSignInResult(result, isGuest: false);
  }

  Future<void> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonceHash = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonceHash,
    );

    final oauthCredential = firebase_auth.OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    final result = await _auth.signInWithCredential(oauthCredential);
    final user = result.user;
    if (user == null) return;

    final displayName = _appleDisplayName(appleCredential) ??
        user.displayName ??
        user.email?.split('@').first ??
        'Morser';

    await _handleSignInResult(result, isGuest: false, displayNameOverride: displayName);
  }

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String? _appleDisplayName(AuthorizationCredentialAppleID credential) {
    final givenName = credential.givenName;
    final familyName = credential.familyName;
    if (givenName != null || familyName != null) {
      return [givenName, familyName].whereType<String>().join(' ').trim();
    }
    return null;
  }

  Future<void> signInAnonymously() async {
    final result = await _auth.signInAnonymously();
    await _handleSignInResult(result, isGuest: true);
  }

  Future<void> sendVerificationCode(String phoneNumber) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (e) {
        throw firebase_auth.FirebaseAuthException(message: e.message, code: e.code);
      },
      codeSent: (verificationId, _) {
        // Store verificationId for later - would need to pass to verify step
        // For now, phone auth flow would need a separate state/callback
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _handleSignInResult(
    firebase_auth.UserCredential result, {
    required bool isGuest,
    String? displayNameOverride,
  }) async {
    final user = result.user;
    if (user == null) throw StateError('No user returned');

    final isNewUser = result.additionalUserInfo?.isNewUser ?? false;
    final displayName = displayNameOverride ??
        user.displayName ??
        user.email?.split('@').first ??
        'Morser';

    if (isNewUser || isGuest) {
      await _firestore.collection('users').doc(user.uid).set({
        'displayName': displayName,
        'displayNameLower': displayName.toLowerCase(),
        'username': '',
        'phoneHash': '',
        'fcmToken': '',
        'isPro': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'morseSettings': {
          'dotDurationMs': 100,
          'dashDurationMs': 300,
          'letterGapMs': 600,
          'wordGapMs': 1400,
          'vibrationIntensity': 'MEDIUM',
        },
      }, SetOptions(merge: true));
    } else {
      await _firestore.collection('users').doc(user.uid).set({
        'displayName': displayName,
        'displayNameLower': displayName.toLowerCase(),
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<bool> needsUsername() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    final doc = await _firestore.collection('users').doc(uid).get();
    final username = doc.data()?['username'] as String?;
    return username == null || username.isEmpty;
  }

  Future<void> claimUsername(String username) async {
    await _functions.httpsCallable('claimUsername').call({'username': username});
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
