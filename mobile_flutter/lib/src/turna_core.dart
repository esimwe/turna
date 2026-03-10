part of '../main.dart';

class ChatPreview {
  ChatPreview({
    required this.chatId,
    required this.name,
    required this.message,
    required this.time,
    this.phone,
    this.avatarUrl,
    this.peerId,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isBlockedByMe = false,
    this.isArchived = false,
    this.folderId,
    this.folderName,
  });

  final String chatId;
  final String name;
  final String message;
  final String time;
  final String? phone;
  final String? avatarUrl;
  final String? peerId;
  final int unreadCount;
  final bool isMuted;
  final bool isBlockedByMe;
  final bool isArchived;
  final String? folderId;
  final String? folderName;
}

class ChatFolder {
  ChatFolder({required this.id, required this.name, required this.sortOrder});

  final String id;
  final String name;
  final int sortOrder;

  factory ChatFolder.fromMap(Map<String, dynamic> map) {
    return ChatFolder(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatInboxData {
  ChatInboxData({required this.chats, required this.folders});

  final List<ChatPreview> chats;
  final List<ChatFolder> folders;
}

class ChatUser {
  ChatUser({required this.id, required this.displayName, this.avatarUrl});

  final String id;
  final String displayName;
  final String? avatarUrl;
}

class TurnaRegisteredContact {
  TurnaRegisteredContact({
    required this.id,
    required this.displayName,
    required this.contactName,
    this.username,
    this.phone,
    this.about,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String contactName;
  final String? username;
  final String? phone;
  final String? about;
  final String? avatarUrl;

  String get resolvedTitle =>
      contactName.trim().isEmpty ? displayName : contactName;

  factory TurnaRegisteredContact.fromMap(Map<String, dynamic> map) {
    return TurnaRegisteredContact(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      contactName: (map['contactName'] ?? '').toString(),
      username: TurnaUserProfile._nullableString(map['username']),
      phone: TurnaUserProfile._nullableString(map['phone']),
      about: TurnaUserProfile._nullableString(map['about']),
      avatarUrl: TurnaUserProfile._nullableString(map['avatarUrl']),
    );
  }

  TurnaUserProfile toUserProfile() {
    return TurnaUserProfile(
      id: id,
      displayName: resolvedTitle,
      username: username,
      phone: phone,
      about: about,
      avatarUrl: avatarUrl,
    );
  }
}

class TurnaUserProfile {
  TurnaUserProfile({
    required this.id,
    required this.displayName,
    this.username,
    this.phone,
    this.email,
    this.about,
    this.avatarUrl,
    this.onboardingCompletedAt,
    this.createdAt,
  });

  final String id;
  final String displayName;
  final String? username;
  final String? phone;
  final String? email;
  final String? about;
  final String? avatarUrl;
  final String? onboardingCompletedAt;
  final String? createdAt;

  factory TurnaUserProfile.fromMap(Map<String, dynamic> map) {
    return TurnaUserProfile(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      username: _nullableString(map['username']),
      phone: _nullableString(map['phone']),
      email: _nullableString(map['email']),
      about: _nullableString(map['about']),
      avatarUrl: _nullableString(map['avatarUrl']),
      onboardingCompletedAt: _nullableString(map['onboardingCompletedAt']),
      createdAt: _nullableString(map['createdAt']),
    );
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}

enum ChatAttachmentKind { image, video, file }

class ChatAttachment {
  ChatAttachment({
    required this.id,
    required this.objectKey,
    required this.kind,
    required this.contentType,
    required this.sizeBytes,
    this.fileName,
    this.width,
    this.height,
    this.durationSeconds,
    this.url,
  });

  final String id;
  final String objectKey;
  final ChatAttachmentKind kind;
  final String? fileName;
  final String contentType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final String? url;

  factory ChatAttachment.fromMap(Map<String, dynamic> map) {
    final kindText = (map['kind'] ?? '').toString().toLowerCase();
    final kind = switch (kindText) {
      'image' => ChatAttachmentKind.image,
      'video' => ChatAttachmentKind.video,
      _ => ChatAttachmentKind.file,
    };

    return ChatAttachment(
      id: (map['id'] ?? '').toString(),
      objectKey: (map['objectKey'] ?? '').toString(),
      kind: kind,
      fileName: TurnaUserProfile._nullableString(map['fileName']),
      contentType: (map['contentType'] ?? '').toString(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      url: TurnaUserProfile._nullableString(map['url']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'objectKey': objectKey,
      'kind': kind.name,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'width': width,
      'height': height,
      'durationSeconds': durationSeconds,
      'url': url,
    };
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.status,
    required this.createdAt,
    this.editedAt,
    this.isEdited = false,
    this.editHistory = const [],
    this.attachments = const [],
    this.errorText,
  });

  final String id;
  final String senderId;
  final String text;
  final ChatMessageStatus status;
  final String createdAt;
  final String? editedAt;
  final bool isEdited;
  final List<ChatMessageEditHistoryEntry> editHistory;
  final List<ChatAttachment> attachments;
  final String? errorText;

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? text,
    ChatMessageStatus? status,
    String? createdAt,
    String? editedAt,
    bool? isEdited,
    List<ChatMessageEditHistoryEntry>? editHistory,
    List<ChatAttachment>? attachments,
    String? errorText,
    bool clearErrorText = false,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      isEdited: isEdited ?? this.isEdited,
      editHistory: editHistory ?? this.editHistory,
      attachments: attachments ?? this.attachments,
      errorText: clearErrorText ? null : (errorText ?? this.errorText),
    );
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: (map['id'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      status: ChatMessageStatusX.fromWire((map['status'] ?? '').toString()),
      createdAt: (map['createdAt'] ?? '').toString(),
      editedAt: TurnaUserProfile._nullableString(map['editedAt']),
      isEdited: map['isEdited'] == true,
      editHistory: (map['editHistory'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChatMessageEditHistoryEntry.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChatAttachment.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toPendingMap() {
    return {
      'id': id,
      'senderId': senderId,
      'text': text,
      'status': status.name,
      'createdAt': createdAt,
      'editedAt': editedAt,
      'isEdited': isEdited,
      'editHistory': editHistory.map((entry) => entry.toMap()).toList(),
      'attachments': attachments
          .map((attachment) => attachment.toMap())
          .toList(),
      'errorText': errorText,
    };
  }

  factory ChatMessage.fromPendingMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: (map['id'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      status: ChatMessageStatusX.fromLocal((map['status'] ?? '').toString()),
      createdAt: (map['createdAt'] ?? '').toString(),
      editedAt: TurnaUserProfile._nullableString(map['editedAt']),
      isEdited: map['isEdited'] == true,
      editHistory: (map['editHistory'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChatMessageEditHistoryEntry.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChatAttachment.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      errorText: TurnaUserProfile._nullableString(map['errorText']),
    );
  }
}

class ChatMessageEditHistoryEntry {
  ChatMessageEditHistoryEntry({required this.text, required this.editedAt});

  final String text;
  final String editedAt;

  factory ChatMessageEditHistoryEntry.fromMap(Map<String, dynamic> map) {
    return ChatMessageEditHistoryEntry(
      text: (map['text'] ?? '').toString(),
      editedAt: (map['editedAt'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {'text': text, 'editedAt': editedAt};
}

enum ChatMessageStatus { sending, queued, failed, sent, delivered, read }

extension ChatMessageStatusX on ChatMessageStatus {
  static ChatMessageStatus fromWire(String value) {
    switch (value) {
      case 'delivered':
        return ChatMessageStatus.delivered;
      case 'read':
        return ChatMessageStatus.read;
      default:
        return ChatMessageStatus.sent;
    }
  }

  static ChatMessageStatus fromLocal(String value) {
    switch (value) {
      case 'sending':
        return ChatMessageStatus.sending;
      case 'queued':
        return ChatMessageStatus.queued;
      case 'failed':
        return ChatMessageStatus.failed;
      case 'delivered':
        return ChatMessageStatus.delivered;
      case 'read':
        return ChatMessageStatus.read;
      default:
        return ChatMessageStatus.sent;
    }
  }
}

class ChatMessagesPage {
  ChatMessagesPage({
    required this.items,
    required this.hasMore,
    required this.nextBefore,
  });

  final List<ChatMessage> items;
  final bool hasMore;
  final String? nextBefore;
}

class TurnaSocketClient extends ChangeNotifier {
  TurnaSocketClient({
    required this.chatId,
    required this.senderId,
    this.peerUserId,
    required this.token,
    this.onSessionExpired,
  });

  final String chatId;
  final String senderId;
  final String? peerUserId;
  final String token;
  final VoidCallback? onSessionExpired;

  static const int _pageSize = 30;
  final List<ChatMessage> messages = [];
  final Map<String, Timer> _messageTimeouts = {};
  final Map<String, ChatMessageStatus> _pendingStatusByMessageId = {};
  io.Socket? _socket;
  Timer? _typingPauseTimer;
  Timer? _peerTypingTimeout;
  bool _historyLoadedFromSocket = false;
  bool _restoredPendingMessages = false;
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

  void connect() {
    loadingInitial = true;
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
      notifyListeners();
    });

    _socket!.onConnectError((data) {
      isConnected = false;
      turnaLog('socket connect_error', data);
      if (_isSessionExpiredSignal(data)) {
        error = 'Oturumun suresi doldu.';
        notifyListeners();
        onSessionExpired?.call();
        return;
      }
      if (messages.isEmpty) {
        error = 'Canli baglanti kurulamadi.';
        loadingInitial = false;
        notifyListeners();
      }
    });

    _socket!.onError((data) {
      turnaLog('socket error', data);
    });

    _socket!.on('auth:session_revoked', (data) {
      turnaLog('socket auth:session_revoked', data);
      error = 'Oturumun suresi doldu.';
      notifyListeners();
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
        _persistPendingMessages();
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
        _persistPendingMessages();
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
        notifyListeners();
      }
    });

    _socket!.on('chat:typing', (data) {
      final payload = _asMap(data);
      if (payload == null) return;
      if ((payload['chatId'] ?? '').toString() != chatId) return;

      final userId = (payload['userId'] ?? '').toString();
      if (userId.isEmpty || userId == senderId) return;
      if (peerUserId != null && userId != peerUserId) return;

      _setPeerTyping(payload['isTyping'] == true);
    });

    _socket!.onDisconnect((reason) {
      isConnected = false;
      _cancelPeerTypingTimeout();
      peerTyping = false;
      turnaLog('socket disconnected', {'reason': reason, 'chatId': chatId});
      notifyListeners();
    });

    _restorePendingMessages();
    _syncMessagesFromHttp(onlyIfEmpty: true);
    _socket!.connect();
  }

  Future<void> _syncMessagesFromHttp({bool onlyIfEmpty = false}) async {
    try {
      if (_historyLoadedFromSocket && onlyIfEmpty) return;
      final page = await ChatApi.fetchMessagesPage(
        token,
        chatId,
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
      _persistPendingMessages();
      notifyListeners();
    } on TurnaUnauthorizedException catch (authError) {
      loadingInitial = false;
      error = authError.toString();
      notifyListeners();
      onSessionExpired?.call();
    } catch (_) {
      loadingInitial = false;
      if (messages.isEmpty) {
        error = 'Mesajlar yuklenemedi.';
      }
      notifyListeners();
    }
  }

  Future<void> loadOlderMessages() async {
    if (loadingMore || !hasMore || messages.isEmpty) return;

    loadingMore = true;
    notifyListeners();

    try {
      final page = await ChatApi.fetchMessagesPage(
        token,
        chatId,
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
    } on TurnaUnauthorizedException catch (authError) {
      error = authError.toString();
      onSessionExpired?.call();
    } catch (_) {
      error = 'Eski mesajlar yuklenemedi.';
    } finally {
      loadingMore = false;
      notifyListeners();
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
    _persistPendingMessages();
    notifyListeners();
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
      notifyListeners();
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
          : 'Baglanti yok. Geri gelince otomatik gonderilecek.',
    );
    messages.add(localMessage);
    _sortMessages();
    await _persistPendingMessages();
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
          : 'Baglanti yok. Geri gelince otomatik gonderilecek.',
      clearErrorText: isConnected,
    );
    await _persistPendingMessages();
    notifyListeners();

    if (isConnected) {
      _emitQueuedMessage(messages[index].id);
    }
  }

  String _pendingMessagesKey() => 'turna_pending_chat_${senderId}_$chatId';

  Future<void> _restorePendingMessages() async {
    if (_restoredPendingMessages) return;
    _restoredPendingMessages = true;

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_pendingMessagesKey()) ?? const [];
    if (rawList.isEmpty) return;

    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final pending = ChatMessage.fromPendingMap(decoded);
        if (messages.any((message) => message.id == pending.id)) continue;
        messages.add(pending);
      } catch (_) {}
    }

    _sortMessages();
    notifyListeners();
    _flushQueuedMessages();
  }

  Future<void> _persistPendingMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = messages
        .where(
          (message) =>
              message.id.startsWith('local_') &&
              (message.status == ChatMessageStatus.queued ||
                  message.status == ChatMessageStatus.failed ||
                  message.status == ChatMessageStatus.sending),
        )
        .map((message) => jsonEncode(message.toPendingMap()))
        .toList();
    await prefs.setStringList(_pendingMessagesKey(), pending);
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
            ? 'Mesaj gonderilemedi. Tekrar dene.'
            : 'Baglanti yok. Geri gelince otomatik gonderilecek.',
      );
      await _persistPendingMessages();
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
        notifyListeners();
        _emitQueuedMessage(pendingId);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await _persistPendingMessages();
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
      notifyListeners();
    }
    if (!isTyping) return;

    _peerTypingTimeout = Timer(const Duration(seconds: 4), () {
      _setPeerTyping(false);
    });
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
    _typingPauseTimer?.cancel();
    _cancelPeerTypingTimeout();
    _socket?.dispose();
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
  });

  final String token;
  final VoidCallback? onSessionExpired;
  final VoidCallback? onInboxUpdate;
  final void Function(Map<String, dynamic> payload)? onIncomingCall;
  final void Function(Map<String, dynamic> payload)? onCallAccepted;
  final void Function(Map<String, dynamic> payload)? onCallDeclined;
  final void Function(Map<String, dynamic> payload)? onCallMissed;
  final void Function(Map<String, dynamic> payload)? onCallEnded;
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

class AuthSession {
  AuthSession({
    required this.token,
    required this.userId,
    required this.displayName,
    this.username,
    this.phone,
    this.avatarUrl,
    this.needsOnboarding = false,
  });

  final String token;
  final String userId;
  final String displayName;
  final String? username;
  final String? phone;
  final String? avatarUrl;
  final bool needsOnboarding;

  static const _tokenKey = 'turna_auth_token';
  static const _userIdKey = 'turna_auth_user_id';
  static const _displayNameKey = 'turna_auth_display_name';
  static const _usernameKey = 'turna_auth_username';
  static const _phoneKey = 'turna_auth_phone';
  static const _avatarUrlKey = 'turna_auth_avatar_url';
  static const _needsOnboardingKey = 'turna_auth_needs_onboarding';

  static Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userId = prefs.getString(_userIdKey);
    final displayName = prefs.getString(_displayNameKey);
    final username = prefs.getString(_usernameKey);
    final phone = prefs.getString(_phoneKey);
    final avatarUrl = prefs.getString(_avatarUrlKey);
    final needsOnboarding = prefs.getBool(_needsOnboardingKey) ?? false;
    if (token == null || userId == null || displayName == null) {
      return null;
    }

    return AuthSession(
      token: token,
      userId: userId,
      displayName: displayName,
      username: username,
      phone: phone,
      avatarUrl: avatarUrl,
      needsOnboarding: needsOnboarding,
    );
  }

  AuthSession copyWith({
    String? token,
    String? userId,
    String? displayName,
    String? username,
    String? phone,
    String? avatarUrl,
    bool? needsOnboarding,
    bool clearPhone = false,
    bool clearAvatarUrl = false,
  }) {
    return AuthSession(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      phone: clearPhone ? null : (phone ?? this.phone),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_displayNameKey, displayName);
    if (username == null || username!.trim().isEmpty) {
      await prefs.remove(_usernameKey);
    } else {
      await prefs.setString(_usernameKey, username!);
    }
    if (phone == null || phone!.trim().isEmpty) {
      await prefs.remove(_phoneKey);
    } else {
      await prefs.setString(_phoneKey, phone!);
    }
    if (avatarUrl == null || avatarUrl!.trim().isEmpty) {
      await prefs.remove(_avatarUrlKey);
    } else {
      await prefs.setString(_avatarUrlKey, avatarUrl!);
    }
    await prefs.setBool(_needsOnboardingKey, needsOnboarding);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_phoneKey);
    await prefs.remove(_avatarUrlKey);
    await prefs.remove(_needsOnboardingKey);
  }
}

class TurnaOtpRequestTicket {
  TurnaOtpRequestTicket({
    required this.phone,
    required this.expiresInSeconds,
    required this.retryAfterSeconds,
  });

  final String phone;
  final int expiresInSeconds;
  final int retryAfterSeconds;
}

class TurnaAuthResult {
  TurnaAuthResult({
    required this.session,
    required this.isNewUser,
    required this.needsOnboarding,
  });

  final AuthSession session;
  final bool isNewUser;
  final bool needsOnboarding;
}

class AuthApi {
  static Future<TurnaOtpRequestTicket> requestOtp({
    required String countryIso,
    required String dialCode,
    required String nationalNumber,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      includeJsonContentType: true,
    );
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/auth/request-otp'),
      headers: headers,
      body: jsonEncode({
        'countryIso': countryIso,
        'dialCode': dialCode,
        'nationalNumber': nationalNumber,
      }),
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(
        ProfileApi._extractApiError(res.body, res.statusCode),
      );
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaOtpRequestTicket(
      phone: (data['phone'] ?? '').toString(),
      expiresInSeconds: (data['expiresInSeconds'] as num?)?.toInt() ?? 180,
      retryAfterSeconds: (data['retryAfterSeconds'] as num?)?.toInt() ?? 60,
    );
  }

  static Future<TurnaAuthResult> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      includeJsonContentType: true,
    );
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/auth/verify-otp'),
      headers: headers,
      body: jsonEncode({'phone': phone, 'code': code}),
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(
        ProfileApi._extractApiError(res.body, res.statusCode),
      );
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final user = map['user'] as Map<String, dynamic>? ?? const {};
    final token = map['accessToken']?.toString();
    final userId = user['id']?.toString();
    final displayName = user['displayName']?.toString();
    if (token == null || userId == null || displayName == null) {
      throw TurnaApiException('Sunucu yaniti gecersiz.');
    }

    final needsOnboarding =
        map['needsOnboarding'] == true || map['isNewUser'] == true;
    final session = AuthSession(
      token: token,
      userId: userId,
      displayName: displayName,
      username: TurnaUserProfile._nullableString(user['username']),
      phone: TurnaUserProfile._nullableString(user['phone']),
      avatarUrl: TurnaUserProfile._nullableString(user['avatarUrl']),
      needsOnboarding: needsOnboarding,
    );

    return TurnaAuthResult(
      session: session,
      isNewUser: map['isNewUser'] == true,
      needsOnboarding: needsOnboarding,
    );
  }

  static Future<void> logout(AuthSession session) async {
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/auth/logout'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
    );

    if (res.statusCode >= 400 && res.statusCode != 401) {
      throw TurnaApiException(
        ProfileApi._extractApiError(res.body, res.statusCode),
      );
    }
  }
}

class TurnaApiException implements Exception {
  TurnaApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TurnaUnauthorizedException extends TurnaApiException {
  TurnaUnauthorizedException([super.message = 'Oturumun suresi doldu.']);
}

class TurnaFirebase {
  static bool _attempted = false;
  static bool _enabled = false;
  static FirebaseAnalytics? _analytics;

  static Future<bool> ensureInitialized() async {
    if (_attempted) return _enabled;
    _attempted = true;

    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
      _enabled = true;
    } catch (error) {
      turnaLog('firebase init skipped', error);
      _enabled = false;
    }

    return _enabled;
  }

  static FirebaseAnalytics? get analytics => _enabled ? _analytics : null;
}

class TurnaAnalytics {
  static Future<void> logEvent(
    String name, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final ready = await TurnaFirebase.ensureInitialized();
    if (!ready) return;

    try {
      await TurnaFirebase.analytics?.logEvent(
        name: name,
        parameters: parameters.map(
          (key, value) => MapEntry<String, Object>(
            key,
            value is String || value is num || value is bool
                ? value as Object
                : (value?.toString() ?? ''),
          ),
        ),
      );
    } catch (error) {
      turnaLog('analytics log skipped', error);
    }
  }
}

class PushApi {
  static Future<void> registerDevice(
    AuthSession session, {
    required String token,
    required String platform,
    String tokenKind = 'standard',
    String? deviceLabel,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      authToken: session.token,
      includeJsonContentType: true,
    );
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/push/devices'),
      headers: headers,
      body: jsonEncode({
        'token': token,
        'platform': platform,
        'tokenKind': tokenKind,
        'deviceLabel': deviceLabel,
      }),
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(
        ProfileApi._extractApiError(res.body, res.statusCode),
      );
    }
  }

  static Future<void> unregisterDevice(
    AuthSession session, {
    required String token,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      authToken: session.token,
      includeJsonContentType: true,
    );
    final res = await http.delete(
      Uri.parse('$kBackendBaseUrl/api/push/devices'),
      headers: headers,
      body: jsonEncode({'token': token}),
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(
        ProfileApi._extractApiError(res.body, res.statusCode),
      );
    }
  }
}

class TurnaPushManager {
  static const _lastPushTokenKey = 'turna_last_push_token';
  static AuthSession? _session;
  static bool _listenersAttached = false;

  static Future<void> syncSession(AuthSession session) async {
    _session = session;
    final ready = await TurnaFirebase.ensureInitialized();
    if (!ready) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token == null || token.trim().isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final previousToken = prefs.getString(_lastPushTokenKey);
      if (previousToken != token) {
        await PushApi.registerDevice(
          session,
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
          tokenKind: 'standard',
          deviceLabel: Platform.isIOS ? 'ios-device' : 'android-device',
        );
        await prefs.setString(_lastPushTokenKey, token);
      }
      await TurnaNativeCallManager.syncVoipToken(session);

      if (!_listenersAttached) {
        _listenersAttached = true;
        FirebaseMessaging.onMessage.listen((message) async {
          turnaLog('push foreground', message.data);
          await TurnaNativeCallManager.handleForegroundRemoteMessage(
            message.data,
          );
        });
        FirebaseMessaging.onMessageOpenedApp.listen((message) async {
          turnaLog('push opened', message.data);
          await TurnaNativeCallManager.handleForegroundRemoteMessage(
            message.data,
          );
        });
        messaging.onTokenRefresh.listen((freshToken) async {
          if (freshToken.trim().isEmpty) return;
          final activeSession = _session;
          if (activeSession == null) return;
          try {
            await PushApi.registerDevice(
              activeSession,
              token: freshToken,
              platform: Platform.isIOS ? 'ios' : 'android',
              tokenKind: 'standard',
              deviceLabel: Platform.isIOS ? 'ios-device' : 'android-device',
            );
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_lastPushTokenKey, freshToken);
          } catch (error) {
            turnaLog('push token refresh register failed', error);
          }
        });
      }
    } catch (error) {
      turnaLog('push sync skipped', error);
    }
  }
}

