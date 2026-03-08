part of '../main.dart';

class MainTabs extends StatefulWidget {
  const MainTabs({
    super.key,
    required this.session,
    required this.onSessionUpdated,
    required this.onLogout,
  });

  final AuthSession session;
  final void Function(AuthSession session) onSessionUpdated;
  final VoidCallback onLogout;

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> with WidgetsBindingObserver {
  int _index = 0;
  int _totalUnreadChats = 0;
  late final PresenceSocketClient _presenceClient;
  final _inboxUpdateNotifier = ValueNotifier<int>(0);
  final _callCoordinator = TurnaCallCoordinator();
  String? _activeIncomingCallId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TurnaPushManager.syncSession(widget.session);
    TurnaNativeCallManager.bindSession(
      session: widget.session,
      coordinator: _callCoordinator,
      onSessionExpired: widget.onLogout,
    );
    TurnaAnalytics.logEvent('app_session_started', {
      'user_id': widget.session.userId,
    });
    _presenceClient = PresenceSocketClient(
      token: widget.session.token,
      onInboxUpdate: () {
        _inboxUpdateNotifier.value++;
      },
      onIncomingCall: _callCoordinator.handleIncoming,
      onCallAccepted: _callCoordinator.handleAccepted,
      onCallDeclined: _callCoordinator.handleDeclined,
      onCallMissed: _callCoordinator.handleMissed,
      onCallEnded: _callCoordinator.handleEnded,
    )..connect();
    _callCoordinator.addListener(_handleCallCoordinator);
  }

  @override
  void didUpdateWidget(covariant MainTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.session.userId != widget.session.userId) {
      TurnaPushManager.syncSession(widget.session);
      TurnaNativeCallManager.bindSession(
        session: widget.session,
        coordinator: _callCoordinator,
        onSessionExpired: widget.onLogout,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callCoordinator.removeListener(_handleCallCoordinator);
    _presenceClient.dispose();
    TurnaNativeCallManager.unbindSession(widget.session.userId);
    _callCoordinator.dispose();
    _inboxUpdateNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _presenceClient.refreshConnection();
      TurnaNativeCallManager.handleAppResumed();
      _inboxUpdateNotifier.value++;
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _presenceClient.disconnectForBackground();
    }
  }

  void _handleCallCoordinator() {
    final incoming = _callCoordinator.takeIncomingCall();
    if (incoming == null) return;
    if (_activeIncomingCallId == incoming.call.id) return;

    _activeIncomingCallId = incoming.call.id;
    final returnChat = buildDirectChatPreviewForCall(
      widget.session,
      incoming.call,
    );
    final shouldOpenChatOnExit = !kTurnaActiveChatRegistry.isChatActive(
      returnChat.chatId,
    );
    Future<void>(() async {
      final navigator = kTurnaNavigatorKey.currentState;
      if (!mounted || navigator == null) return;
      try {
        await navigator.push(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'incoming-call'),
            builder: (_) => IncomingCallPage(
              session: widget.session,
              coordinator: _callCoordinator,
              incoming: incoming,
              onSessionExpired: widget.onLogout,
              returnChatOnExit: shouldOpenChatOnExit ? returnChat : null,
            ),
          ),
        );
      } finally {
        if (mounted) {
          _activeIncomingCallId = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const PlaceholderPage(title: 'Durum'),
      CallsPage(
        session: widget.session,
        callCoordinator: _callCoordinator,
        onSessionExpired: widget.onLogout,
      ),
      const PlaceholderPage(title: 'Araclar'),
      ChatsPage(
        session: widget.session,
        inboxUpdateNotifier: _inboxUpdateNotifier,
        callCoordinator: _callCoordinator,
        onSessionExpired: widget.onLogout,
        onUnreadChanged: (count) {
          if (_totalUnreadChats == count || !mounted) return;
          setState(() => _totalUnreadChats = count);
        },
      ),
      SettingsPage(
        session: widget.session,
        onSessionUpdated: widget.onSessionUpdated,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: _TurnaBottomBar(
        selectedIndex: _index,
        unreadChats: _totalUnreadChats,
        session: widget.session,
        onSelect: (index) => setState(() => _index = index),
      ),
    );
  }
}

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

class _ChatsPageState extends State<ChatsPage> {
  int _refreshTick = 0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.inboxUpdateNotifier?.addListener(_onInboxUpdate);
    _searchController.addListener(_onSearchChanged);
  }

  void _onInboxUpdate() {
    if (!mounted) return;
    setState(() => _refreshTick++);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    widget.inboxUpdateNotifier?.removeListener(_onInboxUpdate);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Turna',
          style: TextStyle(
            color: TurnaColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: const [
          Icon(Icons.qr_code_scanner_outlined),
          SizedBox(width: 12),
          Icon(Icons.camera_alt_outlined),
          SizedBox(width: 12),
          Icon(Icons.more_vert),
          SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<ChatPreview>>(
        future: ChatApi.fetchChats(widget.session, refreshTick: _refreshTick),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            final isAuthError = error is TurnaUnauthorizedException;
            return _CenteredState(
              icon: isAuthError ? Icons.lock_outline : Icons.cloud_off_outlined,
              title: isAuthError
                  ? 'Oturumun suresi doldu'
                  : 'Sohbetler yuklenemedi',
              message: error.toString(),
              primaryLabel: isAuthError ? 'Yeniden giris yap' : 'Tekrar dene',
              onPrimary: isAuthError
                  ? widget.onSessionExpired
                  : () => setState(() => _refreshTick++),
            );
          }

          final chats = snapshot.data ?? [];
          final unreadTotal = chats.fold<int>(
            0,
            (sum, chat) => sum + chat.unreadCount,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onUnreadChanged?.call(unreadTotal);
          });
          final query = _searchController.text.trim().toLowerCase();
          final filteredChats = chats.where((chat) {
            if (query.isEmpty) return true;
            return chat.name.toLowerCase().contains(query) ||
                chat.message.toLowerCase().contains(query);
          }).toList();

          return RefreshIndicator(
            onRefresh: () async => setState(() => _refreshTick++),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filteredChats.isEmpty ? 2 : filteredChats.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Sohbetlerde ara',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
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

                if (filteredChats.isEmpty) {
                  if (chats.isEmpty) {
                    return const _CenteredListState(
                      icon: Icons.chat_bubble_outline,
                      title: 'Henuz sohbet yok',
                      message:
                          'Ilk konusmayi baslatmak icin sag alttaki butondan kisi sec.',
                    );
                  }
                  return _CenteredListState(
                    icon: Icons.search_off,
                    title: 'Sonuc bulunamadi',
                    message:
                        '"${_searchController.text.trim()}" icin eslesen sohbet yok.',
                  );
                }

                final chat = filteredChats[index - 1];
                return ListTile(
                  leading: _ProfileAvatar(
                    label: chat.name,
                    avatarUrl: chat.avatarUrl,
                    authToken: widget.session.token,
                    radius: 22,
                  ),
                  title: Text(
                    chat.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    chat.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        chat.time,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777C79),
                        ),
                      ),
                      if (chat.unreadCount > 0) ...[
                        const SizedBox(height: 6),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: const BoxDecoration(
                            color: TurnaColors.primary,
                            borderRadius: BorderRadius.all(
                              Radius.circular(999),
                            ),
                          ),
                          child: Text(
                            chat.unreadCount > 99
                                ? '99+'
                                : '${chat.unreadCount}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: TurnaColors.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
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
            setState(() => _refreshTick++);
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.chat,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final ChatPreview chat;
  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

PageRoute<void> buildChatRoomRoute({
  required ChatPreview chat,
  required AuthSession session,
  required TurnaCallCoordinator callCoordinator,
  required VoidCallback onSessionExpired,
}) {
  return MaterialPageRoute(
    settings: RouteSettings(
      name: kChatRoomRouteName,
      arguments: {'chatId': chat.chatId},
    ),
    builder: (_) => ChatRoomPage(
      chat: chat,
      session: session,
      callCoordinator: callCoordinator,
      onSessionExpired: onSessionExpired,
    ),
  );
}

ChatPreview buildDirectChatPreviewForCall(
  AuthSession session,
  TurnaCallSummary call,
) {
  return ChatPreview(
    chatId: ChatApi.buildDirectChatId(session.userId, call.peer.id),
    name: call.peer.displayName,
    message: '',
    time: '',
    avatarUrl: call.peer.avatarUrl,
  );
}

class _ChatTimelineEntry {
  const _ChatTimelineEntry._({
    required this.id,
    required this.createdAt,
    this.message,
    this.call,
  });

  factory _ChatTimelineEntry.message(ChatMessage message) {
    return _ChatTimelineEntry._(
      id: 'message:${message.id}',
      createdAt: message.createdAt,
      message: message,
    );
  }

  factory _ChatTimelineEntry.call(TurnaCallHistoryItem call) {
    return _ChatTimelineEntry._(
      id: 'call:${call.id}',
      createdAt: call.createdAt ?? '',
      call: call,
    );
  }

  final String id;
  final String createdAt;
  final ChatMessage? message;
  final TurnaCallHistoryItem? call;

  bool get isMessage => message != null;
}

class _ChatRoomPageState extends State<ChatRoomPage>
    with WidgetsBindingObserver, RouteAware {
  late final TurnaSocketClient _client;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _mediaPicker = ImagePicker();
  final FocusNode _composerFocusNode = FocusNode();
  bool _showScrollToBottom = false;
  bool _attachmentBusy = false;
  bool _hasComposerText = false;
  bool _loadingPeerCalls = false;
  TurnaReplyPayload? _replyDraft;
  _PinnedMessageDraft? _pinnedMessage;
  List<TurnaCallHistoryItem> _peerCalls = const [];
  Set<String> _starredMessageIds = <String>{};
  Set<String> _softDeletedMessageIds = <String>{};
  Set<String> _deletedMessageIds = <String>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  int _lastRenderedTimelineCount = 0;
  Timer? _messageHighlightTimer;
  String? _highlightedMessageId;
  PageRoute<dynamic>? _route;

  String? get _peerUserId =>
      ChatApi.extractPeerUserId(widget.chat.chatId, widget.session.userId);

  String get _pinnedMessageKey => 'turna_pinned_message_${widget.chat.chatId}';
  String get _starredMessagesKey =>
      'turna_starred_messages_${widget.chat.chatId}';
  String get _softDeletedMessagesKey =>
      'turna_soft_deleted_messages_${widget.chat.chatId}';
  String get _deletedMessagesKey =>
      'turna_deleted_messages_${widget.chat.chatId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    turnaLog('chat room init', {
      'chatId': widget.chat.chatId,
      'senderId': widget.session.userId,
    });
    TurnaAnalytics.logEvent('chat_opened', {'chat_id': widget.chat.chatId});
    _client = TurnaSocketClient(
      chatId: widget.chat.chatId,
      senderId: widget.session.userId,
      peerUserId: _peerUserId,
      token: widget.session.token,
      onSessionExpired: widget.onSessionExpired,
    )..connect();
    _client.addListener(_refresh);
    widget.callCoordinator.addListener(_handleCallCoordinatorChanged);
    _controller.addListener(_handleComposerChanged);
    _composerFocusNode.addListener(_refresh);
    _scrollController.addListener(_handleScroll);
    _loadPinnedMessage();
    _loadLocalMessageState();
    unawaited(_loadPeerCallHistory());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || identical(route, _route)) return;
    if (_route != null) {
      kTurnaRouteObserver.unsubscribe(this);
    }
    _route = route;
    kTurnaRouteObserver.subscribe(this, route);
  }

  @override
  void didPush() {
    kTurnaActiveChatRegistry.setCurrent(widget.chat);
    unawaited(_loadPeerCallHistory());
  }

  @override
  void didPopNext() {
    kTurnaActiveChatRegistry.setCurrent(widget.chat);
    unawaited(_loadPeerCallHistory());
  }

  @override
  void didPushNext() {
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
  }

  @override
  void didPop() {
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
  }

  void _refresh() {
    final shouldSnapToBottom =
        !_scrollController.hasClients || _scrollController.offset < 120;
    if (mounted) {
      setState(() {});
    }
    final timelineCount = _buildTimelineEntries().length;
    if (timelineCount != _lastRenderedTimelineCount) {
      _lastRenderedTimelineCount = timelineCount;
      if (shouldSnapToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    }
  }

  void _handleCallCoordinatorChanged() {
    unawaited(_loadPeerCallHistory());
  }

  void _handleComposerChanged() {
    final text = _controller.text;
    _client.updateComposerText(text);
    final hasComposerText = text.trim().isNotEmpty;
    if (hasComposerText != _hasComposerText && mounted) {
      setState(() => _hasComposerText = hasComposerText);
    }
  }

  String? _buildPeerStatusText() {
    if (_peerUserId == null) return null;
    if (_client.peerTyping) return 'yaziyor...';
    if (_client.peerOnline) return 'online';
    final lastSeenAt = _client.peerLastSeenAt;
    if (lastSeenAt == null || lastSeenAt.trim().isEmpty) return null;
    return 'son gorulme ${_formatPresenceTime(lastSeenAt)}';
  }

  String _formatPresenceTime(String iso) {
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return iso;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final seenDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(seenDay).inDays;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (diffDays == 0) return 'bugun $hh:$mm';
    if (diffDays == 1) return 'dun $hh:$mm';

    final dd = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    if (dt.year == now.year) return '$dd.$month $hh:$mm';
    return '$dd.$month.${dt.year} $hh:$mm';
  }

  Future<void> _openPeerProfile() async {
    final peerUserId = _peerUserId;
    if (peerUserId == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          session: widget.session,
          userId: peerUserId,
          fallbackName: widget.chat.name,
          fallbackAvatarUrl: widget.chat.avatarUrl,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _startCall(TurnaCallType type) async {
    final peerUserId = _peerUserId;
    if (peerUserId == null) return;

    try {
      final started = await CallApi.startCall(
        widget.session,
        calleeId: peerUserId,
        type: type,
      );
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OutgoingCallPage(
            session: widget.session,
            coordinator: widget.callCoordinator,
            initialCall: started,
            onSessionExpired: widget.onSessionExpired,
          ),
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
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 180;
    if (shouldShow != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = shouldShow);
    }

    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 220) {
      _client.loadOlderMessages();
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  String _formatMessageTime(String iso) {
    return formatTurnaLocalClock(iso);
  }

  String _formatDayLabel(String iso) {
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(messageDay).inDays;
    if (diffDays == 0) return 'Bugun';
    if (diffDays == 1) return 'Dun';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd.$mm.${dt.year}';
  }

  String _timelineCreatedAt(_ChatTimelineEntry entry) {
    if (entry.message != null) return entry.message!.createdAt;
    final call = entry.call;
    return call?.createdAt ?? call?.endedAt ?? call?.acceptedAt ?? '';
  }

  bool _shouldShowDayChip(List<_ChatTimelineEntry> entries, int index) {
    if (index == entries.length - 1) return true;
    final current = parseTurnaLocalDateTime(_timelineCreatedAt(entries[index]));
    final older = parseTurnaLocalDateTime(
      _timelineCreatedAt(entries[index + 1]),
    );
    if (current == null || older == null) return false;
    return current.year != older.year ||
        current.month != older.month ||
        current.day != older.day;
  }

  String? _guessContentType(String fileName) =>
      guessContentTypeForFileName(fileName);

  String _formatFileSize(int bytes) => formatBytesLabel(bytes);

  Future<void> _loadPeerCallHistory() async {
    final peerUserId = _peerUserId;
    if (peerUserId == null || _loadingPeerCalls) return;

    _loadingPeerCalls = true;
    final shouldSnapToBottom =
        !_scrollController.hasClients || _scrollController.offset < 120;
    final previousCount = _buildTimelineEntries().length;
    try {
      final calls = await CallApi.fetchCalls(widget.session);
      if (!mounted) return;
      final filtered =
          calls.where((item) => item.peer.id == peerUserId).toList()
            ..sort((a, b) {
              final aTime = a.createdAt ?? a.endedAt ?? a.acceptedAt ?? '';
              final bTime = b.createdAt ?? b.endedAt ?? b.acceptedAt ?? '';
              return compareTurnaTimestamps(aTime, bTime);
            });
      setState(() => _peerCalls = filtered);
      final nextCount = _buildTimelineEntries().length;
      _lastRenderedTimelineCount = nextCount;
      if (shouldSnapToBottom && nextCount != previousCount) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      turnaLog('chat call history load failed', error);
    } finally {
      _loadingPeerCalls = false;
    }
  }

  void _showVoiceMessagePlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sesli mesaj yakinda eklenecek.')),
    );
  }

  void _showAttachmentPlaceholder(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label yakinda eklenecek.')));
  }

  Future<void> _loadPinnedMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pinnedMessageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _pinnedMessage = _PinnedMessageDraft.fromMap(map);
      });
    } catch (error) {
      turnaLog('chat pinned message load failed', error);
    }
  }

