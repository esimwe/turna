import 'package:shared_preferences/shared_preferences.dart';

const _kTurnaCallPreferencesActiveUserIdKey =
    'turna_call_preferences_active_user_id';
const _kTurnaSilenceUnknownCallersKeyPrefix =
    'turna_call_silence_unknown_callers';
const _kTurnaKnownContactIdsKeyPrefix = 'turna_call_known_contact_ids';
const _kTurnaKnownContactIdsReadyKeyPrefix =
    'turna_call_known_contact_ids_ready';

String _turnaScopedCallPreferenceKey(String prefix, String userId) {
  return '$prefix:${userId.trim()}';
}

Future<void> setTurnaCallPreferencesActiveUserId(String? userId) async {
  final prefs = await SharedPreferences.getInstance();
  final normalized = userId?.trim() ?? '';
  if (normalized.isEmpty) {
    await prefs.remove(_kTurnaCallPreferencesActiveUserIdKey);
    return;
  }
  await prefs.setString(_kTurnaCallPreferencesActiveUserIdKey, normalized);
}

Future<String?> loadTurnaCallPreferencesActiveUserId() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString(_kTurnaCallPreferencesActiveUserIdKey)?.trim();
  if (userId == null || userId.isEmpty) {
    return null;
  }
  return userId;
}

Future<bool> loadTurnaSilenceUnknownCallersPreference(String userId) async {
  final normalized = userId.trim();
  if (normalized.isEmpty) {
    return false;
  }
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(
        _turnaScopedCallPreferenceKey(
          _kTurnaSilenceUnknownCallersKeyPrefix,
          normalized,
        ),
      ) ??
      false;
}

Future<void> setTurnaSilenceUnknownCallersPreference(
  String userId,
  bool enabled,
) async {
  final normalized = userId.trim();
  if (normalized.isEmpty) {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(
    _turnaScopedCallPreferenceKey(
      _kTurnaSilenceUnknownCallersKeyPrefix,
      normalized,
    ),
    enabled,
  );
}

Future<void> cacheTurnaKnownContactUserIds(
  String userId,
  Iterable<String> userIds,
) async {
  final normalizedUserId = userId.trim();
  if (normalizedUserId.isEmpty) {
    return;
  }

  final normalizedIds =
      userIds
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    _turnaScopedCallPreferenceKey(
      _kTurnaKnownContactIdsKeyPrefix,
      normalizedUserId,
    ),
    normalizedIds,
  );
  await prefs.setBool(
    _turnaScopedCallPreferenceKey(
      _kTurnaKnownContactIdsReadyKeyPrefix,
      normalizedUserId,
    ),
    true,
  );
}

Future<bool> shouldTurnaSilenceIncomingCaller({
  String? activeUserId,
  required String callerUserId,
}) async {
  final normalizedCallerId = callerUserId.trim();
  if (normalizedCallerId.isEmpty) {
    return false;
  }

  final ownerUserId = activeUserId?.trim().isNotEmpty == true
      ? activeUserId!.trim()
      : await loadTurnaCallPreferencesActiveUserId();
  if (ownerUserId == null || ownerUserId.isEmpty) {
    return false;
  }

  final prefs = await SharedPreferences.getInstance();
  final silenceUnknownCallers =
      prefs.getBool(
        _turnaScopedCallPreferenceKey(
          _kTurnaSilenceUnknownCallersKeyPrefix,
          ownerUserId,
        ),
      ) ??
      false;
  if (!silenceUnknownCallers) {
    return false;
  }

  final cacheReady =
      prefs.getBool(
        _turnaScopedCallPreferenceKey(
          _kTurnaKnownContactIdsReadyKeyPrefix,
          ownerUserId,
        ),
      ) ??
      false;
  if (!cacheReady) {
    return false;
  }

  final knownContactIds = prefs.getStringList(
    _turnaScopedCallPreferenceKey(_kTurnaKnownContactIdsKeyPrefix, ownerUserId),
  );
  return !(knownContactIds ?? const <String>[]).contains(normalizedCallerId);
}
