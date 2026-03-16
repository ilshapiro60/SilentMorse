import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../services/chat_repository.dart';
import '../../services/purchase_service.dart';
import '../ads/ad_banner_widget.dart';
import '../theme/silentmorse_theme.dart';
import '../chat/chat_screen.dart';
import '../trainer/trainer_screen.dart';
import '../test/test_screen.dart';
import '../settings/settings_screen.dart';
import 'package:intl/intl.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Expanded(child: _ContactsBody()),
          Consumer<PurchaseService>(
            builder: (context, purchase, _) => AdBannerWidget(
              showAds: !purchase.hasRemovedAds,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context),
        backgroundColor: dotAmber,
        foregroundColor: Colors.black,
        child: const Icon(Icons.edit),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _AddContactSheet(),
    );
  }

}

class _ContactsBody extends StatefulWidget {
  const _ContactsBody();

  @override
  State<_ContactsBody> createState() => _ContactsBodyState();
}

class _ContactsBodyState extends State<_ContactsBody> {
  final _nameCache = <String, String>{};

  Future<void> _ensureName(Chat chat, String myUserId, ChatRepository repo) async {
    final otherId = chat.otherParticipant(myUserId);
    if (otherId.isEmpty || _nameCache.containsKey(otherId)) return;
    final user = await repo.getUserById(otherId);
    if (mounted) {
      setState(() {
        _nameCache[otherId] = user?.displayName ?? user?.username ?? 'Contact';
      });
    }
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _AddContactSheet(),
    );
  }

  void _showCreateGroupSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _CreateGroupSheet(),
    );
  }

  void _showPracticeMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Learn & Practice',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Train your morse code skills',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.abc),
                title: const Text('Learn Morse'),
                subtitle: const Text('Browse alphabet. Short tap = dot, long press = dash'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TrainerScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.touch_app),
                title: const Text('Practice Morse'),
                subtitle: const Text('Tap to encode. Swipe up to send, two fingers to exit'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TestScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ChatRepository>();
    final auth = context.read<AuthService>();
    final myUserId = auth.currentUser?.uid ?? '';

    return StreamBuilder<List<Chat>>(
      stream: repo.observeChats(),
      builder: (context, snapshot) {
        final chats = snapshot.data ?? [];

        return CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(
                'Silent Morse',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.group_add),
                  onPressed: () => _showCreateGroupSheet(context),
                ),
                IconButton(
                  icon: const Icon(Icons.person_add),
                  onPressed: () => _showAddSheet(context),
                ),
                IconButton(
                  icon: const Icon(Icons.school),
                  onPressed: () => _showPracticeMenu(context),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),
            if (chats.isEmpty)
              SliverFillRemaining(
                child: _EmptyContactsState(
                  onAddContact: () => _showAddSheet(context),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final chat = chats[index];
                    final otherId = chat.otherParticipant(myUserId);
                    final contactName = _nameCache[otherId] ?? 'Loading...';
                    _ensureName(chat, myUserId, repo);

                    final chatTitle = chat.isGroup ? (chat.name.isNotEmpty ? chat.name : 'Group') : (_nameCache[otherId] ?? contactName);

                    return _ChatListItem(
                      chat: chat,
                      chatTitle: chatTitle,
                      isGroup: chat.isGroup,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              chatId: chat.id,
                              chatTitle: chatTitle,
                              isGroup: chat.isGroup,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  childCount: chats.length,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChatListItem extends StatelessWidget {
  final Chat chat;
  final String chatTitle;
  final bool isGroup;
  final VoidCallback onTap;

  const _ChatListItem({
    required this.chat,
    required this.chatTitle,
    this.isGroup = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _ContactAvatar(name: chatTitle, size: 52, isGroup: isGroup),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        chatTitle,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isGroup && chat.lastMessageBy.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          '•',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                  if (chat.lastMessage.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      chat.lastMessage,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (chat.lastMessageAt != null)
              Text(
                _formatTimestamp(chat.lastMessageAt!),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime date) {
    final now = DateTime.now();
    if (now.day == date.day && now.month == date.month && now.year == date.year) {
      return DateFormat('HH:mm').format(date);
    }
    if (now.difference(date).inDays < 7) {
      return DateFormat('EEE').format(date);
    }
    return DateFormat('dd/MM').format(date);
  }
}

class _ContactAvatar extends StatelessWidget {
  final String name;
  final int size;
  final bool isGroup;

  const _ContactAvatar({required this.name, this.size = 44, this.isGroup = false});

  @override
  Widget build(BuildContext context) {
    final initial = isGroup ? null : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    final colors = [
      const Color(0xFFE53935),
      const Color(0xFF8E24AA),
      const Color(0xFF1E88E5),
      const Color(0xFF00ACC1),
      const Color(0xFF43A047),
      const Color(0xFFFB8C00),
      const Color(0xFF6D4C41),
      const Color(0xFF546E7A),
    ];
    final color = colors[name.hashCode.abs() % colors.length];

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: isGroup
          ? Icon(Icons.group, color: Colors.white, size: size * 0.5)
          : Text(
              initial ?? '?',
              style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.bold),
            ),
    );
  }
}

class _EmptyContactsState extends StatelessWidget {
  final VoidCallback onAddContact;

  const _EmptyContactsState({required this.onAddContact});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...List.generate(3, (_) => Container(width: 8, height: 8, margin: const EdgeInsets.all(2), decoration: const BoxDecoration(color: dotAmber, shape: BoxShape.circle))),
                const SizedBox(width: 4),
                ...List.generate(3, (_) => Container(width: 20, height: 8, margin: const EdgeInsets.all(2), decoration: BoxDecoration(color: dotAmber, borderRadius: BorderRadius.circular(4)))),
                const SizedBox(width: 4),
                ...List.generate(3, (_) => Container(width: 8, height: 8, margin: const EdgeInsets.all(2), decoration: const BoxDecoration(color: dotAmber, shape: BoxShape.circle))),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'No conversations yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Find a friend by username\nand start tapping',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onAddContact,
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Find Someone'),
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet();

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<User> _searchResults = [];
  bool _isSearching = false;
  bool _isCreatingChat = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final trimmed = query.trim();
      if (trimmed.length < 2) {
        setState(() {
          _searchQuery = query;
          _searchResults = [];
          _isSearching = false;
        });
        return;
      }
      setState(() => _isSearching = true);
      try {
        final repo = context.read<ChatRepository>();
        final myUserId = context.read<AuthService>().currentUser?.uid ?? '';

        final byUsername = await repo.findUserByUsername(trimmed.toLowerCase());
        final byDisplayName = await repo.findUsersByDisplayName(trimmed);

        final seen = <String>{};
        final combined = <User>[];
        if (byUsername != null && byUsername.id != myUserId && !seen.contains(byUsername.id)) {
          seen.add(byUsername.id);
          combined.add(byUsername);
        }
        for (final u in byDisplayName) {
          if (!seen.contains(u.id)) {
            seen.add(u.id);
            combined.add(u);
          }
        }

        if (!mounted) return;
        setState(() {
          _searchQuery = query;
          _searchResults = combined;
          _isSearching = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Search failed: $e';
          _isSearching = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Find someone', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Search by @username or Google name',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: 'e.g. @username or Name',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                suffixIcon: _isSearching
                    ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                    : _searchQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear())
                        : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          if (_searchResults.isNotEmpty)
            ..._searchResults.map((user) => _UserSearchResult(
                  user: user,
                  isLoading: _isCreatingChat,
                  onSelect: () => _startChat(context, user),
                )),
          if (_searchQuery.trim().length >= 2 && _searchResults.isEmpty && !_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No one found for "$_searchQuery"', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startChat(BuildContext context, User user) async {
    setState(() {
      _isCreatingChat = true;
      _error = null;
    });
    try {
      final chatId = await context.read<ChatRepository>().getOrCreateChat(user.id);
      if (!context.mounted) return;
      await context.read<ChatRepository>().addContact(user);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(chatId: chatId, chatTitle: user.displayName, isGroup: false),
        ),
      );
    } catch (e) {
      setState(() {
        _isCreatingChat = false;
        _error = 'Couldn\'t start chat: $e';
      });
    }
  }
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet();

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameController = TextEditingController();
  final _selectedIds = <String>{};
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup(BuildContext context) async {
    if (_selectedIds.isEmpty) {
      setState(() => _error = 'Select at least one person');
      return;
    }
    setState(() {
      _isCreating = true;
      _error = null;
    });
    try {
      final chatId = await context.read<ChatRepository>().createGroupChat(
        _nameController.text.trim(),
        _selectedIds.toList(),
      );
      if (!context.mounted) return;
      final groupName = _nameController.text.trim().isEmpty ? 'Group' : _nameController.text.trim();
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(chatId: chatId, chatTitle: groupName, isGroup: true),
        ),
      );
    } catch (e) {
      setState(() {
        _isCreating = false;
        _error = 'Couldn\'t create group: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: StreamBuilder<List<Contact>>(
        stream: context.read<ChatRepository>().observeContacts(),
        builder: (context, snapshot) {
          final contacts = snapshot.data ?? [];
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Group', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'Group name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Add people', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Add contacts first to create a group',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final c = contacts[index];
                        final displayName = c.nickname.isNotEmpty ? c.nickname : (c.displayName.isNotEmpty ? c.displayName : c.username);
                        final isSelected = _selectedIds.contains(c.userId);
                        return CheckboxListTile(
                          title: Text(displayName),
                          subtitle: c.username.isNotEmpty ? Text('@${c.username}') : null,
                          value: isSelected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.add(c.userId);
                              } else {
                                _selectedIds.remove(c.userId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isCreating || contacts.isEmpty ? null : () => _createGroup(context),
                  child: _isCreating ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create Group'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserSearchResult extends StatelessWidget {
  final User user;
  final bool isLoading;
  final VoidCallback onSelect;

  const _UserSearchResult({required this.user, required this.isLoading, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: isLoading ? null : onSelect,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _ContactAvatar(name: user.displayName, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text('@${user.username}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                    ],
                  ),
                ),
                if (isLoading)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(Icons.message, color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