  Future<void> _persistPinnedMessage(_PinnedMessageDraft? draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (draft == null) {
      await prefs.remove(_pinnedMessageKey);
      return;
    }
    await prefs.setString(_pinnedMessageKey, jsonEncode(draft.toMap()));
  }

  Future<void> _loadLocalMessageState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final starred = prefs.getStringList(_starredMessagesKey) ?? const [];
      final softDeleted =
          prefs.getStringList(_softDeletedMessagesKey) ?? const [];
      final deleted = prefs.getStringList(_deletedMessagesKey) ?? const [];
      if (!mounted) return;
      setState(() {
        _starredMessageIds = starred.toSet();
        _softDeletedMessageIds = softDeleted.toSet();
        _deletedMessageIds = deleted.toSet();
      });
    } catch (error) {
      turnaLog('chat local message state load failed', error);
    }
  }

  Future<void> _persistStarredMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_starredMessagesKey, _starredMessageIds.toList());
  }

  Future<void> _persistSoftDeletedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _softDeletedMessagesKey,
      _softDeletedMessageIds.toList(),
    );
  }

  Future<void> _persistDeletedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_deletedMessagesKey, _deletedMessageIds.toList());
  }

  bool _isMessageDeletedForMe(ChatMessage msg) =>
      _softDeletedMessageIds.contains(msg.id);

  bool _isMessageDeletedPlaceholder(
    ChatMessage msg, {
    ParsedTurnaMessageText? parsed,
  }) => _isMessageDeletedForMe(msg) || (parsed?.deletedForEveryone ?? false);

  bool _canDeleteForEveryone(
    ChatMessage msg, {
    ParsedTurnaMessageText? parsed,
  }) {
    if (msg.senderId != widget.session.userId) return false;
    if (msg.id.startsWith('local_')) return false;
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) return false;
    final createdAt = DateTime.tryParse(msg.createdAt)?.toLocal();
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt) <= const Duration(minutes: 10);
  }

  Future<bool> _showDestructiveConfirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: TurnaColors.error,
                foregroundColor: Colors.white,
              ),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return approved == true;
  }

  Future<void> _setPinnedPreviewIfNeeded(
    String messageId,
    String previewText,
  ) async {
    final current = _pinnedMessage;
    if (current == null || current.messageId != messageId) return;
    final next = _PinnedMessageDraft(
      messageId: current.messageId,
      senderLabel: current.senderLabel,
      previewText: previewText,
    );
    if (mounted) {
      setState(() => _pinnedMessage = next);
    }
    await _persistPinnedMessage(next);
  }

  String _previewSnippetForMessage(ChatMessage msg) {
    final parsed = parseTurnaMessageText(msg.text);
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      return 'Silindi.';
    }
    final text = parsed.text.trim();
    if (text.isNotEmpty) {
      return text.length > 72 ? '${text.substring(0, 72)}...' : text;
    }
    if (msg.attachments.isEmpty) return 'Mesaj';
    final first = msg.attachments.first;
    if (_isAudioAttachment(first)) return 'Sesli mesaj';
    if (first.kind == ChatAttachmentKind.image) return 'Fotograf';
    if (first.kind == ChatAttachmentKind.video) return 'Video';
    return 'Dosya';
  }

  TurnaReplyPayload _replyPayloadForMessage(ChatMessage msg) {
    final mine = msg.senderId == widget.session.userId;
    return TurnaReplyPayload(
      messageId: msg.id,
      senderLabel: mine ? 'Sen' : widget.chat.name,
      previewText: _previewSnippetForMessage(msg),
    );
  }

  Future<List<int>> _downloadAttachmentBytes(ChatAttachment attachment) async {
    final url = attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      throw TurnaApiException('Iletilecek ek icin link bulunamadi.');
    }
    final uri = Uri.parse(url);
    var response = await http.get(uri);
    if (response.statusCode >= 400) {
      response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${widget.session.token}'},
      );
    }
    if (response.statusCode >= 400) {
      throw TurnaApiException('Ek indirilemedi.');
    }
    return response.bodyBytes;
  }

  Future<void> _forwardMessage(ChatMessage msg) async {
    final targetChat = await Navigator.push<ChatPreview>(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardMessagePickerPage(
          session: widget.session,
          currentChatId: widget.chat.chatId,
        ),
      ),
    );
    if (!mounted || targetChat == null) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('${targetChat.name} sohbetine iletiliyor...')),
    );

    try {
      final parsed = parseTurnaMessageText(msg.text);
      final drafts = <OutgoingAttachmentDraft>[];
      for (final attachment in msg.attachments) {
        final bytes = await _downloadAttachmentBytes(attachment);
        final upload = await ChatApi.createAttachmentUpload(
          widget.session,
          chatId: targetChat.chatId,
          kind: attachment.kind,
          contentType: attachment.contentType,
          fileName: attachment.fileName ?? 'dosya',
        );
        final uploadRes = await http.put(
          Uri.parse(upload.uploadUrl),
          headers: upload.headers,
          body: bytes,
        );
        if (uploadRes.statusCode >= 400) {
          throw TurnaApiException('Iletilecek ek yuklenemedi.');
        }
        drafts.add(
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: attachment.kind,
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            sizeBytes: attachment.sizeBytes > 0
                ? attachment.sizeBytes
                : bytes.length,
            width: attachment.width,
            height: attachment.height,
            durationSeconds: attachment.durationSeconds,
          ),
        );
      }

      await ChatApi.sendMessage(
        widget.session,
        chatId: targetChat.chatId,
        text: parsed.text.trim().isEmpty ? null : parsed.text.trim(),
        attachments: drafts,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${targetChat.name} sohbetine iletildi.')),
        );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleStarMessage(ChatMessage msg) async {
    final next = Set<String>.from(_starredMessageIds);
    final nowStarred = !next.contains(msg.id);
    if (nowStarred) {
      next.add(msg.id);
    } else {
      next.remove(msg.id);
    }
    setState(() => _starredMessageIds = next);
    await _persistStarredMessages();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nowStarred ? 'Mesaja yildiz eklendi.' : 'Yildiz kaldirildi.',
        ),
      ),
    );
  }

  Future<void> _deleteMessageLocally(ChatMessage msg) async {
    final wasPinned = _pinnedMessage?.messageId == msg.id;
    final next = Set<String>.from(_deletedMessageIds)..add(msg.id);
    final nextStarred = Set<String>.from(_starredMessageIds)..remove(msg.id);
    final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
      ..remove(msg.id);
    setState(() {
      _deletedMessageIds = next;
      _starredMessageIds = nextStarred;
      _softDeletedMessageIds = nextSoftDeleted;
      if (wasPinned) {
        _pinnedMessage = null;
      }
    });
    await _persistSoftDeletedMessages();
    await _persistDeletedMessages();
    await _persistStarredMessages();
    if (wasPinned) {
      await _persistPinnedMessage(null);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mesaj bu cihazdan silindi.')));
  }

  Future<void> _deleteMessageForMe(ChatMessage msg) async {
    final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
      ..add(msg.id);
    final nextStarred = Set<String>.from(_starredMessageIds)..remove(msg.id);
    setState(() {
      _softDeletedMessageIds = nextSoftDeleted;
      _starredMessageIds = nextStarred;
    });
    await _persistSoftDeletedMessages();
    await _persistStarredMessages();
    await _setPinnedPreviewIfNeeded(msg.id, 'Silindi.');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mesaj sende Silindi. olarak gosteriliyor.'),
      ),
    );
  }

  Future<void> _deleteMessageForEveryone(ChatMessage msg) async {
    try {
      final updated = await ChatApi.deleteMessageForEveryone(
        widget.session,
        messageId: msg.id,
      );
      final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
        ..remove(msg.id);
      if (mounted) {
        setState(() => _softDeletedMessageIds = nextSoftDeleted);
      }
      await _persistSoftDeletedMessages();
      await _setPinnedPreviewIfNeeded(msg.id, 'Silindi.');
      _client.mergeServerMessage(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mesaj herkesten silindi.')));
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _confirmRemoveDeletedPlaceholder(ChatMessage msg) async {
    final confirmed = await _showDestructiveConfirm(
      title: 'Mesajı kaldir',
      message: 'Bu Silindi. mesajı cihazından tamamen kaldirilsin mi?',
      confirmLabel: 'Kaldir',
    );
    if (!confirmed) return;
    await _deleteMessageLocally(msg);
  }

  Future<void> _showDeleteMessageOptions(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    final canDeleteForEveryone = _canDeleteForEveryone(msg, parsed: parsed);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Benden sil'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final confirmed = await _showDestructiveConfirm(
                    title: 'Mesajı senden sil',
                    message:
                        'Bu mesaj sadece senin tarafinda Silindi. olarak gosterilecek.',
                    confirmLabel: 'Benden sil',
                  );
                  if (!confirmed) return;
                  await _deleteMessageForMe(msg);
                },
              ),
              if (canDeleteForEveryone)
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Herkesten sil'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirmed = await _showDestructiveConfirm(
                      title: 'Mesajı herkesten sil',
                      message:
                          'Bu mesaj iki taraf icin de Silindi. olarak degisecek.',
                      confirmLabel: 'Herkesten sil',
                    );
                    if (!confirmed) return;
                    await _deleteMessageForEveryone(msg);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _translateMessage(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    final text = parsed.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cevrilecek metin bulunamadi.')),
      );
      return;
    }

    final uri = Uri.parse(
      'https://translate.google.com/?sl=auto&tl=tr&text=${Uri.encodeComponent(text)}&op=translate',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ceviri acilamadi.')));
    }
  }

  Future<void> _reportMessage(ChatMessage msg) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        const reasons = ['Spam', 'Taciz', 'Uygunsuz icerik', 'Sahte hesap'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final reason in reasons)
                ListTile(
                  title: Text(reason),
                  onTap: () => Navigator.pop(sheetContext, reason),
                ),
            ],
          ),
        );
      },
    );

    if (reason == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Sikayet kaydedildi: $reason')));
  }

  Future<void> _showMoreMessageActions(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      await _confirmRemoveDeletedPlaceholder(msg);
      return;
    }
    final isPinned = _pinnedMessage?.messageId == msg.id;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                ),
                title: Text(isPinned ? 'Sabitlemeyi kaldir' : 'Sabitle'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final next = isPinned
                      ? null
                      : _PinnedMessageDraft(
                          messageId: msg.id,
                          senderLabel: _replyPayloadForMessage(msg).senderLabel,
                          previewText: _previewSnippetForMessage(msg),
                        );
                  if (!mounted) return;
                  setState(() => _pinnedMessage = next);
                  await _persistPinnedMessage(next);
                },
              ),
              ListTile(
                leading: const Icon(Icons.translate_rounded),
                title: const Text('Cevir'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _translateMessage(msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Sikayet Et'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _reportMessage(msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Sil'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteMessageOptions(msg);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleMessageLongPress(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      await _confirmRemoveDeletedPlaceholder(msg);
      return;
    }
    final replyPayload = _replyPayloadForMessage(msg);
    final isStarred = _starredMessageIds.contains(msg.id);
    final textOnly = parsed.text.trim();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    _MessageQuickAction(
                      icon: Icons.reply_rounded,
                      label: 'Cevapla',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() => _replyDraft = replyPayload);
                        _composerFocusNode.requestFocus();
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.forward_rounded,
                      label: 'Ilet',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _forwardMessage(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.copy_all_outlined,
                      label: 'Kopyala',
                      enabled: textOnly.isNotEmpty,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await Clipboard.setData(ClipboardData(text: textOnly));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Mesaj kopyalandi.')),
                        );
                      },
                    ),
                    _MessageQuickAction(
                      icon: isStarred
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      label: isStarred ? 'Yildizi kaldir' : 'Yildiz ekle',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _toggleStarMessage(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Sil',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showDeleteMessageOptions(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.more_horiz_rounded,
                      label: 'Daha fazla',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showMoreMessageActions(msg);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isSameMessageGroup(
    List<_ChatTimelineEntry> displayEntries,
    int currentIndex,
    int neighborIndex,
  ) {
    if (neighborIndex < 0 || neighborIndex >= displayEntries.length) {
      return false;
    }
    final currentEntry = displayEntries[currentIndex];
    final neighborEntry = displayEntries[neighborIndex];
    final current = currentEntry.message;
    final neighbor = neighborEntry.message;
    if (current == null || neighbor == null) return false;
    if (current.senderId != neighbor.senderId) return false;
    final currentDate = parseTurnaLocalDateTime(current.createdAt);
    final neighborDate = parseTurnaLocalDateTime(neighbor.createdAt);
    if (currentDate == null || neighborDate == null) return false;
    return currentDate.year == neighborDate.year &&
        currentDate.month == neighborDate.month &&
        currentDate.day == neighborDate.day;
  }

  EdgeInsets _bubbleMarginFor(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    bool mine,
  ) {
    final joinsOlder = _isSameMessageGroup(displayEntries, index, index + 1);
    final joinsNewer = _isSameMessageGroup(displayEntries, index, index - 1);
    return EdgeInsets.only(
      left: mine ? 56 : 8,
      right: mine ? 8 : 56,
      top: joinsOlder ? TurnaChatTokens.stackGap / 2 : TurnaChatTokens.groupGap,
      bottom: joinsNewer
          ? TurnaChatTokens.stackGap / 2
          : TurnaChatTokens.groupGap / 2,
    );
  }

  List<ChatMessage> _currentDisplayMessages() => _client.messages.reversed
      .where((message) => !_deletedMessageIds.contains(message.id))
      .toList();

  List<_ChatTimelineEntry> _buildTimelineEntries() {
    final entries = <_ChatTimelineEntry>[
      ..._currentDisplayMessages().map(_ChatTimelineEntry.message),
      ..._peerCalls.map(_ChatTimelineEntry.call),
    ];
    entries.sort(
      (a, b) => compareTurnaTimestamps(
        _timelineCreatedAt(b),
        _timelineCreatedAt(a),
      ),
    );
    return entries;
  }

  GlobalKey _messageKeyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, GlobalKey.new);

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    return completer.future;
  }

  void _highlightMessage(String messageId) {
    _messageHighlightTimer?.cancel();
    if (mounted) {
      setState(() => _highlightedMessageId = messageId);
    }
    _messageHighlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || _highlightedMessageId != messageId) return;
      setState(() => _highlightedMessageId = null);
    });
  }

  Future<void> _scrollToReplyTarget(String messageId) async {
    var displayMessages = _currentDisplayMessages();
    var targetIndex = displayMessages.indexWhere(
      (message) => message.id == messageId,
    );

    var loadAttempt = 0;
    while (targetIndex == -1 && _client.hasMore && loadAttempt < 8) {
      await _client.loadOlderMessages();
      loadAttempt += 1;
      await _waitForNextFrame();
      displayMessages = _currentDisplayMessages();
      targetIndex = displayMessages.indexWhere(
        (message) => message.id == messageId,
      );
    }

    if (targetIndex == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yanitlanan mesaj bulunamadi.')),
      );
      return;
    }

    _highlightMessage(messageId);
    await _waitForNextFrame();
    if (!mounted) return;

    var targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext != null) {
      if (!targetContext.mounted) return;
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.34,
      );
      return;
    }

    if (!_scrollController.hasClients) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final ratio = displayMessages.length <= 1
        ? 0.0
        : targetIndex / (displayMessages.length - 1);
    final viewport = _scrollController.position.viewportDimension;
    final offsets = <double>[
      (maxExtent * ratio).clamp(0.0, maxExtent).toDouble(),
      (maxExtent * ratio + viewport * 0.5).clamp(0.0, maxExtent).toDouble(),
    ];

    for (final offset in offsets) {
      await _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      await _waitForNextFrame();
      if (!mounted) return;
      targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null) {
        if (!targetContext.mounted) return;
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.34,
        );
        return;
      }
    }
  }

  Future<void> _handleSendPressed() async {
    if (_attachmentBusy) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final outboundText = _replyDraft == null
        ? text
        : buildTurnaReplyEncodedText(reply: _replyDraft!, text: text);
    _client.send(outboundText);
    TurnaAnalytics.logEvent('message_sent', {
      'chat_id': widget.chat.chatId,
      'kind': 'text',
    });
    _controller.clear();
    if (mounted) {
      setState(() => _replyDraft = null);
    }
    _jumpToBottom();
  }

  String _formatCallTimelineSubtitle(TurnaCallHistoryItem item) {
    final duration = item.durationSeconds;
    if (duration != null && duration > 0) {
      final hours = duration ~/ 3600;
      final minutes = (duration % 3600) ~/ 60;
      final seconds = duration % 60;
      if (hours > 0) {
        return minutes > 0 ? '$hours sa $minutes dk' : '$hours sa';
      }
      if (minutes > 0) return '$minutes dk';
      return '$seconds sn';
    }

    switch (item.status) {
      case TurnaCallStatus.declined:
        return 'Reddedildi';
      case TurnaCallStatus.missed:
        return 'Cevapsiz';
      case TurnaCallStatus.cancelled:
        return 'Iptal edildi';
      case TurnaCallStatus.ringing:
        return 'Caliyor';
      case TurnaCallStatus.accepted:
      case TurnaCallStatus.ended:
        return 'Baglandi';
    }
  }

  Widget _buildCallBubble(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    TurnaCallHistoryItem item,
  ) {
    final mine = item.direction == 'outgoing';
    final bubbleColor = mine
        ? TurnaColors.chatOutgoing.withValues(alpha: 0.14)
        : TurnaColors.chatIncoming;
    final iconBackground = mine
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white;
    final iconColor = item.status == TurnaCallStatus.missed
        ? TurnaColors.error
        : mine
        ? TurnaColors.chatOutgoingText
        : TurnaColors.primary;
    final textColor = mine ? TurnaColors.text : TurnaColors.chatIncomingText;
    final title = item.type == TurnaCallType.video
        ? 'Goruntulu arama'
        : 'Sesli arama';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
              TurnaChatTokens.messageMaxWidthFactor,
        ),
        margin: _bubbleMarginFor(displayEntries, index, mine),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(TurnaChatTokens.bubbleRadius),
            topRight: const Radius.circular(TurnaChatTokens.bubbleRadius),
            bottomLeft: Radius.circular(
              mine
                  ? TurnaChatTokens.bubbleRadiusTail
                  : TurnaChatTokens.bubbleRadius,
            ),
            bottomRight: Radius.circular(
              mine
                  ? TurnaChatTokens.bubbleRadius
                  : TurnaChatTokens.bubbleRadiusTail,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                item.type == TurnaCallType.video
                    ? Icons.videocam_rounded
                    : Icons.call_rounded,
                color: iconColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 44),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          _formatCallTimelineSubtitle(item),
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.82),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatMessageTime(
                          item.createdAt ??
                              item.endedAt ??
                              item.acceptedAt ??
                              '',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: textColor.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    ChatMessage msg,
    bool mine,
  ) {
    final parsed = parseTurnaMessageText(msg.text);
    final isDeletedPlaceholder = _isMessageDeletedPlaceholder(
      msg,
      parsed: parsed,
    );
    final displayText = isDeletedPlaceholder ? 'Silindi.' : parsed.text.trim();
    final visibleAttachments = isDeletedPlaceholder
        ? const <ChatAttachment>[]
        : msg.attachments;
    final hasText = displayText.isNotEmpty;
    final hasError =
        !isDeletedPlaceholder &&
        msg.errorText != null &&
        msg.errorText!.trim().isNotEmpty;
    final isHighlighted = _highlightedMessageId == msg.id;
    final footer = _MessageMetaFooter(
      timeLabel: _formatMessageTime(msg.createdAt),
      mine: mine,
      status: msg.status,
      starred: _starredMessageIds.contains(msg.id),
    );
    final bubbleColor = mine
        ? TurnaColors.chatOutgoing
        : TurnaColors.chatIncoming;
    final resolvedBubbleColor = isHighlighted
        ? Color.alphaBlend(
            TurnaColors.accent.withValues(alpha: mine ? 0.18 : 0.12),
            bubbleColor,
          )
        : bubbleColor;
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(TurnaChatTokens.bubbleRadius),
      topRight: const Radius.circular(TurnaChatTokens.bubbleRadius),
      bottomLeft: Radius.circular(
        mine ? TurnaChatTokens.bubbleRadiusTail : TurnaChatTokens.bubbleRadius,
      ),
      bottomRight: Radius.circular(
        mine ? TurnaChatTokens.bubbleRadius : TurnaChatTokens.bubbleRadiusTail,
      ),
    );
    final bubbleBorder = msg.status == ChatMessageStatus.failed
        ? Border.all(color: Colors.red.shade200)
        : isHighlighted
        ? Border.all(
            color: TurnaColors.accentStrong.withValues(alpha: 0.72),
            width: 1.2,
          )
        : null;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _handleMessageLongPress(msg),
        onTap: isDeletedPlaceholder
            ? () => _confirmRemoveDeletedPlaceholder(msg)
            : mine &&
                  (msg.status == ChatMessageStatus.failed ||
                      msg.status == ChatMessageStatus.queued)
            ? () => _client.retryMessage(msg)
            : null,
        child: AnimatedContainer(
          key: _messageKeyFor(msg.id),
          duration: const Duration(milliseconds: 180),
          constraints: BoxConstraints(
            maxWidth:
                MediaQuery.of(context).size.width *
                TurnaChatTokens.messageMaxWidthFactor,
          ),
          margin: _bubbleMarginFor(displayEntries, index, mine),
          padding: EdgeInsets.fromLTRB(
            12,
            9,
            12,
            msg.attachments.isEmpty && !hasError ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: resolvedBubbleColor,
            borderRadius: bubbleRadius,
            border: bubbleBorder,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: mine ? 0.04 : 0.08),
                blurRadius: mine ? 4 : 10,
                offset: const Offset(0, 1),
              ),
              if (isHighlighted)
                BoxShadow(
                  color: TurnaColors.accent.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 0),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    msg.errorText!,
                    style: TextStyle(
                      fontSize: 11,
                      color: msg.status == ChatMessageStatus.failed
                          ? TurnaColors.error
                          : TurnaColors.textMuted,
                    ),
                  ),
                ),
              if (parsed.reply != null && !isDeletedPlaceholder) ...[
                _ReplySnippetCard(
                  reply: parsed.reply!,
                  mine: mine,
                  onTap: () => _scrollToReplyTarget(parsed.reply!.messageId),
                ),
                if (hasText || msg.attachments.isNotEmpty)
                  const SizedBox(height: 8),
              ],
              if (visibleAttachments.isNotEmpty) ...[
                _ChatAttachmentList(
                  attachments: visibleAttachments,
                  onTap: _openAttachment,
                  formatFileSize: _formatFileSize,
                ),
                if (hasText) const SizedBox(height: 8),
              ],
              if (hasText)
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        right: mine ? 64 : 54,
                        bottom: 4,
                      ),
                      child: Text(
                        displayText,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.28,
                          color: mine
                              ? TurnaColors.chatOutgoingText
                              : TurnaColors.chatIncomingText,
                        ),
                      ),
                    ),
                    footer,
                  ],
                )
              else if (visibleAttachments.isNotEmpty || hasError)
                Align(alignment: Alignment.bottomRight, child: footer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final focused = _composerFocusNode.hasFocus;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyDraft != null)
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 54, bottom: 8),
                child: _ComposerReplyBanner(
                  reply: _replyDraft!,
                  onClose: () => setState(() => _replyDraft = null),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _attachmentBusy ? null : _showAttachmentSheet,
                  icon: _attachmentBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add, size: 28),
                  color: TurnaColors.textSoft,
                ),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: TurnaColors.backgroundSoft,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: focused
                            ? TurnaColors.primary
                            : TurnaColors.border,
                        width: focused ? 1.4 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: TurnaColors.primary.withValues(
                            alpha: focused ? 0.08 : 0.03,
                          ),
                          blurRadius: focused ? 16 : 8,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _composerFocusNode,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Mesaj',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        if (!_hasComposerText)
                          IconButton(
                            onPressed: _attachmentBusy
                                ? null
                                : _pickCameraImage,
                            icon: const Icon(Icons.camera_alt_outlined),
                            color: TurnaColors.textSoft,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _hasComposerText
                      ? Container(
                          key: const ValueKey('send'),
                          width: 46,
                          height: 46,
                          decoration: const BoxDecoration(
                            color: TurnaColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: _attachmentBusy
                                ? null
                                : _handleSendPressed,
                            icon: const Icon(Icons.send_rounded),
                            color: TurnaColors.surface,
                          ),
                        )
                      : Container(
                          key: const ValueKey('mic'),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _attachmentBusy
                                ? null
                                : _showVoiceMessagePlaceholder,
                            icon: const Icon(Icons.mic_none_rounded),
                            color: TurnaColors.textSoft,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPickedAttachment({
    required ChatAttachmentKind kind,
    required String fileName,
    required String contentType,
    required Future<List<int>> Function() readBytes,
    int? sizeBytes,
  }) async {
    setState(() => _attachmentBusy = true);

    try {
      final upload = await ChatApi.createAttachmentUpload(
        widget.session,
        chatId: widget.chat.chatId,
        kind: kind,
        contentType: contentType,
        fileName: fileName,
      );

      final bytes = await readBytes();
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Dosya yuklenemedi.');
      }

      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: widget.chat.chatId,
        text: _controller.text.trim().isEmpty
            ? null
            : (_replyDraft == null
                  ? _controller.text.trim()
                  : buildTurnaReplyEncodedText(
                      reply: _replyDraft!,
                      text: _controller.text.trim(),
                    )),
        attachments: [
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: kind,
            fileName: fileName,
            contentType: contentType,
            sizeBytes: sizeBytes ?? bytes.length,
          ),
        ],
      );

      if (!mounted) return;
      _client.mergeServerMessage(message);
      _controller.clear();
      setState(() => _replyDraft = null);
      _jumpToBottom();
      await TurnaAnalytics.logEvent('attachment_sent', {
        'chat_id': widget.chat.chatId,
        'kind': kind.name,
      });
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
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Future<void> _openMediaComposerFromFiles(List<XFile> files) async {
    final seeds = <MediaComposerSeed>[];

    for (final file in files.take(kComposerMediaLimit)) {
      final contentType = _guessContentType(file.name);
      if (contentType == null) continue;

      late final ChatAttachmentKind kind;
      if (contentType.startsWith('image/')) {
        kind = ChatAttachmentKind.image;
      } else if (contentType.startsWith('video/')) {
        kind = ChatAttachmentKind.video;
      } else {
        continue;
      }

      final sizeBytes = await file.length();
      if (sizeBytes > kInlineAttachmentSoftLimitBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${file.name} 64 MB ustu oldugu icin inline medya olarak gonderilemiyor.',
            ),
          ),
        );
        continue;
      }

      seeds.add(
        MediaComposerSeed(
          kind: kind,
          file: file,
          fileName: file.name,
          contentType: contentType,
          sizeBytes: sizeBytes,
        ),
      );
    }

    if (seeds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gonderilebilir medya bulunamadi.')),
      );
      return;
    }

    if (!mounted) return;
    final message = await Navigator.push<ChatMessage>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaComposerPage(
          session: widget.session,
          chat: widget.chat,
          items: seeds,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );

    if (!mounted || message == null) return;
    _client.mergeServerMessage(message);
    _jumpToBottom();
  }

  Future<void> _pickGalleryMedia() async {
    final files = await _mediaPicker.pickMultipleMedia(
      limit: kComposerMediaLimit,
      imageQuality: kInlineImagePickerQuality,
      maxWidth: kInlineImagePickerMaxDimension,
      maxHeight: kInlineImagePickerMaxDimension,
    );
    if (files.isEmpty) return;
    await _openMediaComposerFromFiles(files);
  }

  Future<void> _pickCameraImage() async {
    final file = await _mediaPicker.pickImage(
      source: ImageSource.camera,
      imageQuality: kInlineImagePickerQuality,
      maxWidth: kInlineImagePickerMaxDimension,
      maxHeight: kInlineImagePickerMaxDimension,
    );
    if (file == null) return;
    await _openMediaComposerFromFiles([file]);
  }

  Future<void> _pickCameraVideo() async {
    final file = await _mediaPicker.pickVideo(source: ImageSource.camera);
    if (file == null) return;
    await _openMediaComposerFromFiles([file]);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final filePath = file.path;
    if (filePath == null || filePath.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Secilen dosya okunamadi.')));
      return;
    }

    final fileName = file.name.trim().isEmpty
        ? filePath.split('/').last
        : file.name.trim();
    await _sendPickedAttachment(
      kind: ChatAttachmentKind.file,
      fileName: fileName,
      contentType:
          guessContentTypeForFileName(fileName) ?? 'application/octet-stream',
      readBytes: () => File(filePath).readAsBytes(),
      sizeBytes: file.size,
    );
  }

  Future<void> _showAttachmentSheet() async {
    if (_attachmentBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            decoration: BoxDecoration(
              color: TurnaColors.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paylas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: TurnaColors.text,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    _AttachmentQuickAction(
                      icon: Icons.photo_camera_outlined,
                      label: 'Kamera',
                      backgroundColor: TurnaColors.primary,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickCameraImage();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.photo_library_outlined,
                      label: 'Galeri',
                      backgroundColor: TurnaColors.accent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickGalleryMedia();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      backgroundColor: TurnaColors.primaryStrong,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickCameraVideo();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.insert_drive_file_outlined,
                      label: 'Belge',
                      backgroundColor: TurnaColors.primaryDeep,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickFile();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.location_on_outlined,
                      label: 'Konum',
                      backgroundColor: TurnaColors.primary400,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showAttachmentPlaceholder('Konum');
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.perm_contact_calendar_outlined,
                      label: 'Kisi',
                      backgroundColor: TurnaColors.accentStrong,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showAttachmentPlaceholder('Kisi');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAttachment(ChatAttachment attachment) async {
    final url = attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya linki hazir degil.')));
      return;
    }

    if (attachment.kind == ChatAttachmentKind.image) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatAttachmentViewerPage(
            imageUrl: url,
            title: attachment.fileName ?? 'Gorsel',
          ),
        ),
      );
      return;
    }

    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya acilamadi.')));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    turnaLog('chat room dispose', {'chatId': widget.chat.chatId});
    if (_route != null) {
      kTurnaRouteObserver.unsubscribe(this);
    }
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
    _client.removeListener(_refresh);
    _client.dispose();
    widget.callCoordinator.removeListener(_handleCallCoordinatorChanged);
    _controller.removeListener(_handleComposerChanged);
    _controller.dispose();
    _composerFocusNode.removeListener(_refresh);
    _composerFocusNode.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _messageHighlightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _client.refreshConnection();
      unawaited(_loadPeerCallHistory());
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _client.disconnectForBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final timelineEntries = _buildTimelineEntries();
    final peerStatusText = _buildPeerStatusText();

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        title: GestureDetector(
          onTap: _peerUserId == null ? null : _openPeerProfile,
          child: Row(
            children: [
              _ProfileAvatar(
                label: widget.chat.name,
                avatarUrl: widget.chat.avatarUrl,
                authToken: widget.session.token,
                radius: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.chat.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (peerStatusText != null)
                      Text(
                        peerStatusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _client.peerTyping
                              ? TurnaColors.primary
                              : TurnaColors.textMuted,
                          fontWeight: _client.peerTyping
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Goruntulu ara',
            onPressed: _peerUserId == null
                ? null
                : () => _startCall(TurnaCallType.video),
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            tooltip: 'Sesli ara',
            onPressed: _peerUserId == null
                ? null
                : () => _startCall(TurnaCallType.audio),
            icon: const Icon(Icons.call_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_client.error != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF1E6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _client.error!,
                style: const TextStyle(color: Color(0xFF7A4B00)),
              ),
            ),
          if (!_client.isConnected)
            Container(
              width: double.infinity,
              color: const Color(0xFFEAF2FF),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Canli baglanti yok. Yazdiklarin siraya alinip tekrar denenecek.',
                style: TextStyle(color: Color(0xFF234B8F)),
              ),
            ),
          if (_attachmentBusy)
            Container(
              width: double.infinity,
              color: TurnaColors.primary50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Medya yukleniyor. Mesaj hazirlaniyor...',
                style: TextStyle(color: TurnaColors.primaryStrong),
              ),
            ),
          if (_pinnedMessage != null)
            _PinnedMessageBar(
              pinned: _pinnedMessage!,
              onClear: () async {
                setState(() => _pinnedMessage = null);
                await _persistPinnedMessage(null);
              },
            ),
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: _ChatWallpaper()),
                if (_client.loadingInitial && timelineEntries.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (timelineEntries.isEmpty)
                  const _CenteredState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Henuz mesaj yok',
                    message: 'Ilk mesaji gondererek sohbeti baslat.',
                  )
                else
                  ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 18),
                    itemCount: timelineEntries.length + 1,
                    itemBuilder: (context, index) {
                      if (index == timelineEntries.length) {
                        if (_client.loadingMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (_client.hasMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                'Eski mesajlar yukleniyor...',
                                style: TextStyle(color: Color(0xFF777C79)),
                              ),
                            ),
                          );
                        }
                        return const SizedBox(height: 24);
                      }

                      final entry = timelineEntries[index];
                      final msg = entry.message;
                      final call = entry.call;
                      return Column(
                        children: [
                          if (_shouldShowDayChip(timelineEntries, index))
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: TurnaChatTokens.dateGap / 2,
                              ),
                              child: _DateSeparatorChip(
                                label: _formatDayLabel(
                                  _timelineCreatedAt(entry),
                                ),
                              ),
                            ),
                          if (msg != null)
                            _buildMessageBubble(
                              timelineEntries,
                              index,
                              msg,
                              msg.senderId == widget.session.userId,
                            )
                          else if (call != null)
                            _buildCallBubble(timelineEntries, index, call),
                        ],
                      );
                    },
                  ),
                if (_client.peerTyping)
                  const Positioned(
                    left: 14,
                    bottom: 12,
                    child: _TypingIndicatorPill(),
                  ),
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.white,
                      foregroundColor: TurnaColors.primary,
                      onPressed: _jumpToBottom,
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
              ],
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }
}

