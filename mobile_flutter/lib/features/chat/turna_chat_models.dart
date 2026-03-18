String? _turnaChatNullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

enum TurnaChatType { direct, group }

enum TurnaChatCollectionType { media, docs, links }

class ChatPreview {
  ChatPreview({
    required this.chatId,
    required this.name,
    required this.message,
    required this.time,
    this.chatType = TurnaChatType.direct,
    this.memberPreviewNames = const <String>[],
    this.phone,
    this.avatarUrl,
    this.peerId,
    this.memberCount = 0,
    this.myRole,
    this.description,
    this.isPublic = false,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isBlockedByMe = false,
    this.isArchived = false,
    this.isFavorited = false,
    this.isLocked = false,
    this.folderId,
    this.folderName,
  });

  final String chatId;
  final String name;
  final String message;
  final String time;
  final TurnaChatType chatType;
  final List<String> memberPreviewNames;
  final String? phone;
  final String? avatarUrl;
  final String? peerId;
  final int memberCount;
  final String? myRole;
  final String? description;
  final bool isPublic;
  final int unreadCount;
  final bool isMuted;
  final bool isBlockedByMe;
  final bool isArchived;
  final bool isFavorited;
  final bool isLocked;
  final String? folderId;
  final String? folderName;

  factory ChatPreview.fromCacheMap(Map<String, dynamic> map) {
    return ChatPreview(
      chatId: (map['chatId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      time: (map['time'] ?? '').toString(),
      chatType: ((map['chatType'] ?? '').toString().toLowerCase() == 'group')
          ? TurnaChatType.group
          : TurnaChatType.direct,
      memberPreviewNames:
          (map['memberPreviewNames'] as List<dynamic>? ?? const [])
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(),
      phone: _turnaChatNullableString(map['phone']),
      avatarUrl: _turnaChatNullableString(map['avatarUrl']),
      peerId: _turnaChatNullableString(map['peerId']),
      memberCount: (map['memberCount'] as num?)?.toInt() ?? 0,
      myRole: _turnaChatNullableString(map['myRole']),
      description: _turnaChatNullableString(map['description']),
      isPublic: map['isPublic'] == true,
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
      isMuted: map['isMuted'] == true,
      isBlockedByMe: map['isBlockedByMe'] == true,
      isArchived: map['isArchived'] == true,
      isFavorited: map['isFavorited'] == true,
      isLocked: map['isLocked'] == true,
      folderId: _turnaChatNullableString(map['folderId']),
      folderName: _turnaChatNullableString(map['folderName']),
    );
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'chatId': chatId,
      'name': name,
      'message': message,
      'time': time,
      'chatType': chatType.name,
      'memberPreviewNames': memberPreviewNames,
      'phone': phone,
      'avatarUrl': avatarUrl,
      'peerId': peerId,
      'memberCount': memberCount,
      'myRole': myRole,
      'description': description,
      'isPublic': isPublic,
      'unreadCount': unreadCount,
      'isMuted': isMuted,
      'isBlockedByMe': isBlockedByMe,
      'isArchived': isArchived,
      'isFavorited': isFavorited,
      'isLocked': isLocked,
      'folderId': folderId,
      'folderName': folderName,
    };
  }
}

class TurnaChatDetail {
  TurnaChatDetail({
    required this.chatId,
    required this.chatType,
    required this.title,
    this.memberPreviewNames = const <String>[],
    this.description,
    this.avatarUrl,
    this.createdByUserId,
    this.memberCount = 0,
    this.myRole,
    this.isPublic = false,
    this.joinApprovalRequired = false,
    this.memberAddPolicy = 'ADMIN_ONLY',
    this.whoCanSend = 'EVERYONE',
    this.whoCanEditInfo = 'EDITOR_ONLY',
    this.whoCanInvite = 'ADMIN_ONLY',
    this.whoCanAddMembers = 'ADMIN_ONLY',
    this.whoCanStartCalls = 'EDITOR_ONLY',
    this.historyVisibleToNewMembers = true,
    this.myCanSend = true,
    this.myIsMuted = false,
    this.myMutedUntil,
    this.myMuteReason,
  });

