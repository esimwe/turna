part of turna_app;

final TurnaPushChatOpenCoordinator kTurnaPushChatOpenCoordinator =
    TurnaPushChatOpenCoordinator();
final TurnaShareTargetCoordinator kTurnaShareTargetCoordinator =
    TurnaShareTargetCoordinator();
final ValueNotifier<Uri?> kTurnaLastLaunchUri = ValueNotifier<Uri?>(null);

class TurnaPushChatOpenCoordinator {
  Object? _owner;
  Future<void> Function(String chatId)? _handler;
  final List<String> _pendingChatIds = <String>[];

  void bind(Object owner, Future<void> Function(String chatId) handler) {
    _owner = owner;
    _handler = handler;
    if (_pendingChatIds.isEmpty) return;
    final pending = List<String>.from(_pendingChatIds);
    _pendingChatIds.clear();
    for (final chatId in pending) {
      unawaited(handler(chatId));
    }
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _handler = null;
  }

  void requestOpen(String chatId) {
    final normalized = chatId.trim();
    if (normalized.isEmpty) return;
    final handler = _handler;
    if (handler != null) {
      unawaited(handler(normalized));
      return;
    }
    if (_pendingChatIds.contains(normalized)) return;
    _pendingChatIds.add(normalized);
  }
}

class TurnaIncomingSharedItem {
  const TurnaIncomingSharedItem({
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String filePath;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  factory TurnaIncomingSharedItem.fromMap(Map<String, dynamic> map) {
    return TurnaIncomingSharedItem(
      filePath: (map['path'] ?? '').toString(),
      fileName: (map['fileName'] ?? '').toString(),
      mimeType: (map['mimeType'] ?? '').toString(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class TurnaIncomingSharePayload {
  const TurnaIncomingSharePayload({required this.items});

  final List<TurnaIncomingSharedItem> items;

  bool get isEmpty => items.isEmpty;

  factory TurnaIncomingSharePayload.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? const [];
    return TurnaIncomingSharePayload(
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => TurnaIncomingSharedItem.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.filePath.trim().isNotEmpty)
          .toList(growable: false),
    );
  }
}

class TurnaShareTargetCoordinator {
  Object? _owner;
  Future<void> Function(TurnaIncomingSharePayload payload)? _handler;
  final List<TurnaIncomingSharePayload> _pendingPayloads =
      <TurnaIncomingSharePayload>[];
  bool _dispatching = false;

  void bind(
    Object owner,
    Future<void> Function(TurnaIncomingSharePayload payload) handler,
  ) {
    _owner = owner;
    _handler = handler;
    unawaited(_pump());
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _handler = null;
  }

  void requestHandle(TurnaIncomingSharePayload payload) {
    if (payload.isEmpty) return;
    _pendingPayloads.add(payload);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_dispatching) return;
    final handler = _handler;
    if (handler == null) return;
    _dispatching = true;
    try {
      while (_pendingPayloads.isNotEmpty && identical(handler, _handler)) {
        final payload = _pendingPayloads.removeAt(0);
        await handler(payload);
      }
    } finally {
      _dispatching = false;
    }
  }
}

class TurnaShareTargetBridge {
  static const MethodChannel _channel = MethodChannel('turna/share_target');
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      await _channel.invokeMethod<void>('shareBridgeReady');
      final payload = await _channel.invokeMethod<dynamic>(
        'consumeInitialPayload',
      );
      _dispatchPayload(payload);
    } catch (error) {
      turnaLog('share target init skipped', error);
    }
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'sharedPayloadUpdated':
        _dispatchPayload(call.arguments);
        return;
      default:
        return;
    }
  }

  static void _dispatchPayload(dynamic payload) {
    if (payload is! Map) return;
    final parsed = TurnaIncomingSharePayload.fromMap(
      Map<String, dynamic>.from(payload),
    );
    if (parsed.isEmpty) return;
    turnaLog('share target payload received', {'items': parsed.items.length});
    kTurnaShareTargetCoordinator.requestHandle(parsed);
  }
}

class TurnaLaunchBridge {
  static const MethodChannel _channel = MethodChannel('turna/launch');
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      await _channel.invokeMethod<void>('launchBridgeReady');
      final payload = await _channel.invokeMethod<dynamic>('consumeInitialUrl');
      _dispatchUrl(payload);
    } catch (error) {
      turnaLog('launch bridge init skipped', error);
    }
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'launchUrlUpdated':
        _dispatchUrl(call.arguments);
        return;
      default:
        return;
    }
  }

  static void _dispatchUrl(dynamic payload) {
    final raw = payload?.toString().trim() ?? '';
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    kTurnaLastLaunchUri.value = uri;
    turnaLog('launch url received', {'url': _sanitizeTurnaLaunchUri(uri)});
  }
}

String _sanitizeTurnaLaunchUri(Uri uri) {
  if (uri.queryParameters.isEmpty) {
    return uri.toString();
  }
  final sanitizedQuery = <String, String>{};
  final keys = uri.queryParameters.keys.toList()..sort();
  for (final key in keys) {
    sanitizedQuery[key] = 'redacted';
  }
  return uri.replace(queryParameters: sanitizedQuery).toString();
}