class _TurnaPendingNativeAction {
  const _TurnaPendingNativeAction({required this.action, required this.body});

  final String action;
  final Map<String, dynamic> body;

  Map<String, dynamic> toMap() => {'action': action, 'body': body};

  factory _TurnaPendingNativeAction.fromMap(Map<String, dynamic> map) {
    return _TurnaPendingNativeAction(
      action: (map['action'] ?? '').toString(),
      body: Map<String, dynamic>.from(map['body'] as Map? ?? const {}),
    );
  }
}

class TurnaNativeCallManager {
  static const _pendingActionKey = 'turna_pending_native_call_action';
  static const _lastVoipPushTokenKey = 'turna_last_voip_push_token';
  static bool _initialized = false;
  static bool _androidPermissionsRequested = false;
  static AuthSession? _session;
  static TurnaCallCoordinator? _coordinator;
  static VoidCallback? _onSessionExpired;
  static final Set<String> _handledActionKeys = <String>{};
  static final Set<String> _suppressedEndEvents = <String>{};
  static final Set<String> _shownIncomingCalls = <String>{};
  static String? _activeCallId;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      Future<void>(() async {
        await _handleCallkitEvent(event);
      });
    });

    if (Platform.isAndroid) {
      await _requestAndroidPermissions();
    }
  }

  static Future<void> bindSession({
    required AuthSession session,
    required TurnaCallCoordinator coordinator,
    required VoidCallback onSessionExpired,
  }) async {
    _session = session;
    _coordinator = coordinator;
    _onSessionExpired = onSessionExpired;
    if (Platform.isAndroid) {
      await _requestAndroidPermissions();
    }
    await syncVoipToken(session);
    await _reconcileStaleCalls(session);
    await _consumePendingAction();
    await _recoverAcceptedNativeCall();
  }

  static void unbindSession(String userId) {
    if (_session?.userId != userId) return;
    _session = null;
    _coordinator = null;
    _onSessionExpired = null;
  }

  static Future<void> handleAppResumed() async {
    final session = _session;
    if (session != null) {
      await _reconcileStaleCalls(session);
    }
    await _consumePendingAction();
    await _recoverAcceptedNativeCall();
  }

  static Future<void> _reconcileStaleCalls(AuthSession session) async {
    try {
      final reconciledCallIds = await CallApi.reconcileCalls(session);
      for (final callId in reconciledCallIds) {
        await endCallUi(callId);
      }
    } catch (error) {
      turnaLog('call reconcile skipped', error);
    }
  }

  static Future<void> handleBackgroundRemoteMessage(
    Map<String, dynamic> data,
  ) async {
    await initialize();
    final type = (data['type'] ?? '').toString();
    if (type == 'incoming_call') {
      await _showIncomingCallkitIfNeeded(data);
      return;
    }
    if (type == 'call_ended') {
      final callId = _readCallId(data);
      if (callId != null) {
        await endCallUi(callId);
      }
    }
  }

  static Future<void> handleForegroundRemoteMessage(
    Map<String, dynamic> data,
  ) async {
    final type = (data['type'] ?? '').toString();
    if (type == 'call_ended') {
      final callId = _readCallId(data);
      if (callId != null) {
        await endCallUi(callId);
      }
    }
  }

  static Future<void> syncVoipToken(AuthSession session) async {
    if (!Platform.isIOS) return;
    try {
      final token = (await FlutterCallkitIncoming.getDevicePushTokenVoIP())
          ?.toString()
          .trim();
      if (token == null || token.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getString(_lastVoipPushTokenKey);
      if (previous == token) return;
      await PushApi.registerDevice(
        session,
        token: token,
        platform: 'ios',
        tokenKind: 'voip',
        deviceLabel: 'ios-voip',
      );
      await prefs.setString(_lastVoipPushTokenKey, token);
      turnaLog('voip token synced');
    } catch (error) {
      turnaLog('voip token sync skipped', error);
    }
  }

  static Future<void> setCallConnected(String callId) async {
    _activeCallId = callId;
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (error) {
      turnaLog('native call connected skipped', error);
    }
  }

  static Future<void> endCallUi(String callId) async {
    _shownIncomingCalls.remove(callId);
    if (_activeCallId == callId) {
      _activeCallId = null;
    }
    _suppressedEndEvents.add(callId);
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (error) {
      turnaLog('native call end skipped', error);
      _suppressedEndEvents.remove(callId);
    }
  }

  static Future<void> _requestAndroidPermissions() async {
    if (!Platform.isAndroid || _androidPermissionsRequested) return;
    _androidPermissionsRequested = true;
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Bildirim izni',
        'rationaleMessagePermission':
            'Gelen aramalari gosterebilmek icin bildirim izni gerekiyor.',
        'postNotificationMessageRequired':
            'Gelen aramalari gosterebilmek icin bildirim izni ver.',
      });
    } catch (error) {
      turnaLog('android notification permission skipped', error);
    }
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (error) {
      turnaLog('android full intent permission skipped', error);
    }
  }

  static Future<void> _handleCallkitEvent(CallEvent event) async {
    final body = _normalizeBody(event.body);
    final callId = _readCallId(body);
    switch (event.event) {
      case Event.actionDidUpdateDevicePushTokenVoip:
        final session = _session;
        if (session != null) {
          await syncVoipToken(session);
        }
        return;
      case Event.actionCallIncoming:
        if (callId != null) {
          _shownIncomingCalls.add(callId);
        }
        return;
      case Event.actionCallAccept:
        await _queueOrHandleAction('accept', body);
        return;
      case Event.actionCallDecline:
        await _queueOrHandleAction('decline', body);
        return;
      case Event.actionCallEnded:
        if (callId != null && _suppressedEndEvents.remove(callId)) {
          return;
        }
        await _queueOrHandleAction('end', body);
        return;
      case Event.actionCallTimeout:
        await _queueOrHandleAction('timeout', body);
        return;
      default:
        return;
    }
  }

  static Future<void> _queueOrHandleAction(
    String action,
    Map<String, dynamic> body,
  ) async {
    final handled = await _handleAction(action, body);
    if (handled) {
      await _clearPendingAction();
      return;
    }
    await _persistPendingAction(
      _TurnaPendingNativeAction(action: action, body: body),
    );
  }

  static Future<bool> _handleAction(
    String action,
    Map<String, dynamic> body,
  ) async {
    final session = _session;
    final coordinator = _coordinator;
    if (session == null || coordinator == null) return false;

    final callId = _readCallId(body);
    if (callId == null || callId.isEmpty) return false;
    final actionKey = '$action:$callId';
    if (_handledActionKeys.contains(actionKey)) {
      return true;
    }

    try {
      switch (action) {
        case 'accept':
          final accepted = await CallApi.acceptCall(session, callId: callId);
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          _shownIncomingCalls.remove(callId);
          await _openAcceptedCall(session, coordinator, accepted);
          return true;
        case 'decline':
          await CallApi.declineCall(session, callId: callId);
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          await endCallUi(callId);
          return true;
        case 'end':
          await CallApi.endCall(session, callId: callId);
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          await endCallUi(callId);
          return true;
        case 'timeout':
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          await endCallUi(callId);
          return true;
        default:
          return false;
      }
    } on TurnaUnauthorizedException {
      _onSessionExpired?.call();
      return true;
    } catch (error) {
      turnaLog('native call action failed', {
        'action': action,
        'callId': callId,
        'error': error.toString(),
      });
      return false;
    }
  }

  static Future<void> _openAcceptedCall(
    AuthSession session,
    TurnaCallCoordinator coordinator,
    TurnaAcceptedCallEvent accepted,
  ) async {
    if (_activeCallId == accepted.call.id) return;
    await Future<void>.delayed(Duration.zero);
    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    _activeCallId = accepted.call.id;
    final returnChat = buildDirectChatPreviewForCall(session, accepted.call);
    final callSession = kTurnaCallUiController.obtainSession(
      session: session,
      coordinator: coordinator,
      call: accepted.call,
      connect: accepted.connect,
      onSessionExpired: _onSessionExpired ?? () {},
      returnChatOnExit: returnChat,
    );
    await navigator.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'active-call'),
        builder: (_) => ActiveCallPage(callSession: callSession),
      ),
    );
  }

  static Future<void> _recoverAcceptedNativeCall() async {
    final session = _session;
    if (session == null) return;
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls is! List || activeCalls.isEmpty) return;
      for (final item in activeCalls) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final accepted = map['accepted'] == true || map['isAccepted'] == true;
        if (!accepted) continue;
        final callId = _readCallId(map);
        if (callId == null || callId.isEmpty) continue;
        await _handleAction('accept', map);
        break;
      }
    } catch (error) {
      turnaLog('active native call recovery skipped', error);
    }
  }

  static Future<void> _persistPendingAction(
    _TurnaPendingNativeAction action,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingActionKey, jsonEncode(action.toMap()));
  }

  static Future<void> _clearPendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingActionKey);
  }

  static Future<void> _consumePendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingActionKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final pending = _TurnaPendingNativeAction.fromMap(map);
      final handled = await _handleAction(pending.action, pending.body);
      if (handled) {
        await prefs.remove(_pendingActionKey);
      }
    } catch (error) {
      turnaLog('pending native call action parse failed', error);
      await prefs.remove(_pendingActionKey);
    }
  }

  static Map<String, dynamic> _normalizeBody(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  static String? _readCallId(Map<String, dynamic> map) {
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : const <String, dynamic>{};
    final id = map['id'] ?? map['callId'] ?? extra['callId'] ?? extra['id'];
    final value = id?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static String _readCallerName(Map<String, dynamic> map) {
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : const <String, dynamic>{};
    return (map['callerDisplayName'] ??
                map['nameCaller'] ??
                extra['callerDisplayName'] ??
                map['handle'] ??
                'Turna')
            .toString()
            .trim()
            .isEmpty
        ? 'Turna'
        : (map['callerDisplayName'] ??
                  map['nameCaller'] ??
                  extra['callerDisplayName'] ??
                  map['handle'] ??
                  'Turna')
              .toString();
  }

  static bool _readIsVideo(Map<String, dynamic> map) {
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : const <String, dynamic>{};
    final raw =
        map['isVideo'] ??
        map['callType'] ??
        extra['callType'] ??
        extra['isVideo'];
    if (raw is bool) return raw;
    final text = raw?.toString().toLowerCase();
    return text == 'video' || text == 'true' || text == '1';
  }

  static Future<void> _showIncomingCallkitIfNeeded(
    Map<String, dynamic> payload,
  ) async {
    final callId = _readCallId(payload);
    if (callId == null || callId.isEmpty) return;
    if (_shownIncomingCalls.contains(callId)) return;
    if (Platform.isIOS) {
      return;
    }

    _shownIncomingCalls.add(callId);
    final isVideo = _readIsVideo(payload);
    final callerName = _readCallerName(payload);
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Turna',
      handle: callerName,
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'Ac',
      textDecline: 'Reddet',
      extra: <String, dynamic>{
        'callId': callId,
        'callerId': (payload['callerId'] ?? '').toString(),
        'callerDisplayName': callerName,
        'callType': isVideo ? 'video' : 'audio',
      },
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Cevapsiz arama',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#101314',
        actionColor: '#2F80ED',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Turna Arama',
        missedCallNotificationChannelName: 'Turna Cevapsiz',
        isShowCallID: false,
        isShowFullLockedScreen: true,
        isImportant: true,
      ),
      ios: IOSParams(
        handleType: 'generic',
        supportsVideo: isVideo,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (error) {
      _shownIncomingCalls.remove(callId);
      turnaLog('native incoming call show failed', error);
    }
  }
}

class AvatarUploadTicket {
  AvatarUploadTicket({
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
  });

  final String objectKey;
  final String uploadUrl;
  final Map<String, String> headers;

  factory AvatarUploadTicket.fromMap(Map<String, dynamic> map) {
    final rawHeaders = map['headers'] as Map<String, dynamic>? ?? const {};
    return AvatarUploadTicket(
      objectKey: (map['objectKey'] ?? '').toString(),
      uploadUrl: (map['uploadUrl'] ?? '').toString(),
      headers: rawHeaders.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }
}

class ChatAttachmentUploadTicket {
  ChatAttachmentUploadTicket({
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
  });

  final String objectKey;
  final String uploadUrl;
  final Map<String, String> headers;

  factory ChatAttachmentUploadTicket.fromMap(Map<String, dynamic> map) {
    final rawHeaders = map['headers'] as Map<String, dynamic>? ?? const {};
    return ChatAttachmentUploadTicket(
      objectKey: (map['objectKey'] ?? '').toString(),
      uploadUrl: (map['uploadUrl'] ?? '').toString(),
      headers: rawHeaders.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }
}

class OutgoingAttachmentDraft {
  OutgoingAttachmentDraft({
    required this.objectKey,
    required this.kind,
    required this.contentType,
    required this.sizeBytes,
    this.fileName,
    this.width,
    this.height,
    this.durationSeconds,
  });

  final String objectKey;
  final ChatAttachmentKind kind;
  final String? fileName;
  final String contentType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationSeconds;

  Map<String, dynamic> toMap() {
    return {
      'objectKey': objectKey,
      'kind': kind.name,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'width': width,
      'height': height,
      'durationSeconds': durationSeconds,
    };
  }
}

class ProfileApi {
  static Future<TurnaUserProfile> fetchMe(AuthSession session) async {
    final res = await http.get(
      Uri.parse('$kBackendBaseUrl/api/profile/me'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    _throwIfApiError(res, label: 'fetchMe');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<TurnaUserProfile> fetchUser(
    AuthSession session,
    String userId,
  ) async {
    final res = await http.get(
      Uri.parse('$kBackendBaseUrl/api/profile/users/$userId'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    _throwIfApiError(res, label: 'fetchUser');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<bool> checkUsernameAvailability(
    AuthSession session,
    String username,
  ) async {
    final normalized = username.trim().toLowerCase().replaceAll('@', '');
    final res = await http.get(
      Uri.parse(
        '$kBackendBaseUrl/api/profile/username-availability',
      ).replace(queryParameters: {'username': normalized}),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    _throwIfApiError(res, label: 'checkUsernameAvailability');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return data['available'] == true;
  }

  static Future<TurnaUserProfile> updateMe(
    AuthSession session, {
    required String displayName,
    required String username,
    required String about,
    required String phone,
    required String email,
  }) async {
    final res = await http.put(
      Uri.parse('$kBackendBaseUrl/api/profile/me'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'displayName': displayName,
        'username': username.trim(),
        'about': about.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
      }),
    );
    _throwIfApiError(res, label: 'updateMe');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<TurnaUserProfile> completeOnboarding(
    AuthSession session, {
    required String displayName,
    required String username,
    required String about,
  }) async {
    final res = await http.put(
      Uri.parse('$kBackendBaseUrl/api/profile/onboarding'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'displayName': displayName,
        'username': username.trim(),
        'about': about.trim(),
      }),
    );
    _throwIfApiError(res, label: 'completeOnboarding');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<AvatarUploadTicket> createAvatarUpload(
    AuthSession session, {
    required String contentType,
    required String fileName,
  }) async {
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/profile/avatar/upload-url'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'contentType': contentType, 'fileName': fileName}),
    );
    _throwIfApiError(res, label: 'createAvatarUpload');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return AvatarUploadTicket.fromMap(data);
  }

  static Future<TurnaUserProfile> completeAvatarUpload(
    AuthSession session, {
    required String objectKey,
  }) async {
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/profile/avatar/complete'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'objectKey': objectKey}),
    );
    _throwIfApiError(res, label: 'completeAvatarUpload');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<TurnaUserProfile> deleteAvatar(AuthSession session) async {
    final res = await http.delete(
      Uri.parse('$kBackendBaseUrl/api/profile/avatar'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    _throwIfApiError(res, label: 'deleteAvatar');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<void> syncContacts(
    AuthSession session,
    List<TurnaContactSyncEntry> contacts,
  ) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      authToken: session.token,
      includeJsonContentType: true,
    );
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/profile/contacts/sync'),
      headers: headers,
      body: jsonEncode({
        'contacts': contacts.map((item) => item.toMap()).toList(),
      }),
    );
    _throwIfApiError(res, label: 'syncContacts');
  }

  static void _throwIfApiError(
    http.Response response, {
    required String label,
  }) {
    if (response.statusCode < 400) return;

    turnaLog('profile api failed', {
      'label': label,
      'statusCode': response.statusCode,
      'body': response.body,
    });
    final message = _extractApiError(response.body, response.statusCode);
    if (response.statusCode == 401) {
      throw TurnaUnauthorizedException(message);
    }
    throw TurnaApiException(message);
  }

  static String _extractApiError(String body, int statusCode) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final error = map['error']?.toString();
      switch (error) {
        case 'phone_already_in_use':
          return 'Bu telefon başka bir hesapta kullanılıyor.';
        case 'phone_change_requires_verification':
          return 'Numara değişikliği için doğrulama gerekiyor.';
        case 'email_already_in_use':
          return 'Bu email başka bir hesapta kullanılıyor.';
        case 'username_already_in_use':
          return 'Bu kullanici adi baska bir hesapta kullaniliyor.';
        case 'invalid_username':
          return 'Kullanici adi uygun degil.';
        case 'validation_error':
          return 'Girilen bilgiler geçersiz.';
        case 'user_not_found':
          return 'Kullanıcı bulunamadı.';
        case 'phone_required':
          return 'Telefon numarasi gerekli.';
        case 'invalid_phone':
          return 'Gecerli bir telefon numarasi gir.';
        case 'invalid_otp_code':
          return 'Kod 6 haneli olmali.';
        case 'otp_cooldown':
          return 'Lutfen biraz bekleyip tekrar dene.';
        case 'otp_rate_limited':
          return 'Cok fazla deneme yapildi. Daha sonra tekrar dene.';
        case 'otp_invalid':
          return 'Kod hatali. Yeniden dene.';
        case 'otp_expired':
          return 'Kodun suresi doldu. Yeni kod iste.';
        case 'otp_attempts_exceeded':
          return 'Cok fazla hatali deneme yapildi. Yeni kod iste.';
        case 'otp_not_found':
          return 'Dogrulama kodu bulunamadi. Yeni kod iste.';
        case 'otp_temporarily_unavailable':
        case 'login_temporarily_unavailable':
        case 'signup_temporarily_unavailable':
          return 'Dogrulama su an kullanilamiyor.';
        case 'storage_not_configured':
          return 'Dosya depolama servisi hazır değil.';
        case 'invalid_avatar_key':
          return 'Avatar yüklemesi doğrulanamadı.';
        case 'invalid_attachment_key':
          return 'Medya yüklemesi doğrulanamadı.';
        case 'message_not_found':
          return 'Mesaj bulunamadi.';
        case 'message_delete_not_allowed':
          return 'Bu mesaj sadece gonderen tarafindan herkesten silinebilir.';
        case 'message_delete_window_expired':
          return 'Mesaj artik herkesten silinemez. 10 dakika siniri doldu.';
        case 'message_edit_not_allowed':
          return 'Bu mesaj artik duzenlenemez.';
        case 'message_edit_window_expired':
          return 'Mesaj duzenleme suresi doldu. 10 dakika siniri doldu.';
        case 'message_edit_text_required':
          return 'Duzenlenecek mesaj bos olamaz.';
        case 'chat_folder_limit_reached':
          return 'En fazla 3 kategori olusturabilirsin.';
        case 'chat_folder_exists':
          return 'Bu kategori adi zaten kullaniliyor.';
        case 'chat_folder_not_found':
          return 'Kategori bulunamadi.';
        case 'lookup_query_required':
          return 'Telefon numarasi veya kullanici adi gir.';
        case 'uploaded_file_not_found':
          return 'Yüklenen dosya bulunamadı.';
        case 'avatar_not_found':
          return 'Avatar bulunamadı.';
        case 'text_or_attachment_required':
          return 'Mesaj veya ek secmelisin.';
        case 'call_provider_not_configured':
          return 'Arama servisi henuz hazir degil.';
        case 'call_conflict':
          return 'Kullanicilardan biri baska bir aramada.';
        case 'invalid_call_target':
          return 'Bu kullanici aranamaz.';
        case 'call_not_found':
          return 'Arama kaydi bulunamadi.';
        case 'call_not_ringing':
          return 'Bu arama artik cevaplanamaz.';
        case 'call_not_active':
          return 'Arama zaten sonlanmis.';
        case 'account_suspended':
          return 'Hesap gecici olarak durduruldu.';
        case 'account_banned':
          return 'Bu hesap kullanima kapatildi.';
        case 'otp_blocked':
          return 'Bu hesap icin dogrulama kapatildi.';
        case 'unauthorized':
        case 'invalid_token':
        case 'session_revoked':
          return 'Oturumun suresi doldu.';
        default:
          return error ?? 'İşlem başarısız ($statusCode)';
      }
    } catch (_) {
      return 'İşlem başarısız ($statusCode)';
    }
  }
}

class ChatApi {
  static Future<ChatInboxData> fetchChats(
    AuthSession session, {
    int refreshTick = 0,
  }) async {
    try {
      final headers = await TurnaDeviceContext.buildHeaders(
        authToken: session.token,
      );
      turnaLog('api fetchChats', {'refreshTick': refreshTick});

      final chatsRes = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats'),
        headers: headers,
      );
      _throwIfApiError(chatsRes);

      final chatsMap = jsonDecode(chatsRes.body) as Map<String, dynamic>;
      final chatsData = (chatsMap['data'] as List<dynamic>? ?? []);
      final foldersData = (chatsMap['folders'] as List<dynamic>? ?? []);
      final chats = chatsData.map((item) {
        final map = item as Map<String, dynamic>;
        final rawTitle = map['title']?.toString() ?? 'Chat';
        final phone = rawTitle.trim().startsWith('+') ? rawTitle.trim() : null;
        final fallbackName = phone == null
            ? rawTitle
            : formatTurnaDisplayPhone(phone);
        return ChatPreview(
          chatId: map['chatId'].toString(),
          name: TurnaContactsDirectory.resolveDisplayLabel(
            phone: phone,
            fallbackName: fallbackName,
          ),
          message: sanitizeTurnaChatPreviewText(
            map['lastMessage']?.toString() ?? '',
          ),
          time: _formatTime(map['lastMessageAt']?.toString()),
          phone: phone,
          avatarUrl: _nullableString(map['avatarUrl']),
          peerId: _nullableString(map['peerId']),
          unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
          isMuted: map['isMuted'] == true,
          isBlockedByMe: map['isBlockedByMe'] == true,
          isArchived: map['isArchived'] == true,
          folderId: _nullableString(map['folderId']),
          folderName: _nullableString(map['folderName']),
        );
      }).toList();
      final folders = foldersData
          .whereType<Map>()
          .map((item) => ChatFolder.fromMap(Map<String, dynamic>.from(item)))
          .toList();
      return ChatInboxData(chats: chats, folders: folders);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sunucuya baglanilamadi.');
    }
  }

  static Future<int> markAllChatsRead(AuthSession session) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/read-all'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return (data['updatedChatCount'] as num?)?.toInt() ?? 0;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesajlar okundu olarak isaretlenemedi.');
    }
  }

  static Future<int> markChatRead(AuthSession session, String chatId) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/read'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return (data['updatedMessageCount'] as num?)?.toInt() ?? 0;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sohbet okundu olarak isaretlenemedi.');
    }
  }

  static Future<bool> setChatMuted(
    AuthSession session, {
    required String chatId,
    required bool muted,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/mute'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'muted': muted}),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return data['muted'] == true;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sohbet sessize alinamadi.');
    }
  }

  static Future<void> clearChat(AuthSession session, String chatId) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/clear'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sohbet temizlenemedi.');
    }
  }

  static Future<bool> setChatBlocked(
    AuthSession session, {
    required String chatId,
    required bool blocked,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/block'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'blocked': blocked}),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return data['blocked'] == true;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException(
        blocked ? 'Kisi engellenemedi.' : 'Engel kaldirilamadi.',
      );
    }
  }

  static Future<int> deleteChats(
    AuthSession session,
    List<String> chatIds,
  ) async {
    try {
      final uniqueChatIds = chatIds.toSet().toList();
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/delete'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'chatIds': uniqueChatIds}),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final deleted = (data['chatIds'] as List<dynamic>? ?? const []);
      return deleted.length;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sohbetler silinemedi.');
    }
  }

  static Future<List<ChatUser>> fetchDirectory(AuthSession session) async {
    try {
      final headers = {'Authorization': 'Bearer ${session.token}'};
      turnaLog('api fetchDirectory');
      final directoryRes = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/directory/list'),
        headers: headers,
      );
      _throwIfApiError(directoryRes);

      final directoryMap =
          jsonDecode(directoryRes.body) as Map<String, dynamic>;
      final users = (directoryMap['data'] as List<dynamic>? ?? []);
      return users.map((item) {
        final map = item as Map<String, dynamic>;
        return ChatUser(
          id: map['id'].toString(),
          displayName: map['displayName']?.toString() ?? 'User',
          avatarUrl: _nullableString(map['avatarUrl']),
        );
      }).toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Kisi listesine ulasilamadi.');
    }
  }

  static Future<TurnaUserProfile?> lookupUser(
    AuthSession session,
    String query,
  ) async {
    try {
      final headers = {'Authorization': 'Bearer ${session.token}'};
      final uri = Uri.parse(
        '$kBackendBaseUrl/api/chats/directory/lookup',
      ).replace(queryParameters: {'q': query.trim()});
      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 404) {
        return null;
      }
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaUserProfile.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Kullanici aranamadi.');
    }
  }

  static Future<List<TurnaRegisteredContact>> fetchRegisteredContacts(
    AuthSession session,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/directory/contacts'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (map['data'] as List<dynamic>? ?? const []);
      return data
          .whereType<Map>()
          .map(
            (item) =>
                TurnaRegisteredContact.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Rehber kisileri yuklenemedi.');
    }
  }

  static Future<ChatFolder> createFolder(
    AuthSession session, {
    required String name,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/folders'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': name.trim()}),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatFolder.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Kategori olusturulamadi.');
    }
  }

  static Future<void> deleteFolder(AuthSession session, String folderId) async {
    try {
      final res = await http.delete(
        Uri.parse('$kBackendBaseUrl/api/chats/folders/$folderId'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Kategori silinemedi.');
    }
  }

  static Future<bool> setChatArchived(
    AuthSession session, {
    required String chatId,
    required bool archived,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/archive'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'archived': archived}),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return data['archived'] == true;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException(
        archived ? 'Sohbet arsivlenemedi.' : 'Sohbet arsivden cikarilamadi.',
      );
    }
  }

  static Future<void> setChatFolder(
    AuthSession session, {
    required String chatId,
    required String? folderId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/folder'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'folderId': folderId}),
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sohbet kategorisi guncellenemedi.');
    }
  }

  static String buildDirectChatId(String currentUserId, String peerUserId) {
    final sorted = [currentUserId, peerUserId]..sort();
    return 'direct_${sorted[0]}_${sorted[1]}';
  }

  static String? extractPeerUserId(String chatId, String currentUserId) {
    if (!chatId.startsWith('direct_')) return null;
    final parts = chatId
        .replaceFirst('direct_', '')
        .split('_')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length != 2) return null;
    if (!parts.contains(currentUserId)) return null;
    return parts.firstWhere((part) => part != currentUserId);
  }

  static Future<ChatMessagesPage> fetchMessagesPage(
    String token,
    String chatId, {
    String? before,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse('$kBackendBaseUrl/api/chats/$chatId/messages')
          .replace(
            queryParameters: {
              'limit': '$limit',
              if (before != null && before.isNotEmpty) 'before': before,
            },
          );

      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (map['data'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final pageInfo = map['pageInfo'] as Map<String, dynamic>? ?? const {};

      return ChatMessagesPage(
        items: items,
        hasMore: pageInfo['hasMore'] == true,
        nextBefore: _nullableString(pageInfo['nextBefore']),
      );
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesajlar yuklenemedi.');
    }
  }

  static Future<ChatAttachmentUploadTicket> createAttachmentUpload(
    AuthSession session, {
    required String chatId,
    required ChatAttachmentKind kind,
    required String contentType,
    required String fileName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/attachments/upload-url'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chatId': chatId,
          'kind': kind.name,
          'contentType': contentType,
          'fileName': fileName,
        }),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatAttachmentUploadTicket.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Dosya yukleme hazirligi basarisiz oldu.');
    }
  }

  static Future<ChatMessage> sendMessage(
    AuthSession session, {
    required String chatId,
    String? text,
    List<OutgoingAttachmentDraft> attachments = const [],
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/messages'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chatId': chatId,
          'text': text?.trim(),
          'attachments': attachments
              .map((attachment) => attachment.toMap())
              .toList(),
        }),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatMessage.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesaj gonderilemedi.');
    }
  }

  static Future<ChatMessage> deleteMessageForEveryone(
    AuthSession session, {
    required String messageId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/messages/$messageId/delete-for-everyone',
        ),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatMessage.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesaj herkesten silinemedi.');
    }
  }

  static Future<ChatMessage> editMessage(
    AuthSession session, {
    required String messageId,
    required String text,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$kBackendBaseUrl/api/chats/messages/$messageId'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'text': text.trim()}),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatMessage.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesaj duzenlenemedi.');
    }
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static void _throwIfApiError(http.Response response) {
    if (response.statusCode < 400) return;

    turnaLog('chat api failed', {
      'statusCode': response.statusCode,
      'body': response.body,
    });
    final message = ProfileApi._extractApiError(
      response.body,
      response.statusCode,
    );
    if (response.statusCode == 401) {
      throw TurnaUnauthorizedException(message);
    }
    throw TurnaApiException(message);
  }

  static String _formatTime(String? iso) {
    return formatTurnaLocalClock(iso);
  }
}

