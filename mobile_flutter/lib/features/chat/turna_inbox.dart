part of turna_app;

class ChatsPage extends StatefulWidget {
  const ChatsPage({
    super.key,
    required this.session,
    required this.onSessionExpired,
    required this.callCoordinator,
    this.inboxUpdateNotifier,
    this.onUnreadChanged,
  });

  final AuthSession session;
  final VoidCallback onSessionExpired;
  final TurnaCallCoordinator callCoordinator;
  final ValueNotifier<int>? inboxUpdateNotifier;
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

enum _ChatsMenuAction { select, markAllRead }

class _ChatsPageViewData {
  const _ChatsPageViewData({
    required this.folders,
    required this.archivedChats,
    required this.filteredChats,
    required this.hasAnyActiveChats,
    required this.unreadTotal,
    required this.query,
  });

  final List<ChatFolder> folders;
  final List<ChatPreview> archivedChats;
  final List<ChatPreview> filteredChats;
  final bool hasAnyActiveChats;
  final int unreadTotal;
  final String query;

  bool get archivedTopVisible => archivedChats.isNotEmpty;
  bool get filtersVisible => folders.isNotEmpty;
}

class _ChatsPageState extends State<ChatsPage> {
  static const String _allChatsFilterId = '__all__';

  int _refreshTick = 0;
  bool _selectionMode = false;
  bool _bulkActionBusy = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedChatIds = <String>{};
  late Future<ChatInboxData> _inboxFuture;
  ChatInboxData? _cachedInbox;
  String _selectedFilterId = _allChatsFilterId;
  ChatInboxData? _cachedViewInbox;
  _ChatsPageViewData? _cachedViewData;
  String _cachedViewQuery = '';
  String _cachedViewFilterId = _allChatsFilterId;
  int? _lastReportedUnreadTotal;

  @override
  void initState() {
    super.initState();
    _cachedInbox = TurnaChatInboxLocalCache.peek(widget.session.userId);
    _inboxFuture = _fetchInbox();
    unawaited(_loadCachedInbox());
    widget.inboxUpdateNotifier?.addListener(_onInboxUpdate);
    _searchController.addListener(_onSearchChanged);
    TurnaContactsDirectory.revision.addListener(_onContactsChanged);
    unawaited(TurnaContactsDirectory.ensureLoaded());
  }

  @override
  void didUpdateWidget(covariant ChatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.session.userId != widget.session.userId) {
      _refreshTick = 0;
      _cachedInbox = null;
      _inboxFuture = _fetchInbox();
    }
  }

  Future<ChatInboxData> _fetchInbox() {
    return ChatApi.fetchChats(widget.session, refreshTick: _refreshTick);
  }

  Future<void> _loadCachedInbox() async {
    final cached = await TurnaChatInboxLocalCache.load(widget.session.userId);
    if (!mounted || cached == null) return;
    setState(() {
      _cachedInbox = cached;
    });
  }

  void _scheduleInboxReload() {
    _refreshTick++;
    _inboxFuture = _fetchInbox();
  }

  Future<void> _reloadInbox() async {
    if (!mounted) return;
    setState(_scheduleInboxReload);
    try {
      await _inboxFuture;
    } catch (_) {}
  }