class _MessageMetaFooter extends StatelessWidget {
  const _MessageMetaFooter({
    required this.timeLabel,
    required this.mine,
    required this.status,
    this.starred = false,
  });

  final String timeLabel;
  final bool mine;
  final ChatMessageStatus status;
  final bool starred;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (starred) ...[
          Icon(
            Icons.star_rounded,
            size: 13,
            color: mine
                ? Colors.white.withValues(alpha: 0.86)
                : TurnaColors.warning,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          timeLabel,
          style: TextStyle(
            fontSize: 11,
            color: mine
                ? Colors.white.withValues(alpha: 0.8)
                : TurnaColors.textMuted,
          ),
        ),
        if (mine) ...[
          const SizedBox(width: 6),
          _StatusTick(status: status, mine: mine),
        ],
      ],
    );
  }
}

class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status, this.mine = false});

  final ChatMessageStatus status;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.done;
    Color color = mine
        ? Colors.white.withValues(alpha: 0.82)
        : TurnaColors.textMuted;

    if (status == ChatMessageStatus.sending) {
      icon = Icons.schedule;
    } else if (status == ChatMessageStatus.queued) {
      icon = Icons.cloud_off_outlined;
    } else if (status == ChatMessageStatus.failed) {
      icon = Icons.error_outline;
      color = TurnaColors.error;
    } else if (status == ChatMessageStatus.delivered) {
      icon = Icons.done_all;
    } else if (status == ChatMessageStatus.read) {
      icon = Icons.done_all;
      color = mine ? TurnaColors.accent : TurnaColors.info;
    }

    return Icon(icon, size: 16, color: color);
  }
}

