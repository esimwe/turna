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
        error = 'Canlı bağlantı kurulamadı.';
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
        error = 'Mesajlar yüklenemedi.';
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
      error = 'Eski mesajlar yüklenemedi.';
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
          : 'Bağlantı yok. Geri gelince otomatik gönderilecek.',
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
          : 'Bağlantı yok. Geri gelince otomatik gönderilecek.',
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
            ? 'Mesaj gönderilemedi. Tekrar dene.'
            : 'Bağlantı yok. Geri gelince otomatik gönderilecek.',
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

String? resolveTurnaSessionAvatarUrl(
  AuthSession session, {
  String? overrideAvatarUrl,
}) {
  final raw = (overrideAvatarUrl ?? session.avatarUrl)?.trim() ?? '';
  if (raw.isEmpty) return null;

  final parsed = Uri.tryParse(raw);
  final isAbsoluteUrl =
      parsed != null &&
      parsed.hasScheme &&
      (parsed.host.isNotEmpty || raw.startsWith('file:'));
  if (isAbsoluteUrl) {
    return normalizeTurnaRemoteUrl(raw);
  }

  return '$kBackendBaseUrl/api/profile/avatar/${Uri.encodeComponent(session.userId)}';
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
          return 'Bu kullanıcı adı başka bir hesapta kullanılıyor.';
        case 'username_change_rate_limited':
          return 'Kullanıcı adını 14 günde en fazla 2 kez değiştirebilirsin.';
        case 'invalid_username':
          return 'Kullanıcı adı uygun değil.';
        case 'validation_error':
          return 'Girilen bilgiler geçersiz.';
        case 'user_not_found':
          return 'Kullanıcı bulunamadı.';
        case 'phone_required':
          return 'Telefon numarası gerekli.';
        case 'invalid_phone':
          return 'Geçerli bir telefon numarası gir.';
        case 'invalid_otp_code':
          return 'Kod 6 haneli olmalı.';
        case 'otp_cooldown':
          return 'Lütfen biraz bekleyip tekrar dene.';
        case 'otp_rate_limited':
          return 'Çok fazla deneme yapıldı. Daha sonra tekrar dene.';
        case 'otp_invalid':
          return 'Kod hatalı. Yeniden dene.';
        case 'otp_expired':
          return 'Kodun suresi doldu. Yeni kod iste.';
        case 'otp_attempts_exceeded':
          return 'Çok fazla hatalı deneme yapıldı. Yeni kod iste.';
        case 'otp_not_found':
          return 'Doğrulama kodu bulunamadı. Yeni kod iste.';
        case 'otp_temporarily_unavailable':
        case 'login_temporarily_unavailable':
        case 'signup_temporarily_unavailable':
          return 'Doğrulama şu an kullanılamıyor.';
        case 'storage_not_configured':
          return 'Dosya depolama servisi hazır değil.';
        case 'invalid_avatar_key':
          return 'Avatar yüklemesi doğrulanamadı.';
        case 'invalid_attachment_key':
          return 'Medya yüklemesi doğrulanamadı.';
        case 'message_not_found':
          return 'Mesaj bulunamadı.';
        case 'message_delete_not_allowed':
          return 'Bu mesaj sadece gönderen tarafından herkesten silinebilir.';
        case 'message_delete_window_expired':
          return 'Mesaj artık herkesten silinemez. 10 dakika sınırı doldu.';
        case 'message_edit_not_allowed':
          return 'Bu mesaj artık düzenlenemez.';
        case 'message_edit_window_expired':
          return 'Mesaj düzenleme süresi doldu. 10 dakika sınırı doldu.';
        case 'message_edit_text_required':
          return 'Düzenlenecek mesaj boş olamaz.';
        case 'chat_folder_limit_reached':
          return 'En fazla 3 kategori oluşturabilirsin.';
        case 'chat_folder_exists':
          return 'Bu kategori adı zaten kullanılıyor.';
        case 'chat_folder_not_found':
          return 'Kategori bulunamadı.';
        case 'lookup_query_required':
          return 'Telefon numarası veya kullanıcı adı gir.';
        case 'uploaded_file_not_found':
          return 'Yüklenen dosya bulunamadı.';
        case 'avatar_not_found':
          return 'Avatar bulunamadı.';
        case 'text_or_attachment_required':
          return 'Mesaj veya ek seçmelisin.';
        case 'call_provider_not_configured':
          return 'Arama servisi henüz hazır değil.';
        case 'call_conflict':
          return 'Kullanıcılardan biri başka bir aramada.';
        case 'invalid_call_target':
          return 'Bu kullanıcı aranamaz.';
        case 'call_not_found':
          return 'Arama kaydı bulunamadı.';
        case 'call_not_ringing':
          return 'Bu arama artik cevaplanamaz.';
        case 'call_not_active':
          return 'Arama zaten sonlanmış.';
        case 'call_not_accepted':
          return 'Bu işlem sadece aktif görüşmede yapılabilir.';
        case 'call_already_video':
          return 'Görüşme zaten görüntülü.';
        case 'video_upgrade_request_conflict':
          return 'Zaten bekleyen bir görüntülü arama isteği var.';
        case 'call_no_pending_video_upgrade':
          return 'Bekleyen görüntülü arama isteği bulunamadı.';
        case 'video_upgrade_invalid_request':
          return 'Bu görüntülü arama isteği geçersiz.';
        case 'account_suspended':
          return 'Hesap geçici olarak durduruldu.';
        case 'account_banned':
          return 'Bu hesap kullanıma kapatıldı.';
        case 'otp_blocked':
          return 'Bu hesap için doğrulama kapatıldı.';
        case 'unauthorized':
        case 'invalid_token':
        case 'session_revoked':
          return 'Oturumun süresi doldu.';
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
        blocked ? 'Kişi engellenemedi.' : 'Engel kaldırılamadı.',
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
      throw TurnaApiException('Kişi listesine ulaşılamadı.');
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
      throw TurnaApiException('Rehber kişileri yüklenemedi.');
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
      throw TurnaApiException('Kategori oluşturulamadı.');
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
        archived ? 'Sohbet arşivlenemedi.' : 'Sohbet arşivden çıkarılamadı.',
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
      throw TurnaApiException('Sohbet kategorisi güncellenemedi.');
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
      throw TurnaApiException('Mesajlar yüklenemedi.');
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
      throw TurnaApiException('Dosya yükleme hazırlığı başarısız oldu.');
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
      throw TurnaApiException('Mesaj gönderilemedi.');
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
