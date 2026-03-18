part of '../app/turna_app.dart';

class TurnaSocketClient extends ChangeNotifier {
  TurnaSocketClient({
    required this.chatId,
    required this.senderId,
    this.peerUserId,
    this.chatType = TurnaChatType.direct,
    required this.token,
    this.onSessionExpired,
  });

  final String chatId;
  final String senderId;
  final String? peerUserId;
  final TurnaChatType chatType;
  final String token;
  final VoidCallback? onSessionExpired;

  static const int _pageSize = 30;
  static const int _recentCacheLimit = 60;
  static final Map<String, List<Map<String, dynamic>>> _warmMessageCache =
      <String, List<Map<String, dynamic>>>{};
  final List<ChatMessage> messages = [];
  final List<TurnaPinnedMessageSummary> _pinnedMessages =
      <TurnaPinnedMessageSummary>[];
  TurnaGroupCallState? _activeGroupCallState;
  final ValueNotifier<int> messagesRevisionListenable = ValueNotifier<int>(0);
  final ValueNotifier<int> headerRevisionListenable = ValueNotifier<int>(0);
  final ValueNotifier<int> contentRevisionListenable = ValueNotifier<int>(0);
  final Map<String, Timer> _messageTimeouts = {};
  final Map<String, ChatMessageStatus> _pendingStatusByMessageId = {};
  final Map<String, Timer> _groupTypingTimeouts = <String, Timer>{};
  final Map<String, String> _typingNamesByUserId = <String, String>{};
  io.Socket? _socket;
  Timer? _typingPauseTimer;
  Timer? _peerTypingTimeout;
  bool _historyLoadedFromSocket = false;
  bool _restoredPendingMessages = false;
  bool _restoredRecentMessages = false;
  bool _isFlushingQueue = false;
  bool _localTyping = false;
  int _localMessageSeq = 0;
  bool isConnected = false;
  bool loadingInitial = true;
  bool loadingMore = false;
  bool hasMore = true;
  bool peerOnline = false;
  bool peerTyping = false;
  String? nextBefore;
  String? error;
  String? peerLastSeenAt;
  int _messagesRevision = 0;
  List<TurnaPinnedMessageSummary> get pinnedMessages =>
      List<TurnaPinnedMessageSummary>.unmodifiable(_pinnedMessages);
  TurnaGroupCallState? get activeGroupCallState => _activeGroupCallState;
  int get messagesRevision => _messagesRevision;

  String? get groupTypingSummary {
    if (chatType != TurnaChatType.group || _typingNamesByUserId.isEmpty) {
      return null;
    }
    final names = _typingNamesByUserId.values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (names.isEmpty) return 'Birisi yazıyor...';
    if (names.length == 1) return '${names.first} yazıyor...';
    if (names.length == 2) return '${names[0]} ve ${names[1]} yazıyor...';
    return '${names.first} ve ${names.length - 1} kişi daha yazıyor...';
  }

  void _replaceGroupTypingUsers(List<Map<String, dynamic>> items) {
    final before = groupTypingSummary;
    for (final timer in _groupTypingTimeouts.values) {
      timer.cancel();
    }
    _groupTypingTimeouts.clear();
    _typingNamesByUserId.clear();

    for (final item in items) {
      final userId = (item['userId'] ?? '').toString();
      final displayName = _nullableString(item['displayName']) ?? 'Birisi';
      if (userId.isEmpty || userId == senderId) continue;
      _typingNamesByUserId[userId] = displayName;
      _groupTypingTimeouts[userId] = Timer(const Duration(seconds: 4), () {
        _groupTypingTimeouts.remove(userId)?.cancel();
        _setGroupTyping(
          userId: userId,
          isTyping: false,
          displayName: displayName,
        );
      });
    }

    if (before != groupTypingSummary) {
      _notifyHeaderListeners();
    }
  }

  Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  bool _isSessionExpiredSignal(Object? data) {
    final raw = '$data';
    return raw.contains('invalid_token') ||
        raw.contains('unauthorized') ||
        raw.contains('session_revoked');
  }

  String _pendingMessagesKey() => 'turna_pending_chat_${senderId}_$chatId';
  String _recentMessagesKey() => 'turna_recent_chat_${senderId}_$chatId';
  String _warmCacheKey() => '$senderId:$chatId';

