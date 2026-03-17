part of '../main.dart';

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
      phone: TurnaUserProfile._nullableString(map['phone']),
      avatarUrl: TurnaUserProfile._nullableString(map['avatarUrl']),
      peerId: TurnaUserProfile._nullableString(map['peerId']),
      memberCount: (map['memberCount'] as num?)?.toInt() ?? 0,
      myRole: TurnaUserProfile._nullableString(map['myRole']),
      description: TurnaUserProfile._nullableString(map['description']),
      isPublic: map['isPublic'] == true,
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
      isMuted: map['isMuted'] == true,
      isBlockedByMe: map['isBlockedByMe'] == true,
      isArchived: map['isArchived'] == true,
      isFavorited: map['isFavorited'] == true,
      isLocked: map['isLocked'] == true,
      folderId: TurnaUserProfile._nullableString(map['folderId']),
      folderName: TurnaUserProfile._nullableString(map['folderName']),
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
      description: TurnaUserProfile._nullableString(map['description']),
      avatarUrl: TurnaUserProfile._nullableString(map['avatarUrl']),
      createdByUserId: TurnaUserProfile._nullableString(map['createdByUserId']),
      memberCount: (map['memberCount'] as num?)?.toInt() ?? 0,
      myRole: TurnaUserProfile._nullableString(map['myRole']),
      isPublic: map['isPublic'] == true,
      joinApprovalRequired: map['joinApprovalRequired'] == true,
      memberAddPolicy:
          TurnaUserProfile._nullableString(map['memberAddPolicy']) ??
          'ADMIN_ONLY',
      whoCanSend:
          TurnaUserProfile._nullableString(map['whoCanSend']) ?? 'EVERYONE',
      whoCanEditInfo:
          TurnaUserProfile._nullableString(map['whoCanEditInfo']) ??
          'EDITOR_ONLY',
      whoCanInvite:
          TurnaUserProfile._nullableString(map['whoCanInvite']) ?? 'ADMIN_ONLY',
      whoCanAddMembers:
          TurnaUserProfile._nullableString(map['whoCanAddMembers']) ??
          TurnaUserProfile._nullableString(map['memberAddPolicy']) ??
          'ADMIN_ONLY',
      whoCanStartCalls:
          TurnaUserProfile._nullableString(map['whoCanStartCalls']) ??
          'EDITOR_ONLY',
      historyVisibleToNewMembers: map['historyVisibleToNewMembers'] != false,
      myCanSend: map['myCanSend'] != false,
      myIsMuted: map['myIsMuted'] == true,
      myMutedUntil: TurnaUserProfile._nullableString(map['myMutedUntil']),
      myMuteReason: TurnaUserProfile._nullableString(map['myMuteReason']),
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
      username: TurnaUserProfile._nullableString(map['username']),
      phone: TurnaUserProfile._nullableString(map['phone']),
      role: TurnaUserProfile._nullableString(map['role']) ?? 'MEMBER',
      canSend: map['canSend'] != false,
      joinedAt: TurnaUserProfile._nullableString(map['joinedAt']),
      lastSeenAt: TurnaUserProfile._nullableString(map['lastSeenAt']),
      isMuted: map['isMuted'] == true,
      mutedUntil: TurnaUserProfile._nullableString(map['mutedUntil']),
      muteReason: TurnaUserProfile._nullableString(map['muteReason']),
      avatarUrl: TurnaUserProfile._nullableString(map['avatarUrl']),
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
          TurnaUserProfile._nullableString(map['inviteUrl']) ??
          'turna://join-group?token=${(map['token'] ?? '').toString()}',
      expiresAt: TurnaUserProfile._nullableString(map['expiresAt']),
      revokedAt: TurnaUserProfile._nullableString(map['revokedAt']),
      createdAt: TurnaUserProfile._nullableString(map['createdAt']),
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
      username: TurnaUserProfile._nullableString(map['username']),
      phone: TurnaUserProfile._nullableString(map['phone']),
      avatarUrl:
          TurnaUserProfile._nullableString(map['avatarUrl']) ??
          TurnaUserProfile._nullableString(map['avatarKey']),
      createdAt: TurnaUserProfile._nullableString(map['createdAt']),
      status: TurnaUserProfile._nullableString(map['status']) ?? 'PENDING',
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
      username: TurnaUserProfile._nullableString(map['username']),
      avatarUrl:
          TurnaUserProfile._nullableString(map['avatarUrl']) ??
          TurnaUserProfile._nullableString(map['avatarKey']),
      reason: TurnaUserProfile._nullableString(map['reason']),
      mutedUntil: TurnaUserProfile._nullableString(map['mutedUntil']),
      createdAt: TurnaUserProfile._nullableString(map['createdAt']),
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
      username: TurnaUserProfile._nullableString(map['username']),
      avatarUrl:
          TurnaUserProfile._nullableString(map['avatarUrl']) ??
          TurnaUserProfile._nullableString(map['avatarKey']),
      reason: TurnaUserProfile._nullableString(map['reason']),
      createdAt: TurnaUserProfile._nullableString(map['createdAt']),
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
    this.city,
    this.country,
    this.expertise,
    this.communityRole,
    this.interests = const <String>[],
    this.socialLinks = const <String>[],
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
  final String? city;
  final String? country;
  final String? expertise;
  final String? communityRole;
  final List<String> interests;
  final List<String> socialLinks;
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
      city: _nullableString(map['city']),
      country: _nullableString(map['country']),
      expertise: _nullableString(map['expertise']),
      communityRole: _nullableString(map['communityRole']),
      interests: _stringList(map['interests']),
      socialLinks: _stringList(map['socialLinks']),
      onboardingCompletedAt: _nullableString(map['onboardingCompletedAt']),
      createdAt: _nullableString(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'username': username,
      'phone': phone,
      'email': email,
      'about': about,
      'avatarUrl': avatarUrl,
      'city': city,
      'country': country,
      'expertise': expertise,
      'communityRole': communityRole,
      'interests': interests,
      'socialLinks': socialLinks,
      'onboardingCompletedAt': onboardingCompletedAt,
      'createdAt': createdAt,
    };
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