class _DateSeparatorChip extends StatelessWidget {
  const _DateSeparatorChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TurnaColors.surfaceHover,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TurnaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: TurnaColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicatorPill extends StatefulWidget {
  const _TypingIndicatorPill();

  @override
  State<_TypingIndicatorPill> createState() => _TypingIndicatorPillState();
}

class _TypingIndicatorPillState extends State<_TypingIndicatorPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacityForDot(int index) {
    final progress = (_controller.value + (index * 0.16)) % 1.0;
    if (progress < 0.5) {
      return 0.32 + (progress / 0.5) * 0.68;
    }
    return 1 - ((progress - 0.5) / 0.5) * 0.68;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: TurnaColors.chatIncoming,
        borderRadius: BorderRadius.circular(TurnaChatTokens.bubbleRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              return Container(
                width: 7,
                height: 7,
                margin: EdgeInsets.only(right: index == 2 ? 0 : 4),
                decoration: BoxDecoration(
                  color: TurnaColors.textMuted.withValues(
                    alpha: _opacityForDot(index),
                  ),
                  shape: BoxShape.circle,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _ChatWallpaper extends StatelessWidget {
  const _ChatWallpaper();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ChatWallpaperPainter());
  }
}

class _ChatWallpaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = TurnaColors.border.withValues(alpha: 0.45);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = TurnaColors.primary50.withValues(alpha: 0.22);

    const stepX = 72.0;
    const stepY = 78.0;
    for (double y = -10; y < size.height + stepY; y += stepY) {
      final row = (y / stepY).round();
      for (double x = 0; x < size.width + stepX; x += stepX) {
        final offsetX = row.isEven ? 10.0 : 36.0;
        final origin = Offset(x + offsetX, y + 16);

        canvas.drawCircle(origin, 6, stroke);
        canvas.drawCircle(origin, 3, fill);

        final rounded = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: origin + const Offset(22, 18),
            width: 18,
            height: 13,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(rounded, stroke);

        final path = Path()
          ..moveTo(origin.dx - 4, origin.dy + 26)
          ..quadraticBezierTo(
            origin.dx + 2,
            origin.dy + 18,
            origin.dx + 8,
            origin.dy + 26,
          )
          ..quadraticBezierTo(
            origin.dx + 14,
            origin.dy + 34,
            origin.dx + 20,
            origin.dy + 26,
          );
        canvas.drawPath(path, stroke);

        canvas.drawArc(
          Rect.fromCircle(center: origin + const Offset(44, 42), radius: 7),
          -math.pi / 6,
          math.pi * 1.2,
          false,
          stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AttachmentQuickAction extends StatelessWidget {
  const _AttachmentQuickAction({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: Colors.white, size: 25),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: TurnaColors.textSoft,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageQuickAction extends StatelessWidget {
  const _MessageQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? TurnaColors.text : TurnaColors.textMuted;
    return SizedBox(
      width: 82,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: TurnaColors.backgroundMuted,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: iconColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplySnippetCard extends StatelessWidget {
  const _ReplySnippetCard({
    required this.reply,
    required this.mine,
    this.onTap,
  });

  final TurnaReplyPayload reply;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = mine
        ? Colors.white.withValues(alpha: 0.85)
        : TurnaColors.primary;
    final background = mine
        ? Colors.white.withValues(alpha: 0.14)
        : TurnaColors.primary50;
    final textColor = mine
        ? Colors.white.withValues(alpha: 0.95)
        : TurnaColors.text;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reply.senderLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reply.previewText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.92),
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerReplyBanner extends StatelessWidget {
  const _ComposerReplyBanner({required this.reply, required this.onClose});

  final TurnaReplyPayload reply;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: TurnaColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TurnaColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: TurnaColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yanitlaniyor: ${reply.senderLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: TurnaColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _PinnedMessageBar extends StatelessWidget {
  const _PinnedMessageBar({required this.pinned, required this.onClear});

  final _PinnedMessageDraft pinned;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: const BoxDecoration(
        color: TurnaColors.surface,
        border: Border(bottom: BorderSide(color: TurnaColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.push_pin_rounded,
            size: 17,
            color: TurnaColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sabitlenen mesaj',
                  style: TextStyle(
                    color: TurnaColors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${pinned.senderLabel}: ${pinned.previewText}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.textSoft,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: TurnaColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _VoiceMessageBubbleSkeleton extends StatelessWidget {
  const _VoiceMessageBubbleSkeleton({
    required this.attachment,
    required this.onTap,
  });

  final ChatAttachment attachment;
  final VoidCallback onTap;

  String _formatDuration() {
    final duration = attachment.durationSeconds;
    if (duration == null || duration <= 0) return '--:--';
    final minutes = (duration ~/ 60).toString().padLeft(2, '0');
    final seconds = (duration % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    const bars = [10, 16, 12, 20, 13, 17, 9, 19, 11, 15, 18, 12];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 236,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: TurnaColors.primary50,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: TurnaColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: bars
                          .map(
                            (height) => Container(
                              width: 3,
                              height: height.toDouble(),
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: TurnaColors.primary.withValues(
                                  alpha: 0.78,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDuration(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: TurnaColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForwardMessagePickerPage extends StatefulWidget {
  const ForwardMessagePickerPage({
    super.key,
    required this.session,
    required this.currentChatId,
  });

  final AuthSession session;
  final String currentChatId;

  @override
  State<ForwardMessagePickerPage> createState() =>
      _ForwardMessagePickerPageState();
}

class _ForwardMessagePickerPageState extends State<ForwardMessagePickerPage> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<ChatPreview>> _chatsFuture;

  @override
  void initState() {
    super.initState();
    _chatsFuture = ChatApi.fetchChats(widget.session);
    _searchController.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Ilet')),
      body: FutureBuilder<List<ChatPreview>>(
        future: _chatsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CenteredState(
              icon: Icons.forward_to_inbox_outlined,
              title: 'Sohbetler yuklenemedi',
              message: snapshot.error.toString(),
            );
          }

          final chats = (snapshot.data ?? const <ChatPreview>[])
              .where((chat) => chat.chatId != widget.currentChatId)
              .where((chat) {
                if (query.isEmpty) return true;
                return chat.name.toLowerCase().contains(query) ||
                    chat.message.toLowerCase().contains(query);
              })
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Sohbet ara',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: TurnaColors.backgroundMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: chats.isEmpty
                    ? const _CenteredState(
                        icon: Icons.chat_bubble_outline,
                        title: 'Sohbet bulunamadi',
                        message: 'Iletilecek baska sohbet bulunmuyor.',
                      )
                    : ListView.builder(
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          return ListTile(
                            leading: _ProfileAvatar(
                              label: chat.name,
                              avatarUrl: chat.avatarUrl,
                              authToken: widget.session.token,
                              radius: 22,
                            ),
                            title: Text(
                              chat.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: chat.message.trim().isEmpty
                                ? null
                                : Text(
                                    chat.message,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => Navigator.pop(context, chat),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChatAttachmentList extends StatelessWidget {
  const _ChatAttachmentList({
    required this.attachments,
    required this.onTap,
    required this.formatFileSize,
  });

  final List<ChatAttachment> attachments;
  final Future<void> Function(ChatAttachment attachment) onTap;
  final String Function(int bytes) formatFileSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: attachments.map((attachment) {
        if (_isAudioAttachment(attachment)) {
          return _VoiceMessageBubbleSkeleton(
            attachment: attachment,
            onTap: () => onTap(attachment),
          );
        }
        if (attachment.kind == ChatAttachmentKind.image) {
          final imageUrl = attachment.url?.trim() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onTap(attachment),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 220,
                  height: 220,
                  color: TurnaColors.backgroundMuted,
                  child: imageUrl.isEmpty
                      ? const Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              ),
            ),
          );
        }

        final isVideo = attachment.kind == ChatAttachmentKind.video;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onTap(attachment),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TurnaColors.backgroundMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: TurnaColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.play_circle_outline
                          : Icons.insert_drive_file_outlined,
                      color: TurnaColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName ?? (isVideo ? 'Video' : 'Dosya'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${isVideo ? 'Video' : 'Dosya'} • ${formatFileSize(attachment.sizeBytes)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TurnaColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class ChatAttachmentViewerPage extends StatelessWidget {
  const ChatAttachmentViewerPage({
    super.key,
    required this.imageUrl,
    required this.title,
  });

  final String imageUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Gorsel yuklenemedi.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum MediaComposerQuality { sd, hd }

extension MediaComposerQualityX on MediaComposerQuality {
  String get label => name.toUpperCase();

  double get imageMaxDimension {
    switch (this) {
      case MediaComposerQuality.sd:
        return kInlineImageSdMaxDimension;
      case MediaComposerQuality.hd:
        return kInlineImageHdMaxDimension;
    }
  }

  int get jpegQuality {
    switch (this) {
      case MediaComposerQuality.sd:
        return 74;
      case MediaComposerQuality.hd:
        return 86;
    }
  }
}

class MediaComposerSeed {
  MediaComposerSeed({
    required this.kind,
    required this.file,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
  });

  final ChatAttachmentKind kind;
  final XFile file;
  final String fileName;
  final String contentType;
  final int sizeBytes;
}

class _MediaCropPreset {
  const _MediaCropPreset({
    required this.id,
    required this.label,
    this.aspectRatio,
    this.useOriginalAspect = false,
    this.fullImage = false,
    this.freeform = false,
  });

  final String id;
  final String label;
  final double? aspectRatio;
  final bool useOriginalAspect;
  final bool fullImage;
  final bool freeform;
}

enum _MediaComposerCropHandle { topLeft, topRight, bottomLeft, bottomRight }

class MediaComposerPage extends StatefulWidget {
  const MediaComposerPage({
    super.key,
    required this.session,
    required this.chat,
    required this.items,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final ChatPreview chat;
  final List<MediaComposerSeed> items;
  final VoidCallback onSessionExpired;

  @override
  State<MediaComposerPage> createState() => _MediaComposerPageState();
}

class _MediaComposerPageState extends State<MediaComposerPage> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _inlineTextController = TextEditingController();
  final FocusNode _inlineTextFocusNode = FocusNode();
  late final PageController _pageController;
  late final List<_MediaComposerItem> _items;
  int _selectedIndex = 0;
  bool _cropMode = false;
  bool _drawMode = false;
  bool _sending = false;
  String? _sendingLabel;
  String? _activeTextOverlayId;
  MediaComposerQuality _quality = MediaComposerQuality.sd;
  double _overlayInteractionBaseScale = 1;
  double _brushSizeFactor = 0.011;
  bool _eraserMode = false;

  _MediaComposerItem get _currentItem => _items[_selectedIndex];

  _MediaComposerTextOverlay? get _activeTextOverlay {
    final overlayId = _activeTextOverlayId;
    if (overlayId == null) return null;
    for (final overlay in _currentItem.textOverlays) {
      if (overlay.id == overlayId) return overlay;
    }
    return null;
  }

  Rect get _currentWorkingCropRect =>
      _currentItem.draftCropRectNormalized ??
      _currentItem.cropRectNormalized ??
      _defaultCropRectFor(_currentItem);

  String get _currentWorkingCropPresetId =>
      _currentItem.draftCropPresetId ?? _currentItem.cropPresetId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _items = widget.items.map(_MediaComposerItem.fromSeed).toList();
    for (final item in _items.where((item) => item.isImage)) {
      unawaited(_primeImageSize(item));
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _inlineTextController.dispose();
    _inlineTextFocusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _primeImageSize(_MediaComposerItem item) async {
    if (!item.isImage || item.sourceSize != null) return;
    final bytes = await item.file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    if (!mounted) return;
    setState(() => item.sourceSize = size);
  }

  Future<void> _showComingSoon(String text) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Rect _displayCropRectFor(_MediaComposerItem item) {
    if (identical(item, _currentItem) && _cropMode) {
      return kComposerFullCropRectNormalized;
    }
    return item.cropRectNormalized ?? kComposerFullCropRectNormalized;
  }

  double _effectiveAspectRatioFor(_MediaComposerItem item, Rect displayCrop) {
    final base = item.sourceSize ?? const Size(1, 1);
    final rotatedWidth = item.rotationTurns.isOdd ? base.height : base.width;
    final rotatedHeight = item.rotationTurns.isOdd ? base.width : base.height;
    return math.max(
      0.1,
      (rotatedWidth * displayCrop.width) /
          math.max(0.1, rotatedHeight * displayCrop.height),
    );
  }

  Size _rotatedSourceSize(_MediaComposerItem item) {
    final base = item.sourceSize ?? const Size(1, 1);
    return item.rotationTurns.isOdd
        ? Size(base.height, base.width)
        : Size(base.width, base.height);
  }

  _MediaCropPreset _cropPresetForId(String id) {
    return _kComposerCropPresets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => _kComposerCropPresets.first,
    );
  }

  double _resolvedCropAspectRatio(
    _MediaComposerItem item,
    _MediaCropPreset preset,
  ) {
    if (preset.useOriginalAspect) {
      final size = _rotatedSourceSize(item);
      return size.width / math.max(0.1, size.height);
    }
    return preset.aspectRatio ?? 1;
  }

  Rect _cropRectForPreset(
    _MediaComposerItem item,
    _MediaCropPreset preset, {
    Offset? center,
  }) {
    if (preset.fullImage) return kComposerFullCropRectNormalized;
    if (preset.freeform) {
      final existing = item.cropRectNormalized;
      if (existing != null &&
          existing != kComposerFullCropRectNormalized &&
          existing.width < 1 &&
          existing.height < 1) {
        return _clampCropRect(existing);
      }
      return Rect.fromLTWH(
        kComposerCropInitialInset,
        kComposerCropInitialInset,
        1 - (kComposerCropInitialInset * 2),
        1 - (kComposerCropInitialInset * 2),
      );
    }

    final imageSize = _rotatedSourceSize(item);
    final imageAspect = imageSize.width / math.max(0.1, imageSize.height);
    final targetAspect = _resolvedCropAspectRatio(item, preset);
    final normalizedAspect = targetAspect / math.max(0.1, imageAspect);
    final available = 1 - (kComposerCropInitialInset * 2);

    var width = available;
    var height = width / math.max(0.1, normalizedAspect);
    if (height > available) {
      height = available;
      width = height * normalizedAspect;
    }

    width = width.clamp(kComposerCropMinSide, 1.0).toDouble();
    height = height.clamp(kComposerCropMinSide, 1.0).toDouble();

    final anchor =
        center ?? item.cropRectNormalized?.center ?? const Offset(0.5, 0.5);
    return _clampCropRect(
      Rect.fromCenter(center: anchor, width: width, height: height),
    );
  }

  double? _lockedNormalizedCropAspectRatio(_MediaComposerItem item) {
    final preset = identical(item, _currentItem) && _cropMode
        ? _cropPresetForId(_currentWorkingCropPresetId)
        : _cropPresetForId(item.cropPresetId);
    if (preset.freeform || preset.fullImage) return null;
    final imageSize = _rotatedSourceSize(item);
    final imageAspect = imageSize.width / math.max(0.1, imageSize.height);
    final targetAspect = _resolvedCropAspectRatio(item, preset);
    return targetAspect / math.max(0.1, imageAspect);
  }

  Rect _normalizedCropToRect(Rect normalizedCrop, Size size) {
    return Rect.fromLTWH(
      normalizedCrop.left * size.width,
      normalizedCrop.top * size.height,
      normalizedCrop.width * size.width,
      normalizedCrop.height * size.height,
    );
  }

  Rect _clampCropRect(Rect rect) {
    final minSide = kComposerCropMinSide;
    var left = rect.left;
    var top = rect.top;
    var right = rect.right;
    var bottom = rect.bottom;

    if ((right - left) < minSide) {
      right = left + minSide;
    }
    if ((bottom - top) < minSide) {
      bottom = top + minSide;
    }

    if (left < 0) {
      right -= left;
      left = 0;
    }
    if (top < 0) {
      bottom -= top;
      top = 0;
    }
    if (right > 1) {
      left -= right - 1;
      right = 1;
    }
    if (bottom > 1) {
      top -= bottom - 1;
      bottom = 1;
    }

    left = left.clamp(0.0, 1.0 - minSide).toDouble();
    top = top.clamp(0.0, 1.0 - minSide).toDouble();
    right = right.clamp(left + minSide, 1.0).toDouble();
    bottom = bottom.clamp(top + minSide, 1.0).toDouble();

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _defaultCropRectFor(_MediaComposerItem item) {
    return _cropRectForPreset(item, _cropPresetForId(item.cropPresetId));
  }

  void _beginCropEditing() {
    _currentItem.draftCropPresetId = _currentItem.cropPresetId;
    _currentItem.draftCropRectNormalized =
        _currentItem.cropRectNormalized ?? _defaultCropRectFor(_currentItem);
    _cropMode = true;
  }

  void _cancelCropEditing() {
    setState(() {
      _currentItem.draftCropRectNormalized = null;
      _currentItem.draftCropPresetId = null;
      _cropMode = false;
    });
  }

  void _applyCropEditing() {
    setState(() {
      _currentItem.cropPresetId = _currentWorkingCropPresetId;
      _currentItem.cropRectNormalized = _currentWorkingCropRect;
      _currentItem.draftCropRectNormalized = null;
      _currentItem.draftCropPresetId = null;
      _cropMode = false;
    });
  }

  void _applyCropPreset(_MediaCropPreset preset) {
    if (!_currentItem.isImage) return;
    final currentCenter = _currentWorkingCropRect.center;
    setState(() {
      _currentItem.draftCropPresetId = preset.id;
      _currentItem.draftCropRectNormalized = _cropRectForPreset(
        _currentItem,
        preset,
        center: currentCenter,
      );
    });
  }

  void _toggleQuality() {
    setState(() {
      _quality = _quality == MediaComposerQuality.sd
          ? MediaComposerQuality.hd
          : MediaComposerQuality.sd;
    });
  }

  Future<void> _toggleCropMode() async {
    if (_currentItem.kind == ChatAttachmentKind.video) {
      await _showComingSoon(
        'Kirpma su an sadece fotograflarda acik. Video kirpmaya sonra gececegiz.',
      );
      return;
    }

    _finishTextEditing();
    if (_cropMode) {
      _applyCropEditing();
      return;
    }

    setState(() {
      _drawMode = false;
      _eraserMode = false;
      if (_currentItem.cropRectNormalized == null) {
        _currentItem.cropPresetId = 'free';
      }
      _beginCropEditing();
    });
  }

  String _nextTextOverlayId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_currentItem.textOverlays.length + 1}';
  }

  void _requestInlineTextFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inlineTextFocusNode.requestFocus();
    });
  }

  void _finishTextEditing() {
    final overlayId = _activeTextOverlayId;
    if (overlayId == null) return;

    final overlay = _activeTextOverlay;
    if (overlay == null) {
      if (mounted) {
        setState(() => _activeTextOverlayId = null);
      }
      _inlineTextController.clear();
      _inlineTextFocusNode.unfocus();
      return;
    }

    final nextText = _inlineTextController.text.trim();
    setState(() {
      if (nextText.isEmpty) {
        _currentItem.textOverlays.removeWhere((item) => item.id == overlayId);
      } else {
        overlay.text = nextText;
      }
      _activeTextOverlayId = null;
    });
    _inlineTextController.clear();
    _inlineTextFocusNode.unfocus();
  }

  void _beginNewTextOverlay({
    required String initialText,
    required bool requestKeyboard,
    bool activateOverlay = true,
  }) {
    if (!_currentItem.isImage) return;
    _finishTextEditing();

    final overlay = _MediaComposerTextOverlay(
      id: _nextTextOverlayId(),
      text: initialText,
      position: kComposerOverlayDefaultPosition,
      scale: 1,
      colorValue: _currentItem.markupColorValue,
    );

    setState(() {
      _cropMode = false;
      _drawMode = false;
      _currentItem.textOverlays.add(overlay);
      _activeTextOverlayId = activateOverlay ? overlay.id : null;
      _inlineTextController.value = activateOverlay
          ? TextEditingValue(
              text: initialText,
              selection: TextSelection.collapsed(offset: initialText.length),
            )
          : const TextEditingValue();
    });

    if (requestKeyboard && activateOverlay) {
      _requestInlineTextFocus();
    } else {
      _inlineTextFocusNode.unfocus();
    }
  }

  void _beginEditingTextOverlay(
    _MediaComposerTextOverlay overlay, {
    required bool requestKeyboard,
  }) {
    if (!_currentItem.isImage) return;
    setState(() {
      _cropMode = false;
      _drawMode = false;
      _activeTextOverlayId = overlay.id;
      _inlineTextController.value = TextEditingValue(
        text: overlay.text,
        selection: TextSelection.collapsed(offset: overlay.text.length),
      );
    });

    if (requestKeyboard) {
      _requestInlineTextFocus();
    } else {
      _inlineTextFocusNode.unfocus();
    }
  }

  Future<void> _editOverlayText({required bool emojiMode}) async {
    if (!_currentItem.isImage) {
      await _showComingSoon('Bu duzenleme su an sadece fotograflarda acik.');
      return;
    }

    if (emojiMode) {
      final selectedEmoji = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF171A19),
        builder: (sheetContext) {
          const emojis = [
            '🙂',
            '😍',
            '🔥',
            '❤️',
            '👏',
            '🎉',
            '😂',
            '😎',
            '🚀',
            '✨',
            '🤝',
            '🫶',
          ];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final emoji in emojis)
                    InkWell(
                      onTap: () => Navigator.pop(sheetContext, emoji),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF222725),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
      if (selectedEmoji == null || !mounted) return;
      _beginNewTextOverlay(
        initialText: selectedEmoji,
        requestKeyboard: false,
        activateOverlay: false,
      );
      return;
    }

    _beginNewTextOverlay(initialText: '', requestKeyboard: true);
  }

  void _syncActiveTextOverlay(String value) {
    final overlay = _activeTextOverlay;
    if (overlay == null) return;
    setState(() {
      overlay.text = value;
    });
  }

  void _toggleDrawMode() {
    if (!_currentItem.isImage) {
      _showComingSoon('Cizim modu su an sadece fotograflarda acik.');
      return;
    }
    _finishTextEditing();
    setState(() {
      _cropMode = false;
      _drawMode = !_drawMode;
      if (!_drawMode) {
        _eraserMode = false;
      }
    });
  }

  void _setBrushSize(double widthFactor) {
    setState(() {
      _eraserMode = false;
      _brushSizeFactor = widthFactor;
    });
  }

  void _toggleEraser() {
    setState(() {
      _eraserMode = !_eraserMode;
    });
  }

  void _rotateCurrent() {
    if (!_currentItem.isImage) {
      _showComingSoon('Dondurme su an sadece fotograflarda acik.');
      return;
    }
    _finishTextEditing();
    setState(() {
      _currentItem.rotationTurns = (_currentItem.rotationTurns + 1) % 4;
      final preset = _cropPresetForId(_currentWorkingCropPresetId);
      final nextCrop = _cropMode
          ? _cropRectForPreset(
              _currentItem,
              preset,
              center: _currentWorkingCropRect.center,
            )
          : null;
      if (_cropMode) {
        _currentItem.draftCropRectNormalized = nextCrop;
      } else {
        _currentItem.cropRectNormalized = nextCrop;
      }
    });
  }

  void _undoCurrentStroke() {
    if (!_currentItem.isImage || _currentItem.strokes.isEmpty) return;
    setState(() {
      _currentItem.strokes.removeLast();
    });
  }

  Offset _normalizePoint(Offset point, Size size, Rect displayCrop) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx =
        displayCrop.left +
        ((point.dx.clamp(0.0, safeWidth) / safeWidth) * displayCrop.width);
    final dy =
        displayCrop.top +
        ((point.dy.clamp(0.0, safeHeight) / safeHeight) * displayCrop.height);
    return Offset(dx, dy);
  }

  Offset _projectPointToDisplay(Offset point, Rect displayCrop) {
    return Offset(
      ((point.dx - displayCrop.left) / displayCrop.width).toDouble(),
      ((point.dy - displayCrop.top) / displayCrop.height).toDouble(),
    );
  }

  Offset _clampOverlayPosition(Offset position, {Rect? bounds}) {
    final rect = bounds ?? kComposerFullCropRectNormalized;
    final marginX = math.min(0.14, rect.width * 0.14);
    final marginY = math.min(0.12, rect.height * 0.12);
    return Offset(
      position.dx.clamp(rect.left + marginX, rect.right - marginX).toDouble(),
      position.dy.clamp(rect.top + marginY, rect.bottom - marginY).toDouble(),
    );
  }

  void _setMarkupColor(double value) {
    if (!_currentItem.isImage) return;
    final clampedValue = value.clamp(0.0, 1.0).toDouble();
    setState(() {
      _currentItem.markupColorValue = clampedValue;
      final activeOverlay = _activeTextOverlay;
      if (activeOverlay != null) {
        activeOverlay.colorValue = clampedValue;
      }
    });
  }

  void _handleOverlayScaleStart(_MediaComposerTextOverlay overlay) {
    _overlayInteractionBaseScale = overlay.scale;
  }

  void _handleOverlayScaleUpdate(
    _MediaComposerTextOverlay overlay,
    ScaleUpdateDetails details,
    Size size,
    Rect displayCrop,
  ) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final movedPosition = Offset(
      overlay.position.dx +
          ((details.focalPointDelta.dx / safeWidth) * displayCrop.width),
      overlay.position.dy +
          ((details.focalPointDelta.dy / safeHeight) * displayCrop.height),
    );

    setState(() {
      overlay.position = _clampOverlayPosition(
        movedPosition,
        bounds: displayCrop,
      );
      overlay.scale = (_overlayInteractionBaseScale * details.scale)
          .clamp(0.7, 3.2)
          .toDouble();
    });
  }

  void _startStroke(Offset point, Size size, Rect displayCrop) {
    if (!_drawMode || !_currentItem.isImage) return;
    if (_eraserMode) {
      _eraseAtPoint(point, size, displayCrop);
      return;
    }
    setState(() {
      _currentItem.strokes.add(
        _MediaComposerStroke(
          color: _currentItem.markupColor,
          widthFactor: _brushSizeFactor,
          points: [_normalizePoint(point, size, displayCrop)],
        ),
      );
    });
  }

  void _appendStroke(Offset point, Size size, Rect displayCrop) {
    if (!_drawMode || !_currentItem.isImage || _currentItem.strokes.isEmpty) {
      if (_drawMode && _eraserMode && _currentItem.isImage) {
        _eraseAtPoint(point, size, displayCrop);
      }
      return;
    }
    if (_eraserMode) {
      _eraseAtPoint(point, size, displayCrop);
      return;
    }
    setState(() {
      _currentItem.strokes.last.points.add(
        _normalizePoint(point, size, displayCrop),
      );
    });
  }

  void _eraseAtPoint(Offset point, Size size, Rect displayCrop) {
    final target = _normalizePoint(point, size, displayCrop);
    final radius = _brushSizeFactor * 2.2;
    final nextStrokes = <_MediaComposerStroke>[];

    for (final stroke in _currentItem.strokes) {
      final nextSegments = <List<Offset>>[];
      var currentSegment = <Offset>[];
      for (final itemPoint in stroke.points) {
        final shouldErase = (itemPoint - target).distance <= radius;
        if (shouldErase) {
          if (currentSegment.length > 1) {
            nextSegments.add(List<Offset>.from(currentSegment));
          } else if (currentSegment.length == 1) {
            nextSegments.add(List<Offset>.from(currentSegment));
          }
          currentSegment = <Offset>[];
          continue;
        }
        currentSegment.add(itemPoint);
      }

      if (currentSegment.isNotEmpty) {
        nextSegments.add(List<Offset>.from(currentSegment));
      }

      for (final segment in nextSegments) {
        if (segment.isEmpty) continue;
        nextStrokes.add(
          _MediaComposerStroke(
            color: stroke.color,
            widthFactor: stroke.widthFactor,
            points: segment,
          ),
        );
      }
    }

    setState(() {
      _currentItem.strokes
        ..clear()
        ..addAll(nextStrokes);
    });
  }

  void _moveCropRect(DragUpdateDetails details, Size size) {
    final currentCrop = _currentWorkingCropRect;
    if (!_cropMode) return;
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx = details.delta.dx / safeWidth;
    final dy = details.delta.dy / safeHeight;

    setState(() {
      _currentItem.draftCropRectNormalized = _clampCropRect(
        currentCrop.shift(Offset(dx, dy)),
      );
    });
  }

  Rect _buildLockedCropRect({
    required _MediaComposerCropHandle handle,
    required Offset anchor,
    required double width,
    required double aspectRatio,
  }) {
    final height = width / math.max(0.1, aspectRatio);
    switch (handle) {
      case _MediaComposerCropHandle.topLeft:
        return Rect.fromLTRB(
          anchor.dx - width,
          anchor.dy - height,
          anchor.dx,
          anchor.dy,
        );
      case _MediaComposerCropHandle.topRight:
        return Rect.fromLTRB(
          anchor.dx,
          anchor.dy - height,
          anchor.dx + width,
          anchor.dy,
        );
      case _MediaComposerCropHandle.bottomLeft:
        return Rect.fromLTRB(
          anchor.dx - width,
          anchor.dy,
          anchor.dx,
          anchor.dy + height,
        );
      case _MediaComposerCropHandle.bottomRight:
        return Rect.fromLTRB(
          anchor.dx,
          anchor.dy,
          anchor.dx + width,
          anchor.dy + height,
        );
    }
  }

  Rect _clampLockedCropRect({
    required _MediaComposerCropHandle handle,
    required Offset anchor,
    required double desiredWidth,
    required double aspectRatio,
  }) {
    final minHeight = math.max(
      kComposerCropMinSide,
      kComposerCropMinSide / aspectRatio,
    );
    final minWidth = math.max(kComposerCropMinSide, minHeight * aspectRatio);

    late final double maxWidth;
    late final double maxHeight;
    switch (handle) {
      case _MediaComposerCropHandle.topLeft:
        maxWidth = anchor.dx;
        maxHeight = anchor.dy;
        break;
      case _MediaComposerCropHandle.topRight:
        maxWidth = 1 - anchor.dx;
        maxHeight = anchor.dy;
        break;
      case _MediaComposerCropHandle.bottomLeft:
        maxWidth = anchor.dx;
        maxHeight = 1 - anchor.dy;
        break;
      case _MediaComposerCropHandle.bottomRight:
        maxWidth = 1 - anchor.dx;
        maxHeight = 1 - anchor.dy;
        break;
    }

    var width = desiredWidth
        .clamp(minWidth, math.max(minWidth, maxWidth))
        .toDouble();
    var height = width / aspectRatio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspectRatio;
    }
    if (height < minHeight) {
      height = minHeight;
      width = height * aspectRatio;
    }
    width = width.clamp(minWidth, math.max(minWidth, maxWidth)).toDouble();
    height = height.clamp(minHeight, math.max(minHeight, maxHeight)).toDouble();
    return _buildLockedCropRect(
      handle: handle,
      anchor: anchor,
      width: width,
      aspectRatio: aspectRatio,
    );
  }

  void _resizeCropRect(
    _MediaComposerCropHandle handle,
    DragUpdateDetails details,
    Size size,
  ) {
    final currentCrop = _currentWorkingCropRect;
    if (!_cropMode) return;
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx = details.delta.dx / safeWidth;
    final dy = details.delta.dy / safeHeight;
    final lockedAspectRatio = _lockedNormalizedCropAspectRatio(_currentItem);

    if (lockedAspectRatio == null) {
      var next = currentCrop;
      switch (handle) {
        case _MediaComposerCropHandle.topLeft:
          next = Rect.fromLTRB(
            currentCrop.left + dx,
            currentCrop.top + dy,
            currentCrop.right,
            currentCrop.bottom,
          );
          break;
        case _MediaComposerCropHandle.topRight:
          next = Rect.fromLTRB(
            currentCrop.left,
            currentCrop.top + dy,
            currentCrop.right + dx,
            currentCrop.bottom,
          );
          break;
        case _MediaComposerCropHandle.bottomLeft:
          next = Rect.fromLTRB(
            currentCrop.left + dx,
            currentCrop.top,
            currentCrop.right,
            currentCrop.bottom + dy,
          );
          break;
        case _MediaComposerCropHandle.bottomRight:
          next = Rect.fromLTRB(
            currentCrop.left,
            currentCrop.top,
            currentCrop.right + dx,
            currentCrop.bottom + dy,
          );
          break;
      }

      setState(() {
        _currentItem.draftCropRectNormalized = _clampCropRect(next);
      });
      return;
    }

    late final Offset anchor;
    late final double desiredWidth;
    switch (handle) {
      case _MediaComposerCropHandle.topLeft:
        anchor = currentCrop.bottomRight;
        desiredWidth = math.max(
          currentCrop.width - dx,
          (currentCrop.height - dy) * lockedAspectRatio,
        );
        break;
      case _MediaComposerCropHandle.topRight:
        anchor = currentCrop.bottomLeft;
        desiredWidth = math.max(
          currentCrop.width + dx,
          (currentCrop.height - dy) * lockedAspectRatio,
        );
        break;
      case _MediaComposerCropHandle.bottomLeft:
        anchor = currentCrop.topRight;
        desiredWidth = math.max(
          currentCrop.width - dx,
          (currentCrop.height + dy) * lockedAspectRatio,
        );
        break;
      case _MediaComposerCropHandle.bottomRight:
        anchor = currentCrop.topLeft;
        desiredWidth = math.max(
          currentCrop.width + dx,
          (currentCrop.height + dy) * lockedAspectRatio,
        );
        break;
    }

    setState(() {
      _currentItem.draftCropRectNormalized = _clampLockedCropRect(
        handle: handle,
        anchor: anchor,
        desiredWidth: desiredWidth,
        aspectRatio: lockedAspectRatio,
      );
    });
  }

  Future<void> _send() async {
    if (_sending || _items.isEmpty) return;
    if (_cropMode) {
      _applyCropEditing();
    }
    _finishTextEditing();

    setState(() {
      _sending = true;
      _sendingLabel = 'Hazirlaniyor...';
    });

    try {
      final attachments = <OutgoingAttachmentDraft>[];
      for (var index = 0; index < _items.length; index++) {
        final item = _items[index];
        if (mounted) {
          setState(() {
            _sendingLabel = '${index + 1}/${_items.length} yukleniyor';
          });
        }

        final prepared = await _prepareAttachment(item);
        final upload = await ChatApi.createAttachmentUpload(
          widget.session,
          chatId: widget.chat.chatId,
          kind: prepared.kind,
          contentType: prepared.contentType,
          fileName: prepared.fileName,
        );

        final uploadRes = await http.put(
          Uri.parse(upload.uploadUrl),
          headers: upload.headers,
          body: prepared.bytes,
        );
        if (uploadRes.statusCode >= 400) {
          throw TurnaApiException('Dosya yuklenemedi.');
        }

        attachments.add(
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: prepared.kind,
            fileName: prepared.fileName,
            contentType: prepared.contentType,
            sizeBytes: prepared.bytes.length,
            width: prepared.width,
            height: prepared.height,
          ),
        );
      }

      final caption = _captionController.text.trim();
      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: widget.chat.chatId,
        text: caption.isEmpty ? null : caption,
        attachments: attachments,
      );

      await TurnaAnalytics.logEvent('attachment_sent', {
        'chat_id': widget.chat.chatId,
        'quality': _quality.name,
        'count': attachments.length,
        'kind': attachments.length == 1 ? attachments.first.kind.name : 'album',
      });

      if (!mounted) return;
      Navigator.pop(context, message);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingLabel = null;
        });
      }
    }
  }

  Future<_PreparedComposerAttachment> _prepareAttachment(
    _MediaComposerItem item,
  ) async {
    final sourceBytes = await item.file.readAsBytes();

    if (!item.isImage) {
      return _PreparedComposerAttachment(
        kind: item.kind,
        fileName: item.fileName,
        contentType: item.contentType,
        bytes: sourceBytes,
      );
    }

    await _primeImageSize(item);
    return _renderImageAttachment(item, sourceBytes);
  }

  List<_MediaComposerStroke> _transformStrokesForCrop(
    List<_MediaComposerStroke> strokes,
    Rect cropRect,
  ) {
    if (cropRect == kComposerFullCropRectNormalized) return strokes;
    return strokes
        .map(
          (stroke) => _MediaComposerStroke(
            color: stroke.color,
            widthFactor: stroke.widthFactor,
            points: stroke.points
                .map(
                  (point) => Offset(
                    (point.dx - cropRect.left) / cropRect.width,
                    (point.dy - cropRect.top) / cropRect.height,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  List<_MediaComposerTextOverlay> _transformTextOverlaysForCrop(
    List<_MediaComposerTextOverlay> overlays,
    Rect cropRect,
  ) {
    if (cropRect == kComposerFullCropRectNormalized) return overlays;
    return overlays
        .map(
          (overlay) => _MediaComposerTextOverlay(
            id: overlay.id,
            text: overlay.text,
            position: Offset(
              (overlay.position.dx - cropRect.left) / cropRect.width,
              (overlay.position.dy - cropRect.top) / cropRect.height,
            ),
            scale: overlay.scale,
            colorValue: overlay.colorValue,
          ),
        )
        .toList();
  }

  Future<ui.Image> _renderRotatedImage(
    ui.Image sourceImage, {
    required int rotationTurns,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final srcRect = Rect.fromLTWH(
      0,
      0,
      sourceImage.width.toDouble(),
      sourceImage.height.toDouble(),
    );
    final paint = Paint()..isAntiAlias = true;

    switch (rotationTurns % 4) {
      case 1:
        canvas.save();
        canvas.translate(width.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, height.toDouble(), width.toDouble()),
          paint,
        );
        canvas.restore();
        break;
      case 2:
        canvas.save();
        canvas.translate(width.toDouble(), height.toDouble());
        canvas.rotate(math.pi);
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          paint,
        );
        canvas.restore();
        break;
      case 3:
        canvas.save();
        canvas.translate(0, height.toDouble());
        canvas.rotate(-math.pi / 2);
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, height.toDouble(), width.toDouble()),
          paint,
        );
        canvas.restore();
        break;
      default:
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          paint,
        );
    }

    return recorder.endRecording().toImage(width, height);
  }

  Future<_PreparedComposerAttachment> _renderImageAttachment(
    _MediaComposerItem item,
    Uint8List sourceBytes,
  ) async {
    final codec = await ui.instantiateImageCodec(sourceBytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final inputSize = Size(
      sourceImage.width.toDouble(),
      sourceImage.height.toDouble(),
    );
    final rotatedInputSize = item.rotationTurns.isOdd
        ? Size(inputSize.height, inputSize.width)
        : inputSize;
    final rotatedWidth = math.max(1, rotatedInputSize.width.round());
    final rotatedHeight = math.max(1, rotatedInputSize.height.round());
    final rotatedImage = await _renderRotatedImage(
      sourceImage,
      rotationTurns: item.rotationTurns,
      width: rotatedWidth,
      height: rotatedHeight,
    );
    final cropRect = item.cropRectNormalized ?? kComposerFullCropRectNormalized;
    final cropSrcRect = Rect.fromLTWH(
      cropRect.left * rotatedWidth,
      cropRect.top * rotatedHeight,
      cropRect.width * rotatedWidth,
      cropRect.height * rotatedHeight,
    );
    final scaledSize = _scaleToMax(
      cropSrcRect.size,
      _quality.imageMaxDimension,
    );
    final outputWidth = math.max(1, scaledSize.width.round());
    final outputHeight = math.max(1, scaledSize.height.round());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawImageRect(
      rotatedImage,
      cropSrcRect,
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
      paint,
    );

    _paintComposerStrokes(
      canvas,
      size: Size(outputWidth.toDouble(), outputHeight.toDouble()),
      strokes: _transformStrokesForCrop(item.strokes, cropRect),
    );
    _paintComposerTextOverlays(
      canvas,
      size: Size(outputWidth.toDouble(), outputHeight.toDouble()),
      overlays: _transformTextOverlaysForCrop(item.textOverlays, cropRect),
    );

    final rendered = await recorder.endRecording().toImage(
      outputWidth,
      outputHeight,
    );
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw TurnaApiException('Gorsel hazirlanamadi.');
    }
    final encodedImage = img.Image.fromBytes(
      width: outputWidth,
      height: outputHeight,
      bytes: data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final jpgBytes = Uint8List.fromList(
      img.encodeJpg(encodedImage, quality: _quality.jpegQuality),
    );

    return _PreparedComposerAttachment(
      kind: item.kind,
      fileName: replaceFileExtension(item.fileName, 'jpg'),
      contentType: 'image/jpeg',
      bytes: jpgBytes,
      width: outputWidth,
      height: outputHeight,
    );
  }

  Size _scaleToMax(Size size, double maxDimension) {
    final longestSide = math.max(size.width, size.height);
    if (longestSide <= maxDimension) return size;
    final scale = maxDimension / longestSide;
    return Size(size.width * scale, size.height * scale);
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentItem;

    return Scaffold(
      backgroundColor: const Color(0xFF101312),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101312),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _toggleQuality,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: TurnaColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _quality.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Kirp',
            onPressed: _toggleCropMode,
            color: _cropMode ? TurnaColors.primary : null,
            icon: const Icon(Icons.crop_outlined),
          ),
          IconButton(
            tooltip: 'Yazi',
            onPressed: _cropMode
                ? null
                : () => _editOverlayText(emojiMode: false),
            icon: const Icon(Icons.text_fields_outlined),
          ),
          IconButton(
            tooltip: 'Ciz',
            onPressed: _cropMode ? null : _toggleDrawMode,
            color: _drawMode ? TurnaColors.primary : null,
            icon: const Icon(Icons.draw_outlined),
          ),
          IconButton(
            tooltip: 'Emoji',
            onPressed: _cropMode
                ? null
                : () => _editOverlayText(emojiMode: true),
            icon: const Icon(Icons.emoji_emotions_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  children: [
                    if (_drawMode && current.isImage)
                      Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ComposerToolChip(
                                label: 'Ince',
                                selected:
                                    !_eraserMode && _brushSizeFactor == 0.008,
                                onTap: () => _setBrushSize(0.008),
                              ),
                              const SizedBox(width: 8),
                              _ComposerToolChip(
                                label: 'Orta',
                                selected:
                                    !_eraserMode && _brushSizeFactor == 0.011,
                                onTap: () => _setBrushSize(0.011),
                              ),
                              const SizedBox(width: 8),
                              _ComposerToolChip(
                                label: 'Kalin',
                                selected:
                                    !_eraserMode && _brushSizeFactor == 0.016,
                                onTap: () => _setBrushSize(0.016),
                              ),
                              const SizedBox(width: 8),
                              _ComposerToolChip(
                                label: 'Silgi',
                                selected: _eraserMode,
                                onTap: _toggleEraser,
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _undoCurrentStroke,
                                child: const Text('Geri al'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        physics: _cropMode
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        itemCount: _items.length,
                        onPageChanged: (index) {
                          _finishTextEditing();
                          setState(() {
                            _selectedIndex = index;
                            _cropMode = false;
                            _drawMode = false;
                            _eraserMode = false;
                            for (final item in _items) {
                              item.draftCropRectNormalized = null;
                              item.draftCropPresetId = null;
                            }
                          });
                        },
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _buildPreviewPage(item);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_items.length > 1)
              SizedBox(
                height: 92,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  scrollDirection: Axis.horizontal,
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final selected = index == _selectedIndex;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: item.isImage
                              ? Image.file(
                                  File(item.file.path),
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: const Color(0xFF1F2322),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.videocam_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_cropMode && current.isImage)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 16, 10),
                child: Row(
                  children: [
                    _ComposerOverlayPillButton(
                      icon: Icons.rotate_90_degrees_ccw_outlined,
                      onTap: _rotateCurrent,
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<String>(
                      initialValue: _currentWorkingCropPresetId,
                      onSelected: (value) =>
                          _applyCropPreset(_cropPresetForId(value)),
                      color: const Color(0xFF1A1F1D),
                      itemBuilder: (_) => _kComposerCropPresets
                          .map(
                            (preset) => PopupMenuItem<String>(
                              value: preset.id,
                              child: Text(
                                preset.label,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC1A1F1D),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.crop_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _cropPresetForId(
                                _currentWorkingCropPresetId,
                              ).label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _cancelCropEditing,
                      child: const Text(
                        'Iptal',
                        style: TextStyle(color: Color(0xFFB7BCB9)),
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: TurnaColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _applyCropEditing,
                      child: const Text('Tamam'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Aciklama ekle',
                        hintStyle: const TextStyle(color: Color(0xFF7C8380)),
                        filled: true,
                        fillColor: const Color(0xFF162033),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_sendingLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _sendingLabel!,
                            style: const TextStyle(
                              color: Color(0xFFB8BFBC),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      FloatingActionButton.small(
                        backgroundColor: TurnaColors.primary,
                        onPressed: _sending ? null : _send,
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPage(_MediaComposerItem item) {
    if (!item.isImage) {
      return Center(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF181D1C),
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.videocam_outlined,
                size: 56,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(
                item.fileName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatBytesLabel(item.sizeBytes),
                style: const TextStyle(color: Color(0xFFB8BFBC), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCurrent = identical(item, _currentItem);
        final isCropingCurrent = isCurrent && _cropMode;
        final activeOverlay = isCurrent ? _activeTextOverlay : null;
        final displayCrop = isCropingCurrent
            ? kComposerFullCropRectNormalized
            : _displayCropRectFor(item);
        final aspectRatio = _effectiveAspectRatioFor(item, displayCrop);
        var width = constraints.maxWidth;
        var height = width / aspectRatio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * aspectRatio;
        }
        final canvasSize = Size(width, height);
        final transformedStrokes = _transformStrokesForCrop(
          item.strokes,
          displayCrop,
        );
        final cropRect = isCropingCurrent
            ? _currentWorkingCropRect
            : (item.cropRectNormalized ?? _defaultCropRectFor(item));
        final cropFrame = _normalizedCropToRect(cropRect, canvasSize);

        final Widget imageLayer;
        if (displayCrop == kComposerFullCropRectNormalized) {
          imageLayer = RotatedBox(
            quarterTurns: item.rotationTurns,
            child: Image.file(File(item.file.path), fit: BoxFit.fill),
          );
        } else {
          final expandedWidth = width / displayCrop.width;
          final expandedHeight = height / displayCrop.height;
          imageLayer = ClipRect(
            child: Transform.translate(
              offset: Offset(
                -(displayCrop.left * expandedWidth),
                -(displayCrop.top * expandedHeight),
              ),
              child: SizedBox(
                width: expandedWidth,
                height: expandedHeight,
                child: RotatedBox(
                  quarterTurns: item.rotationTurns,
                  child: Image.file(File(item.file.path), fit: BoxFit.fill),
                ),
              ),
            ),
          );
        }

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _drawMode
                ? (details) => _startStroke(
                    details.localPosition,
                    canvasSize,
                    displayCrop,
                  )
                : null,
            onPanUpdate: _drawMode
                ? (details) => _appendStroke(
                    details.localPosition,
                    canvasSize,
                    displayCrop,
                  )
                : null,
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageLayer,
                    if (isCurrent && _activeTextOverlay != null)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _finishTextEditing,
                          child: Container(color: Colors.black45),
                        ),
                      ),
                    for (final overlay in item.textOverlays)
                      Builder(
                        builder: (_) {
                          final displayPosition = _projectPointToDisplay(
                            overlay.position,
                            displayCrop,
                          );
                          return Align(
                            alignment: Alignment(
                              (displayPosition.dx * 2) - 1,
                              (displayPosition.dy * 2) - 1,
                            ),
                            child:
                                isCurrent && overlay.id == _activeTextOverlayId
                                ? ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: width * 0.82,
                                    ),
                                    child: TextField(
                                      controller: _inlineTextController,
                                      focusNode: _inlineTextFocusNode,
                                      autofocus: false,
                                      maxLines: 4,
                                      minLines: 1,
                                      textAlign: TextAlign.center,
                                      cursorColor: overlay.color,
                                      style: TextStyle(
                                        color: overlay.color,
                                        fontWeight: FontWeight.w700,
                                        fontSize:
                                            math.max(18, width * 0.06) *
                                            overlay.scale,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 10,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onChanged: _syncActiveTextOverlay,
                                      onSubmitted: (_) => _finishTextEditing(),
                                    ),
                                  )
                                : GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: _drawMode || _cropMode
                                        ? null
                                        : () => _beginEditingTextOverlay(
                                            overlay,
                                            requestKeyboard: true,
                                          ),
                                    onScaleStart: _drawMode || _cropMode
                                        ? null
                                        : (_) =>
                                              _handleOverlayScaleStart(overlay),
                                    onScaleUpdate: _drawMode || _cropMode
                                        ? null
                                        : (details) =>
                                              _handleOverlayScaleUpdate(
                                                overlay,
                                                details,
                                                canvasSize,
                                                displayCrop,
                                              ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: width * 0.82,
                                      ),
                                      child: Text(
                                        overlay.text,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: overlay.color,
                                          fontWeight: FontWeight.w700,
                                          fontSize:
                                              math.max(18, width * 0.06) *
                                              overlay.scale,
                                          shadows: const [
                                            Shadow(
                                              color: Colors.black54,
                                              blurRadius: 10,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _MediaComposerStrokePainter(
                          strokes: transformedStrokes,
                        ),
                      ),
                    ),
                    if (isCurrent && _cropMode)
                      Positioned.fill(
                        child: _ComposerCropOverlay(
                          cropFrame: cropFrame,
                          onMove: (details) =>
                              _moveCropRect(details, canvasSize),
                          onResize: (handle, details) =>
                              _resizeCropRect(handle, details, canvasSize),
                        ),
                      ),
                    if (isCurrent && (_drawMode || activeOverlay != null))
                      Positioned(
                        right: 12,
                        top: 16,
                        bottom: 16,
                        child: _ComposerColorSlider(
                          value:
                              activeOverlay?.colorValue ??
                              item.markupColorValue,
                          color: activeOverlay?.color ?? item.markupColor,
                          onChanged: _setMarkupColor,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ComposerColorSlider extends StatelessWidget {
  const _ComposerColorSlider({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  void _updateFromOffset(Offset localPosition, double height) {
    final safeHeight = height <= 0 ? 1.0 : height;
    onChanged((localPosition.dy / safeHeight).clamp(0.0, 1.0).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _updateFromOffset(details.localPosition, trackHeight),
          onVerticalDragStart: (details) =>
              _updateFromOffset(details.localPosition, trackHeight),
          onVerticalDragUpdate: (details) =>
              _updateFromOffset(details.localPosition, trackHeight),
          child: SizedBox(
            width: 34,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: 16,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: kComposerPaletteStops,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                ),
                Positioned(
                  top: (trackHeight - 24) * value.clamp(0.0, 1.0).toDouble(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ComposerCropOverlay extends StatelessWidget {
  const _ComposerCropOverlay({
    required this.cropFrame,
    required this.onMove,
    required this.onResize,
  });

  final Rect cropFrame;
  final ValueChanged<DragUpdateDetails> onMove;
  final void Function(
    _MediaComposerCropHandle handle,
    DragUpdateDetails details,
  )
  onResize;

  @override
  Widget build(BuildContext context) {
    const handleSize = 30.0;
    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ComposerCropOverlayPainter(cropFrame: cropFrame),
          ),
        ),
        Positioned.fromRect(
          rect: cropFrame,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: onMove,
            child: const SizedBox.expand(),
          ),
        ),
        _buildHandle(
          center: cropFrame.topLeft,
          handle: _MediaComposerCropHandle.topLeft,
          handleSize: handleSize,
        ),
        _buildHandle(
          center: cropFrame.topRight,
          handle: _MediaComposerCropHandle.topRight,
          handleSize: handleSize,
        ),
        _buildHandle(
          center: cropFrame.bottomLeft,
          handle: _MediaComposerCropHandle.bottomLeft,
          handleSize: handleSize,
        ),
        _buildHandle(
          center: cropFrame.bottomRight,
          handle: _MediaComposerCropHandle.bottomRight,
          handleSize: handleSize,
        ),
      ],
    );
  }

  Widget _buildHandle({
    required Offset center,
    required _MediaComposerCropHandle handle,
    required double handleSize,
  }) {
    return Positioned(
      left: center.dx - (handleSize / 2),
      top: center.dy - (handleSize / 2),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) => onResize(handle, details),
        child: Container(
          width: handleSize,
          height: handleSize,
          alignment: Alignment.center,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF101312), width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerCropOverlayPainter extends CustomPainter {
  const _ComposerCropOverlayPainter({required this.cropFrame});

  final Rect cropFrame;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(cropFrame);
    final overlay = Path.combine(PathOperation.difference, outer, inner);

    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );
    canvas.drawRect(
      cropFrame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final thirdWidth = cropFrame.width / 3;
    final thirdHeight = cropFrame.height / 3;

    for (var index = 1; index <= 2; index++) {
      final dx = cropFrame.left + (thirdWidth * index);
      canvas.drawLine(
        Offset(dx, cropFrame.top),
        Offset(dx, cropFrame.bottom),
        gridPaint,
      );

      final dy = cropFrame.top + (thirdHeight * index);
      canvas.drawLine(
        Offset(cropFrame.left, dy),
        Offset(cropFrame.right, dy),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ComposerCropOverlayPainter oldDelegate) {
    return oldDelegate.cropFrame != cropFrame;
  }
}

class _ComposerOverlayPillButton extends StatelessWidget {
  const _ComposerOverlayPillButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB81A1F1D),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _ComposerToolChip extends StatelessWidget {
  const _ComposerToolChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? TurnaColors.primary : const Color(0xFF162033),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaComposerItem {
  _MediaComposerItem({
    required this.kind,
    required this.file,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
  });

  factory _MediaComposerItem.fromSeed(MediaComposerSeed seed) {
    return _MediaComposerItem(
      kind: seed.kind,
      file: seed.file,
      fileName: seed.fileName,
      contentType: seed.contentType,
      sizeBytes: seed.sizeBytes,
    );
  }

  final ChatAttachmentKind kind;
  final XFile file;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final List<_MediaComposerStroke> strokes = [];
  final List<_MediaComposerTextOverlay> textOverlays = [];
  Rect? cropRectNormalized;
  Rect? draftCropRectNormalized;
  String cropPresetId = 'original';
  String? draftCropPresetId;
  double markupColorValue = 0;
  int rotationTurns = 0;
  Size? sourceSize;

  bool get isImage => kind == ChatAttachmentKind.image;

  Color get markupColor => composerColorForValue(markupColorValue);

  bool get hasMarkup =>
      rotationTurns != 0 ||
      strokes.isNotEmpty ||
      textOverlays.isNotEmpty ||
      (cropRectNormalized != null &&
          cropRectNormalized != kComposerFullCropRectNormalized);

  double get effectiveAspectRatio {
    final base = sourceSize ?? const Size(1, 1);
    final width = rotationTurns.isOdd ? base.height : base.width;
    final height = rotationTurns.isOdd ? base.width : base.height;
    return math.max(0.1, width / math.max(0.1, height));
  }
}

class _MediaComposerTextOverlay {
  _MediaComposerTextOverlay({
    required this.id,
    required this.text,
    required this.position,
    required this.scale,
    required this.colorValue,
  });

  final String id;
  String text;
  Offset position;
  double scale;
  double colorValue;

  Color get color => composerColorForValue(colorValue);
}

class _MediaComposerStroke {
  _MediaComposerStroke({
    required this.color,
    required this.points,
    required this.widthFactor,
  });

  final Color color;
  final List<Offset> points;
  final double widthFactor;
}

class _PreparedComposerAttachment {
  _PreparedComposerAttachment({
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.bytes,
    this.width,
    this.height,
  });

  final ChatAttachmentKind kind;
  final String fileName;
  final String contentType;
  final Uint8List bytes;
  final int? width;
  final int? height;
}

class _MediaComposerStrokePainter extends CustomPainter {
  const _MediaComposerStrokePainter({required this.strokes});

  final List<_MediaComposerStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    _paintComposerStrokes(canvas, size: size, strokes: strokes);
  }

  @override
  bool shouldRepaint(covariant _MediaComposerStrokePainter oldDelegate) {
    return true;
  }
}

void _paintComposerStrokes(
  Canvas canvas, {
  required Size size,
  required List<_MediaComposerStroke> strokes,
}) {
  for (final stroke in strokes) {
    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3, size.shortestSide * stroke.widthFactor);
    if (stroke.points.isEmpty) continue;
    if (stroke.points.length == 1) {
      final point = Offset(
        stroke.points.first.dx * size.width,
        stroke.points.first.dy * size.height,
      );
      canvas.drawCircle(point, paint.strokeWidth * 0.5, paint);
      continue;
    }

    final path = Path();
    final first = stroke.points.first;
    path.moveTo(first.dx * size.width, first.dy * size.height);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }
}

void _paintComposerTextOverlays(
  Canvas canvas, {
  required Size size,
  required List<_MediaComposerTextOverlay> overlays,
}) {
  for (final overlay in overlays) {
    final value = overlay.text.trim();
    if (value.isEmpty) continue;

    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: overlay.color,
          fontWeight: FontWeight.w700,
          fontSize: math.max(28, size.width * 0.06) * overlay.scale,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2)),
          ],
        ),
      ),
    )..layout(maxWidth: size.width * 0.82);

    final marginX = size.width * 0.04;
    final marginY = size.height * 0.04;
    final left = (size.width * overlay.position.dx) - (painter.width / 2);
    final top = (size.height * overlay.position.dy) - (painter.height / 2);

    painter.paint(
      canvas,
      Offset(
        left.clamp(marginX, size.width - painter.width - marginX).toDouble(),
        top.clamp(marginY, size.height - painter.height - marginY).toDouble(),
      ),
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
  final TextEditingController _searchController = TextEditingController();
  List<ChatUser> _users = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await ChatApi.fetchDirectory(widget.session);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchController.text.trim().toLowerCase();
    final filtered = _users.where((u) {
      if (q.isEmpty) return true;
      return u.displayName.toLowerCase().contains(q) ||
          u.id.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Sohbet')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Isim veya kullanici ID ara',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: q.isEmpty
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
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _CenteredState(
                    icon: _error!.contains('Oturum')
                        ? Icons.lock_outline
                        : Icons.person_search_outlined,
                    title: _error!.contains('Oturum')
                        ? 'Oturumun suresi doldu'
                        : 'Kisi listesi yuklenemedi',
                    message: _error!,
                    primaryLabel: _error!.contains('Oturum')
                        ? 'Yeniden giris yap'
                        : 'Tekrar dene',
                    onPrimary: _error!.contains('Oturum')
                        ? widget.onSessionExpired
                        : _loadDirectory,
                  )
                : filtered.isEmpty
                ? _CenteredState(
                    icon: _users.isEmpty
                        ? Icons.group_outlined
                        : Icons.search_off,
                    title: _users.isEmpty
                        ? 'Henuz baska kullanici yok'
                        : 'Sonuc bulunamadi',
                    message: _users.isEmpty
                        ? 'Diger kullanicilar kayit oldukca burada listelenecek.'
                        : '"${_searchController.text.trim()}" icin eslesen kisi yok.',
                    primaryLabel: _users.isEmpty ? 'Yenile' : 'Aramayi temizle',
                    onPrimary: _users.isEmpty
                        ? _loadDirectory
                        : _searchController.clear,
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      return ListTile(
                        leading: _ProfileAvatar(
                          label: user.displayName,
                          avatarUrl: user.avatarUrl,
                          authToken: widget.session.token,
                          radius: 22,
                        ),
                        title: Text(user.displayName),
                        subtitle: Text(user.id),
                        onTap: () async {
                          final chat = ChatPreview(
                            chatId: ChatApi.buildDirectChatId(
                              widget.session.userId,
                              user.id,
                            ),
                            name: user.displayName,
                            message: '',
                            time: '',
                            avatarUrl: user.avatarUrl,
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
                          Navigator.of(this.context).pop(true);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