  void _hydrateWarmCache() {
    if (messages.isNotEmpty) return;
    final cached = _warmMessageCache[_warmCacheKey()];
    if (cached == null || cached.isEmpty) return;
    for (final raw in cached) {
      try {
        messages.add(
          ChatMessage.fromPendingMap(Map<String, dynamic>.from(raw)),
        );
      } catch (_) {}
    }
    _sortMessages();
  }

  void _bumpMessagesRevision() {
    _messagesRevision += 1;
    messagesRevisionListenable.value = _messagesRevision;
    contentRevisionListenable.value += 1;
  }

  void _bumpHeaderRevision() {
    headerRevisionListenable.value += 1;
  }

  void _bumpContentRevision() {
    contentRevisionListenable.value += 1;
  }

  void _notifyHeaderListeners() {
    _bumpHeaderRevision();
    notifyListeners();
  }

  void _notifyContentListeners() {
    _bumpContentRevision();
    notifyListeners();
  }

  void _notifyMessageListeners() {
    _bumpMessagesRevision();
    notifyListeners();
  }

  void _notifyHeaderAndContentListeners() {
    _bumpHeaderRevision();
    _bumpContentRevision();
    notifyListeners();
  }

  void connect() {
    _hydrateWarmCache();
    loadingInitial = messages.isEmpty;
    error = null;
    turnaLog('socket connect start', {
      'chatId': chatId,
      'senderId': senderId,
      'url': kBackendBaseUrl,
    });
    _socket = io.io(
      kBackendBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableForceNew()
          .disableMultiplex()
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      isConnected = true;
      turnaLog('socket connected', {'id': _socket?.id, 'chatId': chatId});
      _socket!.emit('chat:join', {'chatId': chatId});
      if (_localTyping) {
        _emitTyping(true);
      }
      _flushQueuedMessages();
      _notifyContentListeners();
    });

    _socket!.onConnectError((data) {
      isConnected = false;
      turnaLog('socket connect_error', data);
      if (_isSessionExpiredSignal(data)) {
        error = 'Oturumun suresi doldu.';
        _notifyContentListeners();
        onSessionExpired?.call();
        return;
      }
      if (messages.isEmpty) {
        error = 'Canlı bağlantı kurulamadı.';
        loadingInitial = false;
        _notifyContentListeners();
      }
    });

    _socket!.onError((data) {
      turnaLog('socket error', data);
    });

    _socket!.on('auth:session_revoked', (data) {
      turnaLog('socket auth:session_revoked', data);
      error = 'Oturumun suresi doldu.';
      _notifyContentListeners();
      onSessionExpired?.call();
    });

    _socket!.on('error:validation', (data) {
      turnaLog('socket error:validation', data);
    });

    _socket!.on('error:internal', (data) {
      turnaLog('socket error:internal', data);
    });
    _socket!.on('error:forbidden', (data) {
      turnaLog('socket error:forbidden', data);
    });

    _socket!.on('chat:history', (data) {
      if (data is List) {
        _historyLoadedFromSocket = true;
        turnaLog('socket chat:history', {
          'count': data.length,
          'chatId': chatId,
        });
        messages
          ..clear()
          ..addAll(
            data.whereType<Map>().map(
              (e) => _applyPendingStatus(
                ChatMessage.fromMap(Map<String, dynamic>.from(e)),
              ),
            ),
          );
        _sortMessages();
        hasMore = data.length >= _pageSize;
        nextBefore = messages.isEmpty ? null : messages.first.createdAt;
        loadingInitial = false;
        error = null;
        _markSeen();
        _persistMessageCaches();
        notifyListeners();
      }
    });

    _socket!.on('chat:inbox:update', (_) {
      _syncMessagesFromHttp();
    });

    _socket!.on('chat:message', (data) {
      if (data is Map) {
        turnaLog('socket chat:message', data);
        final message = ChatMessage.fromMap(Map<String, dynamic>.from(data));
        final resolvedMessage = _applyPendingStatus(message);
        final existingIndex = messages.indexWhere((m) => m.id == message.id);
        if (existingIndex >= 0) {
          messages[existingIndex] = resolvedMessage;
        } else {
          final index = messages.indexWhere(
            (m) =>
                m.senderId == resolvedMessage.senderId &&
                m.text == resolvedMessage.text &&
                m.id.startsWith('local_'),
          );
          if (index >= 0) {
            _cancelMessageTimeout(messages[index].id);
            messages[index] = resolvedMessage;
          } else {
            messages.add(resolvedMessage);
          }
        }
        _sortMessages();
        _persistMessageCaches();
        if (resolvedMessage.senderId != senderId) {
          _markSeen();
        }
        notifyListeners();
      }
    });

