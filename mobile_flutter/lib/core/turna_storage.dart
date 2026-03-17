part of turna_app;

class TurnaSecureStateStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> readString(String key) async {
    try {
      final secure = await _storage.read(key: key);
      if (secure != null && secure.trim().isNotEmpty) {
        return secure;
      }
    } catch (error) {
      turnaLog('secure state read skipped', {'key': key, 'error': '$error'});
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(key);
      if (legacy == null || legacy.trim().isEmpty) {
        return null;
      }
      try {
        await _storage.write(key: key, value: legacy);
        await prefs.remove(key);
      } catch (error) {
        turnaLog('secure state migrate skipped', {
          'key': key,
          'error': '$error',
        });
      }
      return legacy;
    } catch (error) {
      turnaLog('legacy state read skipped', {'key': key, 'error': '$error'});
      return null;
    }
  }

  static Future<bool?> readBool(String key) async {
    try {
      final secure = await _storage.read(key: key);
      if (secure != null && secure.trim().isNotEmpty) {
        return secure == '1' || secure.toLowerCase() == 'true';
      }
    } catch (error) {
      turnaLog('secure bool read skipped', {'key': key, 'error': '$error'});
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getBool(key);
      if (legacy == null) return null;
      try {
        await _storage.write(key: key, value: legacy ? '1' : '0');
        await prefs.remove(key);
      } catch (error) {
        turnaLog('secure bool migrate skipped', {
          'key': key,
          'error': '$error',
        });
      }
      return legacy;
    } catch (error) {
      turnaLog('legacy bool read skipped', {'key': key, 'error': '$error'});
      return null;
    }
  }

  static Future<void> writeString(String key, String? value) async {
    final normalized = value == null || value.trim().isEmpty ? null : value;
    try {
      if (normalized == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: normalized);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    } catch (error) {
      turnaLog('secure state write skipped', {'key': key, 'error': '$error'});
    }

    final prefs = await SharedPreferences.getInstance();
    if (normalized == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, normalized);
    }
  }

  static Future<void> writeBool(String key, bool value) async {
    try {
      await _storage.write(key: key, value: value ? '1' : '0');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    } catch (error) {
      turnaLog('secure bool write skipped', {'key': key, 'error': '$error'});
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (error) {
      turnaLog('secure state delete skipped', {'key': key, 'error': '$error'});
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  static Future<void> deleteMany(Iterable<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }
}

class TurnaLocalStore {
  static const String _dbName = 'turna_local_store_v1.db';
  static const String authSessionTable = 'auth_session';
  static const String userProfileTable = 'user_profile';
  static const String chatInboxTable = 'chat_inbox';
  static const String chatDetailTable = 'chat_detail';
  static const String chatMessageTable = 'chat_message';
  static const String pendingMessageTable = 'pending_message';
  static const String callHistoryTable = 'call_history';

  static Database? _database;
  static Future<Database>? _opening;
  static bool _disabled = false;

  static Future<void> ensureInitialized() async {
    await _databaseOrNull();
  }

  static Future<Database?> _databaseOrNull() async {
    if (_disabled) return null;
    if (_database != null) return _database;
    if (_opening != null) {
      try {
        return await _opening;
      } catch (_) {
        return null;
      }
    }

    final future = _open();
    _opening = future;
    try {
      final db = await future;
      _database = db;
      return db;
    } catch (error) {
      _disabled = true;
      turnaLog('local store disabled', error);
      return null;
    } finally {
      _opening = null;
    }
  }

  static Future<Database> _open() async {
    final databasesPath = await getDatabasesPath();
    final path = '$databasesPath/$_dbName';
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $callHistoryTable (
              owner_user_id TEXT PRIMARY KEY,
              calls_json TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        }
      },
    );
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE $authSessionTable (
        slot TEXT PRIMARY KEY,
        session_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $userProfileTable (
        cache_key TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        is_self INTEGER NOT NULL DEFAULT 0,
        profile_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $chatInboxTable (
        owner_user_id TEXT PRIMARY KEY,
        inbox_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $chatDetailTable (
        owner_user_id TEXT NOT NULL,
        chat_id TEXT NOT NULL,
        detail_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (owner_user_id, chat_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE $chatMessageTable (
        owner_user_id TEXT NOT NULL,
        chat_id TEXT NOT NULL,
        messages_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (owner_user_id, chat_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE $pendingMessageTable (
        owner_user_id TEXT NOT NULL,
        chat_id TEXT NOT NULL,
        messages_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (owner_user_id, chat_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE $callHistoryTable (
        owner_user_id TEXT PRIMARY KEY,
        calls_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<String?> readJsonValue({
    required String table,
    required String valueColumn,
    required Map<String, Object?> where,
  }) async {
    final db = await _databaseOrNull();
    if (db == null) return null;
    try {
      final rows = await db.query(
        table,
        columns: <String>[valueColumn],
        where: _whereClause(where),
        whereArgs: where.values.toList(),
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final value = rows.first[valueColumn];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
      return null;
    } catch (error) {
      turnaLog('local store read skipped', {'table': table, 'error': '$error'});
      return null;
    }
  }

  static Future<bool> writeJsonValue({
    required String table,
    required String valueColumn,
    required Map<String, Object?> keyValues,
    required String jsonValue,
    Map<String, Object?> extraValues = const <String, Object?>{},
  }) async {
    final db = await _databaseOrNull();
    if (db == null) return false;
    try {
      await db.insert(table, <String, Object?>{
        ...keyValues,
        ...extraValues,
        valueColumn: jsonValue,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    } catch (error) {
      turnaLog('local store write skipped', {
        'table': table,
        'error': '$error',
      });
      return false;
    }
  }

  static Future<bool> deleteRows({
    required String table,
    required Map<String, Object?> where,
  }) async {
    final db = await _databaseOrNull();
    if (db == null) return false;
    try {
      await db.delete(
        table,
        where: _whereClause(where),
        whereArgs: where.values.toList(),
      );
      return true;
    } catch (error) {
      turnaLog('local store delete skipped', {
        'table': table,
        'error': '$error',
      });
      return false;
    }
  }

  static String _whereClause(Map<String, Object?> where) {
    return where.keys.map((key) => '$key = ?').join(' AND ');
  }

  static Future<void> clearAppData() async {
    final db = await _databaseOrNull();
    if (db == null) return;
    try {
      await db.transaction((tx) async {
        for (final table in <String>[
          authSessionTable,
          userProfileTable,
          chatInboxTable,
          chatDetailTable,
          chatMessageTable,
          pendingMessageTable,
          callHistoryTable,
        ]) {
          await tx.delete(table);
        }
      });
    } catch (error) {
      turnaLog('local store clear skipped', error);
    }
  }
}

class TurnaAuthSessionLocalRepository {
  static Future<void> saveSnapshot(AuthSession session) async {
    await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.authSessionTable,
      valueColumn: 'session_json',
      keyValues: const <String, Object?>{'slot': 'main'},
      jsonValue: jsonEncode(session._toLocalSnapshotMap()),
    );
  }

  static Future<void> clear() async {
    await TurnaLocalStore.deleteRows(
      table: TurnaLocalStore.authSessionTable,
      where: const <String, Object?>{'slot': 'main'},
    );
  }
}

class TurnaUserProfileLocalRepository {
  static Future<String?> loadRaw({
    required String cacheKey,
    required String legacyPrefsKey,
  }) async {
    final raw =
        await TurnaLocalStore.readJsonValue(
          table: TurnaLocalStore.userProfileTable,
          valueColumn: 'profile_json',
          where: <String, Object?>{'cache_key': cacheKey},
        ) ??
        (await SharedPreferences.getInstance()).getString(legacyPrefsKey);
    return raw == null || raw.trim().isEmpty ? null : raw;
  }

  static Future<bool> saveRaw({
    required String cacheKey,
    required String userId,
    required bool isSelf,
    required String legacyPrefsKey,
    required String rawJson,
  }) async {
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.userProfileTable,
      valueColumn: 'profile_json',
      keyValues: <String, Object?>{'cache_key': cacheKey},
      extraValues: <String, Object?>{
        'user_id': userId,
        'is_self': isSelf ? 1 : 0,
      },
      jsonValue: rawJson,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(legacyPrefsKey);
      return true;
    }
    await prefs.setString(legacyPrefsKey, rawJson);
    return false;
  }

  static Future<void> clearSelf(String legacyPrefsKey) async {
    await TurnaLocalStore.deleteRows(
      table: TurnaLocalStore.userProfileTable,
      where: const <String, Object?>{'cache_key': 'self'},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyPrefsKey);
  }
}

class TurnaChatInboxLocalRepository {
  static Future<String?> loadRaw(String userId, String legacyPrefsKey) async {
    final raw =
        await TurnaLocalStore.readJsonValue(
          table: TurnaLocalStore.chatInboxTable,
          valueColumn: 'inbox_json',
          where: <String, Object?>{'owner_user_id': userId},
        ) ??
        (await SharedPreferences.getInstance()).getString(legacyPrefsKey);
    return raw == null || raw.trim().isEmpty ? null : raw;
  }

  static Future<void> saveRaw(
    String userId,
    String legacyPrefsKey,
    String rawJson,
  ) async {
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.chatInboxTable,
      valueColumn: 'inbox_json',
      keyValues: <String, Object?>{'owner_user_id': userId},
      jsonValue: rawJson,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(legacyPrefsKey);
      return;
    }
    await prefs.setString(legacyPrefsKey, rawJson);
  }

  static Future<void> clear(String userId, String legacyPrefsKey) async {
    await TurnaLocalStore.deleteRows(
      table: TurnaLocalStore.chatInboxTable,
      where: <String, Object?>{'owner_user_id': userId},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyPrefsKey);
  }
}

class TurnaChatDetailLocalRepository {
  static Future<String?> loadRaw(
    String userId,
    String chatId,
    String legacyPrefsKey,
  ) async {
    final raw =
        await TurnaLocalStore.readJsonValue(
          table: TurnaLocalStore.chatDetailTable,
          valueColumn: 'detail_json',
          where: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
        ) ??
        (await SharedPreferences.getInstance()).getString(legacyPrefsKey);
    return raw == null || raw.trim().isEmpty ? null : raw;
  }

  static Future<void> saveRaw(
    String userId,
    String chatId,
    String legacyPrefsKey,
    String rawJson,
  ) async {
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.chatDetailTable,
      valueColumn: 'detail_json',
      keyValues: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
      jsonValue: rawJson,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(legacyPrefsKey);
      return;
    }
    await prefs.setString(legacyPrefsKey, rawJson);
  }

  static Future<void> clear(
    String userId,
    String chatId,
    String legacyPrefsKey,
  ) async {
    await TurnaLocalStore.deleteRows(
      table: TurnaLocalStore.chatDetailTable,
      where: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyPrefsKey);
  }
}

class TurnaChatHistoryLocalRepository {
  static Future<List<ChatMessage>> load(
    String userId,
    String chatId,
    String legacyPrefsKey,
  ) async {
    final rawJson = await TurnaLocalStore.readJsonValue(
      table: TurnaLocalStore.chatMessageTable,
      valueColumn: 'messages_json',
      where: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
    );
    final items = <ChatMessage>[];
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        for (final raw in decoded.whereType<Map>()) {
          items.add(ChatMessage.fromPendingMap(Map<String, dynamic>.from(raw)));
        }
      } catch (_) {}
      return items;
    }

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(legacyPrefsKey) ?? const [];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        items.add(ChatMessage.fromPendingMap(decoded));
      } catch (_) {}
    }
    return items;
  }

  static Future<void> save(
    String userId,
    String chatId,
    String legacyPrefsKey,
    Iterable<ChatMessage> messages,
  ) async {
    final encoded = jsonEncode(
      messages.map((message) => message.toPendingMap()).toList(),
    );
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.chatMessageTable,
      valueColumn: 'messages_json',
      keyValues: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
      jsonValue: encoded,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(legacyPrefsKey);
      return;
    }
    await prefs.setStringList(
      legacyPrefsKey,
      messages.map((message) => jsonEncode(message.toPendingMap())).toList(),
    );
  }

  static Future<void> clear(
    String userId,
    String chatId,
    String legacyPrefsKey,
  ) async {
    await TurnaLocalStore.deleteRows(
      table: TurnaLocalStore.chatMessageTable,
      where: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyPrefsKey);
  }
}

class TurnaCallHistoryLocalRepository {
  static Future<List<TurnaCallHistoryItem>> load(
    String userId,
    String legacyPrefsKey,
  ) async {
    final rawJson = await TurnaLocalStore.readJsonValue(
      table: TurnaLocalStore.callHistoryTable,
      valueColumn: 'calls_json',
      where: <String, Object?>{'owner_user_id': userId},
    );
    final items = <TurnaCallHistoryItem>[];
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        for (final raw in decoded.whereType<Map>()) {
          items.add(
            TurnaCallHistoryItem.fromMap(Map<String, dynamic>.from(raw)),
          );
        }
      } catch (_) {}
      return items;
    }

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(legacyPrefsKey) ?? const [];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        items.add(TurnaCallHistoryItem.fromMap(decoded));
      } catch (_) {}
    }
    return items;
  }

  static Future<void> save(
    String userId,
    String legacyPrefsKey,
    Iterable<TurnaCallHistoryItem> items,
  ) async {
    final encoded = jsonEncode(items.map((item) => item.toMap()).toList());
    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.callHistoryTable,
      valueColumn: 'calls_json',
      keyValues: <String, Object?>{'owner_user_id': userId},
      jsonValue: encoded,
    );
    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      await prefs.remove(legacyPrefsKey);
      return;
    }
    await prefs.setStringList(
      legacyPrefsKey,
      items.map((item) => jsonEncode(item.toMap())).toList(),
    );
  }
}