  final String chatId;
  final TurnaChatType chatType;
  final String title;
  final List<String> memberPreviewNames;
  final String? description;
  final String? avatarUrl;
  final String? createdByUserId;
  final int memberCount;
  final String? myRole;
  final bool isPublic;
  final bool joinApprovalRequired;
  final String memberAddPolicy;
  final String whoCanSend;
  final String whoCanEditInfo;
  final String whoCanInvite;
  final String whoCanAddMembers;
  final String whoCanStartCalls;
  final bool historyVisibleToNewMembers;
  final bool myCanSend;
  final bool myIsMuted;
  final String? myMutedUntil;
  final String? myMuteReason;

  TurnaChatDetail copyWith({
    String? title,
    List<String>? memberPreviewNames,
    String? description,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    int? memberCount,
    String? myRole,
    bool? isPublic,
    bool? joinApprovalRequired,
    String? memberAddPolicy,
    String? whoCanSend,
    String? whoCanEditInfo,
    String? whoCanInvite,
    String? whoCanAddMembers,
    String? whoCanStartCalls,
    bool? historyVisibleToNewMembers,
    bool? myCanSend,
    bool? myIsMuted,
    String? myMutedUntil,
    String? myMuteReason,
  }) {
    return TurnaChatDetail(
      chatId: chatId,
      chatType: chatType,
      title: title ?? this.title,
      memberPreviewNames: memberPreviewNames ?? this.memberPreviewNames,
      description: description ?? this.description,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      createdByUserId: createdByUserId,
      memberCount: memberCount ?? this.memberCount,
      myRole: myRole ?? this.myRole,
      isPublic: isPublic ?? this.isPublic,
      joinApprovalRequired: joinApprovalRequired ?? this.joinApprovalRequired,
      memberAddPolicy: memberAddPolicy ?? this.memberAddPolicy,
      whoCanSend: whoCanSend ?? this.whoCanSend,
      whoCanEditInfo: whoCanEditInfo ?? this.whoCanEditInfo,
      whoCanInvite: whoCanInvite ?? this.whoCanInvite,
      whoCanAddMembers: whoCanAddMembers ?? this.whoCanAddMembers,
      whoCanStartCalls: whoCanStartCalls ?? this.whoCanStartCalls,
      historyVisibleToNewMembers:
          historyVisibleToNewMembers ?? this.historyVisibleToNewMembers,
      myCanSend: myCanSend ?? this.myCanSend,
      myIsMuted: myIsMuted ?? this.myIsMuted,
      myMutedUntil: myMutedUntil ?? this.myMutedUntil,
      myMuteReason: myMuteReason ?? this.myMuteReason,
    );
  }