    _socket!.on('chat:status', (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final messageIds = (payload['messageIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toSet();
      if (messageIds.isEmpty) return;

      final status = ChatMessageStatusX.fromWire(
        (payload['status'] ?? '').toString(),
      );
      var changed = false;
      final unresolvedIds = <String>{};
      for (var i = 0; i < messages.length; i++) {
        final current = messages[i];
        if (!messageIds.contains(current.id)) continue;
        final nextStatus = _pickHigherStatus(current.status, status);
        if (current.status == nextStatus) continue;
        messages[i] = current.copyWith(status: nextStatus);
        changed = true;
      }
      for (final messageId in messageIds) {
        if (messages.any((message) => message.id == messageId)) continue;
        unresolvedIds.add(messageId);
      }
      for (final messageId in unresolvedIds) {
        _pendingStatusByMessageId[messageId] = _pickHigherStatus(
          _pendingStatusByMessageId[messageId] ?? ChatMessageStatus.sent,
          status,
        );
      }
      if (changed) {
        turnaLog('socket chat:status', {
          'count': messageIds.length,
          'status': payload['status'],
        });
        _bumpMessagesRevision();
        notifyListeners();
      }
    });

    _socket!.on('user:presence', (data) {
      final payload = _asMap(data);
      if (payload == null || peerUserId == null) return;

      final userId = (payload['userId'] ?? '').toString();
      if (userId != peerUserId) return;

      final online = payload['online'] == true;
      final lastSeenAt = _nullableString(payload['lastSeenAt']);
      var changed = false;
      if (peerOnline != online) {
        peerOnline = online;
        changed = true;
      }
      if (peerLastSeenAt != lastSeenAt) {
        peerLastSeenAt = lastSeenAt;
        changed = true;
      }
      if (!online && peerTyping) {
        _cancelPeerTypingTimeout();
        peerTyping = false;
        changed = true;
      }
      if (changed) {
        turnaLog('socket user:presence', {
          'chatId': chatId,
          'userId': userId,
          'online': online,
        });
        _notifyHeaderListeners();
      }
    });

    _socket!.on('chat:typing', (data) {
      final payload = _asMap(data);
      if (payload == null) return;
      if ((payload['chatId'] ?? '').toString() != chatId) return;

      final userId = (payload['userId'] ?? '').toString();
      if (chatType == TurnaChatType.group) {
        final typingUsers =
            (payload['typingUsers'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
        if (typingUsers.isNotEmpty || payload['isTyping'] == false) {
          _replaceGroupTypingUsers(typingUsers);
          return;
        }
        if (userId.isEmpty || userId == senderId) return;
        _setGroupTyping(
          userId: userId,
          isTyping: payload['isTyping'] == true,
          displayName: _nullableString(payload['displayName']) ?? 'Birisi',
        );
        return;
      }
      if (userId.isEmpty || userId == senderId) return;
      if (peerUserId != null && userId != peerUserId) return;

      _setPeerTyping(payload['isTyping'] == true);
    });

    _socket!.on('chat:pin:update', (data) {
      final payload = _asMap(data);
      if (payload == null) return;
      if ((payload['chatId'] ?? '').toString() != chatId) return;

      final pinned = (payload['pinnedMessages'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => TurnaPinnedMessageSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
      setPinnedMessages(pinned);
    });

    _socket!.on('chat:group-call:update', (data) {
      final payload = _asMap(data);
      if (payload == null) return;
      if ((payload['chatId'] ?? '').toString() != chatId) return;
      final rawState = payload['state'] as Map?;
      final nextState = rawState == null
          ? null
          : TurnaGroupCallState.fromMap(Map<String, dynamic>.from(rawState));
      final changed =
          _activeGroupCallState?.roomName != nextState?.roomName ||
          _activeGroupCallState?.participantCount !=
              nextState?.participantCount ||
          _activeGroupCallState?.type != nextState?.type ||
          _activeGroupCallState?.microphonePolicy !=
              nextState?.microphonePolicy ||
          _activeGroupCallState?.cameraPolicy != nextState?.cameraPolicy;
      _activeGroupCallState = nextState;
      if (changed) {
        _notifyHeaderAndContentListeners();
      }
    });

    _socket!.onDisconnect((reason) {
      isConnected = false;
      _cancelPeerTypingTimeout();
      peerTyping = false;
      for (final timer in _groupTypingTimeouts.values) {
        timer.cancel();
      }
      _groupTypingTimeouts.clear();
      _typingNamesByUserId.clear();
      turnaLog('socket disconnected', {'reason': reason, 'chatId': chatId});
      _notifyHeaderAndContentListeners();
    });

    _restorePendingMessages();
    _restoreRecentMessages();
    _syncMessagesFromHttp(onlyIfEmpty: true);
    _socket!.connect();
  }

  Future<void> _syncMessagesFromHttp({bool onlyIfEmpty = false}) async {
    try {
      if (_historyLoadedFromSocket && onlyIfEmpty) return;
      final page = await ChatApi.fetchMessagesPage(
        token,
        chatId,
        cacheOwnerId: senderId,
        limit: _pageSize,
      );

      final byId = <String, ChatMessage>{};
      for (final current in messages) {
        byId[current.id] = current;
      }
      for (final serverMessage in page.items) {
        byId[serverMessage.id] = _applyPendingStatus(serverMessage);
      }

      final merged = byId.values.toList()
        ..sort((a, b) => compareTurnaTimestamps(a.createdAt, b.createdAt));
      messages
        ..clear()
        ..addAll(merged);
      hasMore = page.hasMore;
      nextBefore =
          page.nextBefore ??
          (messages.isEmpty ? null : messages.first.createdAt);
      loadingInitial = false;
      error = null;
      _markSeen();
      _persistMessageCaches();
      _notifyMessageListeners();
    } on TurnaUnauthorizedException catch (authError) {
      loadingInitial = false;
      error = authError.toString();
      _notifyContentListeners();
      onSessionExpired?.call();
    } catch (_) {
      loadingInitial = false;
      if (messages.isEmpty) {
        error = 'Mesajlar yüklenemedi.';
      }
      _notifyContentListeners();
    }
  }

  Future<void> loadOlderMessages() async {
    if (loadingMore || !hasMore || messages.isEmpty) return;

    loadingMore = true;
    _notifyContentListeners();

    var messagesChanged = false;
    try {
      final page = await ChatApi.fetchMessagesPage(
        token,
        chatId,
        cacheOwnerId: senderId,
        before: nextBefore ?? messages.first.createdAt,
        limit: _pageSize,
      );

      final byId = <String, ChatMessage>{};
      for (final current in messages) {
        byId[current.id] = current;
      }
      for (final serverMessage in page.items) {
        byId[serverMessage.id] = _applyPendingStatus(serverMessage);
      }
      final merged = byId.values.toList()
        ..sort((a, b) => compareTurnaTimestamps(a.createdAt, b.createdAt));
      messages
        ..clear()
        ..addAll(merged);
      hasMore = page.hasMore;
      nextBefore = page.nextBefore;
      messagesChanged = true;
      _persistMessageCaches();
    } on TurnaUnauthorizedException catch (authError) {
      error = authError.toString();
      onSessionExpired?.call();
    } catch (_) {
      error = 'Eski mesajlar yüklenemedi.';
    } finally {
      loadingMore = false;
      if (messagesChanged) {
        _notifyMessageListeners();
      } else {
        _notifyContentListeners();
      }
    }
  }

  void _markSeen() {
    _socket?.emit('chat:seen', {'chatId': chatId});
  }

  void updateComposerText(String text) {
    final shouldShowTyping = text.trim().isNotEmpty;
    if (shouldShowTyping) {
      if (!_localTyping) {
        _localTyping = true;
        _emitTyping(true);
      }
      _typingPauseTimer?.cancel();
      _typingPauseTimer = Timer(const Duration(seconds: 2), () {
        _localTyping = false;
        _emitTyping(false);
      });
      return;
    }

    _typingPauseTimer?.cancel();
    if (_localTyping) {
      _localTyping = false;
      _emitTyping(false);
    }
  }

  void mergeServerMessage(ChatMessage message) {
    final resolvedMessage = _applyPendingStatus(message);
    final existingIndex = messages.indexWhere((item) => item.id == message.id);
    if (existingIndex >= 0) {
      messages[existingIndex] = resolvedMessage;
    } else {
      messages.add(resolvedMessage);
    }
    _sortMessages();
    _persistMessageCaches();
    notifyListeners();
  }

  void setPinnedMessages(List<TurnaPinnedMessageSummary> items) {
    final normalized = List<TurnaPinnedMessageSummary>.from(items)
      ..sort((a, b) => compareTurnaTimestamps(b.pinnedAt, a.pinnedAt));
    final nextPinnedIds = normalized
        .map((item) => item.messageId)
        .where((item) => item.isNotEmpty)
        .toSet();

    var changed = !_samePinnedMessages(normalized);
    if (changed) {
      _pinnedMessages
        ..clear()
        ..addAll(normalized);
    }

    var messageChanged = false;
    for (var index = 0; index < messages.length; index++) {
      final current = messages[index];
      final shouldBePinned = nextPinnedIds.contains(current.id);
      if (current.isPinned == shouldBePinned) continue;
      messages[index] = current.copyWith(isPinned: shouldBePinned);
      messageChanged = true;
    }

    if (!changed && !messageChanged) return;
    if (messageChanged) {
      _sortMessages();
      unawaited(_persistMessageCaches());
      notifyListeners();
      return;
    }
    _notifyContentListeners();
  }

  void setActiveGroupCallState(TurnaGroupCallState? state) {
    final changed =
        _activeGroupCallState?.roomName != state?.roomName ||
        _activeGroupCallState?.participantCount != state?.participantCount ||
        _activeGroupCallState?.type != state?.type ||
        _activeGroupCallState?.microphonePolicy != state?.microphonePolicy ||
        _activeGroupCallState?.cameraPolicy != state?.cameraPolicy;
    _activeGroupCallState = state;
    if (changed) {
      _notifyHeaderAndContentListeners();
    }
  }

  void refreshConnection() {
    final socket = _socket;
    if (socket == null) return;
    turnaLog('socket refresh requested', {
      'chatId': chatId,
      'connected': socket.connected,
    });
    if (socket.connected) {
      socket.emit('chat:join', {'chatId': chatId});
      _syncMessagesFromHttp();
      return;
    }
    socket.connect();
  }

  void disconnectForBackground() {
    final socket = _socket;
    _typingPauseTimer?.cancel();
    if (_localTyping && socket?.connected == true) {
      _emitTyping(false);
    }
    _localTyping = false;
    if (socket == null) return;

    turnaLog('socket background disconnect', {
      'chatId': chatId,
      'connected': socket.connected,
    });
    if (socket.connected) {
      socket.disconnect();
    }
    if (isConnected || peerTyping) {
      isConnected = false;
      _cancelPeerTypingTimeout();
      peerTyping = false;
      for (final timer in _groupTypingTimeouts.values) {
        timer.cancel();
      }
      _groupTypingTimeouts.clear();
      _typingNamesByUserId.clear();
      _notifyHeaderAndContentListeners();
    }
  }

  Future<void> send(String text) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final localMessage = ChatMessage(
      id: 'local_${senderId}_${_localMessageSeq++}',
      senderId: senderId,
      text: text,
      status: isConnected
          ? ChatMessageStatus.sending
          : ChatMessageStatus.queued,
      createdAt: nowIso,
      errorText: isConnected
          ? null
          : 'Bağlantı yok. Geri gelince otomatik gönderilecek.',
    );
    messages.add(localMessage);
    _sortMessages();
    await _persistMessageCaches();
    notifyListeners();

    turnaLog('socket chat:send', {
      'chatId': chatId,
      'senderId': senderId,
      'textLen': text.length,
    });
    if (isConnected) {
      _emitQueuedMessage(localMessage.id);
    }
  }

  Future<void> retryMessage(ChatMessage message) async {
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index < 0 || !messages[index].id.startsWith('local_')) return;

    messages[index] = messages[index].copyWith(
      status: isConnected
          ? ChatMessageStatus.sending
          : ChatMessageStatus.queued,
      errorText: isConnected
          ? null
          : 'Bağlantı yok. Geri gelince otomatik gönderilecek.',
      clearErrorText: isConnected,
    );
    _bumpMessagesRevision();
    await _persistMessageCaches();
    notifyListeners();

    if (isConnected) {
      _emitQueuedMessage(messages[index].id);
    }
  }

  Future<void> _restorePendingMessages() async {
    if (_restoredPendingMessages) return;
    _restoredPendingMessages = true;

    final pendingMessages = await TurnaPendingMessageLocalRepository.load(
      senderId,
      chatId,
      legacyPrefsKey: _pendingMessagesKey(),
    );
    if (pendingMessages.isEmpty) return;

    for (final pending in pendingMessages) {
      if (messages.any((message) => message.id == pending.id)) continue;
      messages.add(pending);
    }

    _sortMessages();
    _persistWarmCacheSnapshot();
    notifyListeners();
    _flushQueuedMessages();
  }

  Future<void> _restoreRecentMessages() async {
    if (_restoredRecentMessages) return;
    _restoredRecentMessages = true;

    var changed = false;
    final cachedHistory = await TurnaChatHistoryLocalCache.load(
      senderId,
      chatId,
    );
    if (cachedHistory.isNotEmpty) {
      for (final cached in cachedHistory) {
        if (messages.any((message) => message.id == cached.id)) continue;
        messages.add(cached);
        changed = true;
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_recentMessagesKey()) ?? const [];
      for (final raw in rawList) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final cached = ChatMessage.fromPendingMap(decoded);
          if (messages.any((message) => message.id == cached.id)) continue;
          messages.add(cached);
          changed = true;
        } catch (_) {}
      }
    }

    if (!changed) return;
    _sortMessages();
    if (messages.isNotEmpty) {
      loadingInitial = false;
    }
    notifyListeners();
  }

  Future<void> _persistPendingMessages() async {
    final pending = messages
        .where(
          (message) =>
              message.id.startsWith('local_') &&
              (message.status == ChatMessageStatus.queued ||
                  message.status == ChatMessageStatus.failed ||
                  message.status == ChatMessageStatus.sending),
        )
        .toList();
    await TurnaPendingMessageLocalRepository.save(
      senderId,
      chatId,
      pending,
      legacyPrefsKey: _pendingMessagesKey(),
    );
  }

  void _persistWarmCacheSnapshot() {
    final recent = messages.length <= _recentCacheLimit
        ? messages
        : messages.sublist(messages.length - _recentCacheLimit);
    _warmMessageCache[_warmCacheKey()] = recent
        .map((message) => Map<String, dynamic>.from(message.toPendingMap()))
        .toList();
  }

  Future<void> _persistRecentMessages() async {
    _persistWarmCacheSnapshot();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentMessagesKey());
  }

