part of '../main.dart';

enum TurnaCallType { audio, video }

enum TurnaCallStatus { ringing, accepted, declined, missed, ended, cancelled }

class TurnaCallPeer {
  TurnaCallPeer({required this.id, required this.displayName, this.avatarUrl});

  final String id;
  final String displayName;
  final String? avatarUrl;

  factory TurnaCallPeer.fromMap(Map<String, dynamic> map) {
    return TurnaCallPeer(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      avatarUrl: TurnaUserProfile._nullableString(map['avatarUrl']),
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'displayName': displayName, 'avatarUrl': avatarUrl};
  }
}

class TurnaCallSummary {
  TurnaCallSummary({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.type,
    required this.status,
    required this.provider,
    required this.direction,
    required this.peer,
    required this.caller,
    required this.callee,
    this.roomName,
    this.createdAt,
    this.acceptedAt,
    this.endedAt,
  });

  final String id;
  final String callerId;
  final String calleeId;
  final TurnaCallType type;
  final TurnaCallStatus status;
  final String provider;
  final String direction;
  final String? roomName;
  final String? createdAt;
  final String? acceptedAt;
  final String? endedAt;
  final TurnaCallPeer peer;
  final TurnaCallPeer caller;
  final TurnaCallPeer callee;

  TurnaCallSummary copyWith({
    TurnaCallType? type,
    TurnaCallStatus? status,
    String? acceptedAt,
    bool clearAcceptedAt = false,
    String? endedAt,
    bool clearEndedAt = false,
  }) {
    return TurnaCallSummary(
      id: id,
      callerId: callerId,
      calleeId: calleeId,
      type: type ?? this.type,
      status: status ?? this.status,
      provider: provider,
      direction: direction,
      peer: peer,
      caller: caller,
      callee: callee,
      roomName: roomName,
      createdAt: createdAt,
      acceptedAt: clearAcceptedAt ? null : (acceptedAt ?? this.acceptedAt),
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
    );
  }

  factory TurnaCallSummary.fromMap(Map<String, dynamic> map) {
    return TurnaCallSummary(
      id: (map['id'] ?? '').toString(),
      callerId: (map['callerId'] ?? '').toString(),
      calleeId: (map['calleeId'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
      status: switch ((map['status'] ?? '').toString().toLowerCase()) {
        'accepted' => TurnaCallStatus.accepted,
        'declined' => TurnaCallStatus.declined,
        'missed' => TurnaCallStatus.missed,
        'ended' => TurnaCallStatus.ended,
        'cancelled' => TurnaCallStatus.cancelled,
        _ => TurnaCallStatus.ringing,
      },
      provider: (map['provider'] ?? '').toString(),
      direction: (map['direction'] ?? 'outgoing').toString(),
      roomName: TurnaUserProfile._nullableString(map['roomName']),
      createdAt: TurnaUserProfile._nullableString(map['createdAt']),
      acceptedAt: TurnaUserProfile._nullableString(map['acceptedAt']),
      endedAt: TurnaUserProfile._nullableString(map['endedAt']),
      peer: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['peer'] as Map? ?? const {}),
      ),
      caller: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['caller'] as Map? ?? const {}),
      ),
      callee: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['callee'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaCallHistoryItem {
  TurnaCallHistoryItem({
    required this.id,
    required this.type,
    required this.status,
    required this.direction,
    required this.peer,
    this.createdAt,
    this.acceptedAt,
    this.endedAt,
    this.durationSeconds,
  });

  final String id;
  final TurnaCallType type;
  final TurnaCallStatus status;
  final String direction;
  final String? createdAt;
  final String? acceptedAt;
  final String? endedAt;
  final int? durationSeconds;
  final TurnaCallPeer peer;

  factory TurnaCallHistoryItem.fromMap(Map<String, dynamic> map) {
    return TurnaCallHistoryItem(
      id: (map['id'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
      status: switch ((map['status'] ?? '').toString().toLowerCase()) {
        'accepted' => TurnaCallStatus.accepted,
        'declined' => TurnaCallStatus.declined,
        'missed' => TurnaCallStatus.missed,
        'ended' => TurnaCallStatus.ended,
        'cancelled' => TurnaCallStatus.cancelled,
        _ => TurnaCallStatus.ringing,
      },
      direction: (map['direction'] ?? 'outgoing').toString(),
      createdAt: TurnaUserProfile._nullableString(map['createdAt']),
      acceptedAt: TurnaUserProfile._nullableString(map['acceptedAt']),
      endedAt: TurnaUserProfile._nullableString(map['endedAt']),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      peer: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['peer'] as Map? ?? const {}),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'status': status.name,
      'direction': direction,
      'createdAt': createdAt,
      'acceptedAt': acceptedAt,
      'endedAt': endedAt,
      'durationSeconds': durationSeconds,
      'peer': peer.toMap(),
    };
  }
}

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

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_key(userId)) ?? const [];
    final items = <TurnaCallHistoryItem>[];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        items.add(TurnaCallHistoryItem.fromMap(decoded));
      } catch (_) {}
    }
    _warm[userId] = List<TurnaCallHistoryItem>.from(items);
    return items;
  }

  static Future<void> save(
    String userId,
    Iterable<TurnaCallHistoryItem> calls,
  ) async {
    final trimmed = calls.take(_historyLimit).toList();
    _warm[userId] = List<TurnaCallHistoryItem>.from(trimmed);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key(userId),
      trimmed.map((item) => jsonEncode(item.toMap())).toList(),
    );
  }
}