  void _onInboxUpdate() {
    if (!mounted) return;
    setState(_scheduleInboxReload);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onContactsChanged() {
    if (!mounted) return;
    setState(_scheduleInboxReload);
  }

  _ChatsPageViewData _resolveViewData(ChatInboxData inbox) {
    final query = _searchController.text.trim().toLowerCase();
    if (_cachedViewData != null &&
        identical(_cachedViewInbox, inbox) &&
        _cachedViewQuery == query &&
        _cachedViewFilterId == _selectedFilterId) {
      return _cachedViewData!;
    }

    final chats = inbox.chats;
    final folders = inbox.folders;
    final archivedChats = prioritizeTurnaFavoritedChats(
      chats.where((chat) => chat.isArchived),
    );
    final activeChats = prioritizeTurnaFavoritedChats(
      chats.where((chat) => !chat.isArchived),
    );
    final scopedChats = switch (_selectedFilterId) {
      _allChatsFilterId => activeChats,
      _ =>
        activeChats
            .where((chat) => chat.folderId == _selectedFilterId)
            .toList(),
    };
    final filteredChats = query.isEmpty
        ? scopedChats
        : scopedChats
              .where((chat) {
                final searchableMessage = chat.isLocked
                    ? ''
                    : chat.message.toLowerCase();
                return chat.name.toLowerCase().contains(query) ||
                    searchableMessage.contains(query);
              })
              .toList(growable: false);

    final data = _ChatsPageViewData(
      folders: folders,
      archivedChats: archivedChats,
      filteredChats: filteredChats,
      hasAnyActiveChats: activeChats.isNotEmpty,
      unreadTotal: chats.fold<int>(0, (sum, chat) => sum + chat.unreadCount),
      query: query,
    );

    _cachedViewInbox = inbox;
    _cachedViewData = data;
    _cachedViewQuery = query;
    _cachedViewFilterId = _selectedFilterId;
    return data;
  }

  void _reportUnreadTotalIfNeeded(int unreadTotal) {
    if (_lastReportedUnreadTotal == unreadTotal) return;
    _lastReportedUnreadTotal = unreadTotal;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onUnreadChanged?.call(unreadTotal);
    });
  }

  @override
  void dispose() {
    widget.inboxUpdateNotifier?.removeListener(_onInboxUpdate);
    _searchController.removeListener(_onSearchChanged);
    TurnaContactsDirectory.revision.removeListener(_onContactsChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openNewChatPage() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewChatPage(
          session: widget.session,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (created == true && mounted) {
      setState(_scheduleInboxReload);
    }
  }

  Future<void> _openArchivedChatsPage() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ArchivedChatsPage(
          session: widget.session,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted) return;
    setState(_scheduleInboxReload);
  }

  void _enterSelectionMode([String? initialChatId]) {
    setState(() {
      _selectionMode = true;
      _selectedChatIds
        ..clear()
        ..addAll(initialChatId == null ? const <String>[] : [initialChatId]);
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode && _selectedChatIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedChatIds.clear();
    });
  }

  void _toggleChatSelection(String chatId) {
    setState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  void _selectFilter(String filterId) {
    if (_selectedFilterId == filterId) return;
    setState(() => _selectedFilterId = filterId);
  }

  void _handleActionError(Object error) {
    if (error is TurnaUnauthorizedException) {
      widget.onSessionExpired();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _handleChatsMenuAction(_ChatsMenuAction action) async {
    switch (action) {
      case _ChatsMenuAction.select:
        _enterSelectionMode();
        break;
      case _ChatsMenuAction.markAllRead:
        await _markAllChatsRead();
        break;
    }
  }

  Future<void> _markAllChatsRead() async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);

    try {
      final updatedCount = await ChatApi.markAllChatsRead(widget.session);
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatedCount > 0
                ? '$updatedCount sohbet okundu olarak isaretlendi.'
                : 'Okunmamis sohbet yok.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _deleteSelectedChats() async {
    if (_selectedChatIds.isEmpty || _bulkActionBusy) return;

    final selectedCount = _selectedChatIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sohbetleri sil'),
          content: Text(
            selectedCount == 1
                ? 'Secili sohbet listeden kaldirilsin mi? Yeni mesaj gelirse yeniden gorunur.'
                : '$selectedCount secili sohbet listeden kaldirilsin mi? Yeni mesaj gelirse yeniden gorunur.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      final deletedCount = await ChatApi.deleteChats(
        widget.session,
        _selectedChatIds.toList(),
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _selectionMode = false;
        _selectedChatIds.clear();
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedCount > 0
                ? '$deletedCount sohbet silindi.'
                : 'Secili sohbetler silinemedi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _markChatRead(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);
    try {
      final updatedCount = await ChatApi.markChatRead(
        widget.session,
        chat.chatId,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatedCount > 0
                ? '"${chat.name}" okundu olarak isaretlendi.'
                : 'Okunmamis mesaj yok.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleChatMute(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);
    try {
      final muted = await ChatApi.setChatMuted(
        widget.session,
        chatId: chat.chatId,
        muted: !chat.isMuted,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            muted
                ? '"${chat.name}" sessize alindi.'
                : '"${chat.name}" icin bildirimler yeniden acildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleArchiveChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);
    try {
      final archived = await ChatApi.setChatArchived(
        widget.session,
        chatId: chat.chatId,
        archived: !chat.isArchived,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            archived
                ? '"${chat.name}" arşive taşındı.'
                : '"${chat.name}" arşivden çıkarıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleFavoriteChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);
    try {
      final favorited = await ChatApi.setChatFavorited(
        widget.session,
        chatId: chat.chatId,
        favorited: !chat.isFavorited,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            favorited
                ? '"${chat.name}" favorilere eklendi.'
                : '"${chat.name}" favorilerden cikarildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleLockChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    final authenticated = await authenticateLockedChatAccess(
      context,
      chatName: chat.name,
      actionLabel: chat.isLocked
          ? 'kilidini kaldirmak icin'
          : 'kilitlemek icin',
    );
    if (!mounted || !authenticated) return;

    setState(() => _bulkActionBusy = true);
    try {
      final locked = await ChatApi.setChatLocked(
        widget.session,
        chatId: chat.chatId,
        locked: !chat.isLocked,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locked
                ? '"${chat.name}" kilitlendi.'
                : '"${chat.name}" kilidi kaldirildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<String?> _promptFolderName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategori oluştur'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            hintText: 'Kategori adı',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> _deleteFolder(ChatFolder folder) async {
    if (_bulkActionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategori sil'),
        content: Text(
          '"${folder.name}" kategorisi silinsin mi? Kategoriye atanmış sohbetler Tümü içinde kalmaya devam edecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      await ChatApi.deleteFolder(widget.session, folder.id);
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        if (_selectedFilterId == folder.id) {
          _selectedFilterId = _allChatsFilterId;
        }
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${folder.name}" silindi.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _assignChatFolder(
    ChatPreview chat,
    List<ChatFolder> folders,
  ) async {
    if (_bulkActionBusy) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chat.folderId != null)
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: const Text('Kategoriden çıkar'),
                  onTap: () => Navigator.pop(sheetContext, '__clear__'),
                ),
              for (final folder in folders)
                ListTile(
                  leading: Icon(
                    chat.folderId == folder.id
                        ? Icons.check_circle_rounded
                        : Icons.folder_open_outlined,
                  ),
                  title: Text(folder.name),
                  onTap: () => Navigator.pop(sheetContext, folder.id),
                ),
              if (folders.length < 3)
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('Yeni kategori oluştur'),
                  onTap: () => Navigator.pop(sheetContext, '__create__'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    String? nextFolderId;
    if (action == '__create__') {
      final name = await _promptFolderName();
      if (!mounted || name == null) return;
      setState(() => _bulkActionBusy = true);
      try {
        final folder = await ChatApi.createFolder(widget.session, name: name);
        nextFolderId = folder.id;
      } catch (error) {
        if (!mounted) return;
        setState(() => _bulkActionBusy = false);
        _handleActionError(error);
        return;
      }
    } else if (action == '__clear__') {
      nextFolderId = null;
    } else {
      nextFolderId = action;
    }

    setState(() => _bulkActionBusy = true);
    try {
      await ChatApi.setChatFolder(
        widget.session,
        chatId: chat.chatId,
        folderId: nextFolderId,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextFolderId == null
                ? '"${chat.name}" kategoriden çıkarıldı.'
                : '"${chat.name}" kategoriye atandı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _clearChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sohbeti temizle'),
          content: Text(
            '"${chat.name}" sohbetinin içeriği bu cihazda temizlenecek. Karşı tarafta kalmaya devam edecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Temizle'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      await ChatApi.clearChat(widget.session, chat.chatId);
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${chat.name}" temizlendi.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleBlockChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;

    final willBlock = !chat.isBlockedByMe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(willBlock ? 'Kişiyi engelle' : 'Engeli kaldır'),
          content: Text(
            willBlock
                ? '"${chat.name}" artık sana mesaj gönderemez ve seni arayamaz.'
                : '"${chat.name}" ile iletişim yeniden açılsın mı?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(willBlock ? 'Engelle' : 'Kaldır'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      final blocked = await ChatApi.setChatBlocked(
        widget.session,
        chatId: chat.chatId,
        blocked: willBlock,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? '"${chat.name}" engellendi.'
                : '"${chat.name}" engeli kaldırıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteSingleChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sohbeti sil'),
          content: Text(
            '"${chat.name}" sohbeti sadece senden silinecek. Karsi tarafta kalmaya devam edecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      final deletedCount = await ChatApi.deleteChats(widget.session, [
        chat.chatId,
      ]);
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedCount > 0 ? '"${chat.name}" silindi.' : 'Sohbet silinemedi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showChatActions(
    ChatPreview chat,
    List<ChatFolder> folders,
  ) async {
    if (_bulkActionBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ChatListActionTile(
                    icon: Icons.mark_chat_read_outlined,
                    title: 'Okundu olarak işaretle',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _markChatRead(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: chat.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    title: chat.isArchived ? 'Arşivden çıkar' : 'Arşive at',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleArchiveChat(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: chat.isLocked
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline,
                    title: chat.isLocked
                        ? 'Sohbet kilidini kaldır'
                        : 'Sohbeti kilitle',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleLockChat(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: chat.isFavorited
                        ? Icons.star_border_rounded
                        : Icons.star_outline_rounded,
                    title: chat.isFavorited
                        ? 'Favorilerden çıkar'
                        : 'Favorilere ekle',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleFavoriteChat(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: chat.isMuted
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    title: chat.isMuted ? 'Sessizden çıkar' : 'Sessize al',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleChatMute(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: Icons.folder_open_outlined,
                    title: 'Kategori ata',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _assignChatFolder(chat, folders);
                    },
                  ),
                  if (chat.peerId != null)
                    _ChatListActionTile(
                      icon: chat.isBlockedByMe
                          ? Icons.person_add_alt_1_outlined
                          : Icons.block_outlined,
                      title: chat.isBlockedByMe
                          ? 'Engeli kaldır'
                          : 'Kişiyi engelle',
                      destructive: !chat.isBlockedByMe,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _toggleBlockChat(chat);
                      },
                    ),
                  _ChatListActionTile(
                    icon: Icons.layers_clear_outlined,
                    title: 'Sohbeti temizle',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _clearChat(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: Icons.delete_outline,
                    title: 'Sohbeti sil',
                    destructive: true,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _deleteSingleChat(chat);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: _selectionMode
            ? IconButton(
                onPressed: _bulkActionBusy ? null : _exitSelectionMode,
                icon: const Icon(Icons.close),
              )
            : PopupMenuButton<_ChatsMenuAction>(
                onSelected: _handleChatsMenuAction,
                position: PopupMenuPosition.under,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _ChatsMenuAction.select,
                    child: Text('Sec'),
                  ),
                  PopupMenuItem(
                    value: _ChatsMenuAction.markAllRead,
                    child: Text('Tumu okundu'),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 6,
                    top: 8,
                    bottom: 8,
                  ),
                  child: _ChatsMenuAnchorIcon(),
                ),
              ),
        title: Text(
          _selectionMode
              ? (_selectedChatIds.isEmpty
                    ? 'Sohbet sec'
                    : '${_selectedChatIds.length} secildi')
              : 'Sohbetler',
          style: const TextStyle(
            color: TurnaColors.text,
            fontSize: 18.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  onPressed: _selectedChatIds.isEmpty || _bulkActionBusy
                      ? null
                      : _deleteSelectedChats,
                  icon: _bulkActionBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                ),
                const SizedBox(width: 4),
              ]
            : [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.camera_alt_outlined, size: 21),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 12),
                  child: _ChatsNewChatActionButton(onTap: _openNewChatPage),
                ),
              ],
      ),
      body: FutureBuilder<ChatInboxData>(
        future: _inboxFuture,
        initialData: _cachedInbox,
        builder: (context, snapshot) {
          final error = snapshot.error;
          if (snapshot.hasData) {
            _cachedInbox = snapshot.data;
          }
          if (error is TurnaUnauthorizedException) {
            return buildTurnaSessionExpiredRedirect(widget.onSessionExpired);
          }

          final inbox = snapshot.data ?? _cachedInbox;
          if (snapshot.connectionState == ConnectionState.waiting &&
              inbox == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (error != null && inbox == null) {
            return _CenteredState(
              icon: Icons.cloud_off_outlined,
              title: 'Sohbetler yüklenemedi',
              message: error.toString(),
              primaryLabel: 'Tekrar dene',
              onPrimary: _reloadInbox,
            );
          }

          final resolvedInbox =
              inbox ?? ChatInboxData(chats: const [], folders: const []);
          final viewData = _resolveViewData(resolvedInbox);
          final folders = viewData.folders;
          final hasSelectedFolder =
              _selectedFilterId == _allChatsFilterId ||
              folders.any((folder) => folder.id == _selectedFilterId);
          if (!hasSelectedFolder) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _selectedFilterId = _allChatsFilterId);
            });
          }
          _reportUnreadTotalIfNeeded(viewData.unreadTotal);

          final archivedChats = viewData.archivedChats;
          final filteredChats = viewData.filteredChats;
          final archivedTopVisible = viewData.archivedTopVisible;
          final filtersVisible = viewData.filtersVisible;
          final headerSlots =
              1 + (archivedTopVisible ? 1 : 0) + (filtersVisible ? 1 : 0);

          return RefreshIndicator(
            onRefresh: _reloadInbox,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filteredChats.isEmpty
                  ? headerSlots + 1
                  : filteredChats.length + headerSlots,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Sohbetlerde ara',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: viewData.query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () => _searchController.clear(),
                                icon: const Icon(Icons.close),
                              ),
                        filled: true,
                        fillColor: TurnaColors.backgroundMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  );
                }

                var cursor = 1;
                if (archivedTopVisible && index == cursor) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: _ArchivedChatsBanner(
                      archivedCount: archivedChats.length,
                      onTap: _openArchivedChatsPage,
                    ),
                  );
                }
                if (archivedTopVisible) {
                  cursor += 1;
                }

                if (filtersVisible && index == cursor) {
                  return SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      children: [
                        _ChatFilterChip(
                          label: 'Tümü',
                          selected: _selectedFilterId == _allChatsFilterId,
                          onTap: () => _selectFilter(_allChatsFilterId),
                        ),
                        for (final folder in folders)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _ChatFilterChip(
                              label: folder.name,
                              selected: _selectedFilterId == folder.id,
                              onTap: () => _selectFilter(folder.id),
                              onLongPress: () => _deleteFolder(folder),
                            ),
                          ),
                      ],
                    ),
                  );
                }
                if (filtersVisible) {
                  cursor += 1;
                }

                if (filteredChats.isEmpty) {
                  if (!viewData.hasAnyActiveChats && archivedChats.isEmpty) {
                    return const _CenteredListState(
                      icon: Icons.chat_bubble_outline,
                      title: 'Henüz sohbet yok',
                      message:
                          'İlk konuşmayı başlatmak için sağ üstteki artıdan kişi seç.',
                    );
                  }
                  return _CenteredListState(
                    icon: Icons.search_off,
                    title: 'Sonuç bulunamadı',
                    message:
                        '"${_searchController.text.trim()}" için eşleşen sohbet yok.',
                  );
                }

                final chat = filteredChats[index - headerSlots];
                final isLastItem =
                    index == filteredChats.length + headerSlots - 1;
                final isSelected = _selectedChatIds.contains(chat.chatId);
                return _ChatPreviewListTile(
                  chat: chat,
                  authToken: widget.session.token,
                  isSelected: isSelected,
                  showDivider: !isLastItem,
                  onTap: () {
                    if (_selectionMode) {
                      _toggleChatSelection(chat.chatId);
                      return;
                    }
                    Navigator.push(
                      context,
                      buildChatRoomRoute(
                        chat: chat,
                        session: widget.session,
                        callCoordinator: widget.callCoordinator,
                        onSessionExpired: widget.onSessionExpired,
                      ),
                    );
                  },
                  onLongPress: () {
                    if (_selectionMode) return;
                    _showChatActions(chat, folders);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ChatsMenuAnchorIcon extends StatelessWidget {
  const _ChatsMenuAnchorIcon();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: TurnaColors.border.withValues(alpha: 0.9),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset('assets/turna-icon.png', fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: TurnaColors.border.withValues(alpha: 0.9),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x120F172A),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              '...',
              style: TextStyle(
                color: TurnaColors.textMuted,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatListActionTile extends StatelessWidget {
  const _ChatListActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? TurnaColors.error : TurnaColors.text;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ChatsNewChatActionButton extends StatelessWidget {
  const _ChatsNewChatActionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TurnaColors.primary,
      borderRadius: BorderRadius.circular(999),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.add, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class ArchivedChatsPage extends StatefulWidget {
  const ArchivedChatsPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<ArchivedChatsPage> createState() => _ArchivedChatsPageState();
}

class _ArchivedChatsPageState extends State<ArchivedChatsPage> {
  int _refreshTick = 0;
  bool _actionBusy = false;
  ChatInboxData? _cachedInbox;
  ChatInboxData? _cachedArchivedInbox;
  List<ChatPreview>? _cachedArchivedChats;

  @override
  void initState() {
    super.initState();
    _cachedInbox = TurnaChatInboxLocalCache.peek(widget.session.userId);
    unawaited(_loadCachedInbox());
    TurnaContactsDirectory.revision.addListener(_onContactsChanged);
    unawaited(TurnaContactsDirectory.ensureLoaded());
  }

  @override
  void dispose() {
    TurnaContactsDirectory.revision.removeListener(_onContactsChanged);
    super.dispose();
  }

  void _onContactsChanged() {
    if (!mounted) return;
    setState(() => _refreshTick++);
  }

  void _scheduleRefresh() {
    _refreshTick++;
  }

  Future<void> _loadCachedInbox() async {
    final cached = await TurnaChatInboxLocalCache.load(widget.session.userId);
    if (!mounted || cached == null) return;
    setState(() => _cachedInbox = cached);
  }

  List<ChatPreview> _resolveArchivedChats(ChatInboxData inbox) {
    if (_cachedArchivedChats != null &&
        identical(_cachedArchivedInbox, inbox)) {
      return _cachedArchivedChats!;
    }

    final archivedChats = prioritizeTurnaFavoritedChats(
      inbox.chats.where((chat) => chat.isArchived),
    );
    _cachedArchivedInbox = inbox;
    _cachedArchivedChats = archivedChats;
    return archivedChats;
  }

  void _handleActionError(Object error) {
    if (error is TurnaUnauthorizedException) {
      widget.onSessionExpired();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _toggleArchiveChat(ChatPreview chat) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final archived = await ChatApi.setChatArchived(
        widget.session,
        chatId: chat.chatId,
        archived: !chat.isArchived,
      );
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            archived
                ? '"${chat.name}" arşive taşındı.'
                : '"${chat.name}" arşivden çıkarıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleFavoriteChat(ChatPreview chat) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final favorited = await ChatApi.setChatFavorited(
        widget.session,
        chatId: chat.chatId,
        favorited: !chat.isFavorited,
      );
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            favorited
                ? '"${chat.name}" favorilere eklendi.'
                : '"${chat.name}" favorilerden cikarildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleLockChat(ChatPreview chat) async {
    if (_actionBusy) return;
    final authenticated = await authenticateLockedChatAccess(
      context,
      chatName: chat.name,
      actionLabel: chat.isLocked
          ? 'kilidini kaldirmak icin'
          : 'kilitlemek icin',
    );
    if (!mounted || !authenticated) return;

    setState(() => _actionBusy = true);
    try {
      final locked = await ChatApi.setChatLocked(
        widget.session,
        chatId: chat.chatId,
        locked: !chat.isLocked,
      );
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locked
                ? '"${chat.name}" kilitlendi.'
                : '"${chat.name}" kilidi kaldirildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleBlockChat(ChatPreview chat) async {
    if (_actionBusy || chat.peerId == null) return;

    final willBlock = !chat.isBlockedByMe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(willBlock ? 'Kişiyi engelle' : 'Engeli kaldır'),
        content: Text(
          willBlock
              ? '"${chat.name}" artık sana mesaj gönderemez ve seni arayamaz.'
              : '"${chat.name}" ile iletişim yeniden açılsın mı?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(willBlock ? 'Engelle' : 'Kaldır'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      final blocked = await ChatApi.setChatBlocked(
        widget.session,
        chatId: chat.chatId,
        blocked: willBlock,
      );
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? '"${chat.name}" engellendi.'
                : '"${chat.name}" engeli kaldırıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _clearChat(ChatPreview chat) async {
    if (_actionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sohbeti temizle'),
        content: Text(
          '"${chat.name}" sohbetinin içeriği bu cihazda temizlenecek. Karşı tarafta kalmaya devam edecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      await ChatApi.clearChat(widget.session, chat.chatId);
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${chat.name}" temizlendi.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _deleteSingleChat(ChatPreview chat) async {
    if (_actionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sohbeti sil'),
        content: Text(
          '"${chat.name}" sohbeti sadece senden silinecek. Karsi tarafta kalmaya devam edecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      final deletedCount = await ChatApi.deleteChats(widget.session, [
        chat.chatId,
      ]);
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedCount > 0 ? '"${chat.name}" silindi.' : 'Sohbet silinemedi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _showChatActions(ChatPreview chat) async {
    if (_actionBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChatListActionTile(
                  icon: Icons.unarchive_outlined,
                  title: 'Arşivden çıkar',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _toggleArchiveChat(chat);
                  },
                ),
                _ChatListActionTile(
                  icon: chat.isLocked
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                  title: chat.isLocked
                      ? 'Sohbet kilidini kaldır'
                      : 'Sohbeti kilitle',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _toggleLockChat(chat);
                  },
                ),
                _ChatListActionTile(
                  icon: chat.isFavorited
                      ? Icons.star_border_rounded
                      : Icons.star_outline_rounded,
                  title: chat.isFavorited
                      ? 'Favorilerden çıkar'
                      : 'Favorilere ekle',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _toggleFavoriteChat(chat);
                  },
                ),
                if (chat.peerId != null)
                  _ChatListActionTile(
                    icon: chat.isBlockedByMe
                        ? Icons.person_add_alt_1_outlined
                        : Icons.block_outlined,
                    title: chat.isBlockedByMe
                        ? 'Engeli kaldır'
                        : 'Kişiyi engelle',
                    destructive: !chat.isBlockedByMe,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleBlockChat(chat);
                    },
                  ),
                _ChatListActionTile(
                  icon: Icons.layers_clear_outlined,
                  title: 'Sohbeti temizle',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _clearChat(chat);
                  },
                ),
                _ChatListActionTile(
                  icon: Icons.delete_outline,
                  title: 'Sohbeti sil',
                  destructive: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _deleteSingleChat(chat);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Arşiv Sohbetleri',
          style: TextStyle(
            color: TurnaColors.text,
            fontSize: 18.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: FutureBuilder<ChatInboxData>(
        future: ChatApi.fetchChats(widget.session, refreshTick: _refreshTick),
        initialData: _cachedInbox,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _cachedInbox = snapshot.data;
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null &&
              _cachedInbox == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            if (error is TurnaUnauthorizedException) {
              return buildTurnaSessionExpiredRedirect(widget.onSessionExpired);
            }
            return _CenteredState(
              icon: Icons.archive_outlined,
              title: 'Arşiv yüklenemedi',
              message: error.toString(),
              primaryLabel: 'Tekrar dene',
              onPrimary: () => setState(() => _refreshTick++),
            );
          }

          final inbox =
              snapshot.data ??
              _cachedInbox ??
              ChatInboxData(chats: const [], folders: const []);
          final archivedChats = _resolveArchivedChats(inbox);

          return RefreshIndicator(
            onRefresh: () async => setState(() => _refreshTick++),
            child: archivedChats.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      _CenteredListState(
                        icon: Icons.archive_outlined,
                        title: 'Arşiv boş',
                        message:
                            'Arşive attığın sohbetler burada listelenecek.',
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: archivedChats.length,
                    itemBuilder: (context, index) {
                      final chat = archivedChats[index];
                      final isLastItem = index == archivedChats.length - 1;
                      return _ChatPreviewListTile(
                        chat: chat,
                        authToken: widget.session.token,
                        showDivider: !isLastItem,
                        onTap: () {
                          Navigator.push(
                            context,
                            buildChatRoomRoute(
                              chat: chat,
                              session: widget.session,
                              callCoordinator: widget.callCoordinator,
                              onSessionExpired: widget.onSessionExpired,
                            ),
                          );
                        },
                        onLongPress: () => _showChatActions(chat),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class _ChatPreviewListTile extends StatelessWidget {
  const _ChatPreviewListTile({
    required this.chat,
    required this.authToken,
    required this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.showDivider = true,
  });

  final ChatPreview chat;
  final String authToken;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tileColor = isSelected
        ? TurnaColors.primary.withValues(alpha: 0.08)
        : chat.unreadCount > 0
        ? TurnaColors.chatUnreadBg
        : Colors.transparent;
    final groupPreview = chat.memberPreviewNames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final groupMetaText = () {
      if (chat.chatType != TurnaChatType.group) return null;
      final parts = <String>[];
      if (groupPreview.isNotEmpty) {
        parts.add(groupPreview.join(', '));
      }
      if (chat.memberCount > 0) {
        parts.add('${chat.memberCount} üye');
      }
      return parts.isEmpty ? null : parts.join(' · ');
    }();
    final subtitleText = chat.isLocked
        ? 'Sohbet kilitli'
        : (groupMetaText != null && chat.message.trim() == 'Grup oluşturuldu'
              ? groupMetaText
              : chat.message);
    return Material(
      color: tileColor,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _ProfileAvatar(
                          label: chat.name,
                          avatarUrl: chat.avatarUrl,
                          authToken: authToken,
                          radius: 23,
                        ),
                        if (isSelected)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: TurnaColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.6,
                                ),
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      chat.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: TurnaColors.text,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  if (chat.chatType == TurnaChatType.group) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.group_outlined,
                                      size: 15,
                                      color: TurnaColors.textSoft,
                                    ),
                                  ],
                                  if (chat.isFavorited) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: Color(0xFFDAA520),
                                    ),
                                  ],
                                  if (chat.isLocked) ...[
                                    const SizedBox(width: 5),
                                    const Icon(
                                      Icons.lock_outline,
                                      size: 13,
                                      color: TurnaColors.textSoft,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ChatPreviewMeta(chat: chat),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _ChatPreviewSubtitle(text: subtitleText),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              const Divider(
                height: 1,
                thickness: 0.8,
                indent: 74,
                endIndent: 16,
                color: TurnaColors.divider,
              ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedChatsBanner extends StatelessWidget {
  const _ArchivedChatsBanner({
    required this.archivedCount,
    required this.onTap,
  });

  final int archivedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.archive_outlined, color: TurnaColors.textMuted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Arşiv Sohbetleri',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: TurnaColors.text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: TurnaColors.backgroundMuted,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$archivedCount',
                  style: TextStyle(
                    color: TurnaColors.textSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatFilterChip extends StatelessWidget {
  const _ChatFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: TurnaColors.primary.withValues(alpha: 0.16),
        labelStyle: TextStyle(
          color: selected ? TurnaColors.primaryDeep : TurnaColors.textSoft,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(
          color: selected ? TurnaColors.primary : TurnaColors.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        backgroundColor: Colors.white,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _ChatPreviewMeta extends StatelessWidget {
  const _ChatPreviewMeta({required this.chat});

  final ChatPreview chat;

  @override
  Widget build(BuildContext context) {
    final hasUnread = chat.unreadCount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          chat.time,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w400,
            color: hasUnread ? TurnaColors.primary : const Color(0xFF8C959F),
            height: 1.1,
          ),
        ),
        if (hasUnread) ...[
          const SizedBox(height: 7),
          Container(
            constraints: const BoxConstraints(minWidth: 19),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: const BoxDecoration(
              color: TurnaColors.primary,
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
            child: Text(
              chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChatPreviewSubtitleParts {
  const _ChatPreviewSubtitleParts({this.sender, required this.message});

  final String? sender;
  final String message;
}

class _ChatPreviewSubtitle extends StatelessWidget {
  const _ChatPreviewSubtitle({required this.text});

  final String text;

  static _ChatPreviewSubtitleParts _parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const _ChatPreviewSubtitleParts(message: 'Sohbet başlat');
    }

    final dividerIndex = trimmed.indexOf(':');
    if (dividerIndex <= 0 || dividerIndex >= 32) {
      return _ChatPreviewSubtitleParts(message: trimmed);
    }

    final sender = trimmed.substring(0, dividerIndex).trim();
    final message = trimmed.substring(dividerIndex + 1).trim();
    if (sender.isEmpty ||
        message.isEmpty ||
        sender.contains('://') ||
        sender.contains('@')) {
      return _ChatPreviewSubtitleParts(message: trimmed);
    }

    return _ChatPreviewSubtitleParts(sender: sender, message: message);
  }

  @override
  Widget build(BuildContext context) {
    final parts = _parse(text);
    final baseStyle = const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w400,
      color: TurnaColors.textMuted,
      height: 1.2,
    );

    if (parts.sender == null) {
      return Text(
        parts.message,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${parts.sender}: ',
            style: baseStyle.copyWith(
              color: TurnaColors.textSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(text: parts.message, style: baseStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class NewChatPage extends StatefulWidget {
  const NewChatPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  static const List<String> _alphabetIndex = <String>[
    'A',
    'B',
    'C',
    'Ç',
    'D',
    'E',
    'F',
    'G',
    'Ğ',
    'H',
    'I',
    'İ',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'Ö',
    'P',
    'R',
    'S',
    'Ş',
    'T',
    'U',
    'Ü',
    'V',
    'Y',
    'Z',
  ];
  static const double _sectionHeaderHeight = 28;
  static const double _contactRowHeight = 74;
  final TextEditingController _lookupController = TextEditingController();
  final ScrollController _contactsScrollController = ScrollController();
  TurnaUserProfile? _foundUser;
  List<TurnaRegisteredContact> _registeredContacts =
      const <TurnaRegisteredContact>[];
  Timer? _lookupDebounce;
  bool _loading = false;
  bool _syncingContacts = false;
  String? _lookupError;
  String? _directoryError;

  @override
  void initState() {
    super.initState();
    _lookupController.addListener(_handleLookupChanged);
    TurnaContactsDirectory.revision.addListener(_handleContactsChanged);
    unawaited(_refreshRegisteredContacts());
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    TurnaContactsDirectory.revision.removeListener(_handleContactsChanged);
    _lookupController.removeListener(_handleLookupChanged);
    _lookupController.dispose();
    _contactsScrollController.dispose();
    super.dispose();
  }

  void _handleLookupChanged() {
    _lookupDebounce?.cancel();
    if (!mounted) return;
    setState(() {
      if (_lookupError != null) {
        _lookupError = null;
      }
      if (_foundUser != null) {
        _foundUser = null;
      }
    });

    final query = _lookupController.text.trim();
    if (!_shouldTriggerExactLookup(query)) {
      return;
    }

    _lookupDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      unawaited(_searchUser(overrideQuery: query));
    });
  }

  void _handleContactsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshRegisteredContacts({
    bool forceContactReload = false,
  }) async {
    if (_syncingContacts) return;
    setState(() {
      _syncingContacts = true;
      _directoryError = null;
    });

    try {
      await TurnaContactsDirectory.ensureLoaded(force: forceContactReload);
      if (!mounted) return;

      if (!TurnaContactsDirectory.permissionGranted) {
        setState(() => _syncingContacts = false);
        return;
      }

      final contacts = TurnaContactsDirectory.snapshotForSync();
      await ProfileApi.syncContacts(widget.session, contacts);
      final registered = await ChatApi.fetchRegisteredContacts(widget.session);
      if (!mounted) return;
      setState(() {
        _registeredContacts = registered;
        _syncingContacts = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      setState(() => _syncingContacts = false);
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _syncingContacts = false;
        _directoryError = error.toString();
      });
    }
  }

  List<TurnaRegisteredContact> get _filteredRegisteredContacts {
    final rawQuery = _lookupController.text.trim();
    final query = rawQuery.toLowerCase();
    if (query.isEmpty) return _registeredContacts;
    final exactUsername = _normalizeUsernameLookup(rawQuery);
    if (exactUsername != null) {
      return _registeredContacts.where((contact) {
        return ((contact.username ?? '').trim().toLowerCase() == exactUsername);
      }).toList();
    }

    final exactPhone = _normalizeLookupPhoneQuery(rawQuery);
    if (exactPhone != null) {
      final exactDigits = exactPhone.replaceAll(RegExp(r'\D+'), '');
      return _registeredContacts.where((contact) {
        final phoneDigits = (contact.phone ?? '').replaceAll(
          RegExp(r'\D+'),
          '',
        );
        return phoneDigits == exactDigits;
      }).toList();
    }

    final digitsQuery = query.replaceAll(RegExp(r'\D+'), '');
    return _registeredContacts.where((contact) {
      final title = contact.resolvedTitle.toLowerCase();
      final username = (contact.username ?? '').toLowerCase();
      final phone = (contact.phone ?? '').toLowerCase();
      final phoneDigits = phone.replaceAll(RegExp(r'\D+'), '');
      return title.contains(query) ||
          username.contains(query.replaceAll('@', '')) ||
          phone.contains(query) ||
          (digitsQuery.isNotEmpty && phoneDigits.contains(digitsQuery));
    }).toList();
  }

  String? _normalizeUsernameLookup(String query) {
    final trimmed = query.trim();
    if (!trimmed.startsWith('@')) return null;
    final normalized = trimmed
        .replaceFirst(RegExp(r'^@+'), '')
        .trim()
        .toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeLookupPhoneQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    final digits = trimmed.replaceAll(RegExp(r'\D+'), '');
    if (trimmed.startsWith('+')) {
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }
    if (RegExp(r'^05\d{9}$').hasMatch(digits)) {
      return '+90${digits.substring(1)}';
    }
    if (RegExp(r'^5\d{9}$').hasMatch(digits)) {
      return '+90$digits';
    }
    return null;
  }

  bool _shouldTriggerExactLookup(String query) {
    if (_normalizeUsernameLookup(query) != null) return true;
    return _normalizeLookupPhoneQuery(query) != null;
  }

  Future<void> _searchUser({String? overrideQuery}) async {
    final rawQuery = (overrideQuery ?? _lookupController.text).trim();
    final query =
        _normalizeLookupPhoneQuery(rawQuery) ??
        (_normalizeUsernameLookup(rawQuery) != null
            ? '@${_normalizeUsernameLookup(rawQuery)!}'
            : rawQuery);
    if (query.isEmpty) {
      setState(() {
        _lookupError = 'Telefon numarası veya kullanıcı adı gir.';
        _foundUser = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _lookupError = null;
      _foundUser = null;
    });

    try {
      final user = await ChatApi.lookupUser(widget.session, query);
      if (!mounted) return;
      setState(() {
        _foundUser = user;
        _loading = false;
        _lookupError = user == null
            ? 'Bu sorguyla kayıtlı bir Turna hesabı bulunamadı.'
            : null;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lookupError = error.toString();
      });
    }
  }

  Future<void> _openCreateContact() async {
    try {
      final queryPhone = _normalizeLookupPhoneQuery(_lookupController.text);
      final contact = Contact(
        displayName: '',
        phones: queryPhone == null
            ? const <Phone>[]
            : <Phone>[Phone(queryPhone)],
      );
      await FlutterContacts.openExternalInsert(contact);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kişi kartı açılamadı: $error')));
    }
  }

  Future<void> _openCreateGroup() async {
    final navigator = Navigator.of(context);
    final createdChat = await Navigator.push<ChatPreview>(
      context,
      MaterialPageRoute(
        builder: (_) => _CreateGroupPage(
          session: widget.session,
          registeredContacts: _registeredContacts,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || createdChat == null) return;
    await navigator.push(
      buildChatRoomRoute(
        chat: createdChat,
        session: widget.session,
        callCoordinator: widget.callCoordinator,
        onSessionExpired: widget.onSessionExpired,
      ),
    );
    if (!mounted) return;
    navigator.pop(true);
  }

  Future<void> _openChat(TurnaUserProfile user) async {
    final phone = user.phone;
    final fallbackName = phone == null || phone.trim().isEmpty
        ? user.displayName
        : formatTurnaDisplayPhone(phone);
    final chat = ChatPreview(
      chatId: ChatApi.buildDirectChatId(widget.session.userId, user.id),
      name: TurnaContactsDirectory.resolveDisplayLabel(
        phone: phone,
        fallbackName: fallbackName,
      ),
      message: '',
      time: '',
      phone: phone,
      avatarUrl: user.avatarUrl,
      peerId: user.id,
    );
    await Navigator.push(
      context,
      buildChatRoomRoute(
        chat: chat,
        session: widget.session,
        callCoordinator: widget.callCoordinator,
        onSessionExpired: widget.onSessionExpired,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _buildRegisteredContactsSection() {
    if (!TurnaContactsDirectory.permissionGranted &&
        _registeredContacts.isEmpty) {
      return _CenteredState(
        icon: Icons.perm_contact_calendar_outlined,
        title: 'Rehber izni gerekli',
        message:
            'Rehberinde kayıtlı ve Turna kullanan kişileri görmek için rehber izni ver.',
        primaryLabel: 'Rehber iznini iste',
        onPrimary: () => _refreshRegisteredContacts(forceContactReload: true),
      );
    }

    if (_directoryError != null) {
      return _CenteredState(
        icon: Icons.sync_problem_outlined,
        title: 'Rehber senkronize edilemedi',
        message: _directoryError!,
        primaryLabel: 'Kişileri yenile',
        onPrimary: () => _refreshRegisteredContacts(forceContactReload: true),
      );
    }

    if (_syncingContacts && _registeredContacts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final contacts = _filteredRegisteredContacts;
    if (contacts.isEmpty) {
      return _CenteredState(
        icon: Icons.perm_contact_calendar_outlined,
        title: 'Kayıtlı rehber kişisi bulunamadı',
        message: _lookupController.text.trim().isEmpty
            ? 'Rehberinde kayıtlı ve Turna kullanan kişiler burada listelenecek.'
            : 'Arama metnine uyan rehber kişisi bulunamadı.',
        primaryLabel: _lookupController.text.trim().isEmpty
            ? 'Kişileri yenile'
            : 'Kişiyi bul',
        onPrimary: _lookupController.text.trim().isEmpty
            ? () => _refreshRegisteredContacts(forceContactReload: true)
            : _searchUser,
      );
    }

    final grouped = <String, List<TurnaRegisteredContact>>{};
    for (final contact in contacts) {
      final letter = _sectionLetter(contact.resolvedTitle);
      grouped
          .putIfAbsent(letter, () => <TurnaRegisteredContact>[])
          .add(contact);
    }
    final visibleLetters = _alphabetIndex
        .where((letter) => grouped.containsKey(letter))
        .toList(growable: false);
    final offsets = <String, double>{};
    var runningOffset = 0.0;
    for (final letter in visibleLetters) {
      offsets[letter] = runningOffset;
      runningOffset +=
          _sectionHeaderHeight + (grouped[letter]!.length * _contactRowHeight);
    }

    return Stack(
      children: [
        ListView(
          controller: _contactsScrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 30, 24),
          children: [
            for (final letter in visibleLetters) ...[
              SizedBox(
                height: _sectionHeaderHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    letter,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: TurnaColors.textMuted,
                    ),
                  ),
                ),
              ),
              ...grouped[letter]!.map((contact) {
                final subtitleParts = <String>[
                  if ((contact.username ?? '').trim().isNotEmpty)
                    '@${contact.username!.trim()}',
                  if ((contact.phone ?? '').trim().isNotEmpty)
                    formatTurnaDisplayPhone(contact.phone!),
                ];
                return SizedBox(
                  height: _contactRowHeight,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          leading: _ProfileAvatar(
                            label: contact.resolvedTitle,
                            avatarUrl: contact.avatarUrl,
                            authToken: widget.session.token,
                            radius: 24,
                          ),
                          title: Text(
                            contact.resolvedTitle,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: subtitleParts.isEmpty
                              ? null
                              : Text(
                                  subtitleParts.join('  •  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => _openChat(contact.toUserProfile()),
                          onLongPress: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfilePage(
                                  session: widget.session,
                                  userId: contact.id,
                                  fallbackName: contact.resolvedTitle,
                                  fallbackAvatarUrl: contact.avatarUrl,
                                  callCoordinator: widget.callCoordinator,
                                  onSessionExpired: widget.onSessionExpired,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
        Positioned(
          top: 6,
          right: 4,
          bottom: 10,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _alphabetIndex.map((letter) {
              final enabled = offsets.containsKey(letter);
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: !enabled
                      ? null
                      : () {
                          _contactsScrollController.animateTo(
                            offsets[letter]!,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                          );
                        },
                  child: SizedBox(
                    width: 20,
                    child: Center(
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? TurnaColors.primary
                              : TurnaColors.textMuted.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _sectionLetter(String value) {
    final trimmed = value.trimLeft();
    if (trimmed.isEmpty) return '#';
    final first = trimmed.substring(0, 1);
    switch (first.toLowerCase()) {
      case 'ç':
        return 'Ç';
      case 'ğ':
        return 'Ğ';
      case 'ı':
        return 'I';
      case 'i':
        return 'İ';
      case 'ö':
        return 'Ö';
      case 'ş':
        return 'Ş';
      case 'ü':
        return 'Ü';
      default:
        final upper = first.toUpperCase();
        return _alphabetIndex.contains(upper) ? upper : '#';
    }
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: TurnaColors.primary50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: TurnaColors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: TurnaColors.textMuted,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      minLeadingWidth: 0,
    );
  }

  Widget _buildLookupResultCard(String? foundUserName) {
    if (_foundUser == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: TurnaColors.divider),
        ),
        child: Row(
          children: [
            _ProfileAvatar(
              label: foundUserName ?? _foundUser!.displayName,
              avatarUrl: _foundUser!.avatarUrl,
              authToken: widget.session.token,
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    foundUserName ?? _foundUser!.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (_foundUser!.username ?? '').trim().isNotEmpty
                        ? '@${_foundUser!.username!.trim()}'
                        : formatTurnaDisplayPhone(_foundUser!.phone ?? ''),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: TurnaColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _openChat(_foundUser!),
              child: const Text('Sohbet'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lookupInput = _lookupController.text.trim();
    final foundUserName = _foundUser == null
        ? null
        : TurnaContactsDirectory.resolveDisplayLabel(
            phone: _foundUser!.phone,
            fallbackName: _foundUser!.displayName,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni sohbet')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _lookupController,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    hintText: 'Bir ad, numara veya kullanıcı adı aratın',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: lookupInput.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _lookupController.clear();
                              setState(() {
                                _foundUser = null;
                                _lookupError = null;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: TurnaColors.backgroundMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _searchUser(),
                ),
                if (_lookupError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _lookupError!,
                    style: const TextStyle(
                      color: TurnaColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading && _foundUser == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: TurnaColors.divider),
                          ),
                          child: Column(
                            children: [
                              _buildQuickActionTile(
                                icon: Icons.groups_rounded,
                                title: 'Yeni grup',
                                onTap: _openCreateGroup,
                              ),
                              const Divider(height: 1),
                              _buildQuickActionTile(
                                icon: Icons.person_add_alt_1_rounded,
                                title: 'Yeni kişi',
                                onTap: _openCreateContact,
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildLookupResultCard(foundUserName),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                        child: Row(
                          children: [
                            const Text(
                              'Turna\'daki kişiler',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (_syncingContacts)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              TextButton(
                                onPressed: () => _refreshRegisteredContacts(
                                  forceContactReload: true,
                                ),
                                child: const Text('Yenile'),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.62,
                        child: _buildRegisteredContactsSection(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreateGroupPage extends StatefulWidget {
  const _CreateGroupPage({
    required this.session,
    required this.registeredContacts,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final List<TurnaRegisteredContact> registeredContacts;
  final VoidCallback onSessionExpired;

  @override
  State<_CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<_CreateGroupPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  bool _creating = false;

  List<TurnaRegisteredContact> get _filteredContacts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.registeredContacts;
    return widget.registeredContacts.where((contact) {
      final title = contact.resolvedTitle.toLowerCase();
      final username = (contact.username ?? '').toLowerCase();
      final phone = (contact.phone ?? '').toLowerCase();
      return title.contains(query) ||
          username.contains(query.replaceAll('@', '')) ||
          phone.contains(query);
    }).toList();
  }

  Future<void> _createGroup() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Grup adı gerekli.')));
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir kişi daha seçmelisin.')),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final detail = await ChatApi.createGroup(
        widget.session,
        title: title,
        memberUserIds: _selectedIds.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        ChatPreview(
          chatId: detail.chatId,
          name: detail.title,
          message: 'Grup oluşturuldu',
          time: '',
          chatType: TurnaChatType.group,
          memberPreviewNames: detail.memberPreviewNames,
          avatarUrl: detail.avatarUrl,
          memberCount: detail.memberCount,
          myRole: detail.myRole,
          description: detail.description,
          isPublic: detail.isPublic,
        ),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _filteredContacts;
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Grup')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: TurnaColors.divider),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: TurnaColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Grup adı',
                          filled: true,
                          fillColor: TurnaColors.backgroundMuted,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Kişi ara',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: TurnaColors.backgroundMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${_selectedIds.length} kişi seçildi',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: TurnaColors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _creating ? null : _createGroup,
                      child: Text(
                        _creating ? 'Oluşturuluyor...' : 'Grubu oluştur',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: contacts.isEmpty
                ? const Center(
                    child: Text(
                      'Seçilebilir kişi bulunamadı.',
                      style: TextStyle(color: TurnaColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: contacts.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      final selected = _selectedIds.contains(contact.id);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selectedIds.remove(contact.id);
                            } else {
                              _selectedIds.add(contact.id);
                            }
                          });
                        },
                        leading: _ProfileAvatar(
                          label: contact.resolvedTitle,
                          avatarUrl: contact.avatarUrl,
                          authToken: widget.session.token,
                          radius: 24,
                        ),
                        title: Text(
                          contact.resolvedTitle,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            if ((contact.username ?? '').trim().isNotEmpty)
                              '@${contact.username!.trim()}',
                            if ((contact.phone ?? '').trim().isNotEmpty)
                              formatTurnaDisplayPhone(contact.phone!),
                          ].join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Checkbox(
                          value: selected,
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedIds.remove(contact.id);
                              } else {
                                _selectedIds.add(contact.id);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