  Future<void> _persistMessageCaches() async {
    await _persistPendingMessages();
    await _persistRecentMessages();
    await TurnaChatHistoryLocalCache.saveMessages(senderId, chatId, messages);
  }

  void _emitQueuedMessage(String localId) {
    final index = messages.indexWhere((message) => message.id == localId);
    if (index < 0) return;
    final message = messages[index];
    if (!message.id.startsWith('local_')) return;

    _cancelMessageTimeout(localId);
    _socket?.emit('chat:send', {'chatId': chatId, 'text': message.text});
    _messageTimeouts[localId] = Timer(const Duration(seconds: 12), () async {
      final currentIndex = messages.indexWhere((item) => item.id == localId);
      if (currentIndex < 0) return;
      final current = messages[currentIndex];
      if (current.status != ChatMessageStatus.sending) return;

      messages[currentIndex] = current.copyWith(
        status: isConnected
            ? ChatMessageStatus.failed
            : ChatMessageStatus.queued,
        errorText: isConnected
            ? 'Mesaj gönderilemedi. Tekrar dene.'
            : 'Bağlantı yok. Geri gelince otomatik gönderilecek.',
      );
      _bumpMessagesRevision();
      await _persistMessageCaches();
      notifyListeners();
    });
  }

  void _emitTyping(bool isTyping) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    turnaLog('socket chat:typing', {'chatId': chatId, 'isTyping': isTyping});
    socket.emit('chat:typing', {'chatId': chatId, 'isTyping': isTyping});
  }

  Future<void> _flushQueuedMessages() async {
    if (_isFlushingQueue || !isConnected) return;
    _isFlushingQueue = true;
    try {
      final pendingIds = messages
          .where(
            (message) =>
                message.id.startsWith('local_') &&
                (message.status == ChatMessageStatus.queued ||
                    message.status == ChatMessageStatus.failed),
          )
          .map((message) => message.id)
          .toList();

      for (final pendingId in pendingIds) {
        final index = messages.indexWhere((message) => message.id == pendingId);
        if (index < 0) continue;
        messages[index] = messages[index].copyWith(
          status: ChatMessageStatus.sending,
          clearErrorText: true,
        );
        _bumpMessagesRevision();
        notifyListeners();
        _emitQueuedMessage(pendingId);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await _persistMessageCaches();
    } finally {
      _isFlushingQueue = false;
    }
  }

  void _cancelMessageTimeout(String localId) {
    _messageTimeouts.remove(localId)?.cancel();
  }

  void _cancelPeerTypingTimeout() {
    _peerTypingTimeout?.cancel();
    _peerTypingTimeout = null;
  }

  void _setPeerTyping(bool isTyping) {
    _cancelPeerTypingTimeout();
    if (peerTyping != isTyping) {
      peerTyping = isTyping;
      _notifyHeaderListeners();
    }
    if (!isTyping) return;

    _peerTypingTimeout = Timer(const Duration(seconds: 4), () {
      _setPeerTyping(false);
    });
  }

  void _setGroupTyping({
    required String userId,
    required bool isTyping,
    required String displayName,
  }) {
    final before = groupTypingSummary;
    _groupTypingTimeouts.remove(userId)?.cancel();
    if (isTyping) {
      _typingNamesByUserId[userId] = displayName;
      _groupTypingTimeouts[userId] = Timer(const Duration(seconds: 4), () {
        _groupTypingTimeouts.remove(userId)?.cancel();
        _setGroupTyping(
          userId: userId,
          isTyping: false,
          displayName: displayName,
        );
      });
    } else {
      _typingNamesByUserId.remove(userId);
    }
    if (before != groupTypingSummary) {
      _notifyHeaderListeners();
    }
  }

  ChatMessage _applyPendingStatus(ChatMessage message) {
    final pendingStatus = _pendingStatusByMessageId.remove(message.id);
    if (pendingStatus == null) return message;
    final mergedStatus = _pickHigherStatus(message.status, pendingStatus);
    if (mergedStatus == message.status) return message;
    return message.copyWith(status: mergedStatus);
  }

  ChatMessageStatus _pickHigherStatus(
    ChatMessageStatus current,
    ChatMessageStatus incoming,
  ) {
    return _statusRank(incoming) > _statusRank(current) ? incoming : current;
  }

  int _statusRank(ChatMessageStatus status) {
    switch (status) {
      case ChatMessageStatus.sending:
        return 0;
      case ChatMessageStatus.queued:
        return 1;
      case ChatMessageStatus.failed:
        return 2;
      case ChatMessageStatus.sent:
        return 3;
      case ChatMessageStatus.delivered:
        return 4;
      case ChatMessageStatus.read:
        return 5;
    }
  }

  void _sortMessages() {
    messages.sort((a, b) => compareTurnaTimestamps(a.createdAt, b.createdAt));
    _bumpMessagesRevision();
  }

  bool _samePinnedMessages(List<TurnaPinnedMessageSummary> next) {
    if (_pinnedMessages.length != next.length) return false;
    for (var index = 0; index < next.length; index++) {
      final current = _pinnedMessages[index];
      final incoming = next[index];
      if (current.messageId != incoming.messageId) return false;
      if (current.pinnedAt != incoming.pinnedAt) return false;
      if (current.previewText != incoming.previewText) return false;
      if (current.pinnedByUserId != incoming.pinnedByUserId) return false;
    }
    return true;
  }

  @override
  void dispose() {
    turnaLog('socket dispose', {'chatId': chatId, 'senderId': senderId});
    if (_localTyping && _socket?.connected == true) {
      _socket?.emit('chat:typing', {'chatId': chatId, 'isTyping': false});
    }
    for (final timer in _messageTimeouts.values) {
      timer.cancel();
    }
    _messageTimeouts.clear();
    for (final timer in _groupTypingTimeouts.values) {
      timer.cancel();
    }
    _groupTypingTimeouts.clear();
    _typingPauseTimer?.cancel();
    _cancelPeerTypingTimeout();
    _persistWarmCacheSnapshot();
    _socket?.dispose();
    messagesRevisionListenable.dispose();
    headerRevisionListenable.dispose();
    contentRevisionListenable.dispose();
    super.dispose();
  }
}

