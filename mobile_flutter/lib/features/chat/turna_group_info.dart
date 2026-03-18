part of turna_app;

class _TurnaGroupSearchPage extends StatefulWidget {
  const _TurnaGroupSearchPage({
    required this.session,
    required this.chat,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final ChatPreview chat;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupSearchPage> createState() => _TurnaGroupSearchPageState();
}

class _TurnaGroupSearchPageState extends State<_TurnaGroupSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<ChatMessage> _items = const <ChatMessage>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _searched = false;
  bool _hasMore = false;
  String? _nextBefore;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  void _handleSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_runSearch(reset: true));
    });
  }

  Future<void> _runSearch({required bool reset}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _items = const <ChatMessage>[];
        _searched = false;
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
        _nextBefore = null;
        _error = null;
      });
      return;
    }

    if (reset) {
      setState(() {
        _loading = true;
        _searched = true;
        _error = null;
        _nextBefore = null;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final page = await ChatApi.searchMessagesPage(
        widget.session,
        chatId: widget.chat.chatId,
        query: query,
        before: reset ? null : _nextBefore,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _hasMore = page.hasMore;
        _nextBefore = page.nextBefore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Grup içi ara')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Mesaj, dosya veya kişi ara',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: TurnaColors.backgroundMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _runSearch(reset: true),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: TurnaColors.error),
                      ),
                    ),
                  )
                : !_searched
                ? const _CenteredState(
                    icon: Icons.search_rounded,
                    title: 'Aramaya başla',
                    message: 'Gruptaki mesajlarda anahtar kelime ara.',
                  )
                : _items.isEmpty
                ? _CenteredState(
                    icon: Icons.search_off_rounded,
                    title: 'Sonuç yok',
                    message: '"$query" için eşleşen mesaj bulunamadı.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      ..._items.map(
                        (message) => _TurnaGroupMessageResultTile(
                          message: message,
                          onTap: () => Navigator.of(context).pop(message.id),
                        ),
                      ),
                      if (_hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton(
                            onPressed: _loadingMore
                                ? null
                                : () => _runSearch(reset: false),
                            child: Text(
                              _loadingMore
                                  ? 'Yükleniyor...'
                                  : 'Daha fazla sonuç',
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TurnaGroupMediaExplorerPage extends StatelessWidget {
  const _TurnaGroupMediaExplorerPage({
    required this.session,
    required this.chat,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final ChatPreview chat;
  final VoidCallback onSessionExpired;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Paylaşılan içerikler'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Medya'),
              Tab(text: 'Dosyalar'),
              Tab(text: 'Bağlantılar'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TurnaGroupCollectionTab(
              session: session,
              chat: chat,
              type: TurnaChatCollectionType.media,
              emptyTitle: 'Medya yok',
              emptyMessage: 'Bu grupta henüz fotoğraf veya video yok.',
              onSessionExpired: onSessionExpired,
            ),
            _TurnaGroupCollectionTab(
              session: session,
              chat: chat,
              type: TurnaChatCollectionType.docs,
              emptyTitle: 'Dosya yok',
              emptyMessage: 'Bu grupta henüz belge veya dosya yok.',
              onSessionExpired: onSessionExpired,
            ),
            _TurnaGroupCollectionTab(
              session: session,
              chat: chat,
              type: TurnaChatCollectionType.links,
              emptyTitle: 'Bağlantı yok',
              emptyMessage: 'Bu grupta henüz bağlantı paylaşılmadı.',
              onSessionExpired: onSessionExpired,
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnaGroupCollectionTab extends StatefulWidget {
  const _TurnaGroupCollectionTab({
    required this.session,
    required this.chat,
    required this.type,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final ChatPreview chat;
  final TurnaChatCollectionType type;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupCollectionTab> createState() =>
      _TurnaGroupCollectionTabState();
}

class _TurnaGroupCollectionTabState extends State<_TurnaGroupCollectionTab> {
  List<ChatMessage> _items = const <ChatMessage>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _nextBefore;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _nextBefore = null;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final page = await ChatApi.fetchMessageCollectionPage(
        widget.session,
        chatId: widget.chat.chatId,
        type: widget.type,
        before: reset ? null : _nextBefore,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _hasMore = page.hasMore;
        _nextBefore = page.nextBefore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: TurnaColors.error),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return _CenteredState(
        icon: Icons.perm_media_outlined,
        title: widget.emptyTitle,
        message: widget.emptyMessage,
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ..._items.map(
            (message) => _TurnaGroupMessageResultTile(
              message: message,
              onTap: () => Navigator.of(context).pop(message.id),
            ),
          ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: _loadingMore ? null : () => _load(reset: false),
                child: Text(
                  _loadingMore ? 'Yükleniyor...' : 'Daha fazla yükle',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TurnaGroupMessageResultTile extends StatelessWidget {
  const _TurnaGroupMessageResultTile({
    required this.message,
    required this.onTap,
  });

  final ChatMessage message;
  final VoidCallback onTap;

  String _previewText() {
    final parsed = parseTurnaMessageText(message.text);
    if (parsed.text.trim().isNotEmpty) {
      return parsed.text.trim();
    }
    if (parsed.location != null) {
      return parsed.location!.previewLabel;
    }
    if (parsed.contact != null) {
      return parsed.contact!.previewLabel;
    }
    if (message.attachments.isEmpty) return 'Mesaj';
    final first = message.attachments.first;
    if (isTurnaImageAttachment(first)) return 'Fotoğraf';
    if (isTurnaVideoAttachment(first)) return 'Video';
    if (isTurnaAudioAttachment(first)) return 'Ses kaydı';
    return first.fileName?.trim().isNotEmpty == true
        ? first.fileName!.trim()
        : 'Dosya';
  }

  IconData _leadingIcon() {
    if (message.attachments.isNotEmpty) {
      final first = message.attachments.first;
      if (isTurnaImageAttachment(first)) return Icons.photo_library_outlined;
      if (isTurnaVideoAttachment(first)) return Icons.videocam_outlined;
      if (isTurnaAudioAttachment(first)) return Icons.mic_none_rounded;
      return Icons.insert_drive_file_outlined;
    }
    final text = message.text.toLowerCase();
    if (text.contains('http://') ||
        text.contains('https://') ||
        text.contains('www.')) {
      return Icons.link_rounded;
    }
    return Icons.chat_bubble_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final sender = (message.senderDisplayName ?? '').trim().isNotEmpty
        ? message.senderDisplayName!.trim()
        : 'Birisi';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TurnaColors.divider),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: TurnaColors.primary50,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(_leadingIcon(), color: TurnaColors.primary),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                sender,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatTurnaLocalClock(message.createdAt),
              style: const TextStyle(
                fontSize: 12,
                color: TurnaColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _previewText(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: TurnaColors.textSoft, height: 1.3),
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: TurnaColors.textMuted,
        ),
      ),
    );
  }
}

class _TurnaGroupInfoPage extends StatefulWidget {
  const _TurnaGroupInfoPage({
    required this.session,
    required this.chat,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final ChatPreview chat;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupInfoPage> createState() => _TurnaGroupInfoPageState();
}

class _TurnaGroupInfoPageState extends State<_TurnaGroupInfoPage> {
  TurnaChatDetail? _detail;
  List<TurnaGroupMember> _members = const <TurnaGroupMember>[];
  final ImagePicker _avatarPicker = ImagePicker();
  bool _loading = true;
  bool _leaving = false;
  bool _closing = false;
  bool _savingDetail = false;
  bool _loadingMoreMembers = false;
  int _totalMemberCount = 0;
  bool _hasMoreMembers = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detail = TurnaChatDetailLocalCache.peek(
      widget.session.userId,
      widget.chat.chatId,
    );
    unawaited(_load());
  }

  String get _groupTitle => _detail?.title ?? widget.chat.name;
  String? get _groupAvatarUrl => _detail?.avatarUrl ?? widget.chat.avatarUrl;
  int get _groupMemberCount => _detail?.memberCount ?? widget.chat.memberCount;
  String? get _groupDescription =>
      _detail?.description ?? widget.chat.description;
  String get _myRole =>
      (_detail?.myRole ?? widget.chat.myRole ?? '').trim().toUpperCase();
  bool get _isOwner => _myRole == 'OWNER';
  bool get _isAdmin => _myRole == 'ADMIN';
  bool get _isEditor => _myRole == 'EDITOR';
  bool get _canOpenSettings => _isOwner || _isAdmin;
  bool get _canManageRoles => _isOwner || _isAdmin;
  bool get _canEditInfo =>
      _policyAllows(_detail?.whoCanEditInfo ?? 'EDITOR_ONLY', _myRole);
  bool get _canCloseGroup => _isOwner;
  bool get _canAddMembers =>
      _policyAllows(_detail?.whoCanAddMembers ?? 'ADMIN_ONLY', _myRole);

  bool _policyAllows(String policy, String role) {
    final normalizedPolicy = policy.trim().toUpperCase();
    final normalizedRole = role.trim().toUpperCase();
    if (normalizedRole == 'OWNER') return true;
    switch (normalizedPolicy) {
      case 'EVERYONE':
        return true;
      case 'EDITOR_ONLY':
        return normalizedRole == 'ADMIN' || normalizedRole == 'EDITOR';
      case 'ADMIN_ONLY':
        return normalizedRole == 'ADMIN';
      default:
        return false;
    }
  }

  List<String> _availableRoleOptionsFor(TurnaGroupMember member) {
    if (!_canManageRoles) return const <String>[];
    final targetRole = member.role.trim().toUpperCase();
    if (_isOwner) {
      if (targetRole == 'OWNER') return const <String>[];
      return const <String>['ADMIN', 'EDITOR', 'MEMBER'];
    }
    if (_isAdmin) {
      if (targetRole == 'OWNER' || targetRole == 'ADMIN') {
        return const <String>[];
      }
      return const <String>['EDITOR', 'MEMBER'];
    }
    return const <String>[];
  }

  String _formatLastSeen(String? iso) {
    if (iso == null || iso.trim().isEmpty) return 'son görülme bilinmiyor';
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return 'son görülme bilinmiyor';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (diff == 0) return 'bugün $hh:$mm';
    if (diff == 1) return 'dün $hh:$mm';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  String _roleLabel(String? role) {
    switch ((role ?? '').trim().toUpperCase()) {
      case 'OWNER':
        return 'Sahip';
      case 'ADMIN':
        return 'Admin';
      case 'EDITOR':
        return 'Editör';
      default:
        return 'Üye';
    }
  }

  bool _canRemoveMember(TurnaGroupMember member) {
    if (member.userId == widget.session.userId) return false;
    final targetRole = member.role.trim().toUpperCase();
    if (_isOwner) return targetRole != 'OWNER';
    if (_isAdmin) return targetRole == 'EDITOR' || targetRole == 'MEMBER';
    if (_isEditor) return targetRole == 'MEMBER';
    return false;
  }

  bool _canBanMember(TurnaGroupMember member) {
    if (member.userId == widget.session.userId) return false;
    final targetRole = member.role.trim().toUpperCase();
    if (_isOwner) return targetRole != 'OWNER';
    if (_isAdmin) return targetRole == 'EDITOR' || targetRole == 'MEMBER';
    return false;
  }

  String _formatMuteLabel(TurnaGroupMember member) {
    if (!member.isMuted) return 'Sessize al';
    if ((member.mutedUntil ?? '').trim().isEmpty) {
      return 'Kalıcı sessizde';
    }
    final until = parseTurnaLocalDateTime(member.mutedUntil!);
    if (until == null) return 'Sessizde';
    final hh = until.hour.toString().padLeft(2, '0');
    final mm = until.minute.toString().padLeft(2, '0');
    return 'Sessizde • ${until.day.toString().padLeft(2, '0')}.${until.month.toString().padLeft(2, '0')} $hh:$mm';
  }

  Future<String?> _promptForText({
    required String title,
    required String initialValue,
    required String hintText,
    int maxLines = 1,
    int maxLength = 80,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              maxLength: maxLength,
              textCapitalization: maxLines == 1
                  ? TextCapitalization.words
                  : TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hintText),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return value;
  }

  Future<void> _applyGroupDetailUpdate({
    String? title,
    String? description,
    String? avatarObjectKey,
    bool clearAvatar = false,
  }) async {
    if (_savingDetail) return;
    setState(() {
      _savingDetail = true;
      _error = null;
    });
    try {
      final detail = await ChatApi.updateGroupDetail(
        widget.session,
        chatId: widget.chat.chatId,
        title: title,
        description: description,
        avatarObjectKey: avatarObjectKey,
        clearAvatar: clearAvatar,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _savingDetail = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingDetail = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _editGroupTitle() async {
    final value = await _promptForText(
      title: 'Grup adı',
      initialValue: _groupTitle,
      hintText: 'Grup adı',
      maxLength: 80,
    );
    if (value == null || value.trim().isEmpty || value.trim() == _groupTitle) {
      return;
    }
    await _applyGroupDetailUpdate(title: value);
  }

  Future<void> _editGroupDescription() async {
    final value = await _promptForText(
      title: 'Grup açıklaması',
      initialValue: _groupDescription ?? '',
      hintText: 'Bu grup hakkında kısa bir açıklama yaz',
      maxLines: 4,
      maxLength: 240,
    );
    if (value == null) return;
    if (value.trim() == (_groupDescription ?? '').trim()) return;
    await _applyGroupDetailUpdate(description: value);
  }

  Future<void> _changeGroupAvatar() async {
    if (!_canEditInfo || _savingDetail) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeriden seç'),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
              if ((_groupAvatarUrl ?? '').trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Fotoğrafı kaldır'),
                  onTap: () => Navigator.of(context).pop('clear'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == 'clear') {
      await _applyGroupDetailUpdate(clearAvatar: true);
      return;
    }

    final file = await _avatarPicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: kInlineImagePickerQuality,
      maxWidth: kInlineImagePickerMaxDimension,
      maxHeight: kInlineImagePickerMaxDimension,
    );
    if (file == null) return;

    setState(() {
      _savingDetail = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final contentType =
          guessContentTypeForFileName(file.name) ?? 'image/jpeg';
      final upload = await ProfileApi.createAvatarUpload(
        widget.session,
        contentType: contentType,
        fileName: file.name,
      );
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Grup fotoğrafı yüklenemedi.');
      }
      final detail = await ChatApi.updateGroupDetail(
        widget.session,
        chatId: widget.chat.chatId,
        avatarObjectKey: upload.objectKey,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _savingDetail = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingDetail = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Gruptan ayrıl'),
          content: const Text('Gruptan ayrılmak istediğinize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ayrıl'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || _leaving) return;

    setState(() {
      _leaving = true;
      _error = null;
    });
    try {
      await ChatApi.leaveGroup(widget.session, widget.chat.chatId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _leaving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openAddMembers() async {
    if (!_canAddMembers) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TurnaAddGroupMembersPage(
          session: widget.session,
          chatId: widget.chat.chatId,
          existingUserIds: _members.map((item) => item.userId).toSet(),
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || added != true) return;
    await _load(showLoading: false);
  }

  Future<void> _removeMember(TurnaGroupMember member) async {
    if (!_canRemoveMember(member)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Üyeyi çıkar'),
          content: Text(
            '${member.displayName} kişisini bu gruptan çıkarmak istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Çıkar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _error = null);
    try {
      await ChatApi.removeGroupMember(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _changeMemberRole(TurnaGroupMember member) async {
    final options = _availableRoleOptionsFor(member);
    if (options.isEmpty) return;
    final nextRole = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final role in options)
                ListTile(
                  leading: Icon(
                    member.role.trim().toUpperCase() == role
                        ? Icons.check_circle_rounded
                        : Icons.shield_outlined,
                  ),
                  title: Text(_roleLabel(role)),
                  onTap: () => Navigator.of(context).pop(role),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (nextRole == null || nextRole == member.role.trim().toUpperCase()) {
      return;
    }

    setState(() => _error = null);
    try {
      await ChatApi.updateGroupMemberRole(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
        role: nextRole,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _muteMember(TurnaGroupMember member) async {
    if (!_canRemoveMember(member)) return;
    final duration = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Süreli mute seç',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timelapse_rounded),
                title: const Text('1 Saat'),
                onTap: () => Navigator.of(context).pop('1_HOUR'),
              ),
              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: const Text('24 Saat'),
                onTap: () => Navigator.of(context).pop('24_HOURS'),
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Kalıcı'),
                onTap: () => Navigator.of(context).pop('PERMANENT'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (duration == null) return;
    setState(() => _error = null);
    try {
      await ChatApi.muteGroupMember(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
        duration: duration,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _unmuteMember(TurnaGroupMember member) async {
    if (!_canRemoveMember(member)) return;
    setState(() => _error = null);
    try {
      await ChatApi.unmuteGroupMember(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _banMember(TurnaGroupMember member) async {
    if (!_canBanMember(member)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Üyeyi yasakla'),
          content: Text(
            '${member.displayName} kişisini gruptan yasaklamak istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: TurnaColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yasakla'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _error = null);
    try {
      await ChatApi.banGroupMember(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _openMemberModeration(TurnaGroupMember member) async {
    final canRole = _availableRoleOptionsFor(member).isNotEmpty;
    final canMute = _canRemoveMember(member);
    final canBan = _canBanMember(member);
    final canRemove = _canRemoveMember(member);
    if (!canRole && !canMute && !canBan && !canRemove) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canRole)
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Rolü değiştir'),
                  onTap: () => Navigator.of(context).pop('role'),
                ),
              if (canMute)
                ListTile(
                  leading: Icon(
                    member.isMuted
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                  ),
                  title: Text(
                    member.isMuted ? 'Sessizden çıkar' : 'Sessize al',
                  ),
                  subtitle: member.isMuted
                      ? Text(_formatMuteLabel(member))
                      : null,
                  onTap: () => Navigator.of(
                    context,
                  ).pop(member.isMuted ? 'unmute' : 'mute'),
                ),
              if (canBan)
                ListTile(
                  leading: const Icon(Icons.gpp_bad_outlined),
                  title: const Text('Yasakla'),
                  onTap: () => Navigator.of(context).pop('ban'),
                ),
              if (canRemove)
                ListTile(
                  leading: const Icon(Icons.person_remove_alt_1_outlined),
                  title: const Text('Gruptan çıkar'),
                  onTap: () => Navigator.of(context).pop('remove'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'role':
        await _changeMemberRole(member);
        return;
      case 'mute':
        await _muteMember(member);
        return;
      case 'unmute':
        await _unmuteMember(member);
        return;
      case 'ban':
        await _banMember(member);
        return;
      case 'remove':
        await _removeMember(member);
        return;
    }
  }

  Future<void> _openSettings() async {
    if (!_canOpenSettings || _detail == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupSettingsPage(
          session: widget.session,
          chatId: widget.chat.chatId,
          detail: _detail!,
          members: _members,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || changed != true) return;
    await _load(showLoading: false);
  }

  Future<void> _openSharedMediaExplorer() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupMediaExplorerPage(
          session: widget.session,
          chat: widget.chat,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || result == null || result.trim().isEmpty) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _closeGroup() async {
    if (!_canCloseGroup || _closing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Grubu kapat'),
          content: const Text(
            'Bu grubu kapatırsanız sohbet ve içerikler tüm üyeler için kapanır. Devam etmek istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: TurnaColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Grubu Kapat'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() {
      _closing = true;
      _error = null;
    });
    try {
      await ChatApi.closeGroup(widget.session, widget.chat.chatId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _closing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final detail = await ChatApi.fetchChatDetail(
        widget.session,
        widget.chat.chatId,
      );
      final members = await ChatApi.fetchGroupMembers(
        widget.session,
        chatId: widget.chat.chatId,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _members = members.items;
        _totalMemberCount = members.totalCount;
        _hasMoreMembers = members.hasMore;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadMoreMembers() async {
    if (_loadingMoreMembers || !_hasMoreMembers) return;
    setState(() => _loadingMoreMembers = true);
    try {
      final page = await ChatApi.fetchGroupMembers(
        widget.session,
        chatId: widget.chat.chatId,
        offset: _members.length,
      );
      if (!mounted) return;
      final existingIds = _members.map((item) => item.userId).toSet();
      setState(() {
        _members = [
          ..._members,
          ...page.items.where((item) => !existingIds.contains(item.userId)),
        ];
        _totalMemberCount = page.totalCount;
        _hasMoreMembers = page.hasMore;
        _loadingMoreMembers = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMoreMembers = false;
        _error = error.toString();
      });
    }
  }

  Widget _buildHeaderCard() {
    final roleText = _myRole.isEmpty ? null : _roleLabel(_myRole);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: TurnaColors.divider),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: _canEditInfo ? _changeGroupAvatar : null,
                child: _ProfileAvatar(
                  label: _groupTitle,
                  avatarUrl: _groupAvatarUrl,
                  authToken: widget.session.token,
                  radius: 36,
                ),
              ),
              if (_canEditInfo)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: _savingDetail ? null : _changeGroupAvatar,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: TurnaColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _groupTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '$_groupMemberCount üye',
            style: const TextStyle(
              color: TurnaColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if ((_groupDescription ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _groupDescription!.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: TurnaColors.textSoft, height: 1.4),
            ),
          ],
          if (roleText != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: TurnaColors.primary50,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Rolün: $roleText',
                style: const TextStyle(
                  color: TurnaColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (_savingDetail) ...[
            const SizedBox(height: 12),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoTab() {
    return RefreshIndicator(
      onRefresh: () => _load(showLoading: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: TurnaColors.error),
              ),
            ),
          if (_canEditInfo)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TurnaColors.divider),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.drive_file_rename_outline_rounded,
                    ),
                    title: const Text('Grup adını düzenle'),
                    subtitle: Text(
                      _groupTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _editGroupTitle,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notes_rounded),
                    title: const Text('Grup açıklamasını düzenle'),
                    subtitle: Text(
                      (_groupDescription ?? '').trim().isEmpty
                          ? 'Henüz açıklama eklenmedi'
                          : _groupDescription!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _editGroupDescription,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TurnaColors.divider),
            ),
            child: ListTile(
              leading: const Icon(Icons.perm_media_outlined),
              title: const Text('Medya, dosyalar ve bağlantılar'),
              subtitle: const Text('Grupta paylaşılan içerikleri tara'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _openSharedMediaExplorer,
            ),
          ),
          const SizedBox(height: 14),
          if (_canAddMembers)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openAddMembers,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Davet Et'),
              ),
            ),
          if (_canAddMembers) const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _leaving ? null : _leaveGroup,
              icon: _leaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: const Text('Gruptan Ayrıl'),
              style: OutlinedButton.styleFrom(
                foregroundColor: TurnaColors.error,
                side: const BorderSide(color: TurnaColors.error),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          if (_canCloseGroup) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _closing ? null : _closeGroup,
                style: FilledButton.styleFrom(
                  backgroundColor: TurnaColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _closing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever_outlined),
                label: const Text('Grubu Kapat'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    return RefreshIndicator(
      onRefresh: () => _load(showLoading: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              const Text(
                'Üyeler',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_members.length}/$_totalMemberCount',
                style: const TextStyle(
                  color: TurnaColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_canAddMembers) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _openAddMembers,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Üye Ekle'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: TurnaColors.error),
              ),
            ),
          ..._members.map(
            (member) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: TurnaColors.divider),
              ),
              child: Row(
                children: [
                  _ProfileAvatar(
                    label: member.displayName,
                    avatarUrl: member.avatarUrl,
                    authToken: widget.session.token,
                    radius: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatLastSeen(member.lastSeenAt),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: TurnaColors.textMuted,
                          ),
                        ),
                        if (member.isMuted) ...[
                          const SizedBox(height: 3),
                          Text(
                            _formatMuteLabel(member),
                            style: const TextStyle(
                              fontSize: 12,
                              color: TurnaColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: _availableRoleOptionsFor(member).isEmpty
                            ? null
                            : () => _changeMemberRole(member),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: TurnaColors.backgroundMuted,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _roleLabel(member.role),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: TurnaColors.textSoft,
                                ),
                              ),
                              if (_availableRoleOptionsFor(
                                member,
                              ).isNotEmpty) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.expand_more_rounded,
                                  size: 14,
                                  color: TurnaColors.textMuted,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_canRemoveMember(member) ||
                          _canBanMember(member)) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _openMemberModeration(member),
                          borderRadius: BorderRadius.circular(999),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              'Yönet',
                              style: TextStyle(
                                color: TurnaColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(
                child: Text(
                  'Bu grupta henüz üye görünmüyor.',
                  style: TextStyle(color: TurnaColors.textMuted),
                ),
              ),
            ),
          if (_hasMoreMembers) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _loadingMoreMembers ? null : _loadMoreMembers,
                child: Text(
                  _loadingMoreMembers
                      ? 'Yükleniyor...'
                      : 'Daha Fazla Üye Yükle',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Bilgisi'),
        actions: [
          if (_canOpenSettings)
            IconButton(
              tooltip: 'Grup ayarları',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: _loading && _detail == null
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildHeaderCard(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TurnaColors.divider),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: TurnaColors.primary50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      labelColor: TurnaColors.primary,
                      unselectedLabelColor: TurnaColors.textMuted,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Bilgiler'),
                        Tab(text: 'Üyeler'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [_buildInfoTab(), _buildMembersTab()],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