  factory TurnaChatDetail.fromMap(Map<String, dynamic> map) {
    return TurnaChatDetail(
      chatId: (map['chatId'] ?? '').toString(),
      chatType: ((map['chatType'] ?? '').toString().toLowerCase() == 'group')
          ? TurnaChatType.group
          : TurnaChatType.direct,
      title: (map['title'] ?? '').toString(),
      memberPreviewNames:
          (map['memberPreviewNames'] as List<dynamic>? ?? const [])
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(),
      description: _turnaChatNullableString(map['description']),
      avatarUrl: _turnaChatNullableString(map['avatarUrl']),
      createdByUserId: _turnaChatNullableString(map['createdByUserId']),
      memberCount: (map['memberCount'] as num?)?.toInt() ?? 0,
      myRole: _turnaChatNullableString(map['myRole']),
      isPublic: map['isPublic'] == true,
      joinApprovalRequired: map['joinApprovalRequired'] == true,
      memberAddPolicy:
          _turnaChatNullableString(map['memberAddPolicy']) ?? 'ADMIN_ONLY',
      whoCanSend: _turnaChatNullableString(map['whoCanSend']) ?? 'EVERYONE',
      whoCanEditInfo:
          _turnaChatNullableString(map['whoCanEditInfo']) ?? 'EDITOR_ONLY',
      whoCanInvite:
          _turnaChatNullableString(map['whoCanInvite']) ?? 'ADMIN_ONLY',
      whoCanAddMembers:
          _turnaChatNullableString(map['whoCanAddMembers']) ??
          _turnaChatNullableString(map['memberAddPolicy']) ??
          'ADMIN_ONLY',
      whoCanStartCalls:
          _turnaChatNullableString(map['whoCanStartCalls']) ?? 'EDITOR_ONLY',
      historyVisibleToNewMembers: map['historyVisibleToNewMembers'] != false,
      myCanSend: map['myCanSend'] != false,
      myIsMuted: map['myIsMuted'] == true,
      myMutedUntil: _turnaChatNullableString(map['myMutedUntil']),
      myMuteReason: _turnaChatNullableString(map['myMuteReason']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'chatType': chatType.name,
      'title': title,
      'memberPreviewNames': memberPreviewNames,
      'description': description,
      'avatarUrl': avatarUrl,
      'createdByUserId': createdByUserId,
      'memberCount': memberCount,
      'myRole': myRole,
      'isPublic': isPublic,
      'joinApprovalRequired': joinApprovalRequired,
      'memberAddPolicy': memberAddPolicy,
      'whoCanSend': whoCanSend,
      'whoCanEditInfo': whoCanEditInfo,
      'whoCanInvite': whoCanInvite,
      'whoCanAddMembers': whoCanAddMembers,
      'whoCanStartCalls': whoCanStartCalls,
      'historyVisibleToNewMembers': historyVisibleToNewMembers,
      'myCanSend': myCanSend,
      'myIsMuted': myIsMuted,
      'myMutedUntil': myMutedUntil,
      'myMuteReason': myMuteReason,
    };
  }
}

class TurnaGroupMember {
  TurnaGroupMember({
    required this.userId,
    required this.displayName,
    this.username,
    this.phone,
    this.role = 'MEMBER',
    this.canSend = true,
    this.joinedAt,
    this.lastSeenAt,
    this.isMuted = false,
    this.mutedUntil,
    this.muteReason,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? phone;
  final String role;
  final bool canSend;
  final String? joinedAt;
  final String? lastSeenAt;
  final bool isMuted;
  final String? mutedUntil;
  final String? muteReason;
  final String? avatarUrl;

  factory TurnaGroupMember.fromMap(Map<String, dynamic> map) {
    return TurnaGroupMember(
      userId: (map['userId'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      username: _turnaChatNullableString(map['username']),
      phone: _turnaChatNullableString(map['phone']),
      role: _turnaChatNullableString(map['role']) ?? 'MEMBER',
      canSend: map['canSend'] != false,
      joinedAt: _turnaChatNullableString(map['joinedAt']),
      lastSeenAt: _turnaChatNullableString(map['lastSeenAt']),
      isMuted: map['isMuted'] == true,
      mutedUntil: _turnaChatNullableString(map['mutedUntil']),
      muteReason: _turnaChatNullableString(map['muteReason']),
      avatarUrl: _turnaChatNullableString(map['avatarUrl']),
    );
  }
}

class TurnaGroupMembersPage {
  TurnaGroupMembersPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
  });

  final List<TurnaGroupMember> items;
  final int totalCount;
  final bool hasMore;
}

class TurnaGroupInviteLink {
  TurnaGroupInviteLink({
    required this.id,
    required this.token,
    required this.inviteUrl,
    this.expiresAt,
    this.revokedAt,
    this.createdAt,
  });

  final String id;
  final String token;
  final String inviteUrl;
  final String? expiresAt;
  final String? revokedAt;
  final String? createdAt;

  factory TurnaGroupInviteLink.fromMap(Map<String, dynamic> map) {
    return TurnaGroupInviteLink(
      id: (map['id'] ?? '').toString(),
      token: (map['token'] ?? '').toString(),
      inviteUrl:
          _turnaChatNullableString(map['inviteUrl']) ??
          'turna://join-group?token=${(map['token'] ?? '').toString()}',
      expiresAt: _turnaChatNullableString(map['expiresAt']),
      revokedAt: _turnaChatNullableString(map['revokedAt']),
      createdAt: _turnaChatNullableString(map['createdAt']),
    );
  }
}

class TurnaGroupJoinRequest {
  TurnaGroupJoinRequest({
    required this.id,
    required this.userId,
    required this.displayName,
    this.username,
    this.phone,
    this.avatarUrl,
    this.createdAt,
    this.status = 'PENDING',
  });

  final String id;
  final String userId;
  final String displayName;
  final String? username;
  final String? phone;
  final String? avatarUrl;
  final String? createdAt;
  final String status;

  factory TurnaGroupJoinRequest.fromMap(Map<String, dynamic> map) {
    return TurnaGroupJoinRequest(
      id: (map['id'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      username: _turnaChatNullableString(map['username']),
      phone: _turnaChatNullableString(map['phone']),
      avatarUrl:
          _turnaChatNullableString(map['avatarUrl']) ??
          _turnaChatNullableString(map['avatarKey']),
      createdAt: _turnaChatNullableString(map['createdAt']),
      status: _turnaChatNullableString(map['status']) ?? 'PENDING',
    );
  }
}

class TurnaGroupMuteEntry {
  TurnaGroupMuteEntry({
    required this.id,
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.reason,
    this.mutedUntil,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String? reason;
  final String? mutedUntil;
  final String? createdAt;

  factory TurnaGroupMuteEntry.fromMap(Map<String, dynamic> map) {
    return TurnaGroupMuteEntry(
      id: (map['id'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      username: _turnaChatNullableString(map['username']),
      avatarUrl:
          _turnaChatNullableString(map['avatarUrl']) ??
          _turnaChatNullableString(map['avatarKey']),
      reason: _turnaChatNullableString(map['reason']),
      mutedUntil: _turnaChatNullableString(map['mutedUntil']),
      createdAt: _turnaChatNullableString(map['createdAt']),
    );
  }
}

class TurnaGroupBanEntry {
  TurnaGroupBanEntry({
    required this.id,
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.reason,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String? reason;
  final String? createdAt;

  factory TurnaGroupBanEntry.fromMap(Map<String, dynamic> map) {
    return TurnaGroupBanEntry(
      id: (map['id'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      username: _turnaChatNullableString(map['username']),
      avatarUrl:
          _turnaChatNullableString(map['avatarUrl']) ??
          _turnaChatNullableString(map['avatarKey']),
      reason: _turnaChatNullableString(map['reason']),
      createdAt: _turnaChatNullableString(map['createdAt']),
    );
  }
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

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'sortOrder': sortOrder};
  }
}

class ChatInboxData {
  ChatInboxData({required this.chats, required this.folders});

  final List<ChatPreview> chats;
  final List<ChatFolder> folders;

  factory ChatInboxData.fromCacheMap(Map<String, dynamic> map) {
    final chatsData = map['chats'] as List<dynamic>? ?? const [];
    final foldersData = map['folders'] as List<dynamic>? ?? const [];
    return ChatInboxData(
      chats: chatsData
          .whereType<Map>()
          .map(
            (item) => ChatPreview.fromCacheMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      folders: foldersData
          .whereType<Map>()
          .map((item) => ChatFolder.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'chats': chats.map((chat) => chat.toCacheMap()).toList(),
      'folders': folders.map((folder) => folder.toMap()).toList(),
    };
  }
}

class ChatUser {
  ChatUser({required this.id, required this.displayName, this.avatarUrl});

  final String id;
  final String displayName;
  final String? avatarUrl;
}

enum ChatAttachmentKind { image, video, file }

enum ChatAttachmentTransferMode { standard, hd, document }

extension ChatAttachmentTransferModeX on ChatAttachmentTransferMode {
  String get label => switch (this) {
    ChatAttachmentTransferMode.standard => 'Standart',
    ChatAttachmentTransferMode.hd => 'HD',
    ChatAttachmentTransferMode.document => 'Dosya olarak gönder',
  };
}

class ChatAttachment {
  ChatAttachment({
    required this.id,
    required this.objectKey,
    required this.kind,
    required this.transferMode,
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
  final ChatAttachmentTransferMode transferMode;
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
    final transferModeText = (map['transferMode'] ?? '')
        .toString()
        .toLowerCase();
    final transferMode = switch (transferModeText) {
      'hd' => ChatAttachmentTransferMode.hd,
      'document' => ChatAttachmentTransferMode.document,
      _ => ChatAttachmentTransferMode.standard,
    };

    return ChatAttachment(
      id: (map['id'] ?? '').toString(),
      objectKey: (map['objectKey'] ?? '').toString(),
      kind: kind,
      transferMode: transferMode,
      fileName: _turnaChatNullableString(map['fileName']),
      contentType: (map['contentType'] ?? '').toString(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      url: _turnaChatNullableString(map['url']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'objectKey': objectKey,
      'kind': kind.name,
      'transferMode': transferMode.name,
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

class ChatMessageMention {
  const ChatMessageMention({
    required this.userId,
    this.username,
    this.displayName,
  });

  final String userId;
  final String? username;
  final String? displayName;

  factory ChatMessageMention.fromMap(Map<String, dynamic> map) {
    return ChatMessageMention(
      userId: (map['userId'] ?? '').toString(),
      username: _turnaChatNullableString(map['username']),
      displayName: _turnaChatNullableString(map['displayName']),
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'username': username,
    'displayName': displayName,
  };
}

class ChatMessageReaction {
  const ChatMessageReaction({
    required this.emoji,
    required this.count,
    this.userIds = const <String>[],
  });

  final String emoji;
  final int count;
  final List<String> userIds;

  factory ChatMessageReaction.fromMap(Map<String, dynamic> map) {
    return ChatMessageReaction(
      emoji: (map['emoji'] ?? '').toString(),
      count: (map['count'] as num?)?.toInt() ?? 0,
      userIds: (map['userIds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'emoji': emoji,
    'count': count,
    'userIds': userIds,
  };
}

class TurnaPinnedMessageSummary {
  const TurnaPinnedMessageSummary({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.previewText,
    required this.pinnedAt,
    required this.pinnedByUserId,
    required this.messageCreatedAt,
    this.senderDisplayName,
    this.pinnedByDisplayName,
  });

  final String messageId;
  final String chatId;
  final String senderId;
  final String previewText;
  final String pinnedAt;
  final String pinnedByUserId;
  final String messageCreatedAt;
  final String? senderDisplayName;
  final String? pinnedByDisplayName;

  factory TurnaPinnedMessageSummary.fromMap(Map<String, dynamic> map) {
    return TurnaPinnedMessageSummary(
      messageId: (map['messageId'] ?? '').toString(),
      chatId: (map['chatId'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      previewText: (map['previewText'] ?? '').toString(),
      pinnedAt: (map['pinnedAt'] ?? '').toString(),
      pinnedByUserId: (map['pinnedByUserId'] ?? '').toString(),
      messageCreatedAt: (map['messageCreatedAt'] ?? '').toString(),
      senderDisplayName: _turnaChatNullableString(map['senderDisplayName']),
      pinnedByDisplayName: _turnaChatNullableString(map['pinnedByDisplayName']),
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.status,
    required this.createdAt,
    this.chatType,
    this.senderDisplayName,
    this.systemType,
    this.systemPayload,
    this.editedAt,
    this.isEdited = false,
    this.editHistory = const [],
    this.mentions = const [],
    this.reactions = const [],
    this.isPinned = false,
    this.attachments = const [],
    this.errorText,
  });

  final String id;
  final String senderId;
  final String text;
  final ChatMessageStatus status;
  final String createdAt;
  final TurnaChatType? chatType;
  final String? senderDisplayName;
  final String? systemType;
  final Map<String, dynamic>? systemPayload;
  final String? editedAt;
  final bool isEdited;
  final List<ChatMessageEditHistoryEntry> editHistory;
  final List<ChatMessageMention> mentions;
  final List<ChatMessageReaction> reactions;
  final bool isPinned;
  final List<ChatAttachment> attachments;
  final String? errorText;

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? text,
    ChatMessageStatus? status,
    String? createdAt,
    TurnaChatType? chatType,
    String? senderDisplayName,
    String? systemType,
    Map<String, dynamic>? systemPayload,
    String? editedAt,
    bool? isEdited,
    List<ChatMessageEditHistoryEntry>? editHistory,
    List<ChatMessageMention>? mentions,
    List<ChatMessageReaction>? reactions,
    bool? isPinned,
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
      chatType: chatType ?? this.chatType,
      senderDisplayName: senderDisplayName ?? this.senderDisplayName,
      systemType: systemType ?? this.systemType,
      systemPayload: systemPayload ?? this.systemPayload,
      editedAt: editedAt ?? this.editedAt,
      isEdited: isEdited ?? this.isEdited,
      editHistory: editHistory ?? this.editHistory,
      mentions: mentions ?? this.mentions,
      reactions: reactions ?? this.reactions,
      isPinned: isPinned ?? this.isPinned,
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
      chatType: ((map['chatType'] ?? '').toString().toLowerCase() == 'group')
          ? TurnaChatType.group
          : ((map['chatType'] ?? '').toString().toLowerCase() == 'direct')
          ? TurnaChatType.direct
          : null,
      senderDisplayName: _turnaChatNullableString(map['senderDisplayName']),
      systemType: _turnaChatNullableString(map['systemType']),
      systemPayload: map['systemPayload'] is Map
          ? Map<String, dynamic>.from(map['systemPayload'] as Map)
          : null,
      editedAt: _turnaChatNullableString(map['editedAt']),
      isEdited: map['isEdited'] == true,
      editHistory: (map['editHistory'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChatMessageEditHistoryEntry.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      mentions: (map['mentions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ChatMessageMention.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      reactions: (map['reactions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ChatMessageReaction.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      isPinned: map['isPinned'] == true,
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
      'chatType': chatType?.name,
      'senderDisplayName': senderDisplayName,
      'systemType': systemType,
      'systemPayload': systemPayload,
      'editedAt': editedAt,
      'isEdited': isEdited,
      'editHistory': editHistory.map((entry) => entry.toMap()).toList(),
      'mentions': mentions.map((item) => item.toMap()).toList(),
      'reactions': reactions.map((item) => item.toMap()).toList(),
      'isPinned': isPinned,
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
      chatType: ((map['chatType'] ?? '').toString().toLowerCase() == 'group')
          ? TurnaChatType.group
          : ((map['chatType'] ?? '').toString().toLowerCase() == 'direct')
          ? TurnaChatType.direct
          : null,
      senderDisplayName: _turnaChatNullableString(map['senderDisplayName']),
      systemType: _turnaChatNullableString(map['systemType']),
      systemPayload: map['systemPayload'] is Map
          ? Map<String, dynamic>.from(map['systemPayload'] as Map)
          : null,
      editedAt: _turnaChatNullableString(map['editedAt']),
      isEdited: map['isEdited'] == true,
      editHistory: (map['editHistory'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChatMessageEditHistoryEntry.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      mentions: (map['mentions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ChatMessageMention.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      reactions: (map['reactions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ChatMessageReaction.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      isPinned: map['isPinned'] == true,
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChatAttachment.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      errorText: _turnaChatNullableString(map['errorText']),
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