class PresenceSocketClient {
  PresenceSocketClient({
    required this.token,
    this.onSessionExpired,
    this.onInboxUpdate,
    this.onIncomingCall,
    this.onCallAccepted,
    this.onCallDeclined,
    this.onCallMissed,
    this.onCallEnded,
    this.onCallVideoUpgradeRequested,
    this.onCallVideoUpgradeAccepted,
    this.onCallVideoUpgradeDeclined,
  });

  final String token;
  final VoidCallback? onSessionExpired;
  final VoidCallback? onInboxUpdate;
  final void Function(Map<String, dynamic> payload)? onIncomingCall;
  final void Function(Map<String, dynamic> payload)? onCallAccepted;
  final void Function(Map<String, dynamic> payload)? onCallDeclined;
  final void Function(Map<String, dynamic> payload)? onCallMissed;
  final void Function(Map<String, dynamic> payload)? onCallEnded;
  final void Function(Map<String, dynamic> payload)?
  onCallVideoUpgradeRequested;
  final void Function(Map<String, dynamic> payload)? onCallVideoUpgradeAccepted;
  final void Function(Map<String, dynamic> payload)? onCallVideoUpgradeDeclined;
  io.Socket? _socket;
  Timer? _refreshDebounce;

  Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  bool _isSessionExpiredSignal(Object? data) {
    final raw = '$data';
    return raw.contains('invalid_token') ||
        raw.contains('unauthorized') ||
        raw.contains('session_revoked');
  }