class TurnaLocalStateReset {
  static Future<void> clearAppData() async {
    await TurnaLocalStore.clearAppData();
    TurnaProfileLocalCache._warmSelfProfile = null;
    TurnaUserProfileLocalCache._warmProfiles.clear();
    TurnaChatInboxLocalCache._warmInboxes.clear();
    TurnaChatDetailLocalCache._warm.clear();
    TurnaChatHistoryLocalCache._warm.clear();
    TurnaCallHistoryLocalCache._warm.clear();
    TurnaSocketClient._warmMessageCache.clear();
  }

  static Future<void> clearChatState(
    String userId,
    String chatId, {
    bool removeFromInbox = false,
  }) async {
    TurnaChatDetailLocalCache._warm.remove(
      TurnaChatDetailLocalCache._cacheId(userId, chatId),
    );
    TurnaChatHistoryLocalCache._warm.remove(
      TurnaChatHistoryLocalCache._cacheId(userId, chatId),
    );
    TurnaSocketClient._warmMessageCache.remove('$userId:$chatId');

    await TurnaChatDetailLocalRepository.clear(
      userId,
      chatId,
      TurnaChatDetailLocalCache._key(userId, chatId),
    );
    await TurnaChatHistoryLocalRepository.clear(
      userId,
      chatId,
      TurnaChatHistoryLocalCache._key(userId, chatId),
    );
    await TurnaPendingMessageLocalRepository.clear(
      userId,
      chatId,
      legacyPrefsKey: 'turna_pending_chat_${userId}_$chatId',
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('turna_recent_chat_${userId}_$chatId');

    if (!removeFromInbox) return;

    final inbox =
        TurnaChatInboxLocalCache.peek(userId) ??
        await TurnaChatInboxLocalCache.load(userId);
    if (inbox == null) return;

    final nextChats = inbox.chats
        .where((item) => item.chatId != chatId)
        .toList(growable: false);
    if (nextChats.length == inbox.chats.length) return;

    final nextInbox = ChatInboxData(
      chats: nextChats,
      folders: List<ChatFolder>.from(inbox.folders),
    );
    TurnaChatInboxLocalCache._warmInboxes[userId] = nextInbox;
    await TurnaChatInboxLocalRepository.saveRaw(
      userId,
      TurnaChatInboxLocalCache._key(userId),
      jsonEncode(nextInbox.toCacheMap()),
    );
  }
}

class TurnaPendingMessageLocalRepository {
  static Future<List<ChatMessage>> load(
    String userId,
    String chatId, {
    String? legacyPrefsKey,
  }) async {
    final raw = await TurnaLocalStore.readJsonValue(
      table: TurnaLocalStore.pendingMessageTable,
      valueColumn: 'messages_json',
      where: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
    );
    final fromDb = _decodeMessages(raw);
    if (fromDb.isNotEmpty) return fromDb;

    if (legacyPrefsKey == null || legacyPrefsKey.isEmpty) {
      return const <ChatMessage>[];
    }

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(legacyPrefsKey) ?? const <String>[];
    if (rawList.isEmpty) return const <ChatMessage>[];

    final migrated = <ChatMessage>[];
    for (final rawItem in rawList) {
      try {
        final decoded = jsonDecode(rawItem) as Map<String, dynamic>;
        migrated.add(ChatMessage.fromPendingMap(decoded));
      } catch (_) {}
    }
    if (migrated.isNotEmpty) {
      await save(userId, chatId, migrated, legacyPrefsKey: legacyPrefsKey);
    }
    return migrated;
  }

