part of '../../app/turna_app.dart';

class TurnaCallHistoryLocalCache {
  static const int _historyLimit = 240;
  static const String _prefix = 'turna_call_history_v1_';
  static final Map<String, List<TurnaCallHistoryItem>> _warm =
      <String, List<TurnaCallHistoryItem>>{};

  static String _key(String userId) => '$_prefix$userId';

  static List<TurnaCallHistoryItem>? peek(String userId) {
    final cached = _warm[userId];
    if (cached == null) return null;
    return List<TurnaCallHistoryItem>.from(cached);
  }

  static Future<List<TurnaCallHistoryItem>> load(String userId) async {
    final warm = peek(userId);
    if (warm != null) return warm;

    final items = await TurnaCallHistoryLocalRepository.load(
      userId,
      _key(userId),
    );
    _warm[userId] = List<TurnaCallHistoryItem>.from(items);
    return items;
  }

  static Future<void> save(
    String userId,
    Iterable<TurnaCallHistoryItem> calls,
  ) async {
    final trimmed = calls.take(_historyLimit).toList();
    _warm[userId] = List<TurnaCallHistoryItem>.from(trimmed);
    await TurnaCallHistoryLocalRepository.save(userId, _key(userId), trimmed);
  }
}

class CallApi {
  static Future<List<TurnaCallHistoryItem>> fetchCalls(
    AuthSession session, {
    int refreshTick = 0,
  }) async {
    try {
      turnaLog('api fetchCalls', {'refreshTick': refreshTick});
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/calls'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      ChatApi._throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (map['data'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                TurnaCallHistoryItem.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
      await TurnaCallHistoryLocalCache.save(session.userId, items);
      return items;
    } on TurnaUnauthorizedException {
      rethrow;
    } on TurnaApiException {
      final cached = await TurnaCallHistoryLocalCache.load(session.userId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    } catch (_) {
      final cached = await TurnaCallHistoryLocalCache.load(session.userId);
      if (cached.isNotEmpty) {
        return cached;
      }
      throw TurnaApiException('Arama geçmişi yüklenemedi.');
    }
  }

  static Future<({TurnaGroupCallState? state, bool canStart})>
  fetchActiveGroupCall(AuthSession session, {required String chatId}) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/calls/group-chat/$chatId'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      final rawState = data['state'] as Map?;
      return (
        state: rawState == null
            ? null
            : TurnaGroupCallState.fromMap(Map<String, dynamic>.from(rawState)),
        canStart: data['canStart'] == true,
      );
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Grup çağrısı durumu yüklenemedi.');
    }
  }

  static Future<TurnaGroupCallJoinResult> joinGroupCall(
    AuthSession session, {
    required String chatId,
    TurnaCallType? type,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/group-chat/$chatId/join'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({if (type != null) 'type': type.name}),
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      return TurnaGroupCallJoinResult.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Grup çağrısına katılınamadı.');
    }
  }

  static Future<TurnaGroupCallState?> leaveGroupCall(
    AuthSession session, {
    required String chatId,
    required String roomName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/group-chat/$chatId/leave'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'roomName': roomName}),
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      final rawState = data['state'] as Map?;
      if (rawState == null) return null;
      return TurnaGroupCallState.fromMap(Map<String, dynamic>.from(rawState));
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Grup çağrısından çıkılamadı.');
    }
  }

  static Future<TurnaGroupCallState?> updateGroupCallModeration(
    AuthSession session, {
    required String chatId,
    String? microphonePolicy,
    String? cameraPolicy,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$kBackendBaseUrl/api/calls/group-chat/$chatId/moderation'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          ?microphonePolicy: microphonePolicy,
          ?cameraPolicy: cameraPolicy,
        }),
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      final rawState = data['state'] as Map?;
      if (rawState == null) return null;
      return TurnaGroupCallState.fromMap(Map<String, dynamic>.from(rawState));
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Grup çağrısı ayarları güncellenemedi.');
    }
  }

  static Future<TurnaCallSummary> startCall(
    AuthSession session, {
    required String calleeId,
    required TurnaCallType type,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/start'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'calleeId': calleeId, 'type': type.name}),
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      return TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(data['call'] as Map? ?? const {}),
      );
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama başlatılamadı.');
    }
  }

  static Future<TurnaAcceptedCallEvent> acceptCall(
    AuthSession session, {
    required String callId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/$callId/accept'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      return TurnaAcceptedCallEvent(
        call: TurnaCallSummary.fromMap(
          Map<String, dynamic>.from(data['call'] as Map? ?? const {}),
        ),
        connect: TurnaCallConnectPayload.fromMap(
          Map<String, dynamic>.from(data['connect'] as Map? ?? const {}),
        ),
      );
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama kabul edilemedi.');
    }
  }

  static Future<void> declineCall(
    AuthSession session, {
    required String callId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/$callId/decline'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama reddedilemedi.');
    }
  }

  static Future<void> endCall(
    AuthSession session, {
    required String callId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/$callId/end'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama sonlandırılamadı.');
    }
  }

  static Future<TurnaCallVideoUpgradeRequestEvent> requestVideoUpgrade(
    AuthSession session, {
    required String callId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/$callId/video-upgrade/request'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      return TurnaCallVideoUpgradeRequestEvent.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Görüntülü arama isteği gönderilemedi.');
    }
  }

  static Future<TurnaCallVideoUpgradeResolutionEvent> acceptVideoUpgrade(
    AuthSession session, {
    required String callId,
    required String requestId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/$callId/video-upgrade/accept'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'requestId': requestId}),
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      return TurnaCallVideoUpgradeResolutionEvent.fromMap('accepted', data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Görüntülü arama isteği kabul edilemedi.');
    }
  }

  static Future<TurnaCallVideoUpgradeResolutionEvent> declineVideoUpgrade(
    AuthSession session, {
    required String callId,
    required String requestId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/$callId/video-upgrade/decline'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'requestId': requestId}),
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      return TurnaCallVideoUpgradeResolutionEvent.fromMap('declined', data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Görüntülü arama isteği reddedilemedi.');
    }
  }

  static Future<List<String>> reconcileCalls(AuthSession session) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/calls/reconcile'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      ChatApi._throwIfApiError(res);
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map? ?? const {});
      final calls = (data['calls'] as List<dynamic>? ?? const []);
      return calls
          .whereType<Map>()
          .map((item) => (item['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama durumu eşitlenemedi.');
    }
  }
}