TurnaUserProfile buildTurnaSelfProfileFromSession(
  AuthSession session, {
  TurnaUserProfile? previous,
}) {
  return TurnaUserProfile(
    id: session.userId,
    displayName: session.displayName,
    username: session.username,
    phone: session.phone,
    about: previous?.about,
    email: previous?.email,
    avatarUrl: session.avatarUrl ?? previous?.avatarUrl,
    city: previous?.city,
    country: previous?.country,
    expertise: previous?.expertise,
    communityRole: previous?.communityRole,
    interests: previous?.interests ?? const <String>[],
    socialLinks: previous?.socialLinks ?? const <String>[],
    onboardingCompletedAt: previous?.onboardingCompletedAt,
    createdAt: previous?.createdAt,
  );
}

String? normalizeTurnaCommunityAccessRole(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

bool hasTurnaCommunityInternalAccess({TurnaUserProfile? profile}) {
  return normalizeTurnaCommunityAccessRole(profile?.communityRole) != null;
}

class TurnaProfileLocalCache {
  static const String _selfProfileKey = 'turna_profile_me_v1';
  static TurnaUserProfile? _warmSelfProfile;

  static TurnaUserProfile? peekSelfProfile(AuthSession session) {
    final warm = _warmSelfProfile;
    if (warm != null && warm.id == session.userId) {
      return buildTurnaSelfProfileFromSession(session, previous: warm);
    }
    final userWarm = TurnaUserProfileLocalCache.peek(session.userId);
    if (userWarm != null && userWarm.id == session.userId) {
      return buildTurnaSelfProfileFromSession(session, previous: userWarm);
    }
    return buildTurnaSelfProfileFromSession(session);
  }

  static Future<TurnaUserProfile?> loadSelfProfile(AuthSession session) async {
    final raw =
        await TurnaLocalStore.readJsonValue(
          table: TurnaLocalStore.userProfileTable,
          valueColumn: 'profile_json',
          where: const <String, Object?>{'cache_key': 'self'},
        ) ??
        (await SharedPreferences.getInstance()).getString(_selfProfileKey);
    if (raw == null || raw.trim().isEmpty) {
      final fallback = buildTurnaSelfProfileFromSession(session);
      _warmSelfProfile = fallback;
      return fallback;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cached = TurnaUserProfile.fromMap(decoded);
      if (cached.id != session.userId) {
        final fallback = buildTurnaSelfProfileFromSession(session);
        _warmSelfProfile = fallback;
        return fallback;
      }
      final merged = buildTurnaSelfProfileFromSession(
        session,
        previous: cached,
      );
      _warmSelfProfile = merged;
      await saveSelfProfile(merged);
      return merged;
    } catch (_) {
      final fallback = buildTurnaSelfProfileFromSession(session);
      _warmSelfProfile = fallback;
      return fallback;
    }
  }

  static Future<void> saveSelfProfile(TurnaUserProfile profile) async {
    _warmSelfProfile = profile;
    final encoded = jsonEncode(profile.toMap());
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.userProfileTable,
      valueColumn: 'profile_json',
      keyValues: const <String, Object?>{'cache_key': 'self'},
      extraValues: <String, Object?>{'user_id': profile.id, 'is_self': 1},
      jsonValue: encoded,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(_selfProfileKey);
      return;
    }
    await prefs.setString(_selfProfileKey, encoded);
  }

  static Future<void> clearSelfProfile() async {
    _warmSelfProfile = null;
    await TurnaLocalStore.deleteRows(
      table: TurnaLocalStore.userProfileTable,
      where: const <String, Object?>{'cache_key': 'self'},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selfProfileKey);
  }
}

class TurnaUserProfileLocalCache {
  static const String _prefix = 'turna_profile_user_v1_';
  static final Map<String, TurnaUserProfile> _warmProfiles =
      <String, TurnaUserProfile>{};

  static String _key(String userId) => '$_prefix$userId';

  static TurnaUserProfile? peek(String userId) => _warmProfiles[userId];

  static Future<TurnaUserProfile?> load(String userId) async {
    final warm = _warmProfiles[userId];
    if (warm != null) return warm;

    final raw =
        await TurnaLocalStore.readJsonValue(
          table: TurnaLocalStore.userProfileTable,
          valueColumn: 'profile_json',
          where: <String, Object?>{'cache_key': userId},
        ) ??
        (await SharedPreferences.getInstance()).getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final profile = TurnaUserProfile.fromMap(decoded);
      _warmProfiles[userId] = profile;
      await save(profile);
      return profile;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(TurnaUserProfile profile) async {
    _warmProfiles[profile.id] = profile;
    final encoded = jsonEncode(profile.toMap());
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.userProfileTable,
      valueColumn: 'profile_json',
      keyValues: <String, Object?>{'cache_key': profile.id},
      extraValues: <String, Object?>{'user_id': profile.id, 'is_self': 0},
      jsonValue: encoded,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(_key(profile.id));
      return;
    }
    await prefs.setString(_key(profile.id), encoded);
  }
}

class TurnaChatInboxLocalCache {
  static const String _prefix = 'turna_chat_inbox_v1_';
  static final Map<String, ChatInboxData> _warmInboxes =
      <String, ChatInboxData>{};

