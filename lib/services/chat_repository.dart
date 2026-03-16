import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:cloud_functions/cloud_functions.dart';

import '../data/models.dart';
import '../util/morse_haptic_engine.dart';

/// Base class for chat data. [FirestoreChatRepository] is the real impl;
/// [MockChatRepository] is used for screenshot capture.
abstract class ChatRepository {
  Stream<List<Chat>> observeChats();
  Stream<List<Message>> observeMessages(String chatId);
  Future<User?> getUserById(String userId);
  Future<String> getOrCreateChat(String targetUserId);
  Future<String> createGroupChat(String name, List<String> participantIds);
  Future<void> sendMessage(String chatId, String text, {InputMode inputMode = InputMode.typed, String? senderDisplayName});
  Future<void> addContact(User user);
  Stream<List<Contact>> observeContacts();
  Future<User?> findUserByUsername(String username);
  Future<List<User>> findUsersByDisplayName(String query);
}

class FirestoreChatRepository extends ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String get _myUserId => _auth.currentUser?.uid ?? (throw StateError('User not authenticated'));

  // ─────────────────────────────────────────────
  // CHAT LIST
  // ─────────────────────────────────────────────

  @override
  Stream<List<Chat>> observeChats() {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: _myUserId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => Chat.fromFirestore(d)).toList());
  }

  // ─────────────────────────────────────────────
  // CREATE CHAT
  // ─────────────────────────────────────────────

  @override
  Future<String> getOrCreateChat(String targetUserId) async {
    final result = await _functions.httpsCallable('createChat').call({'targetUserId': targetUserId});
    final data = result.data as Map<String, dynamic>;
    return data['chatId'] as String;
  }

  @override
  Future<String> createGroupChat(String name, List<String> participantIds) async {
    final allParticipants = [_myUserId, ...participantIds.where((id) => id != _myUserId)];
    if (allParticipants.length < 2) throw StateError('Group needs at least 2 people');

    final docRef = await _firestore.collection('chats').add({
      'participants': allParticipants,
      'name': name.trim().isEmpty ? 'Group' : name.trim(),
      'lastMessage': '',
      'lastMessageBy': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  // ─────────────────────────────────────────────
  // MESSAGES
  // ─────────────────────────────────────────────

  @override
  Stream<List<Message>> observeMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => Message.fromFirestore(d)).toList());
  }

  @override
  Future<void> sendMessage(String chatId, String text, {InputMode inputMode = InputMode.typed, String? senderDisplayName}) async {
    final morse = MorseHapticEngine.textToMorse(text);
    final data = <String, dynamic>{
      'senderId': _myUserId,
      'text': text,
      'morse': morse,
      'inputMode': inputMode.name.toUpperCase(),
      'sentAt': FieldValue.serverTimestamp(),
      'deliveredAt': null,
      'readAt': null,
    };
    if (senderDisplayName != null && senderDisplayName.isNotEmpty) {
      data['senderDisplayName'] = senderDisplayName;
    }
    await _firestore.collection('chats').doc(chatId).collection('messages').add(data);
    await _firestore.collection('chats').doc(chatId).update({
      'lastMessage': text,
      'lastMessageBy': _myUserId,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAsRead(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'readAt': FieldValue.serverTimestamp()});
  }

  // ─────────────────────────────────────────────
  // USER LOOKUP
  // ─────────────────────────────────────────────

  @override
  Future<User?> findUserByUsername(String username) async {
    final usernameDoc = await _firestore
        .collection('usernames')
        .doc(username.toLowerCase().trim())
        .get();

    final userId = usernameDoc.data()?['userId'] as String?;
    if (userId == null) return null;

    final userDoc = await _firestore.collection('users').doc(userId).get();
    return userDoc.exists ? User.fromFirestore(userDoc) : null;
  }

  /// Search users by Google display name (prefix match, case-insensitive).
  /// Returns up to 20 matches. Excludes the current user.
  @override
  Future<List<User>> findUsersByDisplayName(String query) async {
    final prefix = query.trim().toLowerCase();
    if (prefix.isEmpty) return [];

    final snapshot = await _firestore
        .collection('users')
        .where('displayNameLower', isGreaterThanOrEqualTo: prefix)
        .where('displayNameLower', isLessThanOrEqualTo: '$prefix\uf8ff')
        .limit(20)
        .get();

    final users = snapshot.docs
        .map((d) => User.fromFirestore(d))
        .where((u) => u.id != _myUserId)
        .toList();
    return users;
  }

  @override
  Future<User?> getUserById(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.exists ? User.fromFirestore(doc) : null;
  }

  // ─────────────────────────────────────────────
  // CONTACTS
  // ─────────────────────────────────────────────

  @override
  Stream<List<Contact>> observeContacts() {
    return _firestore
        .collection('users')
        .doc(_myUserId)
        .collection('contacts')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => Contact.fromFirestore(d)).toList());
  }

  @override
  Future<void> addContact(User user) async {
    await _firestore
        .collection('users')
        .doc(_myUserId)
        .collection('contacts')
        .doc(user.id)
        .set({
      'userId': user.id,
      'displayName': user.displayName,
      'username': user.username,
      'nickname': '',
      'addedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─────────────────────────────────────────────
  // USER PROFILE
  // ─────────────────────────────────────────────

  Future<void> updateMorseSettings(MorseSettings settings) async {
    await _firestore.collection('users').doc(_myUserId).update({
      'morseSettings': settings.toMap(),
    });
  }

  Future<void> updateFcmToken(String token) async {
    await _firestore.collection('users').doc(_myUserId).update({'fcmToken': token});
  }
}
