part of '../main.dart';

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
      version: 1,
      onCreate: (db, version) async {
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
      },
    );
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
}

class TurnaPendingChatMessageLocalCache {
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