  static String _key(String userId) => '$_prefix$userId';

  static ChatInboxData? peek(String userId) => _warmInboxes[userId];

  static Future<ChatInboxData?> load(String userId) async {
    final warm = _warmInboxes[userId];
    if (warm != null) return warm;

    final raw =
        await TurnaLocalStore.readJsonValue(
          table: TurnaLocalStore.chatInboxTable,
          valueColumn: 'inbox_json',
          where: <String, Object?>{'owner_user_id': userId},
        ) ??
        (await SharedPreferences.getInstance()).getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final inbox = ChatInboxData.fromCacheMap(decoded);
      _warmInboxes[userId] = inbox;
      await save(userId, inbox);
      return inbox;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String userId, ChatInboxData inbox) async {
    _warmInboxes[userId] = inbox;
    final encoded = jsonEncode(inbox.toCacheMap());
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.chatInboxTable,
      valueColumn: 'inbox_json',
      keyValues: <String, Object?>{'owner_user_id': userId},
      jsonValue: encoded,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(_key(userId));
      return;
    }
    await prefs.setString(_key(userId), encoded);
  }
}

class TurnaChatDetailLocalCache {
  static const String _prefix = 'turna_chat_detail_v1_';
  static final Map<String, TurnaChatDetail> _warm = <String, TurnaChatDetail>{};

  static String _cacheId(String userId, String chatId) => '$userId::$chatId';

  static String _key(String userId, String chatId) {
    final raw = utf8.encode('$userId|$chatId');
    return '$_prefix${base64UrlEncode(raw)}';
  }

  static TurnaChatDetail? peek(String userId, String chatId) {
    return _warm[_cacheId(userId, chatId)];
  }

  static Future<TurnaChatDetail?> load(String userId, String chatId) async {
    final warm = peek(userId, chatId);
    if (warm != null) return warm;

    final raw =
        await TurnaLocalStore.readJsonValue(
          table: TurnaLocalStore.chatDetailTable,
          valueColumn: 'detail_json',
          where: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
        ) ??
        (await SharedPreferences.getInstance()).getString(_key(userId, chatId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final detail = TurnaChatDetail.fromMap(decoded);
      _warm[_cacheId(userId, chatId)] = detail;
      await save(userId, detail);
      return detail;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String userId, TurnaChatDetail detail) async {
    _warm[_cacheId(userId, detail.chatId)] = detail;
    final encoded = jsonEncode(detail.toMap());
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.chatDetailTable,
      valueColumn: 'detail_json',
      keyValues: <String, Object?>{
        'owner_user_id': userId,
        'chat_id': detail.chatId,
      },
      jsonValue: encoded,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(_key(userId, detail.chatId));
      return;
    }
    await prefs.setString(_key(userId, detail.chatId), encoded);
  }
}

class TurnaChatHistoryLocalCache {
  static const int _messageLimit = 320;
  static const String _prefix = 'turna_chat_history_v1_';
  static final Map<String, List<ChatMessage>> _warm =
      <String, List<ChatMessage>>{};

  static String _cacheId(String userId, String chatId) => '$userId::$chatId';

  static String _key(String userId, String chatId) {
    final raw = utf8.encode('$userId|$chatId');
    return '$_prefix${base64UrlEncode(raw)}';
  }

  static List<ChatMessage>? peek(String userId, String chatId) {
    final cached = _warm[_cacheId(userId, chatId)];
    if (cached == null) return null;
    return List<ChatMessage>.from(cached);
  }