enum TurnaCallType { audio, video }

enum TurnaCallStatus { ringing, accepted, declined, missed, ended, cancelled }

class TurnaCallPeer {
  TurnaCallPeer({required this.id, required this.displayName, this.avatarUrl});

  final String id;
  final String displayName;
  final String? avatarUrl;

  factory TurnaCallPeer.fromMap(Map<String, dynamic> map) {
    return TurnaCallPeer(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      avatarUrl: TurnaUserProfile._nullableString(map['avatarUrl']),
    );
  }
}

class TurnaCallSummary {
  TurnaCallSummary({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.type,
    required this.status,
    required this.provider,
    required this.direction,
    required this.peer,
    required this.caller,
    required this.callee,
    this.roomName,
    this.createdAt,
    this.acceptedAt,
    this.endedAt,
  });

  final String id;
  final String callerId;
  final String calleeId;
  final TurnaCallType type;
  final TurnaCallStatus status;
  final String provider;
  final String direction;
  final String? roomName;
  final String? createdAt;
  final String? acceptedAt;
  final String? endedAt;
  final TurnaCallPeer peer;
  final TurnaCallPeer caller;
  final TurnaCallPeer callee;

  factory TurnaCallSummary.fromMap(Map<String, dynamic> map) {
    return TurnaCallSummary(
      id: (map['id'] ?? '').toString(),
      callerId: (map['callerId'] ?? '').toString(),
      calleeId: (map['calleeId'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
      status: switch ((map['status'] ?? '').toString().toLowerCase()) {
        'accepted' => TurnaCallStatus.accepted,
        'declined' => TurnaCallStatus.declined,
        'missed' => TurnaCallStatus.missed,
        'ended' => TurnaCallStatus.ended,
        'cancelled' => TurnaCallStatus.cancelled,
        _ => TurnaCallStatus.ringing,
      },
      provider: (map['provider'] ?? '').toString(),
      direction: (map['direction'] ?? 'outgoing').toString(),
      roomName: TurnaUserProfile._nullableString(map['roomName']),
      createdAt: TurnaUserProfile._nullableString(map['createdAt']),
      acceptedAt: TurnaUserProfile._nullableString(map['acceptedAt']),
      endedAt: TurnaUserProfile._nullableString(map['endedAt']),
      peer: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['peer'] as Map? ?? const {}),
      ),
      caller: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['caller'] as Map? ?? const {}),
      ),
      callee: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['callee'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaCallHistoryItem {
  TurnaCallHistoryItem({
    required this.id,
    required this.type,
    required this.status,
    required this.direction,
    required this.peer,
    this.createdAt,
    this.acceptedAt,
    this.endedAt,
    this.durationSeconds,
  });

  final String id;
  final TurnaCallType type;
  final TurnaCallStatus status;
  final String direction;
  final String? createdAt;
  final String? acceptedAt;
  final String? endedAt;
  final int? durationSeconds;
  final TurnaCallPeer peer;

  factory TurnaCallHistoryItem.fromMap(Map<String, dynamic> map) {
    return TurnaCallHistoryItem(
      id: (map['id'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
      status: switch ((map['status'] ?? '').toString().toLowerCase()) {
        'accepted' => TurnaCallStatus.accepted,
        'declined' => TurnaCallStatus.declined,
        'missed' => TurnaCallStatus.missed,
        'ended' => TurnaCallStatus.ended,
        'cancelled' => TurnaCallStatus.cancelled,
        _ => TurnaCallStatus.ringing,
      },
      direction: (map['direction'] ?? 'outgoing').toString(),
      createdAt: TurnaUserProfile._nullableString(map['createdAt']),
      acceptedAt: TurnaUserProfile._nullableString(map['acceptedAt']),
      endedAt: TurnaUserProfile._nullableString(map['endedAt']),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      peer: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['peer'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaCallConnectPayload {
  TurnaCallConnectPayload({
    required this.provider,
    required this.url,
    required this.roomName,
    required this.token,
    required this.callId,
    required this.type,
  });

  final String provider;
  final String url;
  final String roomName;
  final String token;
  final String callId;
  final TurnaCallType type;

  factory TurnaCallConnectPayload.fromMap(Map<String, dynamic> map) {
    return TurnaCallConnectPayload(
      provider: (map['provider'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      roomName: (map['roomName'] ?? '').toString(),
      token: (map['token'] ?? '').toString(),
      callId: (map['callId'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
    );
  }
}

class TurnaAcceptedCallEvent {
  TurnaAcceptedCallEvent({required this.call, required this.connect});

  final TurnaCallSummary call;
  final TurnaCallConnectPayload connect;

  factory TurnaAcceptedCallEvent.fromMap(Map<String, dynamic> map) {
    return TurnaAcceptedCallEvent(
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
      connect: TurnaCallConnectPayload.fromMap(
        Map<String, dynamic>.from(map['connect'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaIncomingCallEvent {
  TurnaIncomingCallEvent({required this.call});

  final TurnaCallSummary call;

  factory TurnaIncomingCallEvent.fromMap(Map<String, dynamic> map) {
    return TurnaIncomingCallEvent(
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaTerminalCallEvent {
  TurnaTerminalCallEvent({required this.kind, required this.call});

  final String kind;
  final TurnaCallSummary call;

  factory TurnaTerminalCallEvent.fromMap(
    String kind,
    Map<String, dynamic> map,
  ) {
    return TurnaTerminalCallEvent(
      kind: kind,
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaCallCoordinator extends ChangeNotifier {
  TurnaIncomingCallEvent? _pendingIncoming;
  final Map<String, TurnaAcceptedCallEvent> _acceptedEvents = {};
  final Map<String, TurnaTerminalCallEvent> _terminalEvents = {};

  void handleIncoming(Map<String, dynamic> payload) {
    _pendingIncoming = TurnaIncomingCallEvent.fromMap(payload);
    notifyListeners();
  }

  void handleAccepted(Map<String, dynamic> payload) {
    final event = TurnaAcceptedCallEvent.fromMap(payload);
    _acceptedEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleDeclined(Map<String, dynamic> payload) {
    final event = TurnaTerminalCallEvent.fromMap('declined', payload);
    _terminalEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleMissed(Map<String, dynamic> payload) {
    final event = TurnaTerminalCallEvent.fromMap('missed', payload);
    _terminalEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleEnded(Map<String, dynamic> payload) {
    final event = TurnaTerminalCallEvent.fromMap('ended', payload);
    _terminalEvents[event.call.id] = event;
    notifyListeners();
  }

  TurnaIncomingCallEvent? takeIncomingCall() {
    final event = _pendingIncoming;
    _pendingIncoming = null;
    return event;
  }

  TurnaAcceptedCallEvent? consumeAccepted(String callId) {
    return _acceptedEvents.remove(callId);
  }

  TurnaTerminalCallEvent? consumeTerminal(String callId) {
    return _terminalEvents.remove(callId);
  }

  void clearCall(String callId) {
    if (_pendingIncoming?.call.id == callId) {
      _pendingIncoming = null;
    }
    _acceptedEvents.remove(callId);
    _terminalEvents.remove(callId);
  }
}

class CallsPage extends StatefulWidget {
  const CallsPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    widget.callCoordinator.addListener(_onCallUpdate);
  }

  @override
  void dispose() {
    widget.callCoordinator.removeListener(_onCallUpdate);
    super.dispose();
  }

  void _onCallUpdate() {
    if (!mounted) return;
    setState(() => _refreshTick++);
  }

  String _formatTime(String? iso) {
    return formatTurnaLocalClock(iso);
  }

  String _statusLabel(TurnaCallHistoryItem item) {
    switch (item.status) {
      case TurnaCallStatus.accepted:
        if (item.durationSeconds != null && item.durationSeconds! > 0) {
          final minutes = item.durationSeconds! ~/ 60;
          final seconds = item.durationSeconds! % 60;
          return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        }
        return 'Baglandi';
      case TurnaCallStatus.declined:
        return 'Reddedildi';
      case TurnaCallStatus.missed:
        return 'Cevapsiz';
      case TurnaCallStatus.cancelled:
        return 'Iptal edildi';
      case TurnaCallStatus.ended:
        return 'Sonlandi';
      case TurnaCallStatus.ringing:
        return 'Caliyor';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: FutureBuilder<List<TurnaCallHistoryItem>>(
        future: CallApi.fetchCalls(widget.session, refreshTick: _refreshTick),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            final isAuthError = error is TurnaUnauthorizedException;
            if (isAuthError) {
              return buildTurnaSessionExpiredRedirect(widget.onSessionExpired);
            }
            return _CenteredState(
              icon: Icons.call_missed_outgoing,
              title: 'Aramalar yuklenemedi',
              message: error.toString(),
              primaryLabel: 'Tekrar dene',
              onPrimary: () => setState(() => _refreshTick++),
            );
          }

          final calls = snapshot.data ?? const [];
          if (calls.isEmpty) {
            return const _CenteredState(
              icon: Icons.call_outlined,
              title: 'Henuz arama yok',
              message: 'Yaptigin ve aldigin aramalar burada listelenecek.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => setState(() => _refreshTick++),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: calls.length,
              itemBuilder: (context, index) {
                final item = calls[index];
                final isMissed =
                    item.status == TurnaCallStatus.missed ||
                    item.status == TurnaCallStatus.declined;
                return ListTile(
                  leading: _ProfileAvatar(
                    label: item.peer.displayName,
                    avatarUrl: item.peer.avatarUrl,
                    authToken: widget.session.token,
                    radius: 22,
                  ),
                  title: Text(
                    item.peer.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Row(
                    children: [
                      Icon(
                        item.direction == 'incoming'
                            ? Icons.call_received
                            : Icons.call_made,
                        size: 16,
                        color: isMissed
                            ? Colors.red.shade400
                            : TurnaColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _statusLabel(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(item.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777C79),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Icon(
                        item.type == TurnaCallType.video
                            ? Icons.videocam_outlined
                            : Icons.call_outlined,
                        color: const Color(0xFF777C79),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({
    super.key,
    required this.session,
    required this.coordinator,
    required this.incoming,
    required this.onSessionExpired,
    this.returnChatOnExit,
  });

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaIncomingCallEvent incoming;
  final VoidCallback onSessionExpired;
  final ChatPreview? returnChatOnExit;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  bool _busy = false;

  String get _wakeLockReason => 'incoming-call:${widget.incoming.call.id}';

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_handleCoordinator);
    unawaited(TurnaDisplayWakeLock.acquire(_wakeLockReason));
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinator);
    unawaited(TurnaDisplayWakeLock.release(_wakeLockReason));
    super.dispose();
  }

  void _handleCoordinator() {
    final terminal = widget.coordinator.consumeTerminal(
      widget.incoming.call.id,
    );
    if (terminal == null || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final accepted = await CallApi.acceptCall(
        widget.session,
        callId: widget.incoming.call.id,
      );
      widget.coordinator.clearCall(widget.incoming.call.id);
      if (!mounted) return;
      final callSession = kTurnaCallUiController.obtainSession(
        session: widget.session,
        coordinator: widget.coordinator,
        call: accepted.call,
        connect: accepted.connect,
        onSessionExpired: widget.onSessionExpired,
        returnChatOnExit: widget.returnChatOnExit,
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'active-call'),
          builder: (_) => ActiveCallPage(callSession: callSession),
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
      setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CallApi.declineCall(
        widget.session,
        callId: widget.incoming.call.id,
      );
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onSessionExpired();
      }
    } catch (_) {}

    widget.coordinator.clearCall(widget.incoming.call.id);
    await TurnaNativeCallManager.endCallUi(widget.incoming.call.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.incoming.call;
    final isVideo = call.type == TurnaCallType.video;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1112),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Stack(
              children: [
                Center(
                  child: _CallIdentityPanel(
                    authToken: widget.session.token,
                    displayName: call.peer.displayName,
                    avatarUrl: call.peer.avatarUrl,
                    subtitle: isVideo ? 'Goruntulu arama' : 'Sesli arama',
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton(
                          heroTag: 'decline_${call.id}',
                          backgroundColor: Colors.red.shade400,
                          onPressed: _busy ? null : _decline,
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 72),
                        FloatingActionButton(
                          heroTag: 'accept_${call.id}',
                          backgroundColor: TurnaColors.primary,
                          onPressed: _busy ? null : _accept,
                          child: Icon(
                            isVideo ? Icons.videocam : Icons.call,
                            color: Colors.white,
                          ),
                        ),
                      ],
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
}

class OutgoingCallPage extends StatefulWidget {
  const OutgoingCallPage({
    super.key,
    required this.session,
    required this.coordinator,
    required this.initialCall,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaCallSummary initialCall;
  final VoidCallback onSessionExpired;

  @override
  State<OutgoingCallPage> createState() => _OutgoingCallPageState();
}

class _OutgoingCallPageState extends State<OutgoingCallPage> {
  bool _ending = false;
  bool _navigatedToActive = false;

  String get _wakeLockReason => 'outgoing-call:${widget.initialCall.id}';

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_handleCoordinator);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCoordinator());
    unawaited(TurnaDisplayWakeLock.acquire(_wakeLockReason));
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinator);
    unawaited(TurnaDisplayWakeLock.release(_wakeLockReason));
    super.dispose();
  }

  void _handleCoordinator() {
    if (!mounted || _navigatedToActive) return;
    final accepted = widget.coordinator.consumeAccepted(widget.initialCall.id);
    if (accepted != null) {
      _navigatedToActive = true;
      widget.coordinator.clearCall(widget.initialCall.id);
      final callSession = kTurnaCallUiController.obtainSession(
        session: widget.session,
        coordinator: widget.coordinator,
        call: accepted.call,
        connect: accepted.connect,
        onSessionExpired: widget.onSessionExpired,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ActiveCallPage(callSession: callSession),
        ),
      );
      return;
    }

    final terminal = widget.coordinator.consumeTerminal(widget.initialCall.id);
    if (terminal == null) return;

    final message = switch (terminal.kind) {
      'declined' => 'Arama reddedildi.',
      'missed' => 'Cevap yok.',
      _ => 'Arama sonlandi.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  Future<void> _cancelCall() async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      await CallApi.endCall(widget.session, callId: widget.initialCall.id);
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onSessionExpired();
      }
    } catch (_) {}

    widget.coordinator.clearCall(widget.initialCall.id);
    await TurnaNativeCallManager.endCallUi(widget.initialCall.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.initialCall;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1112),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              Center(
                child: _CallIdentityPanel(
                  authToken: widget.session.token,
                  displayName: call.peer.displayName,
                  avatarUrl: call.peer.avatarUrl,
                  subtitle: call.type == TurnaCallType.video
                      ? 'Goruntulu arama caliyor...'
                      : 'Sesli arama caliyor...',
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: FloatingActionButton(
                    backgroundColor: Colors.red.shade400,
                    onPressed: _ending ? null : _cancelCall,
                    child: const Icon(Icons.call_end, color: Colors.white),
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

class _CallIdentityPanel extends StatelessWidget {
  const _CallIdentityPanel({
    required this.authToken,
    required this.displayName,
    required this.avatarUrl,
    required this.subtitle,
  });

  final String authToken;
  final String displayName;
  final String? avatarUrl;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfileAvatar(
            label: displayName,
            avatarUrl: avatarUrl,
            authToken: authToken,
            radius: 48,
          ),
          const SizedBox(height: 20),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB7BCB9), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

abstract class CallProviderAdapter {
  Future<void> connect();
  Future<void> disconnect();
}

enum _AdaptiveCallVideoProfile { low, medium, standard, high }

extension _AdaptiveCallVideoProfileX on _AdaptiveCallVideoProfile {
  String get label => switch (this) {
    _AdaptiveCallVideoProfile.low => '360p',
    _AdaptiveCallVideoProfile.medium => '540p',
    _AdaptiveCallVideoProfile.standard => '720p',
    _AdaptiveCallVideoProfile.high => '1080p',
  };

  lk.VideoParameters get parameters => switch (this) {
    _AdaptiveCallVideoProfile.low => lk.VideoParametersPresets.h360_169,
    _AdaptiveCallVideoProfile.medium => lk.VideoParametersPresets.h540_169,
    _AdaptiveCallVideoProfile.standard => lk.VideoParametersPresets.h720_169,
    _AdaptiveCallVideoProfile.high => lk.VideoParametersPresets.h1080_169,
  };
}

class LiveKitCallAdapter extends ChangeNotifier implements CallProviderAdapter {
  static const _initialVideoProfile = _AdaptiveCallVideoProfile.standard;

  LiveKitCallAdapter({
    required this.connectPayload,
    required this.videoEnabled,
  });

  final TurnaCallConnectPayload connectPayload;
  final bool videoEnabled;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  bool connecting = false;
  bool connected = false;
  bool microphoneEnabled = true;
  bool cameraEnabled = false;
  bool speakerEnabled = false;
  lk.CameraPosition cameraPosition = lk.CameraPosition.front;
  _AdaptiveCallVideoProfile _videoProfile = _initialVideoProfile;
  bool _cameraRetryScheduled = false;
  bool _videoProfileUpdateInFlight = false;
  int _excellentQualityStreak = 0;
  int _goodQualityStreak = 0;
  int _poorQualityStreak = 0;
  String? error;
  String? mediaError;

  lk.Room get room {
    final current = _room;
    if (current == null) {
      throw StateError('livekit_room_not_initialized');
    }
    return current;
  }

  String get videoQualityLabel => _videoProfile.label;

  Iterable<lk.RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[];

  lk.VideoTrack? get primaryRemoteVideoTrack {
    final currentRoom = _room;
    if (currentRoom == null) return null;
    for (final participant in currentRoom.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track is lk.VideoTrack && publication.subscribed) {
          return track;
        }
      }
    }
    return null;
  }

  lk.VideoTrack? get localVideoTrack {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return null;
    for (final publication in localParticipant.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.VideoTrack) {
        return track;
      }
    }
    return null;
  }

  lk.LocalVideoTrack? get localCameraTrack {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return null;
    for (final publication in localParticipant.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.LocalVideoTrack) {
        return track;
      }
    }
    return null;
  }

  Future<lk.Room> _buildRoom() async {
    return lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: true,
        dynacast: false,
        defaultCameraCaptureOptions: lk.CameraCaptureOptions(
          params: _initialVideoProfile.parameters,
        ),
        defaultAudioCaptureOptions: const lk.AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        ),
        defaultAudioPublishOptions: const lk.AudioPublishOptions(
          encoding: lk.AudioEncoding(
            maxBitrate: 24000,
            bitratePriority: lk.Priority.high,
            networkPriority: lk.Priority.high,
          ),
          dtx: true,
          red: true,
        ),
        defaultAudioOutputOptions: lk.AudioOutputOptions(speakerOn: false),
      ),
    );
  }

  Future<bool> _enableCameraWithFallback(
    lk.LocalParticipant localParticipant, {
    required String origin,
  }) async {
    if (Platform.isIOS && origin == 'initial_connect') {
      turnaLog('livekit camera waiting for active lifecycle', {
        'lifecycle': kTurnaLifecycleState.value.name,
      });
      await _waitForActiveLifecycle();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    final attempts =
        <
          ({
            String label,
            _AdaptiveCallVideoProfile? profile,
            lk.CameraCaptureOptions? options,
          })
        >[
          (
            label: 'safe_default',
            profile: _videoProfile,
            options: lk.CameraCaptureOptions(
              cameraPosition: cameraPosition,
              params: _videoProfile.parameters,
            ),
          ),
          (label: 'default', profile: null, options: null),
        ];

    Object? lastError;
    for (final attempt in attempts) {
      try {
        await localParticipant.setCameraEnabled(
          true,
          cameraCaptureOptions: attempt.options,
        );
        cameraEnabled = true;
        if (attempt.profile != null) {
          _videoProfile = attempt.profile!;
        }
        turnaLog('livekit camera enabled', {
          'origin': origin,
          'attempt': attempt.label,
          'profile': _videoProfile.label,
        });
        return true;
      } catch (err) {
        lastError = err;
        turnaLog('livekit camera enable failed', {
          'origin': origin,
          'attempt': attempt.label,
          'error': '$err',
        });
      }
    }

    cameraEnabled = false;
    turnaLog('livekit camera enable exhausted', {
      'origin': origin,
      'error': '$lastError',
    });
    if (Platform.isIOS &&
        origin == 'initial_connect' &&
        connected &&
        !_cameraRetryScheduled) {
      _cameraRetryScheduled = true;
      unawaited(_retryCameraAfterDelay(localParticipant));
    }
    return false;
  }

  Future<void> _waitForActiveLifecycle() async {
    if (kTurnaLifecycleState.value == AppLifecycleState.resumed) {
      return;
    }

    final completer = Completer<void>();
    late VoidCallback listener;
    Timer? timeout;
    listener = () {
      if (kTurnaLifecycleState.value == AppLifecycleState.resumed) {
        timeout?.cancel();
        kTurnaLifecycleState.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    };

    timeout = Timer(const Duration(seconds: 3), () {
      kTurnaLifecycleState.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    kTurnaLifecycleState.addListener(listener);
    await completer.future;
  }

  Future<void> _retryCameraAfterDelay(
    lk.LocalParticipant localParticipant,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!connected || cameraEnabled) {
      _cameraRetryScheduled = false;
      return;
    }
    await _waitForActiveLifecycle();
    await _enableCameraWithFallback(localParticipant, origin: 'initial_retry');
    _cameraRetryScheduled = false;
    notifyListeners();
  }

  void _resetConnectionQualityState() {
    _excellentQualityStreak = 0;
    _goodQualityStreak = 0;
    _poorQualityStreak = 0;
  }

  Future<void> _applyVideoProfile(
    _AdaptiveCallVideoProfile nextProfile, {
    required String reason,
  }) async {
    if (_videoProfileUpdateInFlight || _videoProfile == nextProfile) return;
    final track = localCameraTrack;
    if (track == null) return;

    _videoProfileUpdateInFlight = true;
    try {
      await track.restartTrack(
        lk.CameraCaptureOptions(
          cameraPosition: cameraPosition,
          params: nextProfile.parameters,
        ),
      );
      _videoProfile = nextProfile;
      turnaLog('livekit video profile changed', {
        'reason': reason,
        'profile': nextProfile.label,
      });
      notifyListeners();
    } catch (err) {
      turnaLog('livekit video profile change failed', {
        'reason': reason,
        'profile': nextProfile.label,
        'error': '$err',
      });
    } finally {
      _videoProfileUpdateInFlight = false;
    }
  }

  @override
  Future<void> connect() async {
    if (connecting || connected) return;

    connecting = true;
    error = null;
    mediaError = null;
    notifyListeners();

    try {
      _room ??= await _buildRoom();

      _listener?.dispose();
      _listener = room.createListener()
        ..on<lk.RoomDisconnectedEvent>((_) {
          connected = false;
          connecting = false;
          notifyListeners();
        })
        ..on<lk.ParticipantConnectedEvent>((_) => notifyListeners())
        ..on<lk.ParticipantDisconnectedEvent>((_) => notifyListeners())
        ..on<lk.TrackSubscribedEvent>((_) => notifyListeners())
        ..on<lk.TrackUnsubscribedEvent>((_) => notifyListeners())
        ..on<lk.LocalTrackPublishedEvent>((_) => notifyListeners())
        ..on<lk.LocalTrackUnpublishedEvent>((_) => notifyListeners())
        ..on<lk.ParticipantConnectionQualityUpdatedEvent>(
          _handleConnectionQualityUpdated,
        );

      await room.prepareConnection(connectPayload.url, connectPayload.token);
      await room.connect(connectPayload.url, connectPayload.token);
      connected = true;
      connecting = false;
      error = null;
      _cameraRetryScheduled = false;
      _resetConnectionQualityState();
      notifyListeners();

      final localParticipant = room.localParticipant;
      if (localParticipant == null) {
        throw StateError('local_participant_missing');
      }

      try {
        await localParticipant.setMicrophoneEnabled(true);
        microphoneEnabled = true;
      } catch (err) {
        mediaError = 'Mikrofon acilamadi.';
        turnaLog('livekit microphone enable failed', err);
      }

      try {
        speakerEnabled = false;
        await room.setSpeakerOn(false);
      } catch (err) {
        turnaLog('livekit speaker configure failed', err);
      }

      notifyListeners();

      if (videoEnabled) {
        final cameraReady = await _enableCameraWithFallback(
          localParticipant,
          origin: 'initial_connect',
        );
        if (!cameraReady) {
          mediaError = 'Kamera acilamadi.';
        } else if (mediaError == 'Kamera acilamadi.') {
          mediaError = null;
        }
        notifyListeners();
      }
    } catch (err) {
      connected = false;
      connecting = false;
      error = 'Cagri baglantisi kurulamadi.';
      turnaLog('livekit connect failed', err);
      notifyListeners();
    }
  }

  Future<void> toggleMicrophone() async {
    final next = !microphoneEnabled;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    await localParticipant.setMicrophoneEnabled(next);
    microphoneEnabled = next;
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final next = !cameraEnabled;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    if (next) {
      final enabled = await _enableCameraWithFallback(
        localParticipant,
        origin: 'toggle_camera',
      );
      cameraEnabled = enabled;
      if (enabled) {
        if (mediaError == 'Kamera acilamadi.') {
          mediaError = null;
        }
      } else {
        mediaError = 'Kamera acilamadi.';
      }
    } else {
      await localParticipant.setCameraEnabled(false);
      cameraEnabled = false;
    }
    notifyListeners();
  }

  Future<void> flipCamera() async {
    final track = localCameraTrack;
    if (track == null) return;
    final previousPosition = cameraPosition;
    final nextPosition = previousPosition.switched();
    cameraPosition = nextPosition;
    notifyListeners();
    try {
      await track.setCameraPosition(nextPosition);
    } catch (err) {
      cameraPosition = previousPosition;
      notifyListeners();
      turnaLog('livekit flip camera failed', err);
    }
  }

  Future<void> toggleSpeaker() async {
    if (_room == null) return;
    final next = !speakerEnabled;
    await room.setSpeakerOn(next);
    speakerEnabled = next;
    notifyListeners();
  }

  void _handleConnectionQualityUpdated(
    lk.ParticipantConnectionQualityUpdatedEvent event,
  ) {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return;
    if (event.participant.identity != localParticipant.identity) return;
    if (!videoEnabled || !cameraEnabled) return;

    switch (event.connectionQuality) {
      case lk.ConnectionQuality.excellent:
        _excellentQualityStreak += 1;
        _goodQualityStreak += 1;
        _poorQualityStreak = 0;
        if (_videoProfile != _AdaptiveCallVideoProfile.high &&
            _excellentQualityStreak >= 3) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.high,
              reason: 'excellent_stable',
            ),
          );
        }
        break;
      case lk.ConnectionQuality.good:
        _excellentQualityStreak = 0;
        _goodQualityStreak += 1;
        _poorQualityStreak = 0;
        if (_videoProfile == _AdaptiveCallVideoProfile.low &&
            _goodQualityStreak >= 2) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.medium,
              reason: 'recover_from_low',
            ),
          );
        } else if (_videoProfile == _AdaptiveCallVideoProfile.medium &&
            _goodQualityStreak >= 3) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.standard,
              reason: 'recover_to_standard',
            ),
          );
        }
        break;
      case lk.ConnectionQuality.poor:
      case lk.ConnectionQuality.lost:
        _excellentQualityStreak = 0;
        _goodQualityStreak = 0;
        _poorQualityStreak += 1;
        if (_videoProfile == _AdaptiveCallVideoProfile.high) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.standard,
              reason: 'drop_from_high',
            ),
          );
        } else if (_videoProfile == _AdaptiveCallVideoProfile.standard &&
            _poorQualityStreak >= 2) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.medium,
              reason: 'degrade_to_medium',
            ),
          );
        } else if (_videoProfile == _AdaptiveCallVideoProfile.medium &&
            _poorQualityStreak >= 3) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.low,
              reason: 'degrade_to_low',
            ),
          );
        }
        break;
      case lk.ConnectionQuality.unknown:
        break;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _room?.disconnect();
    } catch (_) {}
    connected = false;
    connecting = false;
    _cameraRetryScheduled = false;
    _resetConnectionQualityState();
    notifyListeners();
  }

  @override
  void dispose() {
    _listener?.dispose();
    _room?.disconnect();
    super.dispose();
  }
}

class TurnaManagedCallSession extends ChangeNotifier {
  TurnaManagedCallSession({
    required this.session,
    required this.coordinator,
    required this.call,
    required this.connect,
    required this.onSessionExpired,
    this.returnChatOnExit,
  }) : adapter = LiveKitCallAdapter(
         connectPayload: connect,
         videoEnabled: call.type == TurnaCallType.video,
       ) {
    adapter.addListener(_handleAdapterChanged);
    coordinator.addListener(_handleCoordinatorChanged);
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!adapter.connected || _ended) return;
      _durationSeconds++;
      notifyListeners();
    });
  }

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaCallSummary call;
  final TurnaCallConnectPayload connect;
  final VoidCallback onSessionExpired;
  final ChatPreview? returnChatOnExit;
  final LiveKitCallAdapter adapter;

  bool _started = false;
  bool _ended = false;
  bool _reportedConnected = false;
  bool presentingFullScreen = false;
  String? terminalMessage;
  int _durationSeconds = 0;
  Timer? _durationTicker;
  bool _wakeLockHeld = false;

  bool get ended => _ended;
  int get durationSeconds => _durationSeconds;
  String get _wakeLockReason => 'active-call:${call.id}';

  String formatDuration() {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    _acquireWakeLock();
    await adapter.connect();
  }

  void setFullScreenVisible(bool value) {
    if (presentingFullScreen == value) return;
    presentingFullScreen = value;
    notifyListeners();
  }

  Future<void> endCall() async {
    if (_ended) return;
    try {
      await CallApi.endCall(session, callId: call.id);
    } on TurnaUnauthorizedException {
      onSessionExpired();
    } catch (_) {}

    coordinator.clearCall(call.id);
    await adapter.disconnect();
    await TurnaNativeCallManager.endCallUi(call.id);
    _releaseWakeLock();
    _ended = true;
    terminalMessage = null;
    notifyListeners();
    kTurnaCallUiController.clearEndedSession(this);
  }

  void _handleAdapterChanged() {
    if (adapter.connected && !_reportedConnected) {
      _reportedConnected = true;
      TurnaNativeCallManager.setCallConnected(call.id);
    }
    notifyListeners();
  }

  void _handleCoordinatorChanged() {
    final terminal = coordinator.consumeTerminal(call.id);
    if (terminal == null || _ended) return;
    coordinator.clearCall(call.id);
    terminalMessage = switch (terminal.kind) {
      'declined' => 'Arama reddedildi.',
      'missed' => 'Cevap yok.',
      _ => 'Arama sonlandi.',
    };
    _releaseWakeLock();
    _ended = true;
    unawaited(adapter.disconnect());
    unawaited(TurnaNativeCallManager.endCallUi(call.id));
    notifyListeners();
    kTurnaCallUiController.clearEndedSession(this);
  }

  void _acquireWakeLock() {
    if (_wakeLockHeld) return;
    _wakeLockHeld = true;
    unawaited(TurnaDisplayWakeLock.acquire(_wakeLockReason));
  }

  void _releaseWakeLock() {
    if (!_wakeLockHeld) return;
    _wakeLockHeld = false;
    unawaited(TurnaDisplayWakeLock.release(_wakeLockReason));
  }

  @override
  void dispose() {
    adapter.removeListener(_handleAdapterChanged);
    coordinator.removeListener(_handleCoordinatorChanged);
    _durationTicker?.cancel();
    _releaseWakeLock();
    adapter.dispose();
    super.dispose();
  }
}

class TurnaCallUiController {
  TurnaManagedCallSession? _currentSession;
  OverlayEntry? _miniOverlayEntry;
  VoidCallback? _miniListener;

  TurnaManagedCallSession obtainSession({
    required AuthSession session,
    required TurnaCallCoordinator coordinator,
    required TurnaCallSummary call,
    required TurnaCallConnectPayload connect,
    required VoidCallback onSessionExpired,
    ChatPreview? returnChatOnExit,
  }) {
    if (_currentSession?.call.id == call.id) {
      return _currentSession!;
    }
    _disposeCurrentSession();
    _currentSession = TurnaManagedCallSession(
      session: session,
      coordinator: coordinator,
      call: call,
      connect: connect,
      onSessionExpired: onSessionExpired,
      returnChatOnExit: returnChatOnExit,
    );
    return _currentSession!;
  }

  void showMini(TurnaManagedCallSession session) {
    hideMini();
    _currentSession = session;
    final navigator = kTurnaNavigatorKey.currentState;
    final overlay = navigator?.overlay;
    if (overlay == null) return;

    _miniListener = () {
      if (session.ended) {
        clearEndedSession(session);
      } else {
        _miniOverlayEntry?.markNeedsBuild();
      }
    };
    session.addListener(_miniListener!);
    _miniOverlayEntry = OverlayEntry(
      builder: (_) => _MiniCallOverlay(session: session),
    );
    overlay.insert(_miniOverlayEntry!);
  }

  void hideMini() {
    final session = _currentSession;
    final listener = _miniListener;
    if (session != null && listener != null) {
      session.removeListener(listener);
    }
    _miniListener = null;
    _miniOverlayEntry?.remove();
    _miniOverlayEntry = null;
  }

  Future<void> expandMini(TurnaManagedCallSession session) async {
    if (session.presentingFullScreen) return;
    hideMini();
    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => ActiveCallPage(callSession: session)),
    );
  }

  void clearEndedSession(TurnaManagedCallSession session) {
    if (!identical(_currentSession, session)) return;
    hideMini();
    if (!session.presentingFullScreen) {
      _currentSession = null;
      session.dispose();
    }
  }

  void releaseFullScreenSession(TurnaManagedCallSession session) {
    if (!identical(_currentSession, session)) return;
    if (session.ended) {
      hideMini();
      _currentSession = null;
      session.dispose();
    }
  }

  void _disposeCurrentSession() {
    hideMini();
    _currentSession?.dispose();
    _currentSession = null;
  }
}

class _MiniCallOverlay extends StatelessWidget {
  const _MiniCallOverlay({required this.session});

  final TurnaManagedCallSession session;

  @override
  Widget build(BuildContext context) {
    final remoteVideo = session.adapter.primaryRemoteVideoTrack;
    return Positioned(
      right: 16,
      top: 92,
      width: 138,
      height: 196,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => kTurnaCallUiController.expandMini(session),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                remoteVideo != null && session.call.type == TurnaCallType.video
                    ? lk.VideoTrackRenderer(remoteVideo)
                    : Container(
                        color: const Color(0xFF111416),
                        child: Center(
                          child: _ProfileAvatar(
                            label: session.call.peer.displayName,
                            avatarUrl: session.call.peer.avatarUrl,
                            authToken: session.session.token,
                            radius: 26,
                          ),
                        ),
                      ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.44),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      session.call.peer.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
}

class ActiveCallPage extends StatefulWidget {
  const ActiveCallPage({super.key, required this.callSession});

  final TurnaManagedCallSession callSession;

  @override
  State<ActiveCallPage> createState() => _ActiveCallPageState();
}

class _ActiveCallPageState extends State<ActiveCallPage> {
  late final TurnaManagedCallSession _callSession;
  bool _ending = false;
  bool _handledSessionEnd = false;
  bool _showLocalVideoPrimary = false;

  @override
  void initState() {
    super.initState();
    _callSession = widget.callSession;
    kTurnaCallUiController.hideMini();
    _callSession
      ..addListener(_refresh)
      ..setFullScreenVisible(true);
    unawaited(_callSession.ensureStarted());
  }

  @override
  void dispose() {
    _callSession
      ..removeListener(_refresh)
      ..setFullScreenVisible(false);
    kTurnaCallUiController.releaseFullScreenSession(_callSession);
    super.dispose();
  }

  void _refresh() {
    if (_callSession.ended && !_handledSessionEnd && mounted) {
      _handledSessionEnd = true;
      final message = _callSession.terminalMessage;
      if (message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      _leaveCallView();
      return;
    }
    if (mounted) setState(() {});
  }

  void _leaveCallView() {
    final returnChat = _callSession.returnChatOnExit;
    if (returnChat == null) {
      Navigator.of(context).pop();
      return;
    }

    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      buildChatRoomRoute(
        chat: returnChat,
        session: _callSession.session,
        callCoordinator: _callSession.coordinator,
        onSessionExpired: _callSession.onSessionExpired,
      ),
      (route) => route.isFirst,
    );
  }

  void _minimizeCall() {
    if (_callSession.call.type != TurnaCallType.video) {
      _leaveCallView();
      return;
    }
    kTurnaCallUiController.showMini(_callSession);
    Navigator.of(context).pop();
  }

  Future<void> _endCall() async {
    if (_ending) return;
    setState(() => _ending = true);
    await _callSession.endCall();
    if (mounted) {
      _leaveCallView();
    }
  }

  void _toggleVideoSwap() {
    final adapter = _callSession.adapter;
    if (_callSession.call.type != TurnaCallType.video ||
        adapter.localVideoTrack == null) {
      return;
    }
    setState(() => _showLocalVideoPrimary = !_showLocalVideoPrimary);
  }

  Widget _buildCallControlButton({
    required VoidCallback? onPressed,
    required Widget child,
    Color backgroundColor = Colors.white12,
    double size = 64,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: onPressed == null
            ? backgroundColor.withValues(alpha: 0.45)
            : backgroundColor,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: IconTheme(
              data: const IconThemeData(size: 28, color: Colors.white),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryCallPlaceholder() {
    final adapter = _callSession.adapter;
    return Container(
      color: const Color(0xFF101314),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProfileAvatar(
              label: _callSession.call.peer.displayName,
              avatarUrl: _callSession.call.peer.avatarUrl,
              authToken: _callSession.session.token,
              radius: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _callSession.call.peer.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              adapter.connecting
                  ? 'Baglaniyor...'
                  : (adapter.connected
                        ? _callSession.formatDuration()
                        : (adapter.error ?? 'Arama hazirlaniyor')),
              style: const TextStyle(color: Color(0xFFB7BCB9), fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreviewCard({
    required Widget child,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }

  Widget _buildPreviewPlaceholder({required bool showLocalUser}) {
    return Container(
      color: const Color(0xFF1A1F20),
      padding: const EdgeInsets.all(14),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showLocalUser ? Icons.videocam_off : Icons.person,
              color: Colors.white70,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              showLocalUser ? 'Sen' : _callSession.call.peer.displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adapter = _callSession.adapter;
    final remoteVideo = adapter.primaryRemoteVideoTrack;
    final localVideo = adapter.localVideoTrack;
    final isVideo = _callSession.call.type == TurnaCallType.video;
    final canSwapVideoViews = isVideo && localVideo != null;
    final showLocalVideoPrimary = canSwapVideoViews && _showLocalVideoPrimary;
    final localPreviewMirrorMode =
        adapter.cameraPosition == lk.CameraPosition.front
        ? lk.VideoViewMirrorMode.mirror
        : lk.VideoViewMirrorMode.off;
    const previewTop = 16.0;
    const previewRight = 16.0;
    const previewWidth = 96.0;
    const previewHeight = 170.0;
    final previewBottom = previewTop + previewHeight + 12;

    Widget primaryContent;
    if (isVideo && showLocalVideoPrimary) {
      primaryContent = lk.VideoTrackRenderer(
        localVideo,
        key: ValueKey(
          'primary-local-${_callSession.call.id}-${adapter.cameraPosition.name}',
        ),
        fit: lk.VideoViewFit.cover,
        mirrorMode: localPreviewMirrorMode,
      );
    } else if (remoteVideo != null && isVideo) {
      primaryContent = lk.VideoTrackRenderer(
        remoteVideo,
        key: ValueKey('primary-remote-${_callSession.call.id}'),
        fit: lk.VideoViewFit.cover,
      );
    } else {
      primaryContent = _buildPrimaryCallPlaceholder();
    }

    final previewOverlays = <Widget>[];
    if (isVideo && localVideo != null) {
      final previewChild = showLocalVideoPrimary
          ? (remoteVideo != null
                ? lk.VideoTrackRenderer(
                    remoteVideo,
                    key: ValueKey('preview-remote-${_callSession.call.id}'),
                    fit: lk.VideoViewFit.cover,
                  )
                : _buildPreviewPlaceholder(showLocalUser: false))
          : lk.VideoTrackRenderer(
              localVideo,
              key: ValueKey(
                'preview-local-${_callSession.call.id}-${adapter.cameraPosition.name}',
              ),
              fit: lk.VideoViewFit.cover,
              mirrorMode: localPreviewMirrorMode,
            );

      previewOverlays.add(
        Positioned(
          right: previewRight,
          top: previewTop,
          width: previewWidth,
          height: previewHeight,
          child: _buildVideoPreviewCard(
            onTap: _toggleVideoSwap,
            child: previewChild,
          ),
        ),
      );
    }

    return PopScope(
      canPop: !isVideo,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isVideo) {
          _minimizeCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF101314),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: isVideo ? _minimizeCall : _leaveCallView,
          ),
          title: Text(_callSession.call.peer.displayName),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: primaryContent),
              ...previewOverlays,
              if (localVideo != null && isVideo && adapter.cameraEnabled)
                Positioned(
                  right: previewRight,
                  top: previewBottom,
                  child: _buildCallControlButton(
                    backgroundColor: Colors.black54,
                    onPressed: adapter.connecting
                        ? null
                        : () => adapter.flipCamera(),
                    child: const Icon(
                      Icons.cameraswitch_outlined,
                      color: Colors.white,
                    ),
                  ),
                ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isVideo) ...[
                      _buildCallControlButton(
                        onPressed: adapter.connecting
                            ? null
                            : () => adapter.toggleCamera(),
                        child: Icon(
                          adapter.cameraEnabled
                              ? Icons.videocam
                              : Icons.videocam_off,
                          color: Colors.white,
                        ),
                      ),
                    ],
                    _buildCallControlButton(
                      onPressed: adapter.connecting
                          ? null
                          : () => adapter.toggleSpeaker(),
                      child: Icon(
                        adapter.speakerEnabled
                            ? Icons.volume_up
                            : Icons.hearing,
                        color: Colors.white,
                      ),
                    ),
                    _buildCallControlButton(
                      onPressed: adapter.connecting
                          ? null
                          : () => adapter.toggleMicrophone(),
                      child: Icon(
                        adapter.microphoneEnabled ? Icons.mic : Icons.mic_off,
                        color: Colors.white,
                      ),
                    ),
                    _buildCallControlButton(
                      backgroundColor: Colors.red.shade400,
                      onPressed: _ending ? null : _endCall,
                      child: const Icon(Icons.call_end, color: Colors.white),
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

class CallApi {
  static Future<List<TurnaCallHistoryItem>> fetchCalls(
    AuthSession session, {
    int refreshTick = 0,
  }) async {
    try {
      turnaLog('api fetchCalls', {'refreshTick': refreshTick});
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/calls'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (map['data'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                TurnaCallHistoryItem.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
      return items;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama gecmisi yuklenemedi.');
    }
  }

  static Future<TurnaCallSummary> startCall(
    AuthSession session, {
    required String calleeId,
    required TurnaCallType type,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/start'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'calleeId': calleeId, 'type': type.name}),
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      return TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(data['call'] as Map? ?? const {}),
      );
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama baslatilamadi.');
    }
  }

  static Future<TurnaAcceptedCallEvent> acceptCall(
    AuthSession session, {
    required String callId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/$callId/accept'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      return TurnaAcceptedCallEvent(
        call: TurnaCallSummary.fromMap(
          Map<String, dynamic>.from(data['call'] as Map? ?? const {}),
        ),
        connect: TurnaCallConnectPayload.fromMap(
          Map<String, dynamic>.from(data['connect'] as Map? ?? const {}),
        ),
      );
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama kabul edilemedi.');
    }
  }

  static Future<void> declineCall(
    AuthSession session, {
    required String callId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/$callId/decline'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama reddedilemedi.');
    }
  }

  static Future<void> endCall(
    AuthSession session, {
    required String callId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/$callId/end'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama sonlandirilamadi.');
    }
  }

  static Future<List<String>> reconcileCalls(AuthSession session) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/reconcile'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      final calls = (data['calls'] as List<dynamic>? ?? const []);
      return calls
          .whereType<Map>()
          .map((item) => (item['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama durumu esitlenemedi.');
    }
  }
}
