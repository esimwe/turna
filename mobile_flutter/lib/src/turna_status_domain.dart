part of '../main.dart';

class TurnaStatusUser {
  TurnaStatusUser({
    required this.id,
    required this.displayName,
    this.phone,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? phone;
  final String? avatarUrl;

  String get resolvedDisplayName => TurnaContactsDirectory.resolveDisplayLabel(
    phone: phone,
    fallbackName: displayName,
  );

  factory TurnaStatusUser.fromMap(Map<String, dynamic> map) {
    return TurnaStatusUser(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      phone: TurnaUserProfile._nullableString(map['phone']),
      avatarUrl: TurnaUserProfile._nullableString(map['avatarUrl']),
    );
  }
}

enum TurnaStatusType { text, image, video }

extension TurnaStatusTypeX on TurnaStatusType {
  static TurnaStatusType fromWire(String value) {
    switch (value.trim().toLowerCase()) {
      case 'image':
        return TurnaStatusType.image;
      case 'video':
        return TurnaStatusType.video;
      default:
        return TurnaStatusType.text;
    }
  }
}

enum TurnaStatusPrivacyMode { myContacts, excludedContacts, onlySharedWith }

extension TurnaStatusPrivacyModeX on TurnaStatusPrivacyMode {
  static TurnaStatusPrivacyMode fromWire(String value) {
    switch (value.trim().toLowerCase()) {
      case 'excluded_contacts':
        return TurnaStatusPrivacyMode.excludedContacts;
      case 'only_shared_with':
        return TurnaStatusPrivacyMode.onlySharedWith;
      default:
        return TurnaStatusPrivacyMode.myContacts;
    }
  }

  String get wireValue {
    switch (this) {
      case TurnaStatusPrivacyMode.excludedContacts:
        return 'excluded_contacts';
      case TurnaStatusPrivacyMode.onlySharedWith:
        return 'only_shared_with';
      case TurnaStatusPrivacyMode.myContacts:
        return 'my_contacts';
    }
  }
}

class TurnaStatusMySummary {
  TurnaStatusMySummary({
    required this.count,
    this.latestAt,
    this.latestType,
    this.previewText,
  });

  final int count;
  final String? latestAt;
  final TurnaStatusType? latestType;
  final String? previewText;

  bool get hasStatuses => count > 0;

  factory TurnaStatusMySummary.fromMap(Map<String, dynamic> map) {
    final latestTypeRaw = TurnaUserProfile._nullableString(map['latestType']);
    return TurnaStatusMySummary(
      count: (map['count'] as num?)?.toInt() ?? 0,
      latestAt: TurnaUserProfile._nullableString(map['latestAt']),
      latestType: latestTypeRaw == null
          ? null
          : TurnaStatusTypeX.fromWire(latestTypeRaw),
      previewText: TurnaUserProfile._nullableString(map['previewText']),
    );
  }
}

class TurnaStatusPrivacySettings {
  TurnaStatusPrivacySettings({
    required this.mode,
    this.targetUserIds = const <String>[],
    this.mutedUserIds = const <String>[],
  });

  final TurnaStatusPrivacyMode mode;
  final List<String> targetUserIds;
  final List<String> mutedUserIds;

  factory TurnaStatusPrivacySettings.fromMap(Map<String, dynamic> map) {
    return TurnaStatusPrivacySettings(
      mode: TurnaStatusPrivacyModeX.fromWire(
        (map['mode'] ?? 'my_contacts').toString(),
      ),
      targetUserIds: (map['targetUserIds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      mutedUserIds: (map['mutedUserIds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
    );
  }
}

class TurnaStatusAuthorSummary {
  TurnaStatusAuthorSummary({
    required this.user,
    required this.latestAt,
    required this.latestType,
    required this.previewText,
    required this.itemCount,
    required this.hasUnviewed,
    required this.muted,
  });

  final TurnaStatusUser user;
  final String latestAt;
  final TurnaStatusType latestType;
  final String previewText;
  final int itemCount;
  final bool hasUnviewed;
  final bool muted;

  factory TurnaStatusAuthorSummary.fromMap(Map<String, dynamic> map) {
    return TurnaStatusAuthorSummary(
      user: TurnaStatusUser.fromMap(
        Map<String, dynamic>.from(map['user'] as Map? ?? const {}),
      ),
      latestAt: (map['latestAt'] ?? '').toString(),
      latestType: TurnaStatusTypeX.fromWire(
        (map['latestType'] ?? 'text').toString(),
      ),
      previewText: (map['previewText'] ?? '').toString(),
      itemCount: (map['itemCount'] as num?)?.toInt() ?? 0,
      hasUnviewed: map['hasUnviewed'] == true,
      muted: map['muted'] == true,
    );
  }
}

class TurnaStatusItem {
  TurnaStatusItem({
    required this.id,
    required this.author,
    required this.type,
    required this.createdAt,
    required this.expiresAt,
    this.text,
    this.textLayout,
    this.backgroundColor,
    this.textColor,
    this.objectKey,
    this.url,
    this.contentType,
    this.fileName,
    this.sizeBytes,
    this.width,
    this.height,
    this.durationSeconds,
    this.viewedByMe = false,
    this.viewedCount = 0,
  });

  final String id;
  final TurnaStatusUser author;
  final TurnaStatusType type;
  final String createdAt;
  final String expiresAt;
  final String? text;
  final TurnaStatusTextLayout? textLayout;
  final String? backgroundColor;
  final String? textColor;
  final String? objectKey;
  final String? url;
  final String? contentType;
  final String? fileName;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final bool viewedByMe;
  final int viewedCount;

  bool get isText => type == TurnaStatusType.text;
  bool get isImage => type == TurnaStatusType.image;
  bool get isVideo => type == TurnaStatusType.video;

  factory TurnaStatusItem.fromMap(Map<String, dynamic> map) {
    return TurnaStatusItem(
      id: (map['id'] ?? '').toString(),
      author: TurnaStatusUser.fromMap(
        Map<String, dynamic>.from(map['author'] as Map? ?? const {}),
      ),
      type: TurnaStatusTypeX.fromWire((map['type'] ?? 'text').toString()),
      createdAt: (map['createdAt'] ?? '').toString(),
      expiresAt: (map['expiresAt'] ?? '').toString(),
      text: TurnaUserProfile._nullableString(map['text']),
      textLayout: map['textLayout'] is Map
          ? TurnaStatusTextLayout.fromMap(
              Map<String, dynamic>.from(map['textLayout'] as Map),
            )
          : null,
      backgroundColor: TurnaUserProfile._nullableString(map['backgroundColor']),
      textColor: TurnaUserProfile._nullableString(map['textColor']),
      objectKey: TurnaUserProfile._nullableString(map['objectKey']),
      url: TurnaUserProfile._nullableString(map['url']),
      contentType: TurnaUserProfile._nullableString(map['contentType']),
      fileName: TurnaUserProfile._nullableString(map['fileName']),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      viewedByMe: map['viewedByMe'] == true,
      viewedCount: (map['viewedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class TurnaStatusTextLayout {
  TurnaStatusTextLayout({
    required this.x,
    required this.y,
    required this.scale,
    this.fontFamily,
  });

  final double x;
  final double y;
  final double scale;
  final String? fontFamily;

  factory TurnaStatusTextLayout.fromMap(Map<String, dynamic> map) {
    return TurnaStatusTextLayout(
      x: ((map['x'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
      y: ((map['y'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
      scale: ((map['scale'] as num?)?.toDouble() ?? 1).clamp(0.6, 3.0),
      fontFamily: TurnaUserProfile._nullableString(map['fontFamily']),
    );
  }

  Map<String, dynamic> toMap() => {
    'x': x,
    'y': y,
    'scale': scale,
    if (fontFamily?.trim().isNotEmpty == true) 'fontFamily': fontFamily!.trim(),
  };
}

class TurnaStatusViewer {
  TurnaStatusViewer({required this.user, required this.viewedAt});

  final TurnaStatusUser user;
  final String viewedAt;

  factory TurnaStatusViewer.fromMap(Map<String, dynamic> map) {
    return TurnaStatusViewer(
      user: TurnaStatusUser.fromMap(
        Map<String, dynamic>.from(map['user'] as Map? ?? const {}),
      ),
      viewedAt: (map['viewedAt'] ?? '').toString(),
    );
  }
}

class TurnaStatusUploadTicket {
  TurnaStatusUploadTicket({
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
  });

  final String objectKey;
  final String uploadUrl;
  final Map<String, String> headers;

  factory TurnaStatusUploadTicket.fromMap(Map<String, dynamic> map) {
    return TurnaStatusUploadTicket(
      objectKey: (map['objectKey'] ?? '').toString(),
      uploadUrl: (map['uploadUrl'] ?? '').toString(),
      headers: (map['headers'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }
}

class TurnaStatusFeedData {
  TurnaStatusFeedData({
    required this.mine,
    required this.privacy,
    required this.updates,
    required this.mutedUpdates,
  });

  final TurnaStatusMySummary mine;
  final TurnaStatusPrivacySettings privacy;
  final List<TurnaStatusAuthorSummary> updates;
  final List<TurnaStatusAuthorSummary> mutedUpdates;

  factory TurnaStatusFeedData.fromMap(Map<String, dynamic> map) {
    return TurnaStatusFeedData(
      mine: TurnaStatusMySummary.fromMap(
        Map<String, dynamic>.from(map['mine'] as Map? ?? const {}),
      ),
      privacy: TurnaStatusPrivacySettings.fromMap(
        Map<String, dynamic>.from(map['privacy'] as Map? ?? const {}),
      ),
      updates: (map['updates'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => TurnaStatusAuthorSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      mutedUpdates: (map['muted'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => TurnaStatusAuthorSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class TurnaStatusUserFeed {
  TurnaStatusUserFeed({
    required this.own,
    required this.user,
    required this.items,
  });

  final bool own;
  final TurnaStatusUser user;
  final List<TurnaStatusItem> items;

  factory TurnaStatusUserFeed.fromMap(Map<String, dynamic> map) {
    return TurnaStatusUserFeed(
      own: map['own'] == true,
      user: TurnaStatusUser.fromMap(
        Map<String, dynamic>.from(map['user'] as Map? ?? const {}),
      ),
      items: (map['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => TurnaStatusItem.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

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
