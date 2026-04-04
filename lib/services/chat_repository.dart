import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:rxdart/rxdart.dart';

import '../data/models.dart';
import '../util/content_filter.dart';
import '../util/morse_haptic_engine.dart';

/// Thrown when starting a 1:1 chat with someone you have blocked.
class BlockedUserException implements Exception {
  const BlockedUserException([
    this.message = 'You blocked this person. Unblock them in Settings to chat again.',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Base class for chat data. [FirestoreChatRepository] is the real impl;
/// [MockChatRepository] is used for screenshot capture.
abstract class ChatRepository {
  Stream<List<Chat>> observeChats();
  Stream<List<Message>> observeMessages(String chatId);
  Future<User?> getUserById(String userId);
  Future<String> getOrCreateChat(String targetUserId);
  Future<String> createGroupChat(String name, List<String> participantIds);
  /// Returns the new message document id.
  /// [onMessageId] is invoked synchronously with that id before the write
  /// completes so UI can track the doc (e.g. broom filter) before snapshot updates.
  Future<String> sendMessage(
    String chatId,
    String text, {
    InputMode inputMode = InputMode.typed,
    String? senderDisplayName,
    void Function(String messageId)? onMessageId,
  });
  Future<void> approveChat(String chatId);
  Future<void> declineChat(String chatId);
  Future<void> deleteChat(String chatId);
  Future<void> deleteMessage(String chatId, String messageId);
  Future<void> pruneOldMessages(String chatId);
  Future<Message?> getLastMyMessage(String chatId);
  Future<void> addContact(User user);
  Stream<List<Contact>> observeContacts();
  Future<User?> findUserByUsername(String username);
  Future<List<User>> findUsersByDisplayName(String query);
  Future<void> blockUser(String targetUserId, String? chatId);
  Future<void> unblockUser(String targetUserId);
  Future<void> reportUser(String targetUserId, String? chatId, String reason);
  Stream<List<String>> observeBlockedUsers();
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
    final chatsStream = _firestore
        .collection('chats')
        .where('participants', arrayContains: _myUserId)
        .snapshots();
    final blockedStream = _firestore
        .collection('users')
        .doc(_myUserId)
        .collection('blockedUsers')
        .snapshots();

    // Re-emit when either chats OR blockedUsers changes (asyncMap on chats alone
    // missed block/unblock updates, so the list stayed stale).
    return Rx.combineLatest2<QuerySnapshot<Map<String, dynamic>>,
        QuerySnapshot<Map<String, dynamic>>, List<Chat>>(
      chatsStream,
      blockedStream,
      (chatSnap, blockedSnap) {
        final blockedIds = blockedSnap.docs.map((d) => d.id).toSet();

        final chats = chatSnap.docs
            .map((d) => Chat.fromFirestore(d))
            .where((chat) {
              if (chat.isGroup) return true;
              final other = chat.otherParticipant(_myUserId);
              if (other.isEmpty) return false;
              return !blockedIds.contains(other);
            })
            .toList();

        chats.sort((a, b) {
          final ta = a.lastMessageAt;
          final tb = b.lastMessageAt;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
        return chats;
      },
    );
  }

  // ─────────────────────────────────────────────
  // CREATE CHAT
  // ─────────────────────────────────────────────

  @override
  Future<String> getOrCreateChat(String targetUserId) async {
    final blocked = await _firestore
        .collection('users')
        .doc(_myUserId)
        .collection('blockedUsers')
        .doc(targetUserId)
        .get();
    if (blocked.exists) {
      throw const BlockedUserException();
    }

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
      'isGroup': true,
      'status': 'ACTIVE',
      'requesterId': '',
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

  /// All message docs for the chat, sorted oldest → newest (pending [sentAt]
  /// last). No Firestore [orderBy]: ordering on [sentAt] can omit or reshuffle
  /// docs while [serverTimestamp] is resolving, which made bubbles vanish.
  @override
  Stream<List<Message>> observeMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .snapshots()
        .map((snapshot) {
      final list =
          snapshot.docs.map((d) => Message.fromFirestore(d)).toList();
      list.sort(_compareMessagesChronological);
      return list;
    });
  }

  static int _compareMessagesChronological(Message a, Message b) {
    final ta = a.sentAt;
    final tb = b.sentAt;
    if (ta == null && tb == null) return a.id.compareTo(b.id);
    if (ta == null) return 1;
    if (tb == null) return -1;
    final c = ta.compareTo(tb);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  @override
  Future<String> sendMessage(
    String chatId,
    String text, {
    InputMode inputMode = InputMode.typed,
    String? senderDisplayName,
    void Function(String messageId)? onMessageId,
  }) async {
    final filtered = filterProfanity(text);
    final morse = MorseHapticEngine.textToMorse(filtered);
    final data = <String, dynamic>{
      'senderId': _myUserId,
      'text': filtered,
      'morse': morse,
      'inputMode': inputMode.name.toUpperCase(),
      'sentAt': FieldValue.serverTimestamp(),
      'deliveredAt': null,
      'readAt': null,
    };
    if (senderDisplayName != null && senderDisplayName.isNotEmpty) {
      data['senderDisplayName'] = senderDisplayName;
    }
    final ref = _firestore.collection('chats').doc(chatId).collection('messages').doc();
    onMessageId?.call(ref.id);
    await ref.set(data);
    await _firestore.collection('chats').doc(chatId).update({
      'lastMessage': filtered,
      'lastMessageBy': _myUserId,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    // Fire-and-forget: prune old messages so the collection stays small.
    pruneOldMessages(chatId);
    return ref.id;
  }

  @override
  Future<void> approveChat(String chatId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .update({'status': 'ACTIVE'});
  }

  @override
  Future<void> declineChat(String chatId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .update({'status': 'DECLINED'});
  }

  @override
  Future<void> deleteChat(String chatId) async {
    // Delete all messages in batches of 500, then delete the chat document.
    const batchSize = 500;
    final messagesRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages');
    QuerySnapshot snapshot;
    do {
      snapshot = await messagesRef.limit(batchSize).get();
      if (snapshot.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } while (snapshot.docs.length == batchSize);

    await _firestore.collection('chats').doc(chatId).delete();
  }

  @override
  Future<void> deleteMessage(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  @override
  Future<Message?> getLastMyMessage(String chatId) async {
    final snapshot = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isEqualTo: _myUserId)
        .orderBy('sentAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return Message.fromFirestore(snapshot.docs.first);
  }

  /// Keep only the latest [keep] messages per sender in a chat.
  /// Deletes older messages from Firestore.
  static const int _kKeepPerSender = 10;

  @override
  Future<void> pruneOldMessages(String chatId) async {
    final messagesRef =
        _firestore.collection('chats').doc(chatId).collection('messages');
    final allDocs = await messagesRef.orderBy('sentAt', descending: true).get();

    final perSender = <String, int>{};
    final toDelete = <DocumentReference>[];

    for (final doc in allDocs.docs) {
      final senderId = doc.data()['senderId'] as String? ?? '';
      final count = perSender[senderId] ?? 0;
      if (count < _kKeepPerSender) {
        perSender[senderId] = count + 1;
      } else {
        toDelete.add(doc.reference);
      }
    }

    if (toDelete.isEmpty) return;

    for (var i = 0; i < toDelete.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = toDelete.sublist(i, i + 500 > toDelete.length ? toDelete.length : i + 500);
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
    }
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

  // ─────────────────────────────────────────────
  // BLOCK & REPORT
  // ─────────────────────────────────────────────

  @override
  Future<void> blockUser(String targetUserId, String? chatId) async {
    await _functions.httpsCallable('blockUser').call({
      'targetUserId': targetUserId,
      if (chatId != null) 'chatId': chatId,
    });
  }

  @override
  Future<void> unblockUser(String targetUserId) async {
    await _functions.httpsCallable('unblockUser').call({
      'targetUserId': targetUserId,
    });
  }

  @override
  Future<void> reportUser(String targetUserId, String? chatId, String reason) async {
    await _functions.httpsCallable('reportContent').call({
      'targetUserId': targetUserId,
      'reason': reason,
      if (chatId != null) 'chatId': chatId,
    });
  }

  @override
  Stream<List<String>> observeBlockedUsers() {
    return _firestore
        .collection('users')
        .doc(_myUserId)
        .collection('blockedUsers')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList());
  }
}
