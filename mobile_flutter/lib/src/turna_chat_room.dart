part of '../main.dart';

class _ComposerEditDraft {
  const _ComposerEditDraft({
    required this.messageId,
    required this.reply,
    required this.originalText,
  });

  final String messageId;
  final TurnaReplyPayload? reply;
  final String originalText;
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
    builder: (_) => _LockedChatAccessGate(
      chat: chat,
      child: ChatRoomPage(
        chat: chat,
        session: session,
        callCoordinator: callCoordinator,
        onSessionExpired: onSessionExpired,
      ),
    ),
  );
}

class _LockedChatAccessGate extends StatefulWidget {
  const _LockedChatAccessGate({required this.chat, required this.child});

  final ChatPreview chat;
  final Widget child;

  @override
  State<_LockedChatAccessGate> createState() => _LockedChatAccessGateState();
}

class _LockedChatAccessGateState extends State<_LockedChatAccessGate> {
  bool _authorized = false;
  bool _authStarted = false;

  @override
  void initState() {
    super.initState();
    _authorized = !widget.chat.isLocked;
    if (!_authorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _authenticate();
      });
    }
  }

  Future<void> _authenticate() async {
    if (_authStarted || !mounted || _authorized) return;
    _authStarted = true;
    final authenticated = await _authenticateLockedChatAccess(
      context,
      chatName: widget.chat.name,
      actionLabel: 'acmak icin',
    );
    if (!mounted) return;
    if (authenticated) {
      setState(() => _authorized = true);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (_authorized) {
      return widget.child;
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
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

class _ResolvedChatMessageText {
  const _ResolvedChatMessageText({
    required this.rawText,
    required this.parsed,
    required this.trimmedText,
    required this.sharedLinks,
    required this.primaryLinkUri,
    required this.linkCaptionText,
  });

  final String rawText;
  final ParsedTurnaMessageText parsed;
  final String trimmedText;
  final List<Uri> sharedLinks;
  final Uri? primaryLinkUri;
  final String linkCaptionText;
}

class _ChatRoomPageState extends State<ChatRoomPage>
    with WidgetsBindingObserver, RouteAware {
  static const Duration _voiceRecordTick = Duration(milliseconds: 140);
  static const Duration _voiceMinDuration = Duration(milliseconds: 600);
  static const double _voiceCancelThreshold = 112;
  static const double _voiceLockThreshold = 84;

  late final TurnaSocketClient _client;
  late final Listenable _headerListenable;
  late final Listenable _contentListenable;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _mediaPicker = ImagePicker();
  final FocusNode _composerFocusNode = FocusNode();
  final rec.AudioRecorder _voiceRecorder = rec.AudioRecorder();
  final Stopwatch _voiceStopwatch = Stopwatch();
  bool _showScrollToBottom = false;
  bool _attachmentBusy = false;
  bool _hasComposerText = false;
  bool _loadingPeerCalls = false;
  bool _voiceRecording = false;
  bool _voiceRecordingLocked = false;
  bool _voiceRecordingPaused = false;
  bool _voiceRecorderBusy = false;
  bool _voiceSlideCancelArmed = false;
  bool _showSecurityBanner = false;
  TurnaReplyPayload? _replyDraft;
  _ComposerEditDraft? _editingDraft;
  List<TurnaGroupMember> _mentionCandidates = const [];
  List<TurnaGroupMember> _mentionSuggestions = const [];
  String? _activeMentionQuery;
  List<TurnaCallHistoryItem> _peerCalls = const [];
  Set<String> _starredMessageIds = <String>{};
  Set<String> _softDeletedMessageIds = <String>{};
  Set<String> _deletedMessageIds = <String>{};
  final Map<String, _ResolvedChatMessageText> _resolvedMessageTextCache =
      <String, _ResolvedChatMessageText>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final List<String> _trackedMessageKeyOrder = <String>[];
  final Set<String> _trackedMessageIds = <String>{};
  List<ChatMessage> _cachedDisplayMessages = const <ChatMessage>[];
  List<_ChatTimelineEntry> _cachedTimelineEntries =
      const <_ChatTimelineEntry>[];
  int _cachedMessagesRevision = -1;
  Object? _cachedDeletedMessageIdsRef;
  Object? _cachedPeerCallsRef;
  bool _hasCachedDisplayMessages = false;
  bool _hasCachedTimelineEntries = false;
  int _lastRenderedTimelineCount = 0;
  Timer? _messageHighlightTimer;
  String? _highlightedMessageId;
  PageRoute<dynamic>? _route;
  Timer? _voiceRecordTimer;
  String? _voiceRecordingPath;
  double _voiceSlideProgress = 0;
  final GlobalKey _voiceMicKey = GlobalKey();
  int? _voicePointerId;
  Offset? _voicePointerOriginGlobal;
  static const int _trackedMessageKeyLimit = 32;
  static const int _resolvedMessageTextCacheLimit = 256;

  bool get _isGroupChat => widget.chat.chatType == TurnaChatType.group;
  TurnaChatDetail? get _cachedGroupDetail => _isGroupChat
      ? TurnaChatDetailLocalCache.peek(
          widget.session.userId,
          widget.chat.chatId,
        )
      : null;
  String? get _peerUserId =>
      ChatApi.extractPeerUserId(widget.chat.chatId, widget.session.userId);
  String? get _groupAvatarUrl =>
      _cachedGroupDetail?.avatarUrl ?? widget.chat.avatarUrl;
  int get _groupMemberCount =>
      _cachedGroupDetail?.memberCount ?? widget.chat.memberCount;
  String get _chatDisplayName => _isGroupChat
      ? ((_cachedGroupDetail?.title.trim().isNotEmpty ?? false)
            ? _cachedGroupDetail!.title.trim()
            : widget.chat.name)
      : TurnaContactsDirectory.resolveDisplayLabel(
          phone: widget.chat.phone,
          fallbackName: widget.chat.name,
        );
  TurnaPinnedMessageSummary? get _activePinnedMessage =>
      _client.pinnedMessages.isEmpty ? null : _client.pinnedMessages.first;
  bool get _canManagePinnedMessages {
    if (!_isGroupChat) return false;
    final detail = _cachedGroupDetail;
    if (detail == null) return true;
    return _policyAllowsForCurrentUser(
      detail.whoCanEditInfo,
      detail.myRole ?? '',
    );
  }

  String get _securityBannerSeenKey =>
      'turna_security_banner_seen_${widget.session.userId}_${widget.chat.chatId}';
  String get _starredMessagesKey =>
      'turna_starred_messages_${widget.chat.chatId}';
  String get _softDeletedMessagesKey =>
      'turna_soft_deleted_messages_${widget.chat.chatId}';
  String get _deletedMessagesKey =>
      'turna_deleted_messages_${widget.chat.chatId}';

  bool _policyAllowsForCurrentUser(String policy, String role) {
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

  bool get _canCurrentUserSendInGroup {
    if (!_isGroupChat) return true;
    final detail = _cachedGroupDetail;
    if (detail == null) return true;
    if (detail.myIsMuted) return false;
    if (detail.myCanSend != true) return false;
    return _policyAllowsForCurrentUser(detail.whoCanSend, detail.myRole ?? '');
  }

  bool get _canCurrentUserStartGroupCalls {
    if (!_isGroupChat) return false;
    final detail = _cachedGroupDetail;
    if (detail == null) return false;
    return _policyAllowsForCurrentUser(
      detail.whoCanStartCalls,
      detail.myRole ?? '',
    );
  }

  TurnaGroupCallState? get _activeGroupCall => _client.activeGroupCallState;

  String? get _groupSendRestrictionText {
    if (!_isGroupChat) return null;
    final detail = _cachedGroupDetail;
    if (detail == null || _canCurrentUserSendInGroup) return null;
    if (detail.myIsMuted) {
      if ((detail.myMutedUntil ?? '').trim().isNotEmpty) {
        final until = parseTurnaLocalDateTime(detail.myMutedUntil!);
        if (until != null) {
          final hh = until.hour.toString().padLeft(2, '0');
          final mm = until.minute.toString().padLeft(2, '0');
          return 'Sessize alındın. ${until.day.toString().padLeft(2, '0')}.${until.month.toString().padLeft(2, '0')} $hh:$mm sonrasına kadar yazamazsın.';
        }
      }
      return (detail.myMuteReason ?? '').trim().isNotEmpty
          ? 'Sessize alındın. ${detail.myMuteReason!.trim()}'
          : 'Sessize alındın. Bu grupta şu an mesaj gönderemezsin.';
    }
    switch ((detail.whoCanSend).trim().toUpperCase()) {
      case 'OWNER_ONLY':
        return 'Bu grupta şu an sadece sahip mesaj gönderebilir.';
      case 'ADMIN_ONLY':
        return 'Bu grupta şu an sadece adminler mesaj gönderebilir.';
      case 'EDITOR_ONLY':
        return 'Bu grupta şu an sadece editör ve üstü mesaj gönderebilir.';
      default:
        return 'Bu grupta mesaj gönderme iznin kapalı.';
    }
  }

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
      chatType: widget.chat.chatType,
      token: widget.session.token,
      onSessionExpired: widget.onSessionExpired,
    );
    _headerListenable = Listenable.merge(<Listenable>[
      _client.headerRevisionListenable,
      TurnaContactsDirectory.revision,
    ]);
    _contentListenable = Listenable.merge(<Listenable>[
      _client.contentRevisionListenable,
      TurnaContactsDirectory.revision,
    ]);
    _client.messagesRevisionListenable.addListener(
      _handleClientMessagesChanged,
    );
    _client.connect();
    widget.callCoordinator.addListener(_handleCallCoordinatorChanged);
    _controller.addListener(_handleComposerChanged);
    _composerFocusNode.addListener(_handleComposerFocusChanged);
    _scrollController.addListener(_handleScroll);
    _loadLocalMessageState();
    unawaited(_loadSecurityBannerState());
    if (_isGroupChat) {
      unawaited(_loadPinnedMessages());
      unawaited(_loadGroupDetail());
      unawaited(_loadActiveGroupCallState());
      unawaited(_loadMentionCandidates());
    }
    if (!_isGroupChat) {
      _restorePeerCallHistoryFromWarmCache();
    }
    unawaited(TurnaContactsDirectory.ensureLoaded());
    if (!_isGroupChat) {
      unawaited(_restorePeerCallHistoryFromDiskCache());
      unawaited(_loadPeerCallHistory());
    }
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
    if (!_isGroupChat) {
      unawaited(_loadPeerCallHistory());
    }
  }

  @override
  void didPopNext() {
    kTurnaActiveChatRegistry.setCurrent(widget.chat);
    if (!_isGroupChat) {
      unawaited(_loadPeerCallHistory());
    }
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
    if (mounted) {
      setState(() {});
    }
  }

  void _handleClientMessagesChanged() {
    final shouldSnapToBottom =
        !_scrollController.hasClients || _scrollController.offset < 120;
    final timelineCount = _buildTimelineEntries().length;
    if (timelineCount != _lastRenderedTimelineCount) {
      _lastRenderedTimelineCount = timelineCount;
      if (shouldSnapToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    }
  }

  void _handleCallCoordinatorChanged() {
    if (_isGroupChat) return;
    unawaited(_loadPeerCallHistory());
  }

  void _handleComposerChanged() {
    final text = _controller.text;
    _client.updateComposerText(text);
    _updateMentionSuggestions(text);
    final hasComposerText = text.trim().isNotEmpty;
    if (hasComposerText != _hasComposerText && mounted) {
      setState(() => _hasComposerText = hasComposerText);
    }
  }

  void _handleComposerFocusChanged() {
    _refresh();
    _updateMentionSuggestions(_controller.text);
  }

  String? _buildPeerStatusText() {
    if (_isGroupChat) {
      final typingSummary = _client.groupTypingSummary;
      if (typingSummary != null) return typingSummary;
      final previewNames =
          (_cachedGroupDetail?.memberPreviewNames ??
                  widget.chat.memberPreviewNames)
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();
      if (previewNames.isNotEmpty) {
        return '${previewNames.join(', ')} · $_groupMemberCount üye';
      }
      if (_groupMemberCount > 0) {
        return '$_groupMemberCount üye';
      }
      return 'Grup sohbeti';
    }
    if (_peerUserId == null) return null;
    if (_client.peerTyping) return 'yazıyor...';
    if (_client.peerOnline) return 'online';
    final lastSeenAt = _client.peerLastSeenAt;
    if (lastSeenAt == null || lastSeenAt.trim().isEmpty) return null;
    return 'son görülme ${_formatPresenceTime(lastSeenAt)}';
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
    if (diffDays == 0) return 'bugün $hh:$mm';
    if (diffDays == 1) return 'dün $hh:$mm';

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
          fallbackName: _chatDisplayName,
          fallbackAvatarUrl: widget.chat.avatarUrl,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _openGroupInfo() async {
    if (!_isGroupChat) return;

    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaGroupInfoPage(
          session: widget.session,
          chat: widget.chat,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
    if (mounted && _isGroupChat) {
      unawaited(_loadGroupDetail());
    }
    if (!mounted) return;
    if (result == true) {
      Navigator.of(context).pop(true);
      return;
    }
    if (result is String && result.trim().isNotEmpty) {
      await _scrollToReplyTarget(result);
    }
  }

  Future<void> _openGroupSearch() async {
    if (!_isGroupChat) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupSearchPage(
          session: widget.session,
          chat: widget.chat,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || result == null || result.trim().isEmpty) return;
    await _scrollToReplyTarget(result);
  }

  Future<void> _loadGroupDetail() async {
    if (!_isGroupChat) return;
    try {
      await ChatApi.fetchChatDetail(widget.session, widget.chat.chatId);
      if (!mounted) return;
      setState(() {});
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (_) {}
  }

  Future<void> _loadActiveGroupCallState() async {
    if (!_isGroupChat) return;
    try {
      final result = await CallApi.fetchActiveGroupCall(
        widget.session,
        chatId: widget.chat.chatId,
      );
      _client.setActiveGroupCallState(result.state);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (_) {}
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

  Future<void> _openGroupCallTypePicker() async {
    if (!_isGroupChat) return;
    if (_activeGroupCall != null) {
      await _joinOrStartGroupCall(_activeGroupCall!.type);
      return;
    }
    if (!_canCurrentUserStartGroupCalls) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu grupta çağrı başlatma yetkin yok.')),
      );
      return;
    }
    final selectedType = await showModalBottomSheet<TurnaCallType>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: const Text('Sesli grup çağrısı'),
                subtitle: const Text('Katılımcılar yalnızca sesle bağlanır.'),
                onTap: () => Navigator.of(context).pop(TurnaCallType.audio),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Görüntülü grup çağrısı'),
                subtitle: const Text(
                  'Katılımcılar kameralarını açıp kapatabilir.',
                ),
                onTap: () => Navigator.of(context).pop(TurnaCallType.video),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selectedType == null) return;
    await _joinOrStartGroupCall(selectedType);
  }

  Future<void> _joinOrStartGroupCall(TurnaCallType type) async {
    if (!_isGroupChat) return;

    try {
      final joined = await CallApi.joinGroupCall(
        widget.session,
        chatId: widget.chat.chatId,
        type: _activeGroupCall == null ? type : null,
      );
      if (joined.state != null) {
        _client.setActiveGroupCallState(joined.state);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupCallPage(
            session: widget.session,
            chat: widget.chat,
            chatClient: _client,
            initialState: joined.state,
            connect: joined.connect,
            myRole: _cachedGroupDetail?.myRole,
            onSessionExpired: widget.onSessionExpired,
          ),
        ),
      );
      if (!mounted) return;
      await _loadActiveGroupCallState();
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

  String? _activeGroupCallLabel() {
    final activeCall = _activeGroupCall;
    if (activeCall == null) return null;
    final starter = (activeCall.startedByDisplayName ?? '').trim();
    final mode = activeCall.type == TurnaCallType.video ? 'görüntülü' : 'sesli';
    final count = activeCall.participantCount;
    if (starter.isNotEmpty) {
      return count > 1
          ? '$starter $mode çağrıda · $count kişi'
          : '$starter $mode çağrı başlattı';
    }
    return count > 1
        ? '$mode grup çağrısı · $count kişi'
        : '$mode grup çağrısı aktif';
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

  String _formatViewerDateTime(String iso) {
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return '';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${dt.year} $hh:$min';
  }

  Future<void> _openSharedUri(
    Uri uri, {
    String errorMessage = 'Bağlantı açılamadı.',
  }) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  String _stripLinksFromText(String text) {
    return text
        .replaceAll(_kTurnaSharedUrlPattern, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _rememberResolvedMessageText(
    String messageId,
    _ResolvedChatMessageText resolved,
  ) {
    _resolvedMessageTextCache.remove(messageId);
    _resolvedMessageTextCache[messageId] = resolved;
    while (_resolvedMessageTextCache.length > _resolvedMessageTextCacheLimit) {
      _resolvedMessageTextCache.remove(_resolvedMessageTextCache.keys.first);
    }
  }

  _ResolvedChatMessageText _resolveMessageText(ChatMessage msg) {
    final cached = _resolvedMessageTextCache[msg.id];
    if (cached != null && cached.rawText == msg.text) {
      _rememberResolvedMessageText(msg.id, cached);
      return cached;
    }

    final parsed = parseTurnaMessageText(msg.text);
    final trimmedText = parsed.text.trim();
    final sharedLinks = trimmedText.isEmpty
        ? const <Uri>[]
        : List<Uri>.unmodifiable(extractTurnaUrls(trimmedText));
    final primaryLinkUri = sharedLinks.isEmpty ? null : sharedLinks.first;
    final resolved = _ResolvedChatMessageText(
      rawText: msg.text,
      parsed: parsed,
      trimmedText: trimmedText,
      sharedLinks: sharedLinks,
      primaryLinkUri: primaryLinkUri,
      linkCaptionText: primaryLinkUri == null
          ? trimmedText
          : _stripLinksFromText(trimmedText),
    );
    _rememberResolvedMessageText(msg.id, resolved);
    return resolved;
  }

  Widget _buildLinkifiedMessageText(String text, {required bool mine}) {
    final baseStyle = TextStyle(
      fontSize: 16,
      height: 1.28,
      color: mine ? TurnaColors.chatOutgoingText : TurnaColors.chatIncomingText,
    );
    final matches = _kTurnaSharedUrlPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final raw = match.group(0) ?? '';
      final uri = parseTurnaSharedUrl(raw);
      if (uri == null) {
        spans.add(TextSpan(text: raw));
      } else {
        spans.add(
          TextSpan(
            text: raw,
            style: baseStyle.copyWith(
              color: mine ? TurnaColors.primary800 : TurnaColors.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openSharedUri(uri),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
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

  String _formatFileSize(int bytes) => formatBytesLabel(bytes);

  List<TurnaCallHistoryItem> _filterPeerCalls(
    Iterable<TurnaCallHistoryItem> calls,
  ) {
    final peerUserId = _peerUserId;
    if (peerUserId == null) return const <TurnaCallHistoryItem>[];

    final filtered = calls.where((item) => item.peer.id == peerUserId).toList()
      ..sort((a, b) {
        final aTime = a.createdAt ?? a.endedAt ?? a.acceptedAt ?? '';
        final bTime = b.createdAt ?? b.endedAt ?? b.acceptedAt ?? '';
        return compareTurnaTimestamps(aTime, bTime);
      });
    return filtered;
  }

  bool _sameCallHistory(
    List<TurnaCallHistoryItem> a,
    List<TurnaCallHistoryItem> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id) return false;
      if (a[index].status != b[index].status) return false;
      if (a[index].createdAt != b[index].createdAt) return false;
      if (a[index].acceptedAt != b[index].acceptedAt) return false;
      if (a[index].endedAt != b[index].endedAt) return false;
      if (a[index].durationSeconds != b[index].durationSeconds) return false;
    }
    return true;
  }

  void _restorePeerCallHistoryFromWarmCache() {
    final cached = TurnaCallHistoryLocalCache.peek(widget.session.userId);
    if (cached == null || cached.isEmpty) return;
    _peerCalls = _filterPeerCalls(cached);
  }

  Future<void> _restorePeerCallHistoryFromDiskCache() async {
    final cached = await TurnaCallHistoryLocalCache.load(widget.session.userId);
    if (!mounted || cached.isEmpty) return;
    final filtered = _filterPeerCalls(cached);
    if (filtered.isEmpty || _sameCallHistory(filtered, _peerCalls)) return;
    setState(() => _peerCalls = filtered);
  }

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
      final filtered = _filterPeerCalls(calls);
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

  void _showVoiceMessageHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ses kaydı için mikrofona basılı tut.')),
    );
  }

  Future<void> _pickLocation() async {
    if (_attachmentBusy) return;
    final selection = await Navigator.of(context).push<TurnaLocationSelection>(
      MaterialPageRoute<TurnaLocationSelection>(
        builder: (_) => const LocationPickerPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || selection == null) return;
    await _sendLocationSelection(selection);
  }

  Future<void> _sendLocationSelection(TurnaLocationSelection selection) async {
    if (_attachmentBusy) return;
    final replyDraft = _replyDraft;
    final outboundText = buildTurnaLocationEncodedText(
      location: selection.payload,
    );
    final encodedText = replyDraft == null
        ? outboundText
        : buildTurnaReplyEncodedText(reply: replyDraft, text: outboundText);
    setState(() => _attachmentBusy = true);

    try {
      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: widget.chat.chatId,
        text: encodedText,
      );
      if (!mounted) return;
      _client.mergeServerMessage(message);
      if (selection.mode == TurnaLocationShareMode.live) {
        await TurnaLiveLocationManager.instance.startShare(
          session: widget.session,
          chatId: widget.chat.chatId,
          message: message,
          payload: selection.payload,
        );
      }
      setState(() => _replyDraft = null);
      _jumpToBottom();
      await TurnaAnalytics.logEvent('location_sent', {
        'chat_id': widget.chat.chatId,
        'mode': selection.mode.name,
        'live_minutes': selection.liveDuration?.inMinutes ?? 0,
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Konum gönderilemedi: $error')));
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Future<void> _pickSharedContact() async {
    if (_attachmentBusy) return;
    final payload = await Navigator.of(context).push<TurnaSharedContactPayload>(
      MaterialPageRoute<TurnaSharedContactPayload>(
        builder: (_) => const ContactSharePickerPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || payload == null) return;
    await _sendSharedContact(payload);
  }

  Future<void> _sendSharedContact(TurnaSharedContactPayload payload) async {
    if (_attachmentBusy) return;
    final replyDraft = _replyDraft;
    final outboundText = buildTurnaContactEncodedText(contact: payload);
    final encodedText = replyDraft == null
        ? outboundText
        : buildTurnaReplyEncodedText(reply: replyDraft, text: outboundText);
    setState(() => _attachmentBusy = true);

    try {
      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: widget.chat.chatId,
        text: encodedText,
      );
      if (!mounted) return;
      _client.mergeServerMessage(message);
      setState(() => _replyDraft = null);
      _jumpToBottom();
      await TurnaAnalytics.logEvent('contact_sent', {
        'chat_id': widget.chat.chatId,
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kişi gönderilemedi: $error')));
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Future<void> _stopLiveLocation(
    ChatMessage msg,
    TurnaLocationPayload payload,
  ) async {
    if (_attachmentBusy) return;
    if (!payload.isLiveActive || (payload.liveId?.trim().isEmpty ?? true)) {
      return;
    }
    setState(() => _attachmentBusy = true);
    try {
      await TurnaLiveLocationManager.instance.stopShare(msg.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Canlı konum durduruldu.')));
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  String _formatVoiceDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Duration get _voiceDuration => _voiceStopwatch.elapsed;

  void _tickVoiceRecording() {
    if (!mounted || !_voiceRecording || _voiceRecordingPaused) return;
    setState(() {});
  }

  void _resetVoiceRecordingState() {
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;
    _voiceStopwatch
      ..stop()
      ..reset();
    _voiceRecording = false;
    _voiceRecordingLocked = false;
    _voiceRecordingPaused = false;
    _voiceSlideCancelArmed = false;
    _voiceSlideProgress = 0;
    _voiceRecordingPath = null;
  }

  Future<void> _startVoiceRecording() async {
    if (_attachmentBusy ||
        _voiceRecorderBusy ||
        _voiceRecording ||
        _hasComposerText ||
        _editingDraft != null) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _voiceRecorderBusy = true);

    try {
      final hasPermission = await _voiceRecorder.hasPermission();
      if (!hasPermission) {
        throw TurnaApiException(
          'Ses kaydı için mikrofon izni vermen gerekiyor.',
        );
      }

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'turna-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${tempDir.path}/$fileName';

      await _voiceRecorder.start(
        const rec.RecordConfig(
          encoder: rec.AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _voiceRecordTimer?.cancel();
      _voiceStopwatch
        ..reset()
        ..start();
      _voiceRecordTimer = Timer.periodic(
        _voiceRecordTick,
        (_) => _tickVoiceRecording(),
      );

      if (!mounted) return;
      setState(() {
        _voiceRecording = true;
        _voiceRecordingLocked = false;
        _voiceRecordingPaused = false;
        _voiceSlideCancelArmed = false;
        _voiceSlideProgress = 0;
        _voiceRecordingPath = path;
        _voiceRecorderBusy = false;
      });
    } on TurnaApiException catch (error) {
      if (!mounted) return;
      setState(() => _voiceRecorderBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _voiceRecorderBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ses kaydı başlatılamadı.')));
      turnaLog('voice record start failed', error);
    }
  }

  void _updateVoiceRecordingGesture(Offset delta) {
    if (!_voiceRecording || _voiceRecordingLocked) return;
    final slideProgress = ((-delta.dx) / _voiceCancelThreshold).clamp(0.0, 1.0);
    final lockProgress = ((-delta.dy) / _voiceLockThreshold).clamp(0.0, 1.0);
    if (lockProgress >= 1) {
      setState(() {
        _voiceRecordingLocked = true;
        _voiceSlideCancelArmed = false;
        _voiceSlideProgress = 0;
      });
      return;
    }
    setState(() {
      _voiceSlideProgress = slideProgress;
      _voiceSlideCancelArmed = slideProgress >= 1;
    });
  }

  bool _isVoiceMicHit(Offset globalPosition) {
    final context = _voiceMicKey.currentContext;
    if (context == null) return false;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return false;
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;
    return rect.contains(globalPosition);
  }

  void _handleComposerPointerDown(PointerDownEvent event) {
    if (_attachmentBusy ||
        _voiceRecorderBusy ||
        _hasComposerText ||
        _editingDraft != null) {
      return;
    }
    if (!_isVoiceMicHit(event.position)) return;
    _voicePointerId = event.pointer;
    _voicePointerOriginGlobal = event.position;
  }

  void _handleComposerPointerMove(PointerMoveEvent event) {
    if (_voicePointerId != event.pointer) return;
    final origin = _voicePointerOriginGlobal;
    if (origin == null) return;
    _updateVoiceRecordingGesture(event.position - origin);
  }

  Future<void> _handleComposerPointerUp(PointerUpEvent event) async {
    if (_voicePointerId != event.pointer) return;
    _voicePointerId = null;
    _voicePointerOriginGlobal = null;
    if (!_voiceRecording || _voiceRecordingLocked) return;
    await _handleVoiceRecordingRelease();
  }

  Future<void> _handleComposerPointerCancel(PointerCancelEvent event) async {
    if (_voicePointerId != event.pointer) return;
    _voicePointerId = null;
    _voicePointerOriginGlobal = null;
    if (!_voiceRecording || _voiceRecordingLocked) return;
    await _cancelVoiceRecording();
  }

  Future<void> _handleVoiceRecordingRelease() async {
    if (!_voiceRecording) return;
    if (_voiceRecordingLocked) return;
    if (_voiceSlideCancelArmed) {
      await _cancelVoiceRecording();
      return;
    }
    await _finishVoiceRecording(send: true);
  }

  Future<void> _toggleLockedVoicePause() async {
    if (!_voiceRecording || !_voiceRecordingLocked || _voiceRecorderBusy) {
      return;
    }
    setState(() => _voiceRecorderBusy = true);
    try {
      if (_voiceRecordingPaused) {
        await _voiceRecorder.resume();
        _voiceStopwatch.start();
      } else {
        await _voiceRecorder.pause();
        _voiceStopwatch.stop();
      }
      if (!mounted) return;
      setState(() {
        _voiceRecordingPaused = !_voiceRecordingPaused;
        _voiceRecorderBusy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _voiceRecorderBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ses kaydı güncellenemedi.')),
      );
      turnaLog('voice record pause toggle failed', error);
    }
  }

  Future<void> _cancelVoiceRecording({bool showFeedback = false}) async {
    final path = _voiceRecordingPath;
    _voiceRecordTimer?.cancel();
    _voiceStopwatch.stop();
    try {
      await _voiceRecorder.cancel();
    } catch (error) {
      turnaLog('voice record cancel failed', error);
    }
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _voiceRecorderBusy = false;
      _resetVoiceRecordingState();
    });
    if (showFeedback) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ses kaydı silindi.')));
    }
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    if (_voiceRecorderBusy) return;
    if (mounted) {
      setState(() => _voiceRecorderBusy = true);
    } else {
      _voiceRecorderBusy = true;
    }
    final capturedDuration = _voiceDuration;
    final fallbackPath = _voiceRecordingPath;
    _voiceRecordTimer?.cancel();
    _voiceStopwatch.stop();

    String? resolvedPath;
    try {
      resolvedPath = send ? await _voiceRecorder.stop() : null;
    } catch (error) {
      turnaLog('voice record stop failed', error);
    }

    if (mounted) {
      setState(() {
        _voiceRecorderBusy = false;
        _resetVoiceRecordingState();
      });
    } else {
      _resetVoiceRecordingState();
    }

    final path = resolvedPath ?? fallbackPath;
    if (!send || path == null || path.trim().isEmpty) return;

    if (capturedDuration < _voiceMinDuration) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ses kaydı çok kısa.')));
      }
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ses kaydı bulunamadı.')));
      }
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ses kaydı boş geldi.')));
      }
      return;
    }

    await _sendPickedAttachment(
      kind: ChatAttachmentKind.file,
      fileName: 'sesli-mesaj-${DateTime.now().millisecondsSinceEpoch}.m4a',
      contentType: 'audio/mp4',
      readBytes: () async => bytes,
      sizeBytes: bytes.length,
      durationSeconds: math.max(1, capturedDuration.inSeconds),
    );

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _loadPinnedMessages() async {
    if (!_isGroupChat) return;
    try {
      final items = await ChatApi.fetchPinnedMessages(
        widget.session,
        chatId: widget.chat.chatId,
      );
      if (!mounted) return;
      _client.setPinnedMessages(items);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      turnaLog('chat pinned messages load failed', error);
    }
  }

  Future<void> _refreshPinnedMessagesIfAffected(String messageId) async {
    if (!_isGroupChat) return;
    if (!_client.pinnedMessages.any((item) => item.messageId == messageId)) {
      return;
    }
    await _loadPinnedMessages();
  }

  Future<void> _loadMentionCandidates() async {
    if (!_isGroupChat) return;
    try {
      final page = await ChatApi.fetchGroupMembers(
        widget.session,
        chatId: widget.chat.chatId,
        limit: 120,
      );
      if (!mounted) return;
      setState(() {
        _mentionCandidates = page.items
            .where((item) => item.userId != widget.session.userId)
            .toList();
      });
      _updateMentionSuggestions(_controller.text);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      turnaLog('chat mention candidates load failed', error);
    }
  }

  Future<void> _loadSecurityBannerState() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadySeen = prefs.getBool(_securityBannerSeenKey) == true;
    if (!mounted || alreadySeen) return;
    setState(() => _showSecurityBanner = true);
    await prefs.setBool(_securityBannerSeenKey, true);
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
              child: const Text('Vazgeç'),
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

  void _updateMentionSuggestions(String text) {
    if (!_isGroupChat || !_composerFocusNode.hasFocus) {
      if (_activeMentionQuery != null || _mentionSuggestions.isNotEmpty) {
        setState(() {
          _activeMentionQuery = null;
          _mentionSuggestions = const [];
        });
      }
      return;
    }

    final selection = _controller.selection;
    final safeCursor = selection.isValid
        ? selection.baseOffset.clamp(0, text.length).toInt()
        : text.length;
    final prefix = text.substring(0, safeCursor);
    final match = RegExp(
      r'(?:^|\s)@([a-z0-9._]{0,24})$',
      caseSensitive: false,
    ).firstMatch(prefix);

    if (match == null) {
      if (_activeMentionQuery != null || _mentionSuggestions.isNotEmpty) {
        setState(() {
          _activeMentionQuery = null;
          _mentionSuggestions = const [];
        });
      }
      return;
    }

    final query = (match.group(1) ?? '').trim().toLowerCase();
    final suggestions = _mentionCandidates
        .where((member) {
          final username = (member.username ?? '').trim().toLowerCase();
          final displayName = member.displayName.trim().toLowerCase();
          if (query.isEmpty) return true;
          return username.startsWith(query) ||
              displayName.startsWith(query) ||
              displayName.contains(query);
        })
        .take(6)
        .toList();

    final sameQuery = _activeMentionQuery == query;
    final sameSuggestions =
        _mentionSuggestions.length == suggestions.length &&
        _mentionSuggestions.asMap().entries.every(
          (entry) => entry.value.userId == suggestions[entry.key].userId,
        );
    if (sameQuery && sameSuggestions) return;
    if (!mounted) return;
    setState(() {
      _activeMentionQuery = query;
      _mentionSuggestions = suggestions;
    });
  }

  String _mentionInsertTextFor(TurnaGroupMember member) {
    final username = member.username?.trim();
    if (username != null && username.isNotEmpty) {
      return '@$username ';
    }
    final fallback = member.displayName.trim().split(RegExp(r'\s+')).first;
    return '@$fallback ';
  }

  void _insertMentionCandidate(TurnaGroupMember member) {
    final text = _controller.text;
    final selection = _controller.selection;
    final safeCursor = selection.isValid
        ? selection.baseOffset.clamp(0, text.length).toInt()
        : text.length;

    var tokenStart = safeCursor - 1;
    while (tokenStart >= 0 && !RegExp(r'\s').hasMatch(text[tokenStart])) {
      tokenStart -= 1;
    }
    tokenStart += 1;
    if (tokenStart >= text.length || text[tokenStart] != '@') return;

    final replacement = _mentionInsertTextFor(member);
    final nextText =
        '${text.substring(0, tokenStart)}$replacement${text.substring(safeCursor)}';
    final nextCursor = tokenStart + replacement.length;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
    _composerFocusNode.requestFocus();
    _updateMentionSuggestions(nextText);
  }

  String _previewSnippetForMessage(ChatMessage msg) {
    if (_isSystemMessage(msg)) {
      return _systemMessageText(msg);
    }
    final resolved = _resolveMessageText(msg);
    final parsed = resolved.parsed;
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      return 'Silindi.';
    }
    if (parsed.location != null) {
      return parsed.location!.previewLabel;
    }
    if (parsed.contact != null) {
      return parsed.contact!.previewLabel;
    }
    final text = resolved.trimmedText;
    if (text.isNotEmpty) {
      return text.length > 72 ? '${text.substring(0, 72)}...' : text;
    }
    if (msg.attachments.isEmpty) return 'Mesaj';
    final first = msg.attachments.first;
    if (_isAudioAttachment(first)) return 'Ses kaydı';
    if (_isImageAttachment(first)) return 'Fotoğraf';
    if (_isVideoAttachment(first)) return 'Video';
    return 'Dosya';
  }

  TurnaReplyPayload _replyPayloadForMessage(ChatMessage msg) {
    final mine = msg.senderId == widget.session.userId;
    return TurnaReplyPayload(
      messageId: msg.id,
      senderLabel: mine ? 'Siz' : _displaySenderNameFor(msg),
      previewText: _previewSnippetForMessage(msg),
    );
  }

  ChatMessage? _findReplyTargetMessage(String messageId) {
    for (final message in _client.messages) {
      if (message.id == messageId && !_deletedMessageIds.contains(message.id)) {
        return message;
      }
    }
    return null;
  }

  ChatMessage _messageForPinnedSummary(TurnaPinnedMessageSummary summary) {
    return _client.messages.firstWhere(
      (message) => message.id == summary.messageId,
      orElse: () => ChatMessage(
        id: summary.messageId,
        senderId: summary.senderId,
        text: summary.previewText,
        status: ChatMessageStatus.sent,
        createdAt: summary.messageCreatedAt,
        senderDisplayName: summary.senderDisplayName,
        isPinned: true,
      ),
    );
  }

  ChatAttachment? _replyVisualAttachmentForMessage(ChatMessage? message) {
    if (message == null) return null;
    for (final attachment in message.attachments) {
      if (_isImageAttachment(attachment) || _isVideoAttachment(attachment)) {
        return attachment;
      }
    }
    return null;
  }

  String _replySenderLabel(
    TurnaReplyPayload reply, {
    ChatMessage? targetMessage,
  }) {
    if (targetMessage != null) {
      return targetMessage.senderId == widget.session.userId
          ? 'Siz'
          : _displaySenderNameFor(targetMessage);
    }
    final label = reply.senderLabel.trim();
    return label == 'Sen' ? 'Siz' : label;
  }

  bool _isSystemMessage(ChatMessage msg) {
    final systemType = msg.systemType?.trim() ?? '';
    return systemType.isNotEmpty;
  }

  bool _isAdminNoticeMessage(ChatMessage msg) {
    final systemType = (msg.systemType ?? '').trim();
    return systemType == 'admin_notice' || systemType == 'admin_notice_silent';
  }

  String _systemMessageText(ChatMessage msg) {
    switch ((msg.systemType ?? '').trim()) {
      case 'admin_notice':
      case 'admin_notice_silent':
        final payload = msg.systemPayload ?? const <String, dynamic>{};
        final title = (payload['title'] ?? '').toString().trim();
        final text = (payload['text'] ?? msg.text).toString().trim();
        return title.isNotEmpty
            ? title
            : (text.isNotEmpty ? text : 'Bilgi notu');
      case 'group_created':
        final creator = (msg.systemPayload?['createdByDisplayName'] ?? '')
            .toString()
            .trim();
        return creator.isEmpty
            ? 'Grup oluşturuldu'
            : 'Grup oluşturuldu - $creator tarafından';
      case 'group_members_added':
        final raw = msg.systemPayload?['memberNames'];
        final names = raw is List
            ? raw
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty)
                  .toList()
            : const <String>[];
        if (names.isEmpty) return 'Yeni üyeler eklendi';
        if (names.length == 1) return '${names.first} gruba eklendi';
        if (names.length == 2) {
          return '${names.first} ve ${names.last} gruba eklendi';
        }
        return '${names.first} ve ${names.length - 1} kişi daha gruba eklendi';
      case 'group_member_left':
        final member = (msg.systemPayload?['leftByDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Bir üye gruptan ayrıldı'
            : '$member gruptan ayrıldı';
      case 'group_member_removed':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Bir üye gruptan çıkarıldı'
            : '$member gruptan çıkarıldı';
      case 'group_info_updated':
        return 'Grup bilgileri güncellendi';
      case 'group_settings_updated':
        return 'Grup ayarları güncellendi';
      case 'group_role_updated':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        final role = (msg.systemPayload?['roleLabel'] ?? '').toString().trim();
        if (member.isEmpty && role.isEmpty) {
          return 'Üye rolü güncellendi';
        }
        if (member.isEmpty) {
          return 'Rol $role olarak güncellendi';
        }
        if (role.isEmpty) {
          return '$member rolü güncellendi';
        }
        return '$member artık $role';
      case 'group_owner_transferred':
        final member = (msg.systemPayload?['newOwnerDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Grup sahipliği devredildi'
            : 'Grup sahipliği $member kişisine devredildi';
      case 'group_join_request_created':
        return 'Katılım isteği gönderildi';
      case 'group_join_request_approved':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Katılım isteği onaylandı'
            : '$member gruba kabul edildi';
      case 'group_member_muted':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Bir üye sessize alındı'
            : '$member sessize alındı';
      case 'group_member_unmuted':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Sessiz kullanıcı kaldırıldı'
            : '$member tekrar konuşabilir';
      case 'group_member_banned':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Bir üye gruptan yasaklandı'
            : '$member gruptan yasaklandı';
      case 'group_member_unbanned':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Yasak kaldırıldı'
            : '$member yasağı kaldırıldı';
      default:
        return msg.text.trim().isEmpty ? 'Sistem mesajı' : msg.text.trim();
    }
  }

  IconData _adminNoticeIcon(ChatMessage msg) {
    final icon = (msg.systemPayload?['icon'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    switch (icon) {
      case 'lock':
        return Icons.lock_rounded;
      case 'megaphone':
        return Icons.campaign_rounded;
      case 'shield':
        return Icons.shield_moon_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'sparkles':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  ({Color background, Color border, Color foreground}) _adminNoticeColors(
    ChatMessage msg,
  ) {
    final icon = (msg.systemPayload?['icon'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    switch (icon) {
      case 'lock':
        return (
          background: const Color(0xFFFFF3D6),
          border: const Color(0xFFF1D493),
          foreground: const Color(0xFF6E5617),
        );
      case 'megaphone':
        return (
          background: const Color(0xFFEAF4FF),
          border: const Color(0xFFB9D8FF),
          foreground: const Color(0xFF245E9C),
        );
      case 'shield':
        return (
          background: const Color(0xFFEAF5EF),
          border: const Color(0xFFB9DEC8),
          foreground: const Color(0xFF2A6B47),
        );
      case 'warning':
        return (
          background: const Color(0xFFFFEFE5),
          border: const Color(0xFFF5C9AF),
          foreground: const Color(0xFF9B4A19),
        );
      case 'sparkles':
        return (
          background: const Color(0xFFF6EEFF),
          border: const Color(0xFFD8C5F4),
          foreground: const Color(0xFF69469D),
        );
      default:
        return (
          background: const Color(0xFFF1F4F8),
          border: const Color(0xFFD6DEE8),
          foreground: const Color(0xFF526271),
        );
    }
  }

  Widget _buildAdminNoticeBubble(ChatMessage msg) {
    final payload = msg.systemPayload ?? const <String, dynamic>{};
    final title = (payload['title'] ?? '').toString().trim();
    final text = (payload['text'] ?? msg.text).toString().trim();
    final colors = _adminNoticeColors(msg);
    final hasTitle = title.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 304),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              crossAxisAlignment: hasTitle
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: colors.foreground.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _adminNoticeIcon(msg),
                    size: 14,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: hasTitle
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.foreground,
                              ),
                            ),
                            if (text.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                text,
                                style: TextStyle(
                                  fontSize: 12.35,
                                  height: 1.3,
                                  fontWeight: FontWeight.w500,
                                  color: colors.foreground,
                                ),
                              ),
                            ],
                          ],
                        )
                      : Text(
                          text.isNotEmpty ? text : 'Bilgi notu',
                          style: TextStyle(
                            fontSize: 12.35,
                            height: 1.28,
                            fontWeight: FontWeight.w600,
                            color: colors.foreground,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _displaySenderNameFor(ChatMessage msg) {
    final raw = (msg.senderDisplayName ?? '').trim();
    if (raw.isNotEmpty) return raw;
    if (msg.senderId == widget.session.userId) return 'Siz';
    return _chatDisplayName;
  }

  bool _canEditMessage(ChatMessage msg, {ParsedTurnaMessageText? parsed}) {
    final resolved = parsed ?? _resolveMessageText(msg).parsed;
    if (msg.senderId != widget.session.userId) return false;
    if (_isMessageDeletedPlaceholder(msg, parsed: resolved)) return false;
    if (resolved.text.trim().isEmpty) return false;
    final createdAt = parseTurnaLocalDateTime(msg.createdAt);
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt).inMinutes < 10;
  }

  void _startEditingMessage(ChatMessage msg, ParsedTurnaMessageText parsed) {
    final visibleText = parsed.text.trim();
    setState(() {
      _replyDraft = null;
      _editingDraft = _ComposerEditDraft(
        messageId: msg.id,
        reply: parsed.reply,
        originalText: visibleText,
      );
      _controller.value = TextEditingValue(
        text: visibleText,
        selection: TextSelection.collapsed(offset: visibleText.length),
      );
    });
    _composerFocusNode.requestFocus();
  }

  void _cancelEditingMessage() {
    if (_editingDraft == null) return;
    setState(() {
      _editingDraft = null;
      _controller.clear();
    });
  }

  Future<File> _downloadAttachmentFile(ChatAttachment attachment) async {
    final url = attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      throw TurnaApiException('Ek için link bulunamadı.');
    }

    final cachedFile = await TurnaLocalMediaCache.getOrDownloadFile(
      cacheKey: 'attachment:${attachment.objectKey}',
      url: url,
      authToken: widget.session.token,
    );
    if (cachedFile != null) {
      return cachedFile;
    }

    throw TurnaApiException('Ek indirilemedi.');
  }

  Future<List<int>> _downloadAttachmentBytes(ChatAttachment attachment) async {
    final file = await _downloadAttachmentFile(attachment);
    return file.readAsBytes();
  }

  Future<void> _saveAttachmentToDevice(ChatAttachment attachment) async {
    try {
      final file = await _downloadAttachmentFile(attachment);
      await TurnaMediaBridge.saveToGallery(
        path: file.path,
        mimeType: attachment.contentType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Medya cihaza kaydedildi.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  List<ChatGalleryMediaItem> _buildMediaGalleryItems() {
    final items = <ChatGalleryMediaItem>[];
    for (final message in _currentDisplayMessages()) {
      final resolved = _resolveMessageText(message);
      if (_isMessageDeletedPlaceholder(message, parsed: resolved.parsed)) {
        continue;
      }
      for (final attachment in message.attachments) {
        if (!_isImageAttachment(attachment) &&
            !_isVideoAttachment(attachment)) {
          continue;
        }
        final url = attachment.url?.trim() ?? '';
        if (url.isEmpty) continue;
        items.add(
          ChatGalleryMediaItem(
            message: message,
            attachment: attachment,
            senderLabel: message.senderId == widget.session.userId
                ? 'Siz'
                : _displaySenderNameFor(message),
            cacheKey: 'attachment:${attachment.objectKey}',
            url: url,
          ),
        );
      }
    }
    return items;
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
      final parsed = _resolveMessageText(msg).parsed;
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
          throw TurnaApiException('İletilecek ek yüklenemedi.');
        }
        drafts.add(
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: attachment.kind,
            transferMode: attachment.transferMode,
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
          nowStarred ? 'Mesaja yıldız eklendi.' : 'Yıldız kaldırıldı.',
        ),
      ),
    );
  }

  Future<void> _deleteMessageLocally(ChatMessage msg) async {
    final next = Set<String>.from(_deletedMessageIds)..add(msg.id);
    final nextStarred = Set<String>.from(_starredMessageIds)..remove(msg.id);
    final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
      ..remove(msg.id);
    setState(() {
      _deletedMessageIds = next;
      _starredMessageIds = nextStarred;
      _softDeletedMessageIds = nextSoftDeleted;
      if (_editingDraft?.messageId == msg.id) {
        _editingDraft = null;
        _controller.clear();
      }
    });
    await _persistSoftDeletedMessages();
    await _persistDeletedMessages();
    await _persistStarredMessages();
    await _refreshPinnedMessagesIfAffected(msg.id);
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
      if (_editingDraft?.messageId == msg.id) {
        _editingDraft = null;
        _controller.clear();
      }
    });
    await _persistSoftDeletedMessages();
    await _persistStarredMessages();
    await _refreshPinnedMessagesIfAffected(msg.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mesaj sende Silindi. olarak gösteriliyor.'),
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
        setState(() {
          _softDeletedMessageIds = nextSoftDeleted;
          if (_editingDraft?.messageId == msg.id) {
            _editingDraft = null;
            _controller.clear();
          }
        });
      }
      await _persistSoftDeletedMessages();
      await _refreshPinnedMessagesIfAffected(msg.id);
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
      title: 'Mesajı kaldır',
      message: 'Bu Silindi. mesajı cihazından tamamen kaldırılsın mı?',
      confirmLabel: 'Kaldır',
    );
    if (!confirmed) return;
    await _deleteMessageLocally(msg);
  }

  Future<void> _showDeleteMessageOptions(ChatMessage msg) async {
    final parsed = _resolveMessageText(msg).parsed;
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
                        'Bu mesaj sadece senin tarafında Silindi. olarak gösterilecek.',
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
                          'Bu mesaj iki taraf için de Silindi. olarak değişecek.',
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
    final text = _resolveMessageText(msg).trimmedText;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çevrilecek metin bulunamadı.')),
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
      ).showSnackBar(const SnackBar(content: Text('Çeviri açılamadı.')));
    }
  }

  Future<void> _reportMessage(ChatMessage msg) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        const reasons = ['Spam', 'Taciz', 'Uygunsuz içerik', 'Sahte hesap'];
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
    ).showSnackBar(SnackBar(content: Text('Şikayet kaydedildi: $reason')));
  }

  String _messageStatusLabel(ChatMessageStatus status) {
    return switch (status) {
      ChatMessageStatus.sending => 'Gönderiliyor',
      ChatMessageStatus.queued => 'Kuyrukta',
      ChatMessageStatus.failed => 'Hatalı',
      ChatMessageStatus.sent => 'Gönderildi',
      ChatMessageStatus.delivered => 'Teslim edildi',
      ChatMessageStatus.read => 'Okundu',
    };
  }

  String _messageTypeLabel(ChatMessage msg, ParsedTurnaMessageText parsed) {
    if (parsed.location != null) {
      return parsed.location!.live ? 'Canlı konum' : 'Konum';
    }
    if (parsed.contact != null) return 'Kişi';
    if (msg.attachments.isNotEmpty) {
      final first = msg.attachments.first;
      if (_isAudioAttachment(first)) return 'Ses kaydı';
      if (_isImageAttachment(first)) return 'Fotoğraf';
      if (_isVideoAttachment(first)) return 'Video';
      return 'Belge';
    }
    return 'Mesaj';
  }

  Future<void> _showMessageInfo(ChatMessage msg) async {
    final parsed = _resolveMessageText(msg).parsed;
    final totalBytes = msg.attachments.fold<int>(
      0,
      (total, item) => total + math.max(0, item.sizeBytes),
    );
    final detailRows = <MapEntry<String, String>>[
      MapEntry('Tür', _messageTypeLabel(msg, parsed)),
      MapEntry(
        'Tarih',
        '${_formatDayLabel(msg.createdAt)} ${_formatMessageTime(msg.createdAt)}',
      ),
      MapEntry('Durum', _messageStatusLabel(msg.status)),
      if (msg.attachments.isNotEmpty)
        MapEntry('Ek sayısı', '${msg.attachments.length}'),
      if (totalBytes > 0) MapEntry('Boyut', _formatFileSize(totalBytes)),
      if (msg.attachments.length == 1 &&
          _isAudioAttachment(msg.attachments.first) &&
          (msg.attachments.first.durationSeconds ?? 0) > 0)
        MapEntry(
          'Süre',
          _formatVoiceDuration(
            Duration(seconds: msg.attachments.first.durationSeconds!),
          ),
        ),
      if (msg.isEdited && (msg.editedAt?.trim().isNotEmpty ?? false))
        MapEntry(
          'Düzenlendi',
          '${_formatDayLabel(msg.editedAt!)} ${_formatMessageTime(msg.editedAt!)}',
        ),
    ];

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mesaj bilgisi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final row in detailRows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 88,
                          child: Text(
                            row.key,
                            style: const TextStyle(
                              color: TurnaColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.value,
                            style: const TextStyle(
                              color: TurnaColors.text,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const List<String> _reactionOptions = <String>[
    '👍',
    '❤️',
    '😂',
    '🔥',
    '👏',
    '😮',
    '😢',
    '🙏',
  ];

  bool _messageHasMyReaction(ChatMessage msg, String emoji) {
    return msg.reactions.any(
      (reaction) =>
          reaction.emoji == emoji &&
          reaction.userIds.contains(widget.session.userId),
    );
  }

  Future<void> _toggleReaction(ChatMessage msg, String emoji) async {
    try {
      final updated = _messageHasMyReaction(msg, emoji)
          ? await ChatApi.removeReaction(
              widget.session,
              messageId: msg.id,
              emoji: emoji,
            )
          : await ChatApi.addReaction(
              widget.session,
              messageId: msg.id,
              emoji: emoji,
            );
      _client.mergeServerMessage(updated);
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

  Future<void> _showReactionPicker(ChatMessage msg) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tepki sec',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _reactionOptions.map((emoji) {
                    final selected = _messageHasMyReaction(msg, emoji);
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _toggleReaction(msg, emoji);
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? TurnaColors.primary50
                              : TurnaColors.backgroundMuted,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : TurnaColors.border,
                          ),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _togglePinnedMessage(ChatMessage msg) async {
    if (!_isGroupChat) return;
    final isPinned =
        msg.isPinned ||
        _client.pinnedMessages.any((item) => item.messageId == msg.id);
    try {
      if (isPinned) {
        await ChatApi.unpinMessage(widget.session, messageId: msg.id);
      } else {
        await ChatApi.pinMessage(widget.session, messageId: msg.id);
      }
      await _loadPinnedMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPinned ? 'Sabit mesaj kaldırıldı.' : 'Mesaj sabitlendi.',
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

  Future<void> _openPinnedMessagesSheet() async {
    final pinnedMessages = _client.pinnedMessages;
    if (pinnedMessages.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sabit mesajlar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: math.min(
                    MediaQuery.of(sheetContext).size.height * 0.48,
                    math.max(88, pinnedMessages.length * 78).toDouble(),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: pinnedMessages.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: TurnaColors.divider),
                    itemBuilder: (context, index) {
                      final item = pinnedMessages[index];
                      final pinnedBy =
                          (item.pinnedByDisplayName ?? '').trim().isNotEmpty
                          ? item.pinnedByDisplayName!.trim()
                          : 'Birisi';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.push_pin_rounded,
                          color: TurnaColors.primary,
                        ),
                        title: Text(
                          item.previewText.trim().isEmpty
                              ? 'Sabit mesaj'
                              : item.previewText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$pinnedBy · ${_formatMessageTime(item.pinnedAt)}',
                        ),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _scrollToReplyTarget(item.messageId);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMoreMessageActions(ChatMessage msg) async {
    final parsed = _resolveMessageText(msg).parsed;
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      await _confirmRemoveDeletedPlaceholder(msg);
      return;
    }
    final isPinned =
        msg.isPinned ||
        _client.pinnedMessages.any((item) => item.messageId == msg.id);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isGroupChat)
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  ),
                  title: Text(isPinned ? 'Sabitlemeyi kaldır' : 'Sabitle'),
                  onTap: !_canManagePinnedMessages
                      ? null
                      : () async {
                          Navigator.pop(sheetContext);
                          await _togglePinnedMessage(msg);
                        },
                ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('Tepki ver'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReactionPicker(msg);
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
                title: const Text('Şikayet Et'),
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

  Future<void> _handleMessageLongPress(
    ChatMessage msg, {
    ChatAttachment? attachment,
  }) async {
    final parsed = _resolveMessageText(msg).parsed;
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      await _confirmRemoveDeletedPlaceholder(msg);
      return;
    }
    final replyPayload = _replyPayloadForMessage(msg);
    final isStarred = _starredMessageIds.contains(msg.id);
    final textOnly = parsed.text.trim();
    final canEdit = _canEditMessage(msg, parsed: parsed);
    final visualAttachment =
        attachment != null &&
            (_isImageAttachment(attachment) || _isVideoAttachment(attachment))
        ? attachment
        : msg.attachments.cast<ChatAttachment?>().firstWhere(
            (item) =>
                item != null &&
                (_isImageAttachment(item) || _isVideoAttachment(item)),
            orElse: () => null,
          );
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
                      icon: Icons.emoji_emotions_outlined,
                      label: 'Tepki',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showReactionPicker(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.reply_rounded,
                      label: 'Cevapla',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() {
                          _editingDraft = null;
                          _replyDraft = replyPayload;
                        });
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
                    if (canEdit)
                      _MessageQuickAction(
                        icon: Icons.edit_outlined,
                        label: 'Duzenle',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _startEditingMessage(msg, parsed);
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
                      label: isStarred ? 'Yıldızı kaldır' : 'Yıldız ekle',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _toggleStarMessage(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.info_outline_rounded,
                      label: 'Bilgi',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showMessageInfo(msg);
                      },
                    ),
                    if (visualAttachment != null)
                      _MessageQuickAction(
                        icon: Icons.download_rounded,
                        label: 'Kaydet',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _saveAttachmentToDevice(visualAttachment);
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

  void _trackMessageKey(String messageId) {
    if (_trackedMessageIds.remove(messageId)) {
      _trackedMessageKeyOrder.remove(messageId);
    }
    _trackedMessageIds.add(messageId);
    _trackedMessageKeyOrder.add(messageId);

    while (_trackedMessageKeyOrder.length > _trackedMessageKeyLimit) {
      final oldestMessageId = _trackedMessageKeyOrder.removeAt(0);
      if (oldestMessageId == _highlightedMessageId) {
        _trackedMessageKeyOrder.add(oldestMessageId);
        continue;
      }
      _trackedMessageIds.remove(oldestMessageId);
      _messageKeys.remove(oldestMessageId);
      break;
    }
  }

  List<ChatMessage> _currentDisplayMessages() {
    if (_hasCachedDisplayMessages &&
        _cachedMessagesRevision == _client.messagesRevision &&
        identical(_cachedDeletedMessageIdsRef, _deletedMessageIds)) {
      return _cachedDisplayMessages;
    }

    _cachedDisplayMessages = _client.messages.reversed
        .where((message) => !_deletedMessageIds.contains(message.id))
        .toList(growable: false);
    _cachedMessagesRevision = _client.messagesRevision;
    _cachedDeletedMessageIdsRef = _deletedMessageIds;
    _cachedPeerCallsRef = null;
    _hasCachedDisplayMessages = true;
    _hasCachedTimelineEntries = false;
    return _cachedDisplayMessages;
  }

  List<_ChatTimelineEntry> _buildTimelineEntries() {
    if (_hasCachedTimelineEntries &&
        _cachedMessagesRevision == _client.messagesRevision &&
        identical(_cachedDeletedMessageIdsRef, _deletedMessageIds) &&
        identical(_cachedPeerCallsRef, _peerCalls)) {
      return _cachedTimelineEntries;
    }

    final entries = <_ChatTimelineEntry>[
      ..._currentDisplayMessages().map(_ChatTimelineEntry.message),
      ..._peerCalls.map(_ChatTimelineEntry.call),
    ];
    entries.sort(
      (a, b) =>
          compareTurnaTimestamps(_timelineCreatedAt(b), _timelineCreatedAt(a)),
    );
    _cachedTimelineEntries = List<_ChatTimelineEntry>.unmodifiable(entries);
    _cachedPeerCallsRef = _peerCalls;
    _hasCachedTimelineEntries = true;
    return _cachedTimelineEntries;
  }

  GlobalKey? _messageKeyFor(String messageId) {
    if (!_trackedMessageIds.contains(messageId)) return null;
    return _messageKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    return completer.future;
  }

  void _highlightMessage(String messageId) {
    _messageHighlightTimer?.cancel();
    _trackMessageKey(messageId);
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
        const SnackBar(content: Text('Yanıtlanan mesaj bulunamadı.')),
      );
      return;
    }

    _highlightMessage(messageId);
    if (!_trackedMessageIds.contains(messageId)) {
      setState(() => _trackMessageKey(messageId));
      await _waitForNextFrame();
      if (!mounted) return;
    }
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
    final editingDraft = _editingDraft;
    if (editingDraft != null) {
      final outboundText = editingDraft.reply == null
          ? text
          : buildTurnaReplyEncodedText(reply: editingDraft.reply!, text: text);
      try {
        final updated = await ChatApi.editMessage(
          widget.session,
          messageId: editingDraft.messageId,
          text: outboundText,
        );
        _client.mergeServerMessage(updated);
        await _refreshPinnedMessagesIfAffected(updated.id);
        if (!mounted) return;
        setState(() => _editingDraft = null);
        _controller.clear();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Mesaj duzenlendi.')));
        return;
      } on TurnaUnauthorizedException {
        if (!mounted) return;
        widget.onSessionExpired();
        return;
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        return;
      }
    }

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
        return 'Cevapsız';
      case TurnaCallStatus.cancelled:
        return 'İptal edildi';
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
          boxShadow: const [TurnaColors.shadowBubble],
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

  Widget _buildSystemMessageBubble(ChatMessage msg) {
    if (_isAdminNoticeMessage(msg)) {
      return _buildAdminNoticeBubble(msg);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: TurnaColors.backgroundMuted,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: TurnaColors.divider),
          ),
          child: Text(
            _systemMessageText(msg),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: TurnaColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityBanner() {
    final message = _isGroupChat
        ? 'Mesajlar ve aramalar uçtan uca güvenli bağlantı kullanılarak iletilir ve gizliliğiniz korunur. Yalnızca bu gruptaki kişiler bu içerikleri okuyabilir, dinleyebilir veya paylaşabilir.'
        : 'Mesajlar ve aramalar uçtan uca güvenli bağlantı kullanılarak iletilir ve gizliliğiniz korunur. Yalnızca bu sohbetteki kişiler bu içerikleri okuyabilir, dinleyebilir veya paylaşabilir.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1D493)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_rounded, size: 16, color: Color(0xFF6E5617)),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Color(0xFF6E5617),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    ChatMessage msg,
    bool mine,
  ) {
    if (_isSystemMessage(msg)) {
      return _buildSystemMessageBubble(msg);
    }
    final resolved = _resolveMessageText(msg);
    final parsed = resolved.parsed;
    final isDeletedPlaceholder = _isMessageDeletedPlaceholder(
      msg,
      parsed: parsed,
    );
    final isPinnedMessage =
        msg.isPinned ||
        _client.pinnedMessages.any((item) => item.messageId == msg.id);
    final displayText = isDeletedPlaceholder
        ? 'Silindi.'
        : resolved.trimmedText;
    final locationPayload = isDeletedPlaceholder ? null : parsed.location;
    final contactPayload = isDeletedPlaceholder ? null : parsed.contact;
    final visibleAttachments = isDeletedPlaceholder
        ? const <ChatAttachment>[]
        : msg.attachments;
    final hasText = displayText.isNotEmpty;
    final hasLocation = locationPayload != null;
    final hasContact = contactPayload != null;
    final hasSingleAudioAttachment =
        visibleAttachments.length == 1 &&
        _isAudioAttachment(visibleAttachments.first);
    final hasSingleVisualAttachment =
        visibleAttachments.length == 1 &&
        !_isAudioAttachment(visibleAttachments.first) &&
        visibleAttachments.first.kind != ChatAttachmentKind.file;
    final hasError =
        !isDeletedPlaceholder &&
        msg.errorText != null &&
        msg.errorText!.trim().isNotEmpty;
    final primaryLinkUri = hasText ? resolved.primaryLinkUri : null;
    final linkCaptionText = hasText ? resolved.linkCaptionText : displayText;
    final showLinkPreview =
        primaryLinkUri != null &&
        !hasLocation &&
        !hasContact &&
        visibleAttachments.isEmpty &&
        !hasError;
    final previewUri = showLinkPreview ? primaryLinkUri : null;
    final showTextBlock =
        hasText && (!showLinkPreview || linkCaptionText.isNotEmpty);
    final useEmbeddedMediaBubble =
        !hasText &&
        !hasError &&
        parsed.reply == null &&
        (locationPayload != null ||
            contactPayload != null ||
            hasSingleVisualAttachment ||
            hasSingleAudioAttachment);
    final isHighlighted = _highlightedMessageId == msg.id;
    final footer = _MessageMetaFooter(
      timeLabel: _formatMessageTime(msg.createdAt),
      mine: mine,
      status: msg.status,
      edited: msg.isEdited,
      starred: _starredMessageIds.contains(msg.id),
    );
    final embeddedFooter = _MessageMetaFooter(
      timeLabel: _formatMessageTime(msg.createdAt),
      mine: mine,
      status: msg.status,
      edited: msg.isEdited,
      starred: _starredMessageIds.contains(msg.id),
      overlay: true,
    );
    final embeddedFooterPlain = _MessageMetaFooter(
      timeLabel: _formatMessageTime(msg.createdAt),
      mine: mine,
      status: msg.status,
      edited: msg.isEdited,
      starred: _starredMessageIds.contains(msg.id),
      overlay: true,
      showOverlayBackground: false,
    );
    final bubbleColor = mine
        ? (_isGroupChat ? const Color(0xFFD7F3E0) : TurnaColors.chatOutgoing)
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
          padding: useEmbeddedMediaBubble
              ? EdgeInsets.zero
              : EdgeInsets.fromLTRB(
                  12,
                  9,
                  12,
                  msg.attachments.isEmpty && !hasError ? 8 : 10,
                ),
          decoration: BoxDecoration(
            color: useEmbeddedMediaBubble
                ? Colors.transparent
                : resolvedBubbleColor,
            borderRadius: bubbleRadius,
            border: useEmbeddedMediaBubble ? null : bubbleBorder,
            boxShadow: [
              if (!useEmbeddedMediaBubble)
                mine
                    ? TurnaColors.shadowBubble
                    : const BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, 1),
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
              if (_isGroupChat && !mine) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _displaySenderNameFor(msg),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: TurnaColors.primary,
                    ),
                  ),
                ),
              ],
              if (isPinnedMessage)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.push_pin_rounded,
                        size: 12,
                        color: TurnaColors.primary,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Sabitlendi',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: TurnaColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
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
                Builder(
                  builder: (context) {
                    final replyTarget = _findReplyTargetMessage(
                      parsed.reply!.messageId,
                    );
                    return _ReplySnippetCard(
                      reply: parsed.reply!,
                      mine: mine,
                      senderLabel: _replySenderLabel(
                        parsed.reply!,
                        targetMessage: replyTarget,
                      ),
                      repliedToCurrentUser: replyTarget != null
                          ? replyTarget.senderId == widget.session.userId
                          : parsed.reply!.senderLabel.trim() == 'Sen' ||
                                parsed.reply!.senderLabel.trim() == 'Siz',
                      previewAttachment: _replyVisualAttachmentForMessage(
                        replyTarget,
                      ),
                      authToken: widget.session.token,
                      onTap: () =>
                          _scrollToReplyTarget(parsed.reply!.messageId),
                    );
                  },
                ),
                if (hasText ||
                    hasLocation ||
                    hasContact ||
                    visibleAttachments.isNotEmpty)
                  const SizedBox(height: 8),
              ],
              if (visibleAttachments.isNotEmpty) ...[
                _ChatAttachmentList(
                  attachments: visibleAttachments,
                  mine: mine,
                  onTap: (attachment) {
                    if (_isImageAttachment(attachment) ||
                        _isVideoAttachment(attachment)) {
                      return _openMediaAttachment(msg, attachment);
                    }
                    return _openAttachment(attachment);
                  },
                  formatFileSize: _formatFileSize,
                  authToken: widget.session.token,
                  onLongPress: (attachment) =>
                      _handleMessageLongPress(msg, attachment: attachment),
                  overlayFooter: useEmbeddedMediaBubble ? embeddedFooter : null,
                  audioOverlayFooter: useEmbeddedMediaBubble
                      ? embeddedFooterPlain
                      : null,
                ),
                if (hasText || hasLocation || hasContact)
                  const SizedBox(height: 8),
              ],
              if (locationPayload != null) ...[
                _TurnaLocationMessageCard(
                  payload: locationPayload,
                  mine: mine,
                  messageId: msg.id,
                  liveClient: _client,
                  overlayFooter: useEmbeddedMediaBubble ? embeddedFooter : null,
                  onStopShare: mine && locationPayload.isLiveActive
                      ? () => _stopLiveLocation(msg, locationPayload)
                      : null,
                ),
                if (hasText || hasContact) const SizedBox(height: 8),
              ],
              if (contactPayload != null) ...[
                _TurnaSharedContactMessageCard(
                  payload: contactPayload,
                  mine: mine,
                  session: widget.session,
                  callCoordinator: widget.callCoordinator,
                  onSessionExpired: widget.onSessionExpired,
                  overlayFooter: useEmbeddedMediaBubble
                      ? embeddedFooterPlain
                      : null,
                ),
                if (hasText) const SizedBox(height: 8),
              ],
              if (previewUri != null) ...[
                _TurnaMessageLinkPreviewCard(
                  uri: previewUri,
                  mine: mine,
                  onTap: () => _openSharedUri(previewUri),
                ),
                if (showTextBlock) const SizedBox(height: 8),
              ],
              if (showTextBlock)
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        right: mine ? 64 : 54,
                        bottom: 4,
                      ),
                      child: _buildLinkifiedMessageText(
                        showLinkPreview ? linkCaptionText : displayText,
                        mine: mine,
                      ),
                    ),
                    footer,
                  ],
                )
              else if (showLinkPreview)
                Align(alignment: Alignment.bottomRight, child: footer)
              else if (!useEmbeddedMediaBubble &&
                  (hasLocation ||
                      hasContact ||
                      visibleAttachments.isNotEmpty ||
                      hasError))
                Align(alignment: Alignment.bottomRight, child: footer),
              if (msg.reactions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: msg.reactions.map((reaction) {
                    final selected = reaction.userIds.contains(
                      widget.session.userId,
                    );
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _toggleReaction(msg, reaction.emoji),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? TurnaColors.primary50
                              : Colors.white.withValues(
                                  alpha: mine ? 0.54 : 0.9,
                                ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : TurnaColors.border,
                          ),
                        ),
                        child: Text(
                          '${reaction.emoji} ${reaction.count}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? TurnaColors.primaryStrong
                                : TurnaColors.text,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final focused = _composerFocusNode.hasFocus;
    final child = _voiceRecording
        ? SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _voiceSlideCancelArmed
                        ? TurnaColors.error.withValues(alpha: 0.32)
                        : TurnaColors.border,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: _voiceRecordingLocked
                    ? _buildLockedVoiceRecorderComposer()
                    : _buildHoldVoiceRecorderComposer(),
              ),
            ),
          )
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_editingDraft != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 48,
                        right: 54,
                        bottom: 8,
                      ),
                      child: _ComposerEditBanner(
                        draft: _editingDraft!,
                        onClose: _cancelEditingMessage,
                      ),
                    ),
                  if (_replyDraft != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 48,
                        right: 54,
                        bottom: 8,
                      ),
                      child: _ComposerReplyBanner(
                        reply: _replyDraft!,
                        onClose: () => setState(() => _replyDraft = null),
                      ),
                    ),
                  if (_mentionSuggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(
                        left: 48,
                        right: 54,
                        bottom: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: TurnaColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _mentionSuggestions.map((member) {
                          final username = (member.username ?? '').trim();
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: TurnaColors.primary50,
                              backgroundImage:
                                  (member.avatarUrl ?? '').trim().isNotEmpty
                                  ? NetworkImage(member.avatarUrl!.trim())
                                  : null,
                              child: (member.avatarUrl ?? '').trim().isEmpty
                                  ? Text(
                                      member.displayName.trim().isEmpty
                                          ? '?'
                                          : member.displayName
                                                .trim()[0]
                                                .toUpperCase(),
                                      style: const TextStyle(
                                        color: TurnaColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              member.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              username.isEmpty ? 'Uye' : '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _insertMentionCandidate(member),
                          );
                        }).toList(),
                      ),
                    ),
                  if (_groupSendRestrictionText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: TurnaColors.backgroundMuted,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: TurnaColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            color: TurnaColors.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _groupSendRestrictionText!,
                              style: const TextStyle(
                                color: TurnaColors.textSoft,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: _attachmentBusy
                              ? null
                              : _showAttachmentSheet,
                          icon: _attachmentBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      hintText: _editingDraft == null
                                          ? 'Mesaj'
                                          : 'Duzenlenmis mesaji yaz',
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 14,
                                          ),
                                    ),
                                  ),
                                ),
                                if (!_hasComposerText && _editingDraft == null)
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
                              : SizedBox(
                                  key: const ValueKey('mic'),
                                  width: 46,
                                  height: 46,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _attachmentBusy
                                        ? null
                                        : _showVoiceMessageHint,
                                    onLongPressStart: _attachmentBusy
                                        ? null
                                        : (_) =>
                                              unawaited(_startVoiceRecording()),
                                    child: Container(
                                      key: _voiceMicKey,
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.mic_none_rounded,
                                        color: _voiceRecorderBusy
                                            ? TurnaColors.textMuted
                                            : TurnaColors.textSoft,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleComposerPointerDown,
      onPointerMove: _handleComposerPointerMove,
      onPointerUp: (event) => unawaited(_handleComposerPointerUp(event)),
      onPointerCancel: (event) =>
          unawaited(_handleComposerPointerCancel(event)),
      child: child,
    );
  }

  Widget _buildHoldVoiceRecorderComposer() {
    final danger = _voiceSlideCancelArmed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: danger
                    ? TurnaColors.error.withValues(alpha: 0.14)
                    : TurnaColors.primary50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic_rounded,
                color: danger ? TurnaColors.error : TurnaColors.primary,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatVoiceDuration(_voiceDuration),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: TurnaColors.text,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: 1 - (_voiceSlideProgress * 0.45),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chevron_left_rounded,
                      size: 20,
                      color: danger ? TurnaColors.error : TurnaColors.textMuted,
                    ),
                    Text(
                      danger ? 'Bırakınca silinecek' : 'iptal için kaydır',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: danger
                            ? TurnaColors.error
                            : TurnaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: TurnaColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 46),
            Expanded(
              child: _VoiceWaveformStrip(
                color: danger ? TurnaColors.error : TurnaColors.primary,
                activeBars: math.min(
                  _VoiceWaveformStrip.barCount,
                  ((_voiceDuration.inMilliseconds / 180).floor() %
                          _VoiceWaveformStrip.barCount) +
                      4,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'yukarı kaydırıp kilitle',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: TurnaColors.textMuted.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLockedVoiceRecorderComposer() {
    final paused = _voiceRecordingPaused;
    return Row(
      children: [
        _VoiceComposerAction(
          icon: Icons.delete_outline_rounded,
          backgroundColor: TurnaColors.error.withValues(alpha: 0.12),
          foregroundColor: TurnaColors.error,
          onTap: _voiceRecorderBusy
              ? null
              : () => unawaited(_cancelVoiceRecording(showFeedback: true)),
        ),
        const SizedBox(width: 12),
        Text(
          _formatVoiceDuration(_voiceDuration),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: TurnaColors.text,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _VoiceWaveformStrip(
            color: paused ? TurnaColors.textMuted : TurnaColors.primary,
            activeBars: paused
                ? 4
                : math.min(
                    _VoiceWaveformStrip.barCount,
                    ((_voiceDuration.inMilliseconds / 180).floor() %
                            _VoiceWaveformStrip.barCount) +
                        4,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        _VoiceComposerAction(
          icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          backgroundColor: TurnaColors.primary50,
          foregroundColor: TurnaColors.primary,
          onTap: _voiceRecorderBusy
              ? null
              : () => unawaited(_toggleLockedVoicePause()),
        ),
        const SizedBox(width: 10),
        _VoiceComposerAction(
          icon: Icons.send_rounded,
          backgroundColor: const Color(0xFF111827),
          foregroundColor: Colors.white,
          onTap: _voiceRecorderBusy
              ? null
              : () => unawaited(_finishVoiceRecording(send: true)),
        ),
      ],
    );
  }

  Future<OutgoingAttachmentDraft> _uploadAttachmentDraft({
    required ChatAttachmentKind kind,
    required String fileName,
    required String contentType,
    ChatAttachmentTransferMode transferMode =
        ChatAttachmentTransferMode.standard,
    Future<List<int>> Function()? readBytes,
    String? filePath,
    int? sizeBytes,
    int? width,
    int? height,
    int? durationSeconds,
  }) async {
    final upload = await ChatApi.createAttachmentUpload(
      widget.session,
      chatId: widget.chat.chatId,
      kind: kind,
      contentType: contentType,
      fileName: fileName,
    );

    int resolvedSizeBytes = sizeBytes ?? 0;
    if (filePath != null && filePath.trim().isNotEmpty) {
      final file = File(filePath);
      if (!await file.exists()) {
        throw TurnaApiException('Dosya okunamadi.');
      }
      if (resolvedSizeBytes <= 0) {
        resolvedSizeBytes = await file.length();
      }
      final request = http.StreamedRequest('PUT', Uri.parse(upload.uploadUrl));
      request.headers.addAll(upload.headers);
      request.contentLength = resolvedSizeBytes;
      final responseFuture = request.send();
      await file.openRead().pipe(request.sink);
      final uploadRes = await responseFuture;
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Dosya yüklenemedi.');
      }
    } else {
      if (readBytes == null) {
        throw TurnaApiException('Dosya okunamadi.');
      }
      final bytes = await readBytes();
      resolvedSizeBytes = sizeBytes ?? bytes.length;
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Dosya yüklenemedi.');
      }
    }

    return OutgoingAttachmentDraft(
      objectKey: upload.objectKey,
      kind: kind,
      transferMode: transferMode,
      fileName: fileName,
      contentType: contentType,
      sizeBytes: resolvedSizeBytes,
      width: width,
      height: height,
      durationSeconds: durationSeconds,
    );
  }

  Future<void> _sendAttachmentDrafts(
    List<OutgoingAttachmentDraft> drafts,
  ) async {
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
      attachments: drafts,
    );

    if (!mounted) return;
    _client.mergeServerMessage(message);
    _controller.clear();
    setState(() => _replyDraft = null);
    _jumpToBottom();
  }

  Future<void> _sendPickedAttachment({
    required ChatAttachmentKind kind,
    required String fileName,
    required String contentType,
    ChatAttachmentTransferMode transferMode =
        ChatAttachmentTransferMode.standard,
    Future<List<int>> Function()? readBytes,
    String? filePath,
    int? sizeBytes,
    int? width,
    int? height,
    int? durationSeconds,
  }) async {
    setState(() => _attachmentBusy = true);

    try {
      final draft = await _uploadAttachmentDraft(
        kind: kind,
        fileName: fileName,
        contentType: contentType,
        transferMode: transferMode,
        readBytes: readBytes,
        filePath: filePath,
        sizeBytes: sizeBytes,
        width: width,
        height: height,
        durationSeconds: durationSeconds,
      );
      await _sendAttachmentDrafts([draft]);
      await TurnaAnalytics.logEvent('attachment_sent', {
        'chat_id': widget.chat.chatId,
        'kind': kind.name,
        'transfer_mode': transferMode.name,
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

  Future<void> _sendDocumentMediaFiles(List<XFile> files) async {
    if (files.isEmpty) return;
    setState(() => _attachmentBusy = true);

    try {
      final drafts = <OutgoingAttachmentDraft>[];
      for (final file in files.take(kComposerMediaLimit)) {
        final fileName = file.name.trim().isEmpty
            ? _fileNameFromPath(file.path)
            : file.name.trim();
        final sizeBytes = await file.length();
        if (!_ensureDocumentSizeAllowed(sizeBytes)) {
          continue;
        }
        drafts.add(
          await _uploadAttachmentDraft(
            kind: ChatAttachmentKind.file,
            fileName: fileName,
            contentType:
                guessContentTypeForFileName(fileName) ??
                'application/octet-stream',
            transferMode: ChatAttachmentTransferMode.document,
            filePath: file.path,
            sizeBytes: sizeBytes,
          ),
        );
      }
      if (drafts.isEmpty) return;
      await _sendAttachmentDrafts(drafts);
      await TurnaAnalytics.logEvent('attachment_sent', {
        'chat_id': widget.chat.chatId,
        'kind': drafts.length == 1 ? drafts.first.kind.name : 'album',
        'transfer_mode': ChatAttachmentTransferMode.document.name,
        'count': drafts.length,
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

  Future<ChatAttachmentTransferMode?> _showMediaTransferModeSheet({
    required String title,
  }) async {
    if (!mounted) return null;
    return showModalBottomSheet<ChatAttachmentTransferMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        Widget option({
          required ChatAttachmentTransferMode mode,
          required IconData icon,
          String? subtitle,
        }) {
          final isDefault = mode == ChatAttachmentTransferMode.standard;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 4,
            ),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: isDefault
                  ? TurnaColors.primary50
                  : TurnaColors.backgroundMuted,
              child: Icon(icon, color: TurnaColors.primary),
            ),
            title: Text(
              mode.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: isDefault
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: TurnaColors.primary50,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Varsayılan',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TurnaColors.primary,
                      ),
                    ),
                  )
                : null,
            onTap: () => Navigator.pop(sheetContext, mode),
          );
        }

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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: TurnaColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Standart medya optimize edilir, HD daha yüksek kalite sunar, dosya modu orijinali gönderir.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: TurnaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                option(
                  mode: ChatAttachmentTransferMode.standard,
                  icon: Icons.tune_rounded,
                  subtitle: 'Hızlı gönderim ve düşük veri kullanımı',
                ),
                option(
                  mode: ChatAttachmentTransferMode.hd,
                  icon: Icons.hd_rounded,
                  subtitle: 'Daha yüksek çözünürlük ve daha az kayıp',
                ),
                option(
                  mode: ChatAttachmentTransferMode.document,
                  icon: Icons.insert_drive_file_outlined,
                  subtitle: 'Orijinal dosyayı hiç işlemden geçirmeden gönder',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMediaComposerFromFiles(
    List<XFile> files, {
    required MediaComposerQuality initialQuality,
  }) async {
    final seeds = await buildTurnaMediaComposerSeeds(context, files);
    if (seeds.isEmpty || !mounted) return;

    final message = await Navigator.push<ChatMessage>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaMediaComposerPage(
          session: widget.session,
          chat: widget.chat,
          items: seeds,
          onSessionExpired: widget.onSessionExpired,
          initialQuality: initialQuality,
        ),
      ),
    );

    if (!mounted || message == null) return;
    _client.mergeServerMessage(message);
    _jumpToBottom();
  }

  Future<void> _pickGalleryPhotos() async {
    final transferMode = await _showMediaTransferModeSheet(
      title: 'Fotoğraf gönder',
    );
    if (transferMode == null) return;
    final files = await _mediaPicker.pickMultiImage(limit: kComposerMediaLimit);
    if (files.isEmpty) return;
    if (transferMode == ChatAttachmentTransferMode.document) {
      await _sendDocumentMediaFiles(files);
      return;
    }
    await _openMediaComposerFromFiles(
      files,
      initialQuality: transferMode == ChatAttachmentTransferMode.hd
          ? MediaComposerQuality.hd
          : MediaComposerQuality.standard,
    );
  }

  Future<void> _pickGalleryVideo() async {
    final transferMode = await _showMediaTransferModeSheet(
      title: 'Video gönder',
    );
    if (transferMode == null) return;
    final file = await _mediaPicker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    if (transferMode == ChatAttachmentTransferMode.document) {
      await _sendDocumentMediaFiles([file]);
      return;
    }
    await _openMediaComposerFromFiles(
      [file],
      initialQuality: transferMode == ChatAttachmentTransferMode.hd
          ? MediaComposerQuality.hd
          : MediaComposerQuality.standard,
    );
  }

  Future<void> _pickCameraImage() async {
    final transferMode = await _showMediaTransferModeSheet(
      title: 'Kamera fotoğrafı gönder',
    );
    if (transferMode == null) return;
    final file = await _mediaPicker.pickImage(source: ImageSource.camera);
    if (file == null) return;
    if (transferMode == ChatAttachmentTransferMode.document) {
      await _sendDocumentMediaFiles([file]);
      return;
    }
    await _openMediaComposerFromFiles(
      [file],
      initialQuality: transferMode == ChatAttachmentTransferMode.hd
          ? MediaComposerQuality.hd
          : MediaComposerQuality.standard,
    );
  }

  bool _ensureDocumentSizeAllowed(int sizeBytes) {
    if (sizeBytes <= 0 || sizeBytes <= kDocumentAttachmentMaxBytes) {
      return true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belge boyutu 2 GB sınırını aşıyor.')),
      );
    }
    return false;
  }

  String _fileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }

  Future<void> _sendDocumentAttachmentFromPath({
    required String filePath,
    String? fileName,
    String? contentType,
    int? sizeBytes,
  }) async {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Secilen dosya okunamadi.')),
        );
      }
      return;
    }

    final file = File(normalizedPath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Secilen dosya bulunamadi.')),
        );
      }
      return;
    }

    final resolvedSizeBytes = sizeBytes ?? await file.length();
    if (!_ensureDocumentSizeAllowed(resolvedSizeBytes)) {
      return;
    }

    final resolvedFileName = (fileName?.trim().isNotEmpty ?? false)
        ? fileName!.trim()
        : _fileNameFromPath(normalizedPath);
    final resolvedContentType = (contentType?.trim().isNotEmpty ?? false)
        ? contentType!.trim()
        : (guessContentTypeForFileName(resolvedFileName) ??
              'application/octet-stream');

    await _sendPickedAttachment(
      kind: ChatAttachmentKind.file,
      fileName: resolvedFileName,
      contentType: resolvedContentType,
      transferMode: ChatAttachmentTransferMode.document,
      filePath: normalizedPath,
      sizeBytes: resolvedSizeBytes,
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final filePath = file.path;
    final fileName = file.name.trim().isEmpty
        ? (filePath == null || filePath.trim().isEmpty
              ? 'belge'
              : _fileNameFromPath(filePath))
        : file.name.trim();

    if (filePath != null && filePath.trim().isNotEmpty) {
      await _sendDocumentAttachmentFromPath(
        filePath: filePath,
        fileName: fileName,
        sizeBytes: file.size > 0 ? file.size : null,
      );
      return;
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Secilen dosya okunamadi.')));
      return;
    }
    if (!_ensureDocumentSizeAllowed(bytes.length)) {
      return;
    }

    await _sendPickedAttachment(
      kind: ChatAttachmentKind.file,
      fileName: fileName,
      contentType:
          guessContentTypeForFileName(fileName) ?? 'application/octet-stream',
      transferMode: ChatAttachmentTransferMode.document,
      readBytes: () async => bytes,
      sizeBytes: file.size > 0 ? file.size : bytes.length,
    );
  }

  Future<void> _pickDocumentMedia() async {
    final file = await _mediaPicker.pickMedia();
    if (file == null) return;
    final fileName = file.name.trim().isEmpty
        ? _fileNameFromPath(file.path)
        : file.name.trim();
    await _sendDocumentAttachmentFromPath(
      filePath: file.path,
      fileName: fileName,
      contentType: guessContentTypeForFileName(fileName),
      sizeBytes: await file.length(),
    );
  }

  Future<void> _scanDocumentAndSend() async {
    try {
      final scan = await TurnaMediaBridge.scanDocument();
      if (scan == null) return;
      await _sendDocumentAttachmentFromPath(
        filePath: scan.path,
        fileName: scan.fileName,
        contentType: scan.mimeType,
        sizeBytes: scan.sizeBytes,
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      final message = error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'Belge tarayıcı açılamadı.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showPaymentPlaceholderModal() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF27D06F),
                        Color(0xFF00B8FF),
                        Color(0xFFFFC23A),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.payments_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Ödeme Yap',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hazırlanıyor...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: TurnaColors.textMuted),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7F9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Çok yakında Turna ödemeleri burada olacak.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: TurnaColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDocumentPickerSheet() async {
    if (_attachmentBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        Future<void> handleSelection(Future<void> Function() action) async {
          Navigator.pop(sheetContext);
          await Future<void>.delayed(const Duration(milliseconds: 140));
          if (!mounted) return;
          await action();
        }

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F6),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 44),
                    const Expanded(
                      child: Text(
                        'Belge seçin',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: TurnaColors.text,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        splashRadius: 20,
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF5C5C5F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Boyutu en fazla 2 GB olan orijinal dosyaları gönderin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.38,
                      color: TurnaColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DocumentPickerActionTile(
                        title: 'Dosyalardan seç',
                        icon: Icons.insert_drive_file_outlined,
                        onTap: () => unawaited(handleSelection(_pickFile)),
                      ),
                      const Divider(height: 1, indent: 20, endIndent: 20),
                      _DocumentPickerActionTile(
                        title: 'Fotoğraf veya video seç',
                        icon: Icons.photo_library_outlined,
                        onTap: () =>
                            unawaited(handleSelection(_pickDocumentMedia)),
                      ),
                      const Divider(height: 1, indent: 20, endIndent: 20),
                      _DocumentPickerActionTile(
                        title: 'Belgeyi tarayın',
                        icon: Icons.document_scanner_outlined,
                        onTap: () =>
                            unawaited(handleSelection(_scanDocumentAndSend)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                  'Paylaş',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: TurnaColors.text,
                  ),
                ),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                  children: [
                    _AttachmentQuickAction(
                      icon: Icons.photo_library_outlined,
                      label: 'Fotoğraflar',
                      backgroundColor: TurnaColors.accent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        unawaited(
                          Future<void>.delayed(
                            const Duration(milliseconds: 140),
                            _pickGalleryPhotos,
                          ),
                        );
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.video_library_outlined,
                      label: 'Videolar',
                      backgroundColor: TurnaColors.primaryStrong,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        unawaited(
                          Future<void>.delayed(
                            const Duration(milliseconds: 140),
                            _pickGalleryVideo,
                          ),
                        );
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.photo_camera_outlined,
                      label: 'Kamera',
                      backgroundColor: TurnaColors.primary,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        unawaited(
                          Future<void>.delayed(
                            const Duration(milliseconds: 140),
                            _pickCameraImage,
                          ),
                        );
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.payments_rounded,
                      label: 'Ödeme Yap',
                      backgroundColor: const Color(0xFF1FCB76),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF2BD56F),
                          Color(0xFF00B7FF),
                          Color(0xFFFFC93D),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showPaymentPlaceholderModal();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.insert_drive_file_outlined,
                      label: 'Belge',
                      backgroundColor: TurnaColors.primaryDeep,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        unawaited(
                          Future<void>.delayed(
                            const Duration(milliseconds: 140),
                            _showDocumentPickerSheet,
                          ),
                        );
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.perm_contact_calendar_outlined,
                      label: 'Kişi',
                      backgroundColor: TurnaColors.accentStrong,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickSharedContact();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.location_on_outlined,
                      label: 'Konum',
                      backgroundColor: TurnaColors.primary400,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickLocation();
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
      ).showSnackBar(const SnackBar(content: Text('Dosya linki hazır değil.')));
      return;
    }

    if (_isImageAttachment(attachment) || _isVideoAttachment(attachment)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatAttachmentViewerPage(
            session: widget.session,
            items: [
              ChatGalleryMediaItem(
                attachment: attachment,
                senderLabel: attachment.fileName ?? 'Medya',
                cacheKey: 'attachment:${attachment.objectKey}',
                url: url,
              ),
            ],
            initialIndex: 0,
            autoOpenInitialVideoFullscreen: _isVideoAttachment(attachment),
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
      ).showSnackBar(const SnackBar(content: Text('Dosya açılamadı.')));
    }
  }

  Future<void> _openMediaAttachment(
    ChatMessage sourceMessage,
    ChatAttachment attachment,
  ) async {
    final url = attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya linki hazır değil.')));
      return;
    }
    final galleryItems = _buildMediaGalleryItems();
    final initialIndex = galleryItems.indexWhere(
      (item) =>
          item.message?.id == sourceMessage.id &&
          item.attachment.objectKey == attachment.objectKey,
    );
    final itemsToOpen = initialIndex < 0
        ? [
            ChatGalleryMediaItem(
              message: sourceMessage,
              attachment: attachment,
              senderLabel: sourceMessage.senderId == widget.session.userId
                  ? 'Siz'
                  : _displaySenderNameFor(sourceMessage),
              cacheKey: 'attachment:${attachment.objectKey}',
              url: url,
            ),
          ]
        : galleryItems;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatAttachmentViewerPage(
          session: widget.session,
          items: itemsToOpen,
          initialIndex: initialIndex < 0 ? 0 : initialIndex,
          autoOpenInitialVideoFullscreen: _isVideoAttachment(attachment),
          formatTimestamp: _formatViewerDateTime,
          isStarred: (message) => _starredMessageIds.contains(message.id),
          onReply: (message) async {
            final replyPayload = _replyPayloadForMessage(message);
            setState(() {
              _editingDraft = null;
              _replyDraft = replyPayload;
            });
            _composerFocusNode.requestFocus();
          },
          onForward: _forwardMessage,
          onToggleStar: _toggleStarMessage,
          onDeleteForMe: (message) async {
            await _deleteMessageForMe(message);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    turnaLog('chat room dispose', {'chatId': widget.chat.chatId});
    if (_route != null) {
      kTurnaRouteObserver.unsubscribe(this);
    }
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
    _client.messagesRevisionListenable.removeListener(
      _handleClientMessagesChanged,
    );
    _client.dispose();
    widget.callCoordinator.removeListener(_handleCallCoordinatorChanged);
    _controller.removeListener(_handleComposerChanged);
    _controller.dispose();
    _composerFocusNode.removeListener(_handleComposerFocusChanged);
    _composerFocusNode.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _voiceRecordTimer?.cancel();
    unawaited(_voiceRecorder.cancel());
    unawaited(_voiceRecorder.dispose());
    _messageHighlightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _client.refreshConnection();
      unawaited(_loadPeerCallHistory());
      if (_isGroupChat) {
        unawaited(_loadActiveGroupCallState());
      }
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_voiceRecording) {
        unawaited(_cancelVoiceRecording());
      }
      _client.disconnectForBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        title: AnimatedBuilder(
          animation: _headerListenable,
          builder: (context, _) {
            final peerStatusText = _buildPeerStatusText();
            final peerTyping = _client.peerTyping;
            return GestureDetector(
              onTap: _isGroupChat
                  ? _openGroupInfo
                  : (_peerUserId == null ? null : _openPeerProfile),
              child: Row(
                children: [
                  _ProfileAvatar(
                    label: _chatDisplayName,
                    avatarUrl: _isGroupChat
                        ? _groupAvatarUrl
                        : widget.chat.avatarUrl,
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
                          _chatDisplayName,
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
                              color: peerTyping
                                  ? TurnaColors.primary
                                  : TurnaColors.textMuted,
                              fontWeight: peerTyping
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          if (_isGroupChat)
            AnimatedBuilder(
              animation: _headerListenable,
              builder: (context, _) {
                final activeGroupCall = _activeGroupCall;
                return IconButton(
                  tooltip: activeGroupCall == null
                      ? (_canCurrentUserStartGroupCalls
                            ? 'Grup çağrısı başlat'
                            : 'Aktif çağrı varsa katıl')
                      : 'Aktif grup çağrısına katıl',
                  onPressed:
                      (activeGroupCall == null &&
                          !_canCurrentUserStartGroupCalls)
                      ? null
                      : _openGroupCallTypePicker,
                  icon: Icon(
                    activeGroupCall?.type == TurnaCallType.video
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    color: activeGroupCall == null
                        ? null
                        : TurnaColors.primaryStrong,
                  ),
                );
              },
            ),
          if (_isGroupChat)
            IconButton(
              tooltip: 'Grup içi ara',
              onPressed: _openGroupSearch,
              icon: const Icon(Icons.search_rounded),
            ),
          if (_isGroupChat)
            IconButton(
              tooltip: 'Grup bilgisi',
              onPressed: _openGroupInfo,
              icon: const Icon(Icons.info_outline_rounded),
            ),
          if (!_isGroupChat) ...[
            IconButton(
              tooltip: 'Görüntülü ara',
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
        ],
      ),
      body: AnimatedBuilder(
        animation: _contentListenable,
        builder: (context, _) {
          final timelineEntries = _buildTimelineEntries();
          return Column(
            children: [
              if (_client.error != null)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFFF1E6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    _client.error!,
                    style: const TextStyle(color: Color(0xFF7A4B00)),
                  ),
                ),
              if (_attachmentBusy)
                Container(
                  width: double.infinity,
                  color: TurnaColors.primary50,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: const Text(
                    'Medya yükleniyor. Mesaj hazırlanıyor...',
                    style: TextStyle(color: TurnaColors.primaryStrong),
                  ),
                ),
              if (_activePinnedMessage != null)
                _PinnedMessageBar(
                  pinned: _activePinnedMessage!,
                  onTap: _openPinnedMessagesSheet,
                  onClear: _canManagePinnedMessages
                      ? () => _togglePinnedMessage(
                          _messageForPinnedSummary(_activePinnedMessage!),
                        )
                      : null,
                ),
              if (_activeGroupCall != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: TurnaColors.primary50,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: TurnaColors.primary200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _activeGroupCall!.type == TurnaCallType.video
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        color: TurnaColors.primaryStrong,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _activeGroupCallLabel() ?? 'Aktif grup çağrısı',
                          style: const TextStyle(
                            color: TurnaColors.primary800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _joinOrStartGroupCall(_activeGroupCall!.type),
                        child: const Text('Katıl'),
                      ),
                    ],
                  ),
                ),
              if (_showSecurityBanner) _buildSecurityBanner(),
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(child: _ChatWallpaper()),
                    if (timelineEntries.isEmpty && _client.loadingInitial)
                      const SizedBox.expand()
                    else if (timelineEntries.isEmpty)
                      const _CenteredState(
                        icon: Icons.chat_bubble_outline,
                        title: 'Henüz mesaj yok',
                        message: 'İlk mesajı göndererek sohbeti başlat.',
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
                                child: Center(
                                  child: Text(
                                    'Eski mesajlar ekleniyor...',
                                    style: TextStyle(color: Color(0xFF777C79)),
                                  ),
                                ),
                              );
                            }
                            if (_client.hasMore) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: Text(
                                    'Eski mesajlar yükleniyor...',
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
          );
        },
      ),
    );
  }
}

class _MessageMetaFooter extends StatelessWidget {
  const _MessageMetaFooter({
    required this.timeLabel,
    required this.mine,
    required this.status,
    this.edited = false,
    this.starred = false,
    this.overlay = false,
    this.showOverlayBackground = true,
  });

  final String timeLabel;
  final bool mine;
  final ChatMessageStatus status;
  final bool edited;
  final bool starred;
  final bool overlay;
  final bool showOverlayBackground;

  @override
  Widget build(BuildContext context) {
    final textColor = overlay
        ? (showOverlayBackground
              ? Colors.white.withValues(alpha: 0.94)
              : (mine
                    ? TurnaColors.chatOutgoingText.withValues(alpha: 0.54)
                    : TurnaColors.textMuted))
        : (mine ? TurnaColors.chatOutgoingMeta : TurnaColors.textMuted);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (starred) ...[
          Icon(
            Icons.star_rounded,
            size: 13,
            color: overlay && showOverlayBackground
                ? Colors.white.withValues(alpha: 0.96)
                : (mine ? TurnaColors.chatOutgoingMeta : TurnaColors.warning),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          edited ? 'düzenlendi $timeLabel' : timeLabel,
          style: TextStyle(fontSize: 11, color: textColor),
        ),
        if (mine) ...[
          const SizedBox(width: 6),
          _StatusTick(
            status: status,
            mine: mine,
            overlay: overlay,
            showOverlayBackground: showOverlayBackground,
          ),
        ],
      ],
    );
    if (!overlay || !showOverlayBackground) return content;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(999),
      ),
      child: content,
    );
  }
}

class _StatusTick extends StatelessWidget {
  const _StatusTick({
    required this.status,
    this.mine = false,
    this.overlay = false,
    this.showOverlayBackground = true,
  });

  final ChatMessageStatus status;
  final bool mine;
  final bool overlay;
  final bool showOverlayBackground;

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.done;
    Color color = overlay && showOverlayBackground
        ? Colors.white.withValues(alpha: 0.94)
        : (mine ? TurnaColors.chatOutgoingMeta : TurnaColors.textMuted);

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
      color = mine ? TurnaColors.chatOutgoingRead : TurnaColors.info;
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
    this.gradient,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: backgroundColor,
                gradient: gradient,
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

class _DocumentPickerActionTile extends StatelessWidget {
  const _DocumentPickerActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: TurnaColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(icon, size: 28, color: const Color(0xFF151515)),
            ],
          ),
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
    required this.senderLabel,
    required this.repliedToCurrentUser,
    required this.authToken,
    this.previewAttachment,
    this.onTap,
  });

  final TurnaReplyPayload reply;
  final bool mine;
  final String senderLabel;
  final bool repliedToCurrentUser;
  final String authToken;
  final ChatAttachment? previewAttachment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = repliedToCurrentUser
        ? const Color(0xFF1976D2)
        : const Color(0xFFD35F49);
    final background = mine ? const Color(0xFFD8EDC7) : const Color(0xFFF4F5F7);
    final textColor = TurnaColors.text;
    final attachment = previewAttachment;
    final hasThumbnail = attachment != null;
    final mediaLabel = reply.previewText.trim().isEmpty
        ? 'Medya'
        : reply.previewText;

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
                      senderLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          reply.previewText == 'Video'
                              ? Icons.videocam_rounded
                              : reply.previewText == 'Fotoğraf'
                              ? Icons.photo_camera_rounded
                              : Icons.subtitles_rounded,
                          size: 18,
                          color: textColor.withValues(alpha: 0.76),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            mediaLabel,
                            maxLines: hasThumbnail ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.92),
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasThumbnail) ...[
                const SizedBox(width: 8),
                _ReplySnippetThumbnail(
                  attachment: attachment,
                  authToken: authToken,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplySnippetThumbnail extends StatelessWidget {
  const _ReplySnippetThumbnail({
    required this.attachment,
    required this.authToken,
  });

  final ChatAttachment attachment;
  final String authToken;

  @override
  Widget build(BuildContext context) {
    final cacheKey = 'attachment:${attachment.objectKey}';
    final url = attachment.url?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 52,
        height: 52,
        child: _isVideoAttachment(attachment)
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _TurnaVideoThumbnail(
                    cacheKey: cacheKey,
                    url: url,
                    authToken: authToken,
                    contentType: attachment.contentType,
                    fileName: attachment.fileName,
                    fit: BoxFit.cover,
                    loading: const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xFFBEC5C8)),
                    ),
                    error: const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xFFBEC5C8)),
                    ),
                  ),
                  Container(color: Colors.black.withValues(alpha: 0.16)),
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              )
            : _TurnaCachedImage(
                cacheKey: cacheKey,
                imageUrl: url,
                authToken: authToken,
                fit: BoxFit.cover,
                loading: const ColoredBox(color: Color(0xFFBEC5C8)),
                error: const ColoredBox(color: Color(0xFFBEC5C8)),
              ),
      ),
    );
  }
}

class _TurnaMessageLinkPreviewCard extends StatefulWidget {
  const _TurnaMessageLinkPreviewCard({
    required this.uri,
    required this.mine,
    required this.onTap,
  });

  final Uri uri;
  final bool mine;
  final VoidCallback onTap;

  @override
  State<_TurnaMessageLinkPreviewCard> createState() =>
      _TurnaMessageLinkPreviewCardState();
}

class _TurnaMessageLinkPreviewCardState
    extends State<_TurnaMessageLinkPreviewCard> {
  late Future<TurnaLinkPreviewMetadata> _future;
  TurnaLinkPreviewMetadata? _initialData;

  @override
  void initState() {
    super.initState();
    _bindPreview();
  }

  @override
  void didUpdateWidget(covariant _TurnaMessageLinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      _bindPreview();
    }
  }

  void _bindPreview() {
    _initialData = TurnaLinkPreviewCache.peek(widget.uri);
    _future = TurnaLinkPreviewCache.resolve(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final surfaceColor = mine
        ? Colors.white.withValues(alpha: 0.44)
        : const Color(0xFFF6F8FB);
    final borderColor = mine
        ? Colors.white.withValues(alpha: 0.22)
        : TurnaColors.border;

    return FutureBuilder<TurnaLinkPreviewMetadata>(
      future: _future,
      initialData: _initialData,
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final host = preview?.host.isNotEmpty == true
            ? preview!.host
            : widget.uri.host.replaceFirst(
                RegExp(r'^www\.', caseSensitive: false),
                '',
              );
        final title = (preview?.title.trim().isNotEmpty ?? false)
            ? preview!.title.trim()
            : (host.isEmpty ? widget.uri.toString() : host);
        final displayUrl = preview?.displayUrl ?? widget.uri.toString();

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 250,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: mine
                          ? Colors.white.withValues(alpha: 0.5)
                          : TurnaColors.backgroundMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.link_rounded,
                      color: mine
                          ? TurnaColors.primary800
                          : TurnaColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.22,
                            fontWeight: FontWeight.w700,
                            color: mine
                                ? TurnaColors.chatOutgoingText
                                : TurnaColors.chatIncomingText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: mine
                                ? TurnaColors.chatOutgoingText.withValues(
                                    alpha: 0.72,
                                  )
                                : TurnaColors.textMuted,
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
      },
    );
  }
}

class _ComposerReplyBanner extends StatelessWidget {
  const _ComposerReplyBanner({required this.reply, required this.onClose});

  final TurnaReplyPayload reply;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final senderLabel = reply.senderLabel.trim() == 'Sen'
        ? 'Siz'
        : reply.senderLabel;
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
                  'Yanıtlanıyor: $senderLabel',
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

class _ComposerEditBanner extends StatelessWidget {
  const _ComposerEditBanner({required this.draft, required this.onClose});

  final _ComposerEditDraft draft;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
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
                const Text(
                  'Mesaj duzenleniyor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: TurnaColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  draft.originalText,
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
  const _PinnedMessageBar({
    required this.pinned,
    required this.onTap,
    this.onClear,
  });

  final TurnaPinnedMessageSummary pinned;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final senderLabel = (pinned.senderDisplayName ?? '').trim().isNotEmpty
        ? pinned.senderDisplayName!.trim()
        : 'Mesaj';
    return Material(
      color: TurnaColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: const BoxDecoration(
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
                      '$senderLabel: ${pinned.previewText}',
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
                onPressed: onTap,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
                color: TurnaColors.textMuted,
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: TurnaColors.textMuted,
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
  late Future<ChatInboxData> _chatsFuture;
  ChatInboxData? _cachedInbox;

  @override
  void initState() {
    super.initState();
    _cachedInbox = TurnaChatInboxLocalCache.peek(widget.session.userId);
    _chatsFuture = ChatApi.fetchChats(widget.session);
    unawaited(_loadCachedInbox());
    _searchController.addListener(_refresh);
  }

  Future<void> _loadCachedInbox() async {
    final cached = await TurnaChatInboxLocalCache.load(widget.session.userId);
    if (!mounted || cached == null) return;
    setState(() => _cachedInbox = cached);
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
      body: FutureBuilder<ChatInboxData>(
        future: _chatsFuture,
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
            return _CenteredState(
              icon: Icons.forward_to_inbox_outlined,
              title: 'Sohbetler yüklenemedi',
              message: snapshot.error.toString(),
            );
          }

          final chats =
              ((snapshot.data ?? _cachedInbox)?.chats ?? const <ChatPreview>[])
                  .where((chat) => !chat.isArchived)
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
                        title: 'Sohbet bulunamadı',
                        message: 'İletilecek başka sohbet bulunmuyor.',
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
    required this.mine,
    required this.onTap,
    required this.formatFileSize,
    required this.authToken,
    this.onLongPress,
    this.overlayFooter,
    this.audioOverlayFooter,
  });

  final List<ChatAttachment> attachments;
  final bool mine;
  final Future<void> Function(ChatAttachment attachment) onTap;
  final String Function(int bytes) formatFileSize;
  final String authToken;
  final ValueChanged<ChatAttachment>? onLongPress;
  final Widget? overlayFooter;
  final Widget? audioOverlayFooter;

  @override
  Widget build(BuildContext context) {
    final showOverlay = overlayFooter != null && attachments.length == 1;
    Widget? buildTransferBadge(ChatAttachment attachment) {
      if (attachment.transferMode != ChatAttachmentTransferMode.hd) {
        return null;
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'HD',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      children: attachments.map<Widget>((attachment) {
        if (_isAudioAttachment(attachment)) {
          return _VoiceMessageBubble(
            attachment: attachment,
            mine: mine,
            authToken: authToken,
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(attachment),
            overlayFooter: showOverlay
                ? (audioOverlayFooter ?? overlayFooter)
                : null,
          );
        }

        if (_isImageAttachment(attachment)) {
          final imageUrl = attachment.url?.trim() ?? '';
          final transferBadge = buildTransferBadge(attachment);
          return Padding(
            padding: EdgeInsets.only(bottom: showOverlay ? 0 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onTap(attachment),
              onLongPress: onLongPress == null
                  ? null
                  : () => onLongPress!(attachment),
              child: SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        width: 220,
                        height: 220,
                        color: TurnaColors.backgroundMuted,
                        child: imageUrl.isEmpty
                            ? const Center(
                                child: Icon(Icons.image_not_supported_outlined),
                              )
                            : _TurnaCachedImage(
                                cacheKey: 'attachment:${attachment.objectKey}',
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                loading: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                error: const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                      ),
                    ),
                    if (transferBadge != null)
                      Positioned(left: 10, top: 10, child: transferBadge),
                    if (showOverlay)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Container(
                            height: 70,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(22),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.22),
                                  Colors.black.withValues(alpha: 0.34),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showOverlay)
                      Positioned(right: 8, bottom: 8, child: overlayFooter!),
                  ],
                ),
              ),
            ),
          );
        }

        final isVideo = _isVideoAttachment(attachment);
        if (isVideo) {
          final transferBadge = buildTransferBadge(attachment);
          return Padding(
            padding: EdgeInsets.only(bottom: showOverlay ? 0 : 8),
            child: InkWell(
              onTap: () => onTap(attachment),
              onLongPress: onLongPress == null
                  ? null
                  : () => onLongPress!(attachment),
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 220,
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: _TurnaVideoThumbnail(
                          cacheKey: 'attachment:${attachment.objectKey}',
                          url: attachment.url?.trim() ?? '',
                          authToken: authToken,
                          contentType: attachment.contentType,
                          fileName: attachment.fileName,
                          fit: BoxFit.cover,
                          loading: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF31424A),
                                  Color(0xFF1E2A30),
                                  Color(0xFF11181D),
                                ],
                              ),
                            ),
                          ),
                          error: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF31424A),
                                  Color(0xFF1E2A30),
                                  Color(0xFF11181D),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (transferBadge != null)
                        Positioned(left: 10, top: 10, child: transferBadge),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.34),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        right: showOverlay ? 82 : 14,
                        bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              attachment.fileName ?? 'Video',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Video • ${formatFileSize(attachment.sizeBytes)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showOverlay)
                        Positioned(right: 8, bottom: 8, child: overlayFooter!),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onTap(attachment),
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(attachment),
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
                    child: const Icon(
                      Icons.insert_drive_file_outlined,
                      color: TurnaColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName ?? 'Dosya',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dosya • ${formatFileSize(attachment.sizeBytes)}',
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
