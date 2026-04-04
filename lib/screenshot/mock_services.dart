
import '../data/models.dart';
import '../services/chat_repository.dart';

/// Mock ChatRepository for screenshot capture. Returns fake chats and messages.
class MockChatRepository extends ChatRepository {
  static final _fakeChats = [
    Chat(
      id: 'chat1',
      participants: ['screenshot-user', 'contact1'],
      name: '',
      lastMessage: '... --- ...',
      lastMessageBy: 'contact1',
      lastMessageAt: DateTime.now().subtract(const Duration(minutes: 2)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Chat(
      id: 'chat2',
      participants: ['screenshot-user', 'contact2'],
      name: '',
      lastMessage: 'HI THERE',
      lastMessageBy: 'screenshot-user',
      lastMessageAt: DateTime.now().subtract(const Duration(hours: 1)),
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    Chat(
      id: 'chat3',
      participants: ['screenshot-user', 'c1', 'c2'],
      name: 'Team',
      lastMessage: 'SEND HELP',
      lastMessageBy: 'c1',
      lastMessageAt: DateTime.now().subtract(const Duration(minutes: 30)),
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
    ),
  ];

  static final _fakeMessages = [
    Message(
      id: 'm1',
      senderId: 'contact1',
      senderDisplayName: 'Alex',
      text: '... --- ...',
      morse: '... --- ...',
      inputMode: InputMode.typed,
      sentAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    Message(
      id: 'm2',
      senderId: 'screenshot-user',
      senderDisplayName: '',
      text: 'HI THERE',
      morse: '.... ..   - .... . .-. .',
      inputMode: InputMode.typed,
      sentAt: DateTime.now().subtract(const Duration(minutes: 3)),
    ),
    Message(
      id: 'm3',
      senderId: 'contact1',
      senderDisplayName: 'Alex',
      text: 'I AM OK',
      morse: '..   .- --   --- -.-',
      inputMode: InputMode.typed,
      sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
    ),
  ];

  @override
  Stream<List<Chat>> observeChats() => Stream.value(_fakeChats);

  @override
  Stream<List<Message>> observeMessages(String chatId) => Stream.value(_fakeMessages);

  @override
  Future<User?> getUserById(String id) async => User(
        id: id,
        displayName: id == 'contact1' ? 'Alex' : id == 'contact2' ? 'Sam' : 'Contact',
        username: id == 'contact1' ? 'alex_m' : 'user',
      );

  @override
  Future<String> getOrCreateChat(String targetUserId) async => 'mock-chat-id';

  @override
  Future<String> createGroupChat(String name, List<String> participantIds) async => 'mock-group-id';

  @override
  Future<String> sendMessage(
    String chatId,
    String text, {
    InputMode inputMode = InputMode.typed,
    String? senderDisplayName,
    void Function(String messageId)? onMessageId,
  }) async {
    onMessageId?.call('mock-message-id');
    return 'mock-message-id';
  }

  @override
  Future<void> approveChat(String chatId) async {}

  @override
  Future<void> declineChat(String chatId) async {}

  @override
  Future<void> deleteChat(String chatId) async {}

  @override
  Future<void> deleteMessage(String chatId, String messageId) async {}

  @override
  Future<void> pruneOldMessages(String chatId) async {}

  @override
  Future<Message?> getLastMyMessage(String chatId) async => null;

  @override
  Future<void> addContact(User user) async {}

  @override
  Stream<List<Contact>> observeContacts() => Stream.value([]);

  @override
  Future<User?> findUserByUsername(String username) async => null;

  @override
  Future<List<User>> findUsersByDisplayName(String query) async => [];

  @override
  Future<void> blockUser(String targetUserId, String? chatId) async {}

  @override
  Future<void> unblockUser(String targetUserId) async {}

  @override
  Future<void> reportUser(String targetUserId, String? chatId, String reason) async {}

  @override
  Stream<List<String>> observeBlockedUsers() => Stream.value([]);
}
