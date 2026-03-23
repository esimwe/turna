part of '../app/turna_app.dart';

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

  static Future<TurnaChatDetail> updateDirectMessageExpiration(
    AuthSession session, {
    required String chatId,
    required int? messageExpirationSeconds,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/message-expiration'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messageExpirationSeconds': messageExpirationSeconds,
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
      throw TurnaApiException('Süreli mesaj ayarı güncellenemedi.');
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
      await TurnaLocalStateReset.clearChatState(session.userId, chatId);
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
      for (final chatId in deleted) {
        final normalized = chatId.toString().trim();
        if (normalized.isEmpty) continue;
        await TurnaLocalStateReset.clearChatState(
          session.userId,
          normalized,
          removeFromInbox: true,
        );
      }
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
      final contacts = data
          .whereType<Map>()
          .map(
            (item) =>
                TurnaRegisteredContact.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
      await TurnaRegisteredContactsLocalCache.save(session.userId, contacts);
      await cacheTurnaKnownContactUserIds(
        session.userId,
        contacts.map((item) => item.id),
      );
      return contacts;
    } on TurnaUnauthorizedException {
      rethrow;
    } on TurnaApiException {
      final cached = await TurnaRegisteredContactsLocalCache.load(
        session.userId,
      );
      if (cached != null) return cached;
      rethrow;
    } catch (_) {
      final cached = await TurnaRegisteredContactsLocalCache.load(
        session.userId,
      );
      if (cached != null) return cached;
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

  static String buildSavedMessagesChatId(String userId) {
    return buildDirectChatId(userId, userId);
  }

  static bool isSavedMessagesChatId(String chatId, String currentUserId) {
    return chatId == buildSavedMessagesChatId(currentUserId);
  }

  static ChatPreview buildSavedMessagesChatPreview(
    AuthSession session, {
    String message = '',
    String time = '',
    int unreadCount = 0,
    bool isMuted = false,
    bool isArchived = false,
    bool isFavorited = false,
    bool isLocked = false,
    String? folderId,
    String? folderName,
  }) {
    final selfProfile = TurnaUserProfileLocalCache.peek(session.userId);
    return ChatPreview(
      chatId: buildSavedMessagesChatId(session.userId),
      name: 'Kendime Notlar',
      message: message,
      time: time,
      avatarUrl: resolveTurnaSessionAvatarUrl(
        session,
        overrideAvatarUrl: selfProfile?.avatarUrl,
      ),
      unreadCount: unreadCount,
      isMuted: isMuted,
      isArchived: isArchived,
      isFavorited: isFavorited,
      isLocked: isLocked,
      folderId: folderId,
      folderName: folderName,
    );
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
    for (final part in parts) {
      if (part != currentUserId) return part;
    }
    return null;
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
    bool silent = false,
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
          'silent': silent,
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

  static Future<TurnaScheduledMessageSummary> scheduleMessage(
    AuthSession session, {
    required String chatId,
    required String text,
    required DateTime scheduledFor,
    bool silent = false,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/messages/scheduled'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chatId': chatId,
          'text': text.trim(),
          'scheduledFor': scheduledFor.toUtc().toIso8601String(),
          'silent': silent,
        }),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaScheduledMessageSummary.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Zamanlanmış mesaj oluşturulamadı.');
    }
  }

  static Future<List<TurnaScheduledMessageSummary>> listScheduledMessages(
    AuthSession session, {
    required String chatId,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/scheduled-messages'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (map['data'] as List<dynamic>? ?? const []);
      return data
          .whereType<Map>()
          .map(
            (item) => TurnaScheduledMessageSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Zamanlanmış mesajlar yüklenemedi.');
    }
  }

  static Future<void> deleteScheduledMessage(
    AuthSession session, {
    required String scheduledMessageId,
  }) async {
    try {
      final request = http.Request(
        'DELETE',
        Uri.parse(
          '$kBackendBaseUrl/api/chats/scheduled-messages/$scheduledMessageId',
        ),
      );
      request.headers.addAll({
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      });
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      _throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Zamanlanmış mesaj iptal edilemedi.');
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
    String? packId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/messages/$messageId/reactions'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'emoji': emoji,
          if (packId != null && packId.trim().isNotEmpty)
            'packId': packId.trim(),
        }),
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

  static Future<TurnaReactionPackCatalog> fetchReactionPacks(
    AuthSession session,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/reaction-packs'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaReactionPackCatalog.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Emoji paketleri yüklenemedi.');
    }
  }

  static Future<TurnaReactionPackCatalog> updateReactionPackPreferences(
    AuthSession session, {
    List<String>? installedPackIds,
    List<String>? favoriteEmojis,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$kBackendBaseUrl/api/chats/reaction-packs/preferences'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          ...?installedPackIds == null
              ? null
              : {'installedPackIds': installedPackIds},
          ...?favoriteEmojis == null
              ? null
              : {'favoriteEmojis': favoriteEmojis},
        }),
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaReactionPackCatalog.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Emoji paketleri güncellenemedi.');
    }
  }

  static Future<Map<String, dynamic>> fetchExpressionPackCatalog(
    AuthSession session,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/expression-packs'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return Map<String, dynamic>.from(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sticker paketleri yüklenemedi.');
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
    turnaThrowApiError(response.body, response.statusCode);
  }

  static String _formatTime(String? iso) {
    return formatTurnaLocalClock(iso);
  }
}