  void connect() {
    _socket = io.io(
      kBackendBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableForceNew()
          .disableMultiplex()
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect(
      (_) => turnaLog('presence connected', {'id': _socket?.id}),
    );
    _socket!.onDisconnect(
      (reason) => turnaLog('presence disconnected', {'reason': reason}),
    );
    _socket!.onConnectError((data) {
      turnaLog('presence connect_error', data);
      if (_isSessionExpiredSignal(data)) {
        onSessionExpired?.call();
      }
    });
    _socket!.on('auth:session_revoked', (data) {
      turnaLog('presence auth:session_revoked', data);
      onSessionExpired?.call();
    });

    _socket!.on('chat:inbox:update', (_) {
      turnaLog('presence inbox:update received');
      _scheduleInboxRefresh();
    });
    _socket!.on('chat:message', (_) {
      turnaLog('presence chat:message received');
      _scheduleInboxRefresh();
    });
    _socket!.on('chat:status', (_) {
      turnaLog('presence chat:status received');
      _scheduleInboxRefresh();
    });
    _socket!.on('call:incoming', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:incoming received', map);
      onIncomingCall?.call(map);
    });
    _socket!.on('call:accepted', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:accepted received', map);
      onCallAccepted?.call(map);
    });
    _socket!.on('call:declined', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:declined received', map);
      onCallDeclined?.call(map);
    });
    _socket!.on('call:missed', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:missed received', map);
      onCallMissed?.call(map);
    });
    _socket!.on('call:ended', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:ended received', map);
      onCallEnded?.call(map);
    });
    _socket!.on('call:video-upgrade:requested', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:video-upgrade:requested received', map);
      onCallVideoUpgradeRequested?.call(map);
    });
    _socket!.on('call:video-upgrade:accepted', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:video-upgrade:accepted received', map);
      onCallVideoUpgradeAccepted?.call(map);
    });
    _socket!.on('call:video-upgrade:declined', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:video-upgrade:declined received', map);
      onCallVideoUpgradeDeclined?.call(map);
    });

    _socket!.connect();
  }

  void refreshConnection() {
    final socket = _socket;
    if (socket == null) return;
    turnaLog('presence refresh requested', {'connected': socket.connected});
    if (socket.connected) {
      _scheduleInboxRefresh();
      return;
    }
    socket.connect();
    _scheduleInboxRefresh();
  }

  void disconnectForBackground() {
    final socket = _socket;
    if (socket == null) return;
    turnaLog('presence background disconnect', {'connected': socket.connected});
    if (socket.connected) {
      socket.disconnect();
    }
  }

  void _scheduleInboxRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 120), () {
      onInboxUpdate?.call();
    });
  }

  void dispose() {
    _refreshDebounce?.cancel();
    _socket?.dispose();
  }
}
