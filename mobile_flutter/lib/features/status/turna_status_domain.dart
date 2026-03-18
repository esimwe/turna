part of '../../app/turna_app.dart';

class TurnaStatusApi {
  static Future<TurnaStatusFeedData> fetchFeed(AuthSession session) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/statuses'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaStatusFeedData.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Durumlar yüklenemedi.');
    }
  }

  static Future<TurnaStatusPrivacySettings> fetchPrivacySettings(
    AuthSession session,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/statuses/preferences'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaStatusPrivacySettings.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Durum gizliliği yüklenemedi.');
    }
  }

  static Future<TurnaStatusPrivacySettings> updatePrivacySettings(
    AuthSession session, {
    required TurnaStatusPrivacyMode mode,
    required List<String> targetUserIds,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/statuses/preferences'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'mode': mode.wireValue,
          'targetUserIds': targetUserIds.toSet().toList(),
        }),
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaStatusPrivacySettings.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Durum gizliliği güncellenemedi.');
    }
  }

  static Future<TurnaStatusUploadTicket> createUpload(
    AuthSession session, {
    required TurnaStatusType type,
    required String contentType,
    required String fileName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/statuses/upload-url'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'type': type == TurnaStatusType.video ? 'video' : 'image',
          'contentType': contentType,
          'fileName': fileName,
        }),
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaStatusUploadTicket.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Durum yükleme hazırlığı başarısız oldu.');
    }
  }

  static Future<TurnaStatusItem> createTextStatus(
    AuthSession session, {
    required String text,
    required String backgroundColor,
    required String textColor,
    TurnaStatusTextLayout? textLayout,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/statuses'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'type': 'text',
          'text': text.trim(),
          if (textLayout != null) 'textLayout': textLayout.toMap(),
          'backgroundColor': backgroundColor,
          'textColor': textColor,
        }),
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaStatusItem.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Metin durumu paylaşılamadı.');
    }
  }

  static Future<TurnaStatusItem> createMediaStatus(
    AuthSession session, {
    required TurnaStatusType type,
    required String objectKey,
    required String contentType,
    required String fileName,
    required int sizeBytes,
    int? width,
    int? height,
    int? durationSeconds,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/statuses'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'type': type == TurnaStatusType.video ? 'video' : 'image',
          'objectKey': objectKey,
          'contentType': contentType,
          'fileName': fileName,
          'sizeBytes': sizeBytes,
          'width': width,
          'height': height,
          'durationSeconds': durationSeconds,
        }),
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaStatusItem.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Durum paylaşılamadı.');
    }
  }

  static Future<TurnaStatusUserFeed> fetchUserFeed(
    AuthSession session,
    String userId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/statuses/users/$userId'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return TurnaStatusUserFeed.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Durum akışı yüklenemedi.');
    }
  }

  static Future<void> markViewed(AuthSession session, String statusId) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/statuses/$statusId/view'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Durum görüntülenemedi.');
    }
  }

  static Future<List<TurnaStatusViewer>> fetchViewers(
    AuthSession session,
    String statusId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/statuses/$statusId/viewers'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (map['data'] as List<dynamic>? ?? const []);
      return data
          .whereType<Map>()
          .map(
            (item) =>
                TurnaStatusViewer.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Durumu görenler yüklenemedi.');
    }
  }

  static Future<bool> setMuted(
    AuthSession session, {
    required String userId,
    required bool muted,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/statuses/users/$userId/mute'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'muted': muted}),
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return data['muted'] == true;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException(
        muted ? 'Durum sessize alınamadı.' : 'Durum sesi açılamadı.',
      );
    }
  }
}
