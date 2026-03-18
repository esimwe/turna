part of 'turna_app.dart';

mixin _TurnaMainTabsRuntime on State<MainTabs> {
  ValueNotifier<int> get _inboxUpdateNotifier;
  TurnaCallCoordinator get _callCoordinator;
  bool get _openingPushChat;
  set _openingPushChat(bool value);
  String? get _lastPushOpenedChatId;
  set _lastPushOpenedChatId(String? value);

  void focusChatsTab();
  void _handleSessionExpired();

  ChatPreview? _findChatPreview(ChatInboxData? inbox, String chatId) {
    if (inbox == null) return null;
    for (final chat in inbox.chats) {
      if (chat.chatId == chatId) return chat;
    }
    return null;
  }

  ChatPreview _previewFromDetail(TurnaChatDetail detail) {
    final title = detail.title.trim();
    return ChatPreview(
      chatId: detail.chatId,
      chatType: detail.chatType,
      name: title.isEmpty ? 'Sohbet' : title,
      message: '',
      time: '',
      avatarUrl: detail.avatarUrl,
      memberPreviewNames: detail.memberPreviewNames,
      memberCount: detail.memberCount,
      myRole: detail.myRole,
      description: detail.description,
      isPublic: detail.isPublic,
    );
  }

  Future<ChatPreview?> _resolvePushChatPreview(String chatId) async {
    final userId = widget.session.userId;
    final cachedInbox =
        TurnaChatInboxLocalCache.peek(userId) ??
        await TurnaChatInboxLocalCache.load(userId);
    final cachedMatch = _findChatPreview(cachedInbox, chatId);
    if (cachedMatch != null) return cachedMatch;

    try {
      final freshInbox = await ChatApi.fetchChats(widget.session);
      final freshMatch = _findChatPreview(freshInbox, chatId);
      if (freshMatch != null) return freshMatch;
    } catch (error) {
      turnaLog('push chat inbox refresh skipped', {
        'chatId': chatId,
        'error': error.toString(),
      });
    }

    try {
      final detail = await ChatApi.fetchChatDetail(widget.session, chatId);
      return _previewFromDetail(detail);
    } catch (error) {
      turnaLog('push chat detail load failed', {
        'chatId': chatId,
        'error': error.toString(),
      });
      return null;
    }
  }

  Future<void> _handlePushChatOpen(String chatId) async {
    final normalizedChatId = chatId.trim();
    if (!mounted || normalizedChatId.isEmpty) return;
    if (_openingPushChat && _lastPushOpenedChatId == normalizedChatId) return;
    if (kTurnaActiveChatRegistry.isChatActive(normalizedChatId)) {
      focusChatsTab();
      _inboxUpdateNotifier.value++;
      return;
    }

    _openingPushChat = true;
    _lastPushOpenedChatId = normalizedChatId;
    try {
      focusChatsTab();
      _inboxUpdateNotifier.value++;
      final chat = await _resolvePushChatPreview(normalizedChatId);
      if (!mounted || chat == null) return;
      if (kTurnaActiveChatRegistry.isChatActive(chat.chatId)) return;
      final navigator = kTurnaNavigatorKey.currentState;
      if (navigator == null) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      await navigator.push(
        buildChatRoomRoute(
          chat: chat,
          session: widget.session,
          callCoordinator: _callCoordinator,
          onSessionExpired: _handleSessionExpired,
        ),
      );
    } finally {
      _openingPushChat = false;
    }
  }

  ChatAttachmentKind _attachmentKindForSharedItem(
    TurnaIncomingSharedItem item,
  ) {
    final mimeType = item.mimeType.toLowerCase();
    if (mimeType.startsWith('image/')) {
      return ChatAttachmentKind.image;
    }
    if (mimeType.startsWith('video/')) {
      return ChatAttachmentKind.video;
    }
    final guessed =
        guessContentTypeForFileName(item.fileName)?.toLowerCase() ?? '';
    if (guessed.startsWith('image/')) {
      return ChatAttachmentKind.image;
    }
    if (guessed.startsWith('video/')) {
      return ChatAttachmentKind.video;
    }
    return ChatAttachmentKind.file;
  }

  Future<OutgoingAttachmentDraft> _uploadIncomingSharedItem(
    ChatPreview targetChat,
    TurnaIncomingSharedItem item,
  ) async {
    final file = File(item.filePath);
    if (!await file.exists()) {
      throw TurnaApiException('Paylasilan dosya bulunamadi.');
    }

    final fileName = item.fileName.trim().isNotEmpty
        ? item.fileName.trim()
        : file.uri.pathSegments.last;
    final contentType = item.mimeType.trim().isNotEmpty
        ? item.mimeType.trim()
        : (guessContentTypeForFileName(fileName) ?? 'application/octet-stream');
    final kind = _attachmentKindForSharedItem(item);
    final sizeBytes = item.sizeBytes > 0 ? item.sizeBytes : await file.length();

    if (kind != ChatAttachmentKind.file) {
      final prepared = await _prepareTurnaInlineMediaAttachment(
        MediaComposerSeed(
          kind: kind,
          file: XFile(file.path, name: fileName, mimeType: contentType),
          fileName: fileName,
          contentType: contentType,
          sizeBytes: sizeBytes,
        ),
      );
      final upload = await ChatApi.createAttachmentUpload(
        widget.session,
        chatId: targetChat.chatId,
        kind: prepared.kind,
        contentType: prepared.contentType,
        fileName: prepared.fileName,
      );
      await _uploadPreparedIncomingSharedAttachment(upload, prepared);
      turnaLog('share target media uploaded', {
        'chatId': targetChat.chatId,
        'kind': prepared.kind.name,
        'transferMode': MediaComposerQuality.standard.transferMode.name,
      });
      return OutgoingAttachmentDraft(
        objectKey: upload.objectKey,
        kind: prepared.kind,
        transferMode: MediaComposerQuality.standard.transferMode,
        fileName: prepared.fileName,
        contentType: prepared.contentType,
        sizeBytes: prepared.sizeBytes,
        width: prepared.width,
        height: prepared.height,
        durationSeconds: prepared.durationSeconds,
      );
    }

    final upload = await ChatApi.createAttachmentUpload(
      widget.session,
      chatId: targetChat.chatId,
      kind: kind,
      contentType: contentType,
      fileName: fileName,
    );

    final request = http.StreamedRequest('PUT', Uri.parse(upload.uploadUrl));
    request.headers.addAll(upload.headers);
    request.contentLength = sizeBytes;
    final responseFuture = request.send();
    await file.openRead().pipe(request.sink);
    final uploadRes = await responseFuture;
    if (uploadRes.statusCode >= 400) {
      throw TurnaApiException('Paylasilan dosya yuklenemedi.');
    }

    return OutgoingAttachmentDraft(
      objectKey: upload.objectKey,
      kind: kind,
      transferMode: ChatAttachmentTransferMode.document,
      fileName: fileName,
      contentType: contentType,
      sizeBytes: sizeBytes,
    );
  }

  Future<void> _uploadPreparedIncomingSharedAttachment(
    ChatAttachmentUploadTicket upload,
    _PreparedComposerAttachment prepared,
  ) async {
    if (prepared.filePath != null && prepared.filePath!.trim().isNotEmpty) {
      final file = File(prepared.filePath!);
      if (!await file.exists()) {
        throw TurnaApiException('Hazirlanan dosya bulunamadi.');
      }
      final request = http.StreamedRequest('PUT', Uri.parse(upload.uploadUrl));
      request.headers.addAll(upload.headers);
      request.contentLength = prepared.sizeBytes;
      final responseFuture = request.send();
      await file.openRead().pipe(request.sink);
      final uploadRes = await responseFuture;
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Paylasilan dosya yuklenemedi.');
      }
      return;
    }

    final bytes = prepared.bytes;
    if (bytes == null) {
      throw TurnaApiException('Hazirlanan dosya okunamadi.');
    }
    final uploadRes = await http.put(
      Uri.parse(upload.uploadUrl),
      headers: upload.headers,
      body: bytes,
    );
    if (uploadRes.statusCode >= 400) {
      throw TurnaApiException('Paylasilan dosya yuklenemedi.');
    }
  }

  TurnaStatusType? _statusTypeForSharedItem(TurnaIncomingSharedItem item) {
    final mimeType = item.mimeType.toLowerCase();
    if (mimeType.startsWith('image/')) {
      return TurnaStatusType.image;
    }
    if (mimeType.startsWith('video/')) {
      return TurnaStatusType.video;
    }
    final guessed =
        guessContentTypeForFileName(item.fileName)?.toLowerCase() ?? '';
    if (guessed.startsWith('image/')) {
      return TurnaStatusType.image;
    }
    if (guessed.startsWith('video/')) {
      return TurnaStatusType.video;
    }
    return null;
  }

  Future<void> _shareIncomingPayloadToChat(
    ChatPreview targetChat,
    TurnaIncomingSharePayload payload, {
    String? text,
  }) async {
    final drafts = <OutgoingAttachmentDraft>[];
    for (final item in payload.items) {
      drafts.add(await _uploadIncomingSharedItem(targetChat, item));
    }
    if (drafts.isEmpty) {
      throw TurnaApiException('Paylasilacak dosya bulunamadi.');
    }
    await ChatApi.sendMessage(
      widget.session,
      chatId: targetChat.chatId,
      text: text,
      attachments: drafts,
    );
  }

  Future<void> _shareIncomingPayloadToStatus(
    TurnaIncomingSharePayload payload,
  ) async {
    var sharedAny = false;
    for (final item in payload.items) {
      final type = _statusTypeForSharedItem(item);
      if (type == null) {
        continue;
      }
      final file = File(item.filePath);
      if (!await file.exists()) {
        continue;
      }
      final fileName = item.fileName.trim().isNotEmpty
          ? item.fileName.trim()
          : file.uri.pathSegments.last;
      final contentType = item.mimeType.trim().isNotEmpty
          ? item.mimeType.trim()
          : (guessContentTypeForFileName(fileName) ??
                (type == TurnaStatusType.video ? 'video/mp4' : 'image/jpeg'));
      final sizeBytes = item.sizeBytes > 0
          ? item.sizeBytes
          : await file.length();
      final upload = await TurnaStatusApi.createUpload(
        widget.session,
        type: type,
        contentType: contentType,
        fileName: fileName,
      );

      final request = http.StreamedRequest('PUT', Uri.parse(upload.uploadUrl));
      request.headers.addAll(upload.headers);
      request.contentLength = sizeBytes;
      final responseFuture = request.send();
      await file.openRead().pipe(request.sink);
      final uploadRes = await responseFuture;
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Durum dosyasi yuklenemedi.');
      }

      await TurnaStatusApi.createMediaStatus(
        widget.session,
        type: type,
        objectKey: upload.objectKey,
        contentType: contentType,
        fileName: fileName,
        sizeBytes: sizeBytes,
      );
      sharedAny = true;
    }

    if (!sharedAny) {
      throw TurnaApiException(
        'Bu paylasim durum olarak gonderilebilecek fotograf veya video icermiyor.',
      );
    }
  }

  Future<void> _handleIncomingSharePayload(
    TurnaIncomingSharePayload payload,
  ) async {
    if (!mounted || payload.isEmpty) return;
    turnaLog('share target handling started', {'items': payload.items.length});
    focusChatsTab();
    _inboxUpdateNotifier.value++;

    NavigatorState? navigator = kTurnaNavigatorKey.currentState;
    var attempts = 0;
    while (navigator == null && attempts < 10) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      navigator = kTurnaNavigatorKey.currentState;
      attempts++;
    }
    if (navigator == null) {
      turnaLog('share target navigator unavailable');
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    turnaLog('share target picker presenting');

    final selection = await navigator.push<TurnaShareTargetSelectionResult>(
      MaterialPageRoute(
        builder: (_) => ForwardMessagePickerPage(
          session: widget.session,
          currentChatId: '',
          title: 'Turna\'da paylas',
          sharePayload: payload,
          callCoordinator: _callCoordinator,
          onSessionExpired: _handleSessionExpired,
        ),
      ),
    );
    turnaLog('share target picker dismissed', {
      'hasSelection': selection != null,
      'hasTargets': selection?.hasTargets ?? false,
    });
    if (!mounted || selection == null || !selection.hasTargets) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Paylasim gonderiliyor...')),
    );

    try {
      if (selection.shareToStatus) {
        await _shareIncomingPayloadToStatus(payload);
      }
      for (final chat in selection.chats) {
        await _shareIncomingPayloadToChat(
          chat,
          payload,
          text: selection.caption,
        );
      }
      if (!mounted) return;
      final sentTargetCount =
          selection.chats.length + (selection.shareToStatus ? 1 : 0);
      final sentTargetLabel = sentTargetCount == 1
          ? (selection.shareToStatus && selection.chats.isEmpty
                ? 'Durumum'
                : selection.chats.first.name)
          : '$sentTargetCount hedefe';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$sentTargetLabel gonderildi.')));
      _inboxUpdateNotifier.value++;
      if (!selection.shareToStatus && selection.chats.length == 1) {
        await navigator.push(
          buildChatRoomRoute(
            chat: selection.chats.first,
            session: widget.session,
            callCoordinator: _callCoordinator,
            onSessionExpired: _handleSessionExpired,
          ),
        );
      }
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      _handleSessionExpired();
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