class TurnaCallConnectPayload {
  TurnaCallConnectPayload({
    required this.provider,
    required this.url,
    required this.roomName,
    required this.token,
    required this.callId,
    required this.type,
  });

  final String provider;
  final String url;
  final String roomName;
  final String token;
  final String callId;
  final TurnaCallType type;

  factory TurnaCallConnectPayload.fromMap(Map<String, dynamic> map) {
    return TurnaCallConnectPayload(
      provider: (map['provider'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      roomName: (map['roomName'] ?? '').toString(),
      token: (map['token'] ?? '').toString(),
      callId: (map['callId'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
    );
  }
}

class TurnaAcceptedCallEvent {
  TurnaAcceptedCallEvent({required this.call, required this.connect});

  final TurnaCallSummary call;
  final TurnaCallConnectPayload connect;

  factory TurnaAcceptedCallEvent.fromMap(Map<String, dynamic> map) {
    return TurnaAcceptedCallEvent(
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
      connect: TurnaCallConnectPayload.fromMap(
        Map<String, dynamic>.from(map['connect'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaIncomingCallEvent {
  TurnaIncomingCallEvent({required this.call});

  final TurnaCallSummary call;

  factory TurnaIncomingCallEvent.fromMap(Map<String, dynamic> map) {
    return TurnaIncomingCallEvent(
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaTerminalCallEvent {
  TurnaTerminalCallEvent({required this.kind, required this.call});

  final String kind;
  final TurnaCallSummary call;

  factory TurnaTerminalCallEvent.fromMap(
    String kind,
    Map<String, dynamic> map,
  ) {
    return TurnaTerminalCallEvent(
      kind: kind,
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaCallVideoUpgradeRequestEvent {
  TurnaCallVideoUpgradeRequestEvent({
    required this.call,
    required this.requestId,
    required this.requestedByUserId,
  });

  final TurnaCallSummary call;
  final String requestId;
  final String requestedByUserId;

  factory TurnaCallVideoUpgradeRequestEvent.fromMap(Map<String, dynamic> map) {
    return TurnaCallVideoUpgradeRequestEvent(
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
      requestId: (map['requestId'] ?? '').toString(),
      requestedByUserId: (map['requestedByUserId'] ?? '').toString(),
    );
  }
}

class TurnaCallVideoUpgradeResolutionEvent {
  TurnaCallVideoUpgradeResolutionEvent({
    required this.kind,
    required this.call,
    required this.requestId,
    required this.actedByUserId,
  });

  final String kind;
  final TurnaCallSummary call;
  final String requestId;
  final String actedByUserId;

  factory TurnaCallVideoUpgradeResolutionEvent.fromMap(
    String kind,
    Map<String, dynamic> map,
  ) {
    return TurnaCallVideoUpgradeResolutionEvent(
      kind: kind,
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
      requestId: (map['requestId'] ?? '').toString(),
      actedByUserId: (map['actedByUserId'] ?? '').toString(),
    );
  }
}

class TurnaCallCoordinator extends ChangeNotifier {
  TurnaIncomingCallEvent? _pendingIncoming;
  final Map<String, TurnaAcceptedCallEvent> _acceptedEvents = {};
  final Map<String, TurnaTerminalCallEvent> _terminalEvents = {};
  final Map<String, TurnaCallVideoUpgradeRequestEvent> _videoUpgradeRequests =
      {};
  final Map<String, TurnaCallVideoUpgradeResolutionEvent>
  _videoUpgradeResolutions = {};

  void handleIncoming(Map<String, dynamic> payload) {
    _pendingIncoming = TurnaIncomingCallEvent.fromMap(payload);
    notifyListeners();
  }

  void handleAccepted(Map<String, dynamic> payload) {
    final event = TurnaAcceptedCallEvent.fromMap(payload);
    _acceptedEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleDeclined(Map<String, dynamic> payload) {
    final event = TurnaTerminalCallEvent.fromMap('declined', payload);
    _terminalEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleMissed(Map<String, dynamic> payload) {
    final event = TurnaTerminalCallEvent.fromMap('missed', payload);
    _terminalEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleEnded(Map<String, dynamic> payload) {
    final event = TurnaTerminalCallEvent.fromMap('ended', payload);
    _terminalEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleVideoUpgradeRequested(Map<String, dynamic> payload) {
    final event = TurnaCallVideoUpgradeRequestEvent.fromMap(payload);
    _videoUpgradeRequests[event.call.id] = event;
    notifyListeners();
  }

  void handleVideoUpgradeAccepted(Map<String, dynamic> payload) {
    final event = TurnaCallVideoUpgradeResolutionEvent.fromMap(
      'accepted',
      payload,
    );
    _videoUpgradeResolutions[event.call.id] = event;
    notifyListeners();
  }

  void handleVideoUpgradeDeclined(Map<String, dynamic> payload) {
    final event = TurnaCallVideoUpgradeResolutionEvent.fromMap(
      'declined',
      payload,
    );
    _videoUpgradeResolutions[event.call.id] = event;
    notifyListeners();
  }

  TurnaIncomingCallEvent? takeIncomingCall() {
    final event = _pendingIncoming;
    _pendingIncoming = null;
    return event;
  }

  TurnaAcceptedCallEvent? consumeAccepted(String callId) {
    return _acceptedEvents.remove(callId);
  }

  TurnaTerminalCallEvent? consumeTerminal(String callId) {
    return _terminalEvents.remove(callId);
  }

  TurnaCallVideoUpgradeRequestEvent? consumeVideoUpgradeRequest(String callId) {
    return _videoUpgradeRequests.remove(callId);
  }

  TurnaCallVideoUpgradeResolutionEvent? consumeVideoUpgradeResolution(
    String callId,
  ) {
    return _videoUpgradeResolutions.remove(callId);
  }

  void clearCall(String callId) {
    if (_pendingIncoming?.call.id == callId) {
      _pendingIncoming = null;
    }
    _acceptedEvents.remove(callId);
    _terminalEvents.remove(callId);
    _videoUpgradeRequests.remove(callId);
    _videoUpgradeResolutions.remove(callId);
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
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      final cached = await TurnaCallHistoryLocalCache.load(session.userId);
      if (cached.isNotEmpty) {
        return cached;
      }
      throw TurnaApiException('Arama geçmişi yüklenemedi.');
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