  static Future<void> save(
    String userId,
    String chatId,
    Iterable<ChatMessage> messages, {
    String? legacyPrefsKey,
  }) async {
    final encodedItems = messages.map((item) => item.toPendingMap()).toList();
    if (encodedItems.isEmpty) {
      await clear(userId, chatId, legacyPrefsKey: legacyPrefsKey);
      return;
    }

    final saved = await TurnaLocalStore.writeJsonValue(
      table: TurnaLocalStore.pendingMessageTable,
      valueColumn: 'messages_json',
      keyValues: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
      jsonValue: jsonEncode(encodedItems),
    );

    final prefs = await SharedPreferences.getInstance();
    if (saved) {
      if (legacyPrefsKey != null && legacyPrefsKey.isNotEmpty) {
        await prefs.remove(legacyPrefsKey);
      }
      return;
    }

    if (legacyPrefsKey != null && legacyPrefsKey.isNotEmpty) {
      await prefs.setStringList(
        legacyPrefsKey,
        encodedItems.map((item) => jsonEncode(item)).toList(),
      );
    }
  }

  static Future<void> clear(
    String userId,
    String chatId, {
    String? legacyPrefsKey,
  }) async {
    await TurnaLocalStore.deleteRows(
      table: TurnaLocalStore.pendingMessageTable,
      where: <String, Object?>{'owner_user_id': userId, 'chat_id': chatId},
    );
    if (legacyPrefsKey == null || legacyPrefsKey.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyPrefsKey);
  }

  static List<ChatMessage> _decodeMessages(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <ChatMessage>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                ChatMessage.fromPendingMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      return const <ChatMessage>[];
    }
  }
}