  static Future<List<ChatMessage>> load(String userId, String chatId) async {
    final warm = peek(userId, chatId);
    if (warm != null) return warm;

    final items = <ChatMessage>[];
    final rawJson = await TurnaLocalStore.readJsonValue(
      table: TurnaLocalStore.chatMessageTable,
      valueColumn: 'messages_json',
      where: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
    );
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        for (final raw in decoded.whereType<Map>()) {
          items.add(ChatMessage.fromPendingMap(Map<String, dynamic>.from(raw)));
        }
      } catch (_) {}
    } else {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_key(userId, chatId)) ?? const [];
      for (final raw in rawList) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          items.add(ChatMessage.fromPendingMap(decoded));
        } catch (_) {}
      }
    }
    items.sort((a, b) => compareTurnaTimestamps(a.createdAt, b.createdAt));
    _warm[_cacheId(userId, chatId)] = List<ChatMessage>.from(items);
    if (items.isNotEmpty) {
      await saveMessages(userId, chatId, items);
    }
    return items;
  }

  static Future<void> saveMessages(
    String userId,
    String chatId,
    Iterable<ChatMessage> messages,
  ) async {
    final merged = messages.toList()
      ..sort((a, b) => compareTurnaTimestamps(a.createdAt, b.createdAt));
    final trimmed = merged.length <= _messageLimit
        ? merged
        : merged.sublist(merged.length - _messageLimit);
    _warm[_cacheId(userId, chatId)] = List<ChatMessage>.from(trimmed);

    final encoded = jsonEncode(
      trimmed.map((message) => message.toPendingMap()).toList(),
    );
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.chatMessageTable,
      valueColumn: 'messages_json',
      keyValues: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
      jsonValue: encoded,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(_key(userId, chatId));
      return;
    }
    await prefs.setStringList(
      _key(userId, chatId),
      trimmed.map((message) => jsonEncode(message.toPendingMap())).toList(),
    );
  }

  static Future<void> mergePage(
    String userId,
    String chatId,
    Iterable<ChatMessage> pageItems,
  ) async {
    final existing = await load(userId, chatId);
    final byId = <String, ChatMessage>{};
    for (final item in existing) {
      byId[item.id] = item;
    }
    for (final item in pageItems) {
      byId[item.id] = item;
    }
    await saveMessages(userId, chatId, byId.values);
  }
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
      username: TurnaUserProfile._nullableString(map['username']),
      displayName: TurnaUserProfile._nullableString(map['displayName']),
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
      senderDisplayName: TurnaUserProfile._nullableString(
        map['senderDisplayName'],
      ),
      pinnedByDisplayName: TurnaUserProfile._nullableString(
        map['pinnedByDisplayName'],
      ),
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
      senderDisplayName: TurnaUserProfile._nullableString(
        map['senderDisplayName'],
      ),
      systemType: TurnaUserProfile._nullableString(map['systemType']),
      systemPayload: map['systemPayload'] is Map
          ? Map<String, dynamic>.from(map['systemPayload'] as Map)
          : null,
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
      senderDisplayName: TurnaUserProfile._nullableString(
        map['senderDisplayName'],
      ),
      systemType: TurnaUserProfile._nullableString(map['systemType']),
      systemPayload: map['systemPayload'] is Map
          ? Map<String, dynamic>.from(map['systemPayload'] as Map)
          : null,
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

    final pendingMessages = await TurnaPendingChatMessageLocalCache.load(
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
    await TurnaPendingChatMessageLocalCache.save(
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
    final token = await TurnaSecureStateStore.readString(_tokenKey);
    final userId = await TurnaSecureStateStore.readString(_userIdKey);
    final displayName = await TurnaSecureStateStore.readString(_displayNameKey);
    final username = await TurnaSecureStateStore.readString(_usernameKey);
    final phone = await TurnaSecureStateStore.readString(_phoneKey);
    final avatarUrl = await TurnaSecureStateStore.readString(_avatarUrlKey);
    final needsOnboarding =
        await TurnaSecureStateStore.readBool(_needsOnboardingKey) ?? false;
    if (token == null || userId == null || displayName == null) {
      return null;
    }

    final session = AuthSession(
      token: token,
      userId: userId,
      displayName: displayName,
      username: username,
      phone: phone,
      avatarUrl: avatarUrl,
      needsOnboarding: needsOnboarding,
    );
    await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.authSessionTable,
      valueColumn: 'session_json',
      keyValues: const <String, Object?>{'slot': 'main'},
      jsonValue: jsonEncode(session._toLocalSnapshotMap()),
    );
    return session;
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

  Map<String, dynamic> _toLocalSnapshotMap() {
    return <String, dynamic>{
      'userId': userId,
      'displayName': displayName,
      'username': username,
      'phone': phone,
      'avatarUrl': avatarUrl,
      'needsOnboarding': needsOnboarding,
    };
  }

  Future<void> save() async {
    await TurnaSecureStateStore.writeString(_tokenKey, token);
    await TurnaSecureStateStore.writeString(_userIdKey, userId);
    await TurnaSecureStateStore.writeString(_displayNameKey, displayName);
    await TurnaSecureStateStore.writeString(_usernameKey, username);
    await TurnaSecureStateStore.writeString(_phoneKey, phone);
    await TurnaSecureStateStore.writeString(_avatarUrlKey, avatarUrl);
    await TurnaSecureStateStore.writeBool(_needsOnboardingKey, needsOnboarding);
    await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.authSessionTable,
      valueColumn: 'session_json',
      keyValues: const <String, Object?>{'slot': 'main'},
      jsonValue: jsonEncode(_toLocalSnapshotMap()),
    );
  }

  static Future<void> clear() async {
    await TurnaSecureStateStore.deleteMany(const <String>[
      _tokenKey,
      _userIdKey,
      _displayNameKey,
      _usernameKey,
      _phoneKey,
      _avatarUrlKey,
      _needsOnboardingKey,
    ]);
    await TurnaLocalStore.deleteRows(
      table: TurnaLocalStore.authSessionTable,
      where: const <String, Object?>{'slot': 'main'},
    );
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
  static bool _initialMessageChecked = false;

  static Future<void> _handleChatPushOpen(Map<String, dynamic> data) async {
    if ((data['type'] ?? '').toString() != 'chat_message') return;
    final chatId = (data['chatId'] ?? '').toString().trim();
    if (chatId.isEmpty) return;
    kTurnaPushChatOpenCoordinator.requestOpen(chatId);
  }

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

      final previousToken = await TurnaSecureStateStore.readString(
        _lastPushTokenKey,
      );
      if (previousToken != token) {
        await PushApi.registerDevice(
          session,
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
          tokenKind: 'standard',
          deviceLabel: Platform.isIOS ? 'ios-device' : 'android-device',
        );
        await TurnaSecureStateStore.writeString(_lastPushTokenKey, token);
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
          await _handleChatPushOpen(message.data);
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
            await TurnaSecureStateStore.writeString(
              _lastPushTokenKey,
              freshToken,
            );
          } catch (error) {
            turnaLog('push token refresh register failed', error);
          }
        });
      }
      if (!_initialMessageChecked) {
        _initialMessageChecked = true;
        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          turnaLog('push initial', initialMessage.data);
          await _handleChatPushOpen(initialMessage.data);
          await TurnaNativeCallManager.handleForegroundRemoteMessage(
            initialMessage.data,
          );
        }
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
    required this.transferMode,
    required this.contentType,
    required this.sizeBytes,
    this.fileName,
    this.width,
    this.height,
    this.durationSeconds,
  });

  final String objectKey;
  final ChatAttachmentKind kind;
  final ChatAttachmentTransferMode transferMode;
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
      'transferMode': transferMode.name,
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
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/profile/me'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res, label: 'fetchMe');

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final profile = TurnaUserProfile.fromMap(data);
      await TurnaProfileLocalCache.saveSelfProfile(profile);
      await TurnaUserProfileLocalCache.save(profile);
      return profile;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      final cached = await TurnaProfileLocalCache.loadSelfProfile(session);
      if (cached != null) return cached;
      throw TurnaApiException('Profil yuklenemedi.');
    }
  }

  static Future<TurnaUserProfile> fetchUser(
    AuthSession session,
    String userId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/profile/users/$userId'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res, label: 'fetchUser');

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final profile = TurnaUserProfile.fromMap(data);
      await TurnaUserProfileLocalCache.save(profile);
      return profile;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      final cached = await TurnaUserProfileLocalCache.load(userId);
      if (cached != null) return cached;
      throw TurnaApiException('Kullanici profili yuklenemedi.');
    }
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
    required String city,
    required String country,
    required String expertise,
    required String communityRole,
    required List<String> interests,
    required List<String> socialLinks,
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
        'city': city.trim(),
        'country': country.trim(),
        'expertise': expertise.trim(),
        'communityRole': communityRole.trim(),
        'interests': interests,
        'socialLinks': socialLinks,
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
        case 'message_reaction_not_allowed':
          return 'Bu mesaja tepki eklenemez.';
        case 'chat_search_query_required':
          return 'Arama için bir metin gir.';
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
        case 'group_title_required':
          return 'Grup adı gerekli.';
        case 'group_min_members_required':
          return 'Bir grup oluşturmak için en az bir kişi daha seçmelisin.';
        case 'group_member_limit_exceeded':
          return 'Bu grup 2048 üye sınırına ulaştı.';
        case 'group_member_not_found':
          return 'Seçilen üyelerden biri bulunamadı.';
        case 'group_member_add_not_allowed':
          return 'Bu gruba üye ekleme yetkin yok.';
        case 'group_invite_not_allowed':
          return 'Bu grupta davet bağlantısı yönetme yetkin yok.';
        case 'group_invite_not_found':
          return 'Davet bağlantısı bulunamadı.';
        case 'group_invite_expired':
          return 'Bu davet bağlantısının süresi dolmuş.';
        case 'group_private':
          return 'Bu grup özel. Katılmak için davet bağlantısı gerekli.';
        case 'group_join_request_review_not_allowed':
          return 'Katılım isteklerini yönetme yetkin yok.';
        case 'group_join_request_not_found':
          return 'Katılım isteği bulunamadı.';
        case 'group_join_banned':
          return 'Bu gruba katılman engellenmiş.';
        case 'group_not_found':
          return 'Grup bulunamadı.';
        case 'group_owner_leave_not_allowed':
          return 'Grup sahibi önce sahipliği devretmeli.';
        case 'group_member_mute_not_allowed':
          return 'Bu üyeyi sessize alma yetkin yok.';
        case 'group_member_ban_not_allowed':
          return 'Bu üyeyi yasaklama yetkin yok.';
        case 'group_pin_not_allowed':
          return 'Bu grupta sabit mesaj yönetme yetkin yok.';
        case 'group_call_state_unavailable':
          return 'Grup çağrısı durumu şu an kullanılamıyor.';
        case 'group_call_type_required':
          return 'Başlatmak için sesli veya görüntülü çağrı seç.';
        case 'group_call_not_allowed':
          return 'Bu grupta çağrı başlatma yetkin yok.';
        case 'group_call_not_active':
          return 'Aktif grup çağrısı bulunamadı.';
        case 'group_call_moderation_not_allowed':
          return 'Bu çağrıyı yönetme yetkin yok.';
        case 'group_ban_not_found':
          return 'Aktif yasak kaydı bulunamadı.';
        case 'chat_send_restricted':
          return 'Bu grupta mesaj gönderme iznin kapalı.';
        case 'chat_rate_limited':
          return 'Çok hızlı mesaj gönderiyorsun. Biraz bekleyip tekrar dene.';
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
        final chatType =
            ((map['chatType'] ?? '').toString().toLowerCase() == 'group')
            ? TurnaChatType.group
            : TurnaChatType.direct;
        final rawTitle = map['title']?.toString() ?? 'Chat';
        final phone =
            chatType == TurnaChatType.direct && rawTitle.trim().startsWith('+')
            ? rawTitle.trim()
            : null;
        final fallbackName = phone == null
            ? rawTitle
            : formatTurnaDisplayPhone(phone);
        return ChatPreview(
          chatId: map['chatId'].toString(),
          chatType: chatType,
          name: TurnaContactsDirectory.resolveDisplayLabel(
            phone: phone,
            fallbackName: fallbackName,
          ),
          memberPreviewNames:
              (map['memberPreviewNames'] as List<dynamic>? ?? const [])
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty)
                  .toList(),
          message: sanitizeTurnaChatPreviewText(
            map['lastMessage']?.toString() ?? '',
          ),
          time: _formatTime(map['lastMessageAt']?.toString()),
          phone: phone,
          avatarUrl: _nullableString(map['avatarUrl']),
          peerId: _nullableString(map['peerId']),
          memberCount: (map['memberCount'] as num?)?.toInt() ?? 0,
          myRole: _nullableString(map['myRole']),
          description: _nullableString(map['description']),
          isPublic: map['isPublic'] == true,
          unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
          isMuted: map['isMuted'] == true,
          isBlockedByMe: map['isBlockedByMe'] == true,
          isArchived: map['isArchived'] == true,
          isFavorited: map['isFavorited'] == true,
          isLocked: map['isLocked'] == true,
          folderId: _nullableString(map['folderId']),
          folderName: _nullableString(map['folderName']),
        );
      }).toList();
      final folders = foldersData
          .whereType<Map>()
          .map((item) => ChatFolder.fromMap(Map<String, dynamic>.from(item)))
          .toList();
      final inbox = ChatInboxData(chats: chats, folders: folders);
      await TurnaChatInboxLocalCache.save(session.userId, inbox);
      return inbox;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      final cached = await TurnaChatInboxLocalCache.load(session.userId);
      if (cached != null) return cached;
      throw TurnaApiException('Sunucuya baglanilamadi.');
    }
  }

  static Future<TurnaChatDetail> fetchChatDetail(
    AuthSession session,
    String chatId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final detail = TurnaChatDetail.fromMap(data);
      await TurnaChatDetailLocalCache.save(session.userId, detail);
      return detail;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      final cached = await TurnaChatDetailLocalCache.load(
        session.userId,
        chatId,
      );
      if (cached != null) return cached;
      throw TurnaApiException('Sohbet detayları yüklenemedi.');
    }
  }

  static Future<TurnaGroupMembersPage> fetchGroupMembers(
    AuthSession session, {
    required String chatId,
    int limit = 40,
    int offset = 0,
  }) async {
    try {
      final uri = Uri.parse(
        '$kBackendBaseUrl/api/chats/$chatId/members',
      ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset'});
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (map['data'] as List<dynamic>? ?? const []);
      final pageInfo = map['pageInfo'] as Map<String, dynamic>? ?? const {};
      return TurnaGroupMembersPage(
        items: data
            .whereType<Map>()
            .map(
              (item) =>
                  TurnaGroupMember.fromMap(Map<String, dynamic>.from(item)),
            )
            .toList(),
        totalCount: (pageInfo['totalCount'] as num?)?.toInt() ?? data.length,
        hasMore: pageInfo['hasMore'] == true,
      );
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Grup üyeleri yüklenemedi.');
    }
  }

  static Future<TurnaChatDetail> updateGroupDetail(
    AuthSession session, {
    required String chatId,
    String? title,
    String? description,
    String? avatarObjectKey,
    bool clearAvatar = false,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          ...?title == null ? null : {'title': title.trim()},
          ...?description == null ? null : {'description': description.trim()},
          ...?avatarObjectKey == null
              ? null
              : {'avatarObjectKey': avatarObjectKey},
          if (clearAvatar) 'clearAvatar': true,
        }),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final detail = TurnaChatDetail.fromMap(data);
      await TurnaChatDetailLocalCache.save(session.userId, detail);
      return detail;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Grup bilgileri güncellenemedi.');
    }
  }

  static Future<List<TurnaGroupMember>> addGroupMembers(
    AuthSession session, {
    required String chatId,
    required List<String> memberUserIds,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/members'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'memberUserIds': memberUserIds.map((item) => item.trim()).toList(),
        }),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (map['data'] as List<dynamic>? ?? const []);
      return data
          .whereType<Map>()
          .map(
            (item) => TurnaGroupMember.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Üyeler eklenemedi.');
    }
  }

  static Future<TurnaChatDetail> updateGroupSettings(
    AuthSession session, {
    required String chatId,
    bool? isPublic,
    bool? joinApprovalRequired,
    String? whoCanSend,
    String? whoCanEditInfo,
    String? whoCanInvite,
    String? whoCanAddMembers,
    String? whoCanStartCalls,
    bool? historyVisibleToNewMembers,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/settings'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          ...?isPublic == null ? null : {'isPublic': isPublic},
          ...?joinApprovalRequired == null
              ? null
              : {'joinApprovalRequired': joinApprovalRequired},
          ...?whoCanSend == null ? null : {'whoCanSend': whoCanSend},
          ...?whoCanEditInfo == null
              ? null
              : {'whoCanEditInfo': whoCanEditInfo},
          ...?whoCanInvite == null ? null : {'whoCanInvite': whoCanInvite},
          ...?whoCanAddMembers == null
              ? null
              : {'whoCanAddMembers': whoCanAddMembers},
          ...?whoCanStartCalls == null
              ? null
              : {'whoCanStartCalls': whoCanStartCalls},
          ...?historyVisibleToNewMembers == null
              ? null
              : {'historyVisibleToNewMembers': historyVisibleToNewMembers},
        }),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final detail = TurnaChatDetail.fromMap(data);
      await TurnaChatDetailLocalCache.save(session.userId, detail);
      return detail;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Grup ayarları güncellenemedi.');
    }
  }

  static Future<void> updateGroupMemberRole(
    AuthSession session, {
    required String chatId,
    required String memberUserId,
    required String role,
  }) async {
    try {
      final res = await http.put(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/$chatId/members/$memberUserId/role',
        ),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'role': role}),
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Üye rolü güncellenemedi.');
    }
  }

  static Future<TurnaChatDetail> transferGroupOwnership(
    AuthSession session, {
    required String chatId,
    required String newOwnerUserId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/owner-transfer'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'newOwnerUserId': newOwnerUserId}),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final detail = TurnaChatDetail.fromMap(data);
      await TurnaChatDetailLocalCache.save(session.userId, detail);
      return detail;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sahiplik devredilemedi.');
    }
  }

  static Future<List<TurnaGroupInviteLink>> fetchGroupInviteLinks(
    AuthSession session, {
    required String chatId,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/invite-links'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (map['data'] as List<dynamic>? ?? const []);
      return data
          .whereType<Map>()
          .map(
            (item) =>
                TurnaGroupInviteLink.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Davet bağlantıları yüklenemedi.');
    }
  }

  static Future<TurnaGroupInviteLink> createGroupInviteLink(
    AuthSession session, {
    required String chatId,
    required String duration,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/invite-links'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'duration': duration}),
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaGroupInviteLink.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Davet bağlantısı oluşturulamadı.');
    }
  }

  static Future<void> revokeGroupInviteLink(
    AuthSession session, {
    required String chatId,
    required String inviteLinkId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/$chatId/invite-links/$inviteLinkId/revoke',
        ),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Davet bağlantısı iptal edilemedi.');
    }
  }

  static Future<List<TurnaGroupJoinRequest>> fetchGroupJoinRequests(
    AuthSession session, {
    required String chatId,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/join-requests'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (map['data'] as List<dynamic>? ?? const []);
      return data
          .whereType<Map>()
          .map(
            (item) =>
                TurnaGroupJoinRequest.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Katılım istekleri yüklenemedi.');
    }
  }

  static Future<void> approveGroupJoinRequest(
    AuthSession session, {
    required String chatId,
    required String requestId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/$chatId/join-requests/$requestId/approve',
        ),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Katılım isteği onaylanamadı.');
    }
  }

  static Future<void> rejectGroupJoinRequest(
    AuthSession session, {
    required String chatId,
    required String requestId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/$chatId/join-requests/$requestId/reject',
        ),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Katılım isteği reddedilemedi.');
    }
  }

  static Future<List<TurnaGroupMuteEntry>> fetchGroupMutes(
    AuthSession session, {
    required String chatId,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/mutes'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (map['data'] as List<dynamic>? ?? const []);
      return data
          .whereType<Map>()
          .map(
            (item) =>
                TurnaGroupMuteEntry.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sessize alınan üyeler yüklenemedi.');
    }
  }

  static Future<void> muteGroupMember(
    AuthSession session, {
    required String chatId,
    required String memberUserId,
    required String duration,
    String? reason,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/$chatId/members/$memberUserId/mute',
        ),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'duration': duration,
          ...?reason == null ? null : {'reason': reason.trim()},
        }),
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Üye sessize alınamadı.');
    }
  }

  static Future<void> unmuteGroupMember(
    AuthSession session, {
    required String chatId,
    required String memberUserId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/$chatId/members/$memberUserId/unmute',
        ),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Üye sessizden çıkarılamadı.');
    }
  }

  static Future<List<TurnaGroupBanEntry>> fetchGroupBans(
    AuthSession session, {
    required String chatId,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/bans'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (map['data'] as List<dynamic>? ?? const []);
      return data
          .whereType<Map>()
          .map(
            (item) =>
                TurnaGroupBanEntry.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Yasaklı üyeler yüklenemedi.');
    }
  }

  static Future<void> banGroupMember(
    AuthSession session, {
    required String chatId,
    required String memberUserId,
    String? reason,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/$chatId/members/$memberUserId/ban',
        ),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          ...?reason == null ? null : {'reason': reason.trim()},
        }),
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Üye yasaklanamadı.');
    }
  }

  static Future<void> unbanGroupMember(
    AuthSession session, {
    required String chatId,
    required String memberUserId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/$chatId/bans/$memberUserId/unban',
        ),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Üye yasağı kaldırılamadı.');
    }
  }

  static Future<void> removeGroupMember(
    AuthSession session, {
    required String chatId,
    required String memberUserId,
  }) async {
    try {
      final res = await http.delete(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/members/$memberUserId'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Üye gruptan çıkarılamadı.');
    }
  }

  static Future<TurnaChatDetail> createGroup(
    AuthSession session, {
    required String title,
    required List<String> memberUserIds,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/groups'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'title': title.trim(),
          'memberUserIds': memberUserIds.map((item) => item.trim()).toList(),
        }),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final detail = TurnaChatDetail.fromMap(data);
      await TurnaChatDetailLocalCache.save(session.userId, detail);
      return detail;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Grup oluşturulamadı.');
    }
  }

  static Future<void> leaveGroup(AuthSession session, String chatId) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/leave'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Gruptan ayrılınamadı.');
    }
  }

  static Future<void> closeGroup(AuthSession session, String chatId) async {
    try {
      final res = await http.delete(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Grup kapatılamadı.');
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

  static Future<bool> setChatFavorited(
    AuthSession session, {
    required String chatId,
    required bool favorited,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/favorite'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'favorited': favorited}),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return data['favorited'] == true;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException(
        favorited
            ? 'Sohbet favorilere eklenemedi.'
            : 'Sohbet favorilerden çıkarılamadı.',
      );
    }
  }

  static Future<bool> setChatLocked(
    AuthSession session, {
    required String chatId,
    required bool locked,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/lock'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'locked': locked}),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return data['locked'] == true;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException(
        locked ? 'Sohbet kilitlenemedi.' : 'Sohbet kilidi kaldırılamadı.',
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
    String? cacheOwnerId,
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
      if (cacheOwnerId != null && cacheOwnerId.trim().isNotEmpty) {
        await TurnaChatHistoryLocalCache.mergePage(cacheOwnerId, chatId, items);
      }

      return ChatMessagesPage(
        items: items,
        hasMore: pageInfo['hasMore'] == true,
        nextBefore: _nullableString(pageInfo['nextBefore']),
      );
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      if (cacheOwnerId != null && cacheOwnerId.trim().isNotEmpty) {
        final cached = await TurnaChatHistoryLocalCache.load(
          cacheOwnerId,
          chatId,
        );
        if (cached.isNotEmpty) {
          final sorted = List<ChatMessage>.from(cached)
            ..sort((a, b) => compareTurnaTimestamps(a.createdAt, b.createdAt));
          final window = before == null || before.isEmpty
              ? sorted
              : sorted
                    .where(
                      (message) =>
                          compareTurnaTimestamps(message.createdAt, before) < 0,
                    )
                    .toList();
          final limited = window.length <= limit
              ? window
              : window.sublist(window.length - limit);
          return ChatMessagesPage(
            items: limited,
            hasMore: window.length > limit,
            nextBefore: limited.isEmpty ? null : limited.first.createdAt,
          );
        }
      }
      throw TurnaApiException('Mesajlar yüklenemedi.');
    }
  }

  static Future<ChatMessagesPage> searchMessagesPage(
    AuthSession session, {
    required String chatId,
    required String query,
    String? before,
    int limit = 30,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return ChatMessagesPage(
        items: const <ChatMessage>[],
        hasMore: false,
        nextBefore: null,
      );
    }

    try {
      final uri = Uri.parse('$kBackendBaseUrl/api/chats/$chatId/search')
          .replace(
            queryParameters: {
              'q': trimmedQuery,
              'limit': '$limit',
              if (before != null && before.isNotEmpty) 'before': before,
            },
          );
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (map['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => ChatMessage.fromMap(Map<String, dynamic>.from(item)))
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
      final cached = await TurnaChatHistoryLocalCache.load(
        session.userId,
        chatId,
      );
      final normalized = trimmedQuery.toLowerCase();
      final filtered =
          cached.where((message) {
            if ((message.systemType ?? '').trim().isNotEmpty) return false;
            final text = message.text.toLowerCase();
            final sender = (message.senderDisplayName ?? '').toLowerCase();
            final fileNames = message.attachments
                .map((attachment) => (attachment.fileName ?? '').toLowerCase())
                .join(' ');
            return text.contains(normalized) ||
                sender.contains(normalized) ||
                fileNames.contains(normalized);
          }).toList()..sort(
            (a, b) => compareTurnaTimestamps(a.createdAt, b.createdAt),
          );
      final window = before == null || before.isEmpty
          ? filtered
          : filtered
                .where(
                  (message) =>
                      compareTurnaTimestamps(message.createdAt, before) < 0,
                )
                .toList();
      final limited = window.length <= limit
          ? window
          : window.sublist(window.length - limit);
      return ChatMessagesPage(
        items: limited,
        hasMore: window.length > limit,
        nextBefore: limited.isEmpty ? null : limited.first.createdAt,
      );
    }
  }

  static Future<ChatMessagesPage> fetchMessageCollectionPage(
    AuthSession session, {
    required String chatId,
    required TurnaChatCollectionType type,
    String? before,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse('$kBackendBaseUrl/api/chats/$chatId/media-items')
          .replace(
            queryParameters: {
              'type': type.name,
              'limit': '$limit',
              if (before != null && before.isNotEmpty) 'before': before,
            },
          );
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (map['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => ChatMessage.fromMap(Map<String, dynamic>.from(item)))
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
      final cached = await TurnaChatHistoryLocalCache.load(
        session.userId,
        chatId,
      );
      bool matches(ChatMessage message) {
        if ((message.systemType ?? '').trim().isNotEmpty) return false;
        switch (type) {
          case TurnaChatCollectionType.media:
            return message.attachments.any(
              (attachment) =>
                  attachment.kind == ChatAttachmentKind.image ||
                  attachment.kind == ChatAttachmentKind.video,
            );
          case TurnaChatCollectionType.docs:
            return message.attachments.any(
              (attachment) => attachment.kind == ChatAttachmentKind.file,
            );
          case TurnaChatCollectionType.links:
            final text = message.text.toLowerCase();
            return text.contains('http://') ||
                text.contains('https://') ||
                text.contains('www.');
        }
      }

      final filtered = cached.where(matches).toList()
        ..sort((a, b) => compareTurnaTimestamps(a.createdAt, b.createdAt));
      final window = before == null || before.isEmpty
          ? filtered
          : filtered
                .where(
                  (message) =>
                      compareTurnaTimestamps(message.createdAt, before) < 0,
                )
                .toList();
      final limited = window.length <= limit
          ? window
          : window.sublist(window.length - limit);
      return ChatMessagesPage(
        items: limited,
        hasMore: window.length > limit,
        nextBefore: limited.isEmpty ? null : limited.first.createdAt,
      );
    }
  }

  static Future<List<TurnaPinnedMessageSummary>> fetchPinnedMessages(
    AuthSession session, {
    required String chatId,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/pins'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      return (map['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => TurnaPinnedMessageSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sabit mesajlar yüklenemedi.');
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

  static Future<ChatMessage> addReaction(
    AuthSession session, {
    required String messageId,
    required String emoji,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/messages/$messageId/reactions'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'emoji': emoji}),
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatMessage.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Tepki eklenemedi.');
    }
  }

  static Future<ChatMessage> removeReaction(
    AuthSession session, {
    required String messageId,
    required String emoji,
  }) async {
    try {
      final request = http.Request(
        'DELETE',
        Uri.parse('$kBackendBaseUrl/api/chats/messages/$messageId/reactions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode({'emoji': emoji});
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatMessage.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Tepki kaldırılamadı.');
    }
  }

  static Future<TurnaPinnedMessageSummary> pinMessage(
    AuthSession session, {
    required String messageId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/messages/$messageId/pin'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaPinnedMessageSummary.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesaj sabitlenemedi.');
    }
  }

  static Future<void> unpinMessage(
    AuthSession session, {
    required String messageId,
  }) async {
    try {
      final res = await http.delete(
        Uri.parse('$kBackendBaseUrl/api/chats/messages/$messageId/pin'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesaj sabitlemesi kaldırılamadı.');
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
