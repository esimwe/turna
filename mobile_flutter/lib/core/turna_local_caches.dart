part of '../app/turna_app.dart';

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
    final raw = await TurnaUserProfileLocalRepository.loadRaw(
      cacheKey: 'self',
      legacyPrefsKey: _selfProfileKey,
    );
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
    await TurnaUserProfileLocalRepository.saveRaw(
      cacheKey: 'self',
      userId: profile.id,
      isSelf: true,
      legacyPrefsKey: _selfProfileKey,
      rawJson: jsonEncode(profile.toMap()),
    );
  }

  static Future<void> clearSelfProfile() async {
    _warmSelfProfile = null;
    await TurnaUserProfileLocalRepository.clearSelf(_selfProfileKey);
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

    final raw = await TurnaUserProfileLocalRepository.loadRaw(
      cacheKey: userId,
      legacyPrefsKey: _key(userId),
    );
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
    await TurnaUserProfileLocalRepository.saveRaw(
      cacheKey: profile.id,
      userId: profile.id,
      isSelf: false,
      legacyPrefsKey: _key(profile.id),
      rawJson: jsonEncode(profile.toMap()),
    );
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

    final raw = await TurnaChatInboxLocalRepository.loadRaw(
      userId,
      _key(userId),
    );
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
    await TurnaChatInboxLocalRepository.saveRaw(
      userId,
      _key(userId),
      jsonEncode(inbox.toCacheMap()),
    );
  }
}

class TurnaStatusFeedLocalCache {
  static const String _prefix = 'turna_status_feed_v1_';
  static final Map<String, TurnaStatusFeedData> _warm =
      <String, TurnaStatusFeedData>{};

  static String _key(String userId) => '$_prefix$userId';

  static TurnaStatusFeedData? peek(String userId) => _warm[userId];

  static Future<TurnaStatusFeedData?> load(String userId) async {
    final warm = peek(userId);
    if (warm != null) return warm;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final feed = TurnaStatusFeedData.fromMap(decoded);
      _warm[userId] = feed;
      return feed;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String userId, Map<String, dynamic> rawData) async {
    final normalized = Map<String, dynamic>.from(rawData);
    _warm[userId] = TurnaStatusFeedData.fromMap(normalized);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), jsonEncode(normalized));
  }

  static Future<void> clearAll() async {
    _warm.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
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

    final raw = await TurnaChatDetailLocalRepository.loadRaw(
      userId,
      chatId,
      _key(userId, chatId),
    );
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
    await TurnaChatDetailLocalRepository.saveRaw(
      userId,
      detail.chatId,
      _key(userId, detail.chatId),
      jsonEncode(detail.toMap()),
    );
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

    final items = await TurnaChatHistoryLocalRepository.load(
      userId,
      chatId,
      _key(userId, chatId),
    );
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

    await TurnaChatHistoryLocalRepository.save(
      userId,
      chatId,
      _key(userId, chatId),
      trimmed,
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

class TurnaStarredMessagesLocalCache {
  static const String _prefix = 'turna_starred_messages_v2_';
  static const String _legacyPrefix = 'turna_starred_messages_';
  static final Map<String, Set<String>> _warm = <String, Set<String>>{};

  static String _cacheId(String userId, String chatId) => '$userId::$chatId';

  static String _key(String userId, String chatId) {
    final raw = utf8.encode('$userId|$chatId');
    return '$_prefix${base64UrlEncode(raw)}';
  }

  static String _legacyKey(String chatId) => '$_legacyPrefix$chatId';

  static Set<String>? peek(String userId, String chatId) {
    final cached = _warm[_cacheId(userId, chatId)];
    if (cached == null) return null;
    return Set<String>.from(cached);
  }

  static Future<Set<String>> load(String userId, String chatId) async {
    final warm = peek(userId, chatId);
    if (warm != null) return warm;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key(userId, chatId));
    final legacy = prefs.getStringList(_legacyKey(chatId));
    final ids = <String>{...?stored, ...?stored == null ? legacy : null}
      ..removeWhere((item) => item.trim().isEmpty);
    _warm[_cacheId(userId, chatId)] = ids;
    return Set<String>.from(ids);
  }

  static Future<void> save(
    String userId,
    String chatId,
    Iterable<String> messageIds,
  ) async {
    final normalized = messageIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    _warm[_cacheId(userId, chatId)] = normalized;

    final prefs = await SharedPreferences.getInstance();
    final key = _key(userId, chatId);
    if (normalized.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setStringList(key, normalized.toList());
  }

  static Future<void> migrateLegacyForChats(
    String userId,
    Iterable<String> chatIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    for (final chatId in chatIds) {
      final key = _key(userId, chatId);
      if (prefs.containsKey(key)) continue;
      final legacy = prefs.getStringList(_legacyKey(chatId));
      if (legacy == null || legacy.isEmpty) continue;
      final normalized = legacy
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet();
      if (normalized.isEmpty) continue;
      _warm[_cacheId(userId, chatId)] = normalized;
      await prefs.setStringList(key, normalized.toList());
    }
  }

  static Future<Map<String, Set<String>>> loadAll(
    String userId, {
    Iterable<String>? knownChatIds,
  }) async {
    if (knownChatIds != null) {
      await migrateLegacyForChats(userId, knownChatIds);
    }

    final prefs = await SharedPreferences.getInstance();
    final result = <String, Set<String>>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final encoded = key.substring(_prefix.length);
      try {
        final decoded = utf8.decode(
          base64Url.decode(base64Url.normalize(encoded)),
        );
        final separatorIndex = decoded.indexOf('|');
        if (separatorIndex <= 0 || separatorIndex >= decoded.length - 1) {
          continue;
        }
        final ownerId = decoded.substring(0, separatorIndex);
        final chatId = decoded.substring(separatorIndex + 1);
        if (ownerId != userId || chatId.isEmpty) continue;
        final ids = prefs
            .getStringList(key)
            ?.map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet();
        if (ids == null || ids.isEmpty) continue;
        result[chatId] = ids;
        _warm[_cacheId(userId, chatId)] = ids;
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  static Future<int> countForChat(String userId, String chatId) async {
    final ids = await load(userId, chatId);
    return ids.length;
  }
}

class TurnaAuthSessionStore {
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
    await TurnaAuthSessionLocalRepository.saveSnapshot(session);
    return session;
  }

  static Future<void> save(AuthSession session) async {
    await TurnaSecureStateStore.writeString(_tokenKey, session.token);
    await TurnaSecureStateStore.writeString(_userIdKey, session.userId);
    await TurnaSecureStateStore.writeString(
      _displayNameKey,
      session.displayName,
    );
    await TurnaSecureStateStore.writeString(_usernameKey, session.username);
    await TurnaSecureStateStore.writeString(_phoneKey, session.phone);
    await TurnaSecureStateStore.writeString(_avatarUrlKey, session.avatarUrl);
    await TurnaSecureStateStore.writeBool(
      _needsOnboardingKey,
      session.needsOnboarding,
    );
    await TurnaAuthSessionLocalRepository.saveSnapshot(session);
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
    await TurnaPushManager.clearSessionArtifacts();
    await TurnaNativeCallManager.clearSessionArtifacts();
    await TurnaAuthSessionLocalRepository.clear();
    await TurnaLocalStateReset.clearAppData();
  }
}
