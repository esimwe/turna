import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'turna_logging.dart';

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
