import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart' as cam;
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide Event;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart' as pm;
import 'package:record/record.dart' as rec;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart' as vp;

import 'community_shell_preview.dart';

part 'src/turna_shell.dart';
part 'src/turna_inbox.dart';
part 'src/turna_chat_room.dart';
part 'src/turna_group_info.dart';
part 'src/turna_group_settings.dart';
part 'src/turna_media_composer.dart';
part 'src/turna_voice.dart';
part 'src/turna_auth_flow.dart';
part 'src/turna_profile_shell.dart';
part 'src/turna_core.dart';
part 'src/turna_calls.dart';
part 'src/turna_call_runtime.dart';
part 'src/turna_call_ui.dart';
part 'src/turna_media.dart';
part 'src/turna_status_domain.dart';
part 'src/turna_status_feed.dart';
part 'src/turna_status_viewer.dart';
part 'src/turna_location.dart';
part 'src/turna_contact.dart';
part 'src/turna_status.dart';

String _normalizeTurnaBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

const String _kDefaultBackendBaseUrl = 'https://api.turna.im';
final String kBackendBaseUrl = _normalizeTurnaBaseUrl(
  const String.fromEnvironment(
    'TURNA_BACKEND_URL',
    defaultValue: _kDefaultBackendBaseUrl,
  ),
);
const String kTurnaStadiaRasterStyle = 'alidade_smooth';
const int kTurnaLiveLocationUpdateDistanceMeters = 15;
const int kTurnaLiveLocationUpdateIntervalSeconds = 15;

class TurnaAppConfig {
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}
    _loaded = true;
  }

  static String get stadiaMapsApiKey =>
      (dotenv.env['STADIA_MAPS_API_KEY'] ?? '').trim();

  static bool get hasStadiaMapsKey => stadiaMapsApiKey.isNotEmpty;
}

const bool kTurnaDebugLogs = true;
const String kChatRoomRouteName = 'chat-room';
const int kComposerMediaLimit = 30;
const int kInlineAttachmentSoftLimitBytes = 64 * 1024 * 1024;
const int kDocumentAttachmentMaxBytes = 2 * 1024 * 1024 * 1024;
const int kStatusMaxVideoDurationSeconds = 60;
const int kInlineImagePickerQuality = 82;
const double kInlineImagePickerMaxDimension = 2200;
const double kInlineImageSdMaxDimension = 1600;
const double kInlineImageHdMaxDimension = 2560;
const int kInlineVideoStandardMaxHeight = 720;
const int kInlineVideoHdMaxHeight = 1080;
const int kInlineVideoStandardBitrate = 1800000;
const int kInlineVideoHdBitrate = 4200000;
const Offset kComposerOverlayDefaultPosition = Offset(0.5, 0.5);
const Rect kComposerFullCropRectNormalized = Rect.fromLTWH(0, 0, 1, 1);
const double kComposerCropInitialInset = 0.08;
const double kComposerCropMinSide = 0.18;
const List<Color> kComposerPaletteStops = [
  Color(0xFFFFFFFF),
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFD60A),
  Color(0xFF34C759),
  Color(0xFF00C7BE),
  Color(0xFF0A84FF),
  Color(0xFF5E5CE6),
  Color(0xFFBF5AF2),
  Color(0xFFFF2D55),
];
const List<_MediaCropPreset> _kComposerCropPresets = [
  _MediaCropPreset(id: 'free', label: 'Serbest', freeform: true),
  _MediaCropPreset(id: 'fit', label: 'Sigdir', fullImage: true),
  _MediaCropPreset(id: 'original', label: 'Orijinal', useOriginalAspect: true),
  _MediaCropPreset(id: 'square', label: 'Kare', aspectRatio: 1),
  _MediaCropPreset(id: '2x3', label: '2:3', aspectRatio: 2 / 3),
  _MediaCropPreset(id: '3x5', label: '3:5', aspectRatio: 3 / 5),
  _MediaCropPreset(id: '3x4', label: '3:4', aspectRatio: 3 / 4),
  _MediaCropPreset(id: '4x5', label: '4:5', aspectRatio: 4 / 5),
  _MediaCropPreset(id: '5x7', label: '5:7', aspectRatio: 5 / 7),
  _MediaCropPreset(id: '9x16', label: '9:16', aspectRatio: 9 / 16),
];

final GlobalKey<NavigatorState> kTurnaNavigatorKey =
    GlobalKey<NavigatorState>();
final RouteObserver<PageRoute<dynamic>> kTurnaRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
final ValueNotifier<AppLifecycleState> kTurnaLifecycleState = ValueNotifier(
  AppLifecycleState.resumed,
);
final TurnaActiveChatRegistry kTurnaActiveChatRegistry =
    TurnaActiveChatRegistry();
final TurnaCallUiController kTurnaCallUiController = TurnaCallUiController();
final TurnaPushChatOpenCoordinator kTurnaPushChatOpenCoordinator =
    TurnaPushChatOpenCoordinator();
final TurnaShareTargetCoordinator kTurnaShareTargetCoordinator =
    TurnaShareTargetCoordinator();

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
    kTurnaShareTargetCoordinator.requestHandle(parsed);
  }
}

class TurnaColors {
  static const primary50 = Color(0xFFEEF7FF);
  static const primary100 = Color(0xFFD9EEFF);
  static const primary200 = Color(0xFFBCE0FF);
  static const primary300 = Color(0xFF8FCBFF);
  static const primary400 = Color(0xFF5BB0FF);
  static const primary = Color(0xFF2F80ED);
  static const primaryStrong = Color(0xFF1F6FEB);
  static const primaryDeep = Color(0xFF1B4ED8);
  static const primary800 = Color(0xFF163EA8);
  static const primary900 = Color(0xFF132F7D);
  static const accent100 = Color(0xFFDFF8FF);
  static const accent200 = Color(0xFFB8EFFF);
  static const accent300 = Color(0xFF7FE2FF);
  static const accent = Color(0xFF38BDF8);
  static const accentStrong = Color(0xFF00C2FF);
  static const accentDeep = Color(0xFF00A7DF);
  static const navy700 = Color(0xFF14213D);
  static const navy800 = Color(0xFF0F172A);
  static const navy900 = Color(0xFF0B1220);

  static const background = Color(0xFFFFFFFF);
  static const backgroundSoft = Color(0xFFF7F9FC);
  static const backgroundMuted = Color(0xFFEEF4FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHover = Color(0xFFF3F8FF);
  static const border = Color(0xFFD8E6F5);
  static const divider = Color(0xFFE2ECF7);

  static const text = Color(0xFF0F172A);
  static const textSoft = Color(0xFF334155);
  static const textMuted = Color(0xFF64748B);
  static const textInverse = Color(0xFFFFFFFF);

  static const chatOutgoing = Color(0xFFE2FFC8);
  static const chatOutgoingText = Color(0xFF23291B);
  static const chatOutgoingMeta = Color(0xFF88A274);
  static const chatOutgoingRead = Color(0xFF1D89F8);
  static const chatIncoming = Color(0xFFEDF4FB);
  static const chatIncomingText = Color(0xFF0F172A);
  static const chatUnreadBg = Color(0xFFEEF7FF);
  static const chatActive = Color(0xFF38BDF8);

  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const info = Color(0xFF38BDF8);

  static const avatarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary300, primary],
  );
  static const chatOutgoingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [chatOutgoing, chatOutgoing],
  );
  static const shadowBubble = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 3,
    offset: Offset(0, 1),
  );
  static const shadowSoft = BoxShadow(
    color: Color(0x0D000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );
  static const shadowFab = BoxShadow(
    color: Color(0x402F80ED),
    blurRadius: 20,
    offset: Offset(0, 8),
  );
}

class TurnaChatTokens {
  static const bubbleRadius = 20.0;
  static const bubbleRadiusTail = 8.0;
  static const messageMaxWidthFactor = 0.76;
  static const stackGap = 4.0;
  static const groupGap = 10.0;
  static const sectionGap = 14.0;
  static const dateGap = 18.0;
}

final RegExp _kTurnaReplyMarkerPattern = RegExp(
  r'^\[\[turna-reply:([A-Za-z0-9_-]+)\]\]\n?',
);
final RegExp _kTurnaLocationMarkerPattern = RegExp(
  r'^\[\[turna-location:([A-Za-z0-9_-]+)\]\]\n?',
);
final RegExp _kTurnaContactMarkerPattern = RegExp(
  r'^\[\[turna-contact:([A-Za-z0-9_-]+)\]\]\n?',
);
const String _kTurnaDeletedEveryoneMarker = '[[turna-deleted-everyone]]';

class TurnaReplyPayload {
  const TurnaReplyPayload({
    required this.messageId,
    required this.senderLabel,
    required this.previewText,
  });

  final String messageId;
  final String senderLabel;
  final String previewText;

  Map<String, dynamic> toMap() => {
    'messageId': messageId,
    'senderLabel': senderLabel,
    'previewText': previewText,
  };

  factory TurnaReplyPayload.fromMap(Map<String, dynamic> map) {
    return TurnaReplyPayload(
      messageId: (map['messageId'] ?? '').toString(),
      senderLabel: (map['senderLabel'] ?? '').toString(),
      previewText: (map['previewText'] ?? '').toString(),
    );
  }
}

class ParsedTurnaMessageText {
  const ParsedTurnaMessageText({
    required this.text,
    this.reply,
    this.location,
    this.contact,
    this.deletedForEveryone = false,
  });

  final String text;
  final TurnaReplyPayload? reply;
  final TurnaLocationPayload? location;
  final TurnaSharedContactPayload? contact;
  final bool deletedForEveryone;
}

class _PinnedMessageDraft {
  const _PinnedMessageDraft({
    required this.messageId,
    required this.senderLabel,
    required this.previewText,
  });

  final String messageId;
  final String senderLabel;
  final String previewText;

  Map<String, dynamic> toMap() => {
    'messageId': messageId,
    'senderLabel': senderLabel,
    'previewText': previewText,
  };

  factory _PinnedMessageDraft.fromMap(Map<String, dynamic> map) {
    return _PinnedMessageDraft(
      messageId: (map['messageId'] ?? '').toString(),
      senderLabel: (map['senderLabel'] ?? '').toString(),
      previewText: (map['previewText'] ?? '').toString(),
    );
  }
}

ParsedTurnaMessageText parseTurnaMessageText(String raw) {
  if (raw.trim() == _kTurnaDeletedEveryoneMarker) {
    return const ParsedTurnaMessageText(
      text: 'Silindi.',
      deletedForEveryone: true,
    );
  }

  var working = raw;
  TurnaReplyPayload? reply;

  final replyMatch = _kTurnaReplyMarkerPattern.firstMatch(working);
  if (replyMatch != null) {
    try {
      final encoded = replyMatch.group(1)!;
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
      );
      reply = TurnaReplyPayload.fromMap(
        jsonDecode(decoded) as Map<String, dynamic>,
      );
      working = working.substring(replyMatch.end);
    } catch (_) {
      return ParsedTurnaMessageText(text: raw);
    }
  }

  final locationMatch = _kTurnaLocationMarkerPattern.firstMatch(working);
  if (locationMatch != null) {
    try {
      final encoded = locationMatch.group(1)!;
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
      );
      final payload = TurnaLocationPayload.fromMap(
        jsonDecode(decoded) as Map<String, dynamic>,
      );
      final cleaned = working.substring(locationMatch.end).trimLeft();
      return ParsedTurnaMessageText(
        text: cleaned,
        reply: reply,
        location: payload,
      );
    } catch (_) {
      return ParsedTurnaMessageText(text: raw);
    }
  }

  final contactMatch = _kTurnaContactMarkerPattern.firstMatch(working);
  if (contactMatch != null) {
    try {
      final encoded = contactMatch.group(1)!;
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
      );
      final payload = TurnaSharedContactPayload.fromMap(
        jsonDecode(decoded) as Map<String, dynamic>,
      );
      final cleaned = working.substring(contactMatch.end).trimLeft();
      return ParsedTurnaMessageText(
        text: cleaned,
        reply: reply,
        contact: payload,
      );
    } catch (_) {
      return ParsedTurnaMessageText(text: raw);
    }
  }

  return ParsedTurnaMessageText(text: working, reply: reply);
}

String buildTurnaReplyEncodedText({
  required TurnaReplyPayload reply,
  required String text,
}) {
  final encoded = base64UrlEncode(
    utf8.encode(jsonEncode(reply.toMap())),
  ).replaceAll('=', '');
  return '[[turna-reply:$encoded]]\n$text';
}

String buildTurnaLocationEncodedText({required TurnaLocationPayload location}) {
  final encoded = base64UrlEncode(
    utf8.encode(jsonEncode(location.toMap())),
  ).replaceAll('=', '');
  return '[[turna-location:$encoded]]';
}

String buildTurnaContactEncodedText({
  required TurnaSharedContactPayload contact,
}) {
  final encoded = base64UrlEncode(
    utf8.encode(jsonEncode(contact.toMap())),
  ).replaceAll('=', '');
  return '[[turna-contact:$encoded]]';
}

String sanitizeTurnaChatPreviewText(String raw) {
  final parsed = parseTurnaMessageText(raw);
  if (parsed.deletedForEveryone) return parsed.text;
  if (parsed.location != null) {
    return parsed.location!.previewLabel;
  }
  if (parsed.contact != null) {
    return parsed.contact!.previewLabel;
  }
  final cleaned = parsed.text.trim();
  if (cleaned.isNotEmpty) return cleaned;
  return parsed.reply?.previewText ?? raw;
}

void turnaLog(String message, [Object? data]) {
  if (!kTurnaDebugLogs) return;
  if (data != null) {
    debugPrint('[turna-mobile] $message | $data');
    return;
  }
  debugPrint('[turna-mobile] $message');
}

Map<String, String>? buildTurnaAuthHeaders(String? authToken) {
  final trimmed = authToken?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return {'Authorization': 'Bearer $trimmed'};
}

String normalizeTurnaRemoteUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final remote = Uri.tryParse(trimmed);
  final backend = Uri.tryParse(kBackendBaseUrl);
  if (remote == null || backend == null) return trimmed;

  final sameHost = remote.host.toLowerCase() == backend.host.toLowerCase();
  final shouldUpgradeToHttps =
      sameHost && backend.scheme == 'https' && remote.scheme == 'http';
  if (!shouldUpgradeToHttps) return trimmed;

  return remote
      .replace(
        scheme: 'https',
        port: remote.hasPort && remote.port != 80 ? remote.port : null,
      )
      .toString();
}

final RegExp _kTurnaSharedUrlPattern = RegExp(
  r'((?:(?:https?:\/\/)|(?:www\.))?(?<!@)(?:[a-z0-9-]+\.)+[a-z]{2,}(?:[\/?#][^\s<]*)?)',
  caseSensitive: false,
);

String _trimTurnaUrlEdgePunctuation(String value) {
  var current = value.trim();
  while (current.isNotEmpty && RegExp(r'[\])},.!?;:]+$').hasMatch(current)) {
    current = current.substring(0, current.length - 1);
  }
  return current;
}

Uri? parseTurnaSharedUrl(String raw) {
  final trimmed = _trimTurnaUrlEdgePunctuation(raw);
  if (trimmed.isEmpty) return null;
  final normalized =
      trimmed.startsWith('http://') || trimmed.startsWith('https://')
      ? trimmed
      : 'https://$trimmed';
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.trim().isEmpty) return null;
  return uri;
}

List<Uri> extractTurnaUrls(String text) {
  final found = <Uri>[];
  final seen = <String>{};
  for (final match in _kTurnaSharedUrlPattern.allMatches(text)) {
    final uri = parseTurnaSharedUrl(match.group(0) ?? '');
    if (uri == null) continue;
    final key = uri.toString();
    if (seen.add(key)) {
      found.add(uri);
    }
  }
  return found;
}

class TurnaLinkPreviewMetadata {
  const TurnaLinkPreviewMetadata({
    required this.uri,
    required this.title,
    required this.host,
    required this.displayUrl,
  });

  final Uri uri;
  final String title;
  final String host;
  final String displayUrl;
}

class TurnaLinkPreviewCache {
  static final Map<String, TurnaLinkPreviewMetadata> _resolved = {};
  static final Map<String, Future<TurnaLinkPreviewMetadata>> _pending = {};
  static final RegExp _titlePattern = RegExp(
    r'<title[^>]*>(.*?)<\/title>',
    caseSensitive: false,
    dotAll: true,
  );

  static TurnaLinkPreviewMetadata? peek(Uri uri) => _resolved[uri.toString()];

  static Future<TurnaLinkPreviewMetadata> resolve(Uri uri) async {
    final normalized = uri.toString();
    final cached = _resolved[normalized];
    if (cached != null) return cached;

    final pending = _pending[normalized];
    if (pending != null) return pending;

    final future = _fetch(uri);
    _pending[normalized] = future;
    try {
      final resolved = await future;
      _resolved[normalized] = resolved;
      return resolved;
    } finally {
      if (identical(_pending[normalized], future)) {
        _pending.remove(normalized);
      }
    }
  }

  static Future<TurnaLinkPreviewMetadata> _fetch(Uri uri) async {
    final host = uri.host.replaceFirst(
      RegExp(r'^www\.', caseSensitive: false),
      '',
    );
    final displayUrl = host.isEmpty ? uri.toString() : '$host${uri.path}';

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Turna/1.0 Mobile',
        },
      );
      if (response.statusCode >= 400 || response.bodyBytes.isEmpty) {
        return TurnaLinkPreviewMetadata(
          uri: uri,
          title: host.isEmpty ? uri.toString() : host,
          host: host,
          displayUrl: displayUrl,
        );
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final rawTitle = _titlePattern.firstMatch(html)?.group(1) ?? '';
      final cleanedTitle = rawTitle
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .trim();

      return TurnaLinkPreviewMetadata(
        uri: uri,
        title: cleanedTitle.isEmpty
            ? (host.isEmpty ? uri.toString() : host)
            : cleanedTitle,
        host: host,
        displayUrl: displayUrl,
      );
    } catch (_) {
      return TurnaLinkPreviewMetadata(
        uri: uri,
        title: host.isEmpty ? uri.toString() : host,
        host: host,
        displayUrl: displayUrl,
      );
    }
  }
}

class TurnaMediaBridge {
  static const MethodChannel _channel = MethodChannel('turna/media');

  static Future<void> saveToGallery({
    required String path,
    String? mimeType,
  }) async {
    await _channel.invokeMethod('saveToGallery', {
      'path': path,
      'mimeType': mimeType,
    });
  }

  static Future<void> shareFile({
    required String path,
    String? mimeType,
  }) async {
    await _channel.invokeMethod('shareFile', {
      'path': path,
      'mimeType': mimeType,
    });
  }

  static Future<void> saveFile({
    required String path,
    String? mimeType,
    String? fileName,
  }) async {
    await _channel.invokeMethod('saveFile', {
      'path': path,
      'mimeType': mimeType,
      'fileName': fileName,
    });
  }

  static Future<TurnaDocumentScanResult?> scanDocument() async {
    final payload = await _channel.invokeMapMethod<String, dynamic>(
      'scanDocument',
    );
    if (payload == null) return null;
    return TurnaDocumentScanResult.fromMap(Map<String, dynamic>.from(payload));
  }

  static Future<TurnaProcessedVideoResult> processVideo({
    required String path,
    required ChatAttachmentTransferMode transferMode,
    String? fileName,
  }) async {
    final payload = await _channel.invokeMapMethod<String, dynamic>(
      'processVideo',
      {'path': path, 'transferMode': transferMode.name, 'fileName': fileName},
    );
    if (payload == null) {
      throw TurnaApiException('Video islenemedi.');
    }
    return TurnaProcessedVideoResult.fromMap(
      Map<String, dynamic>.from(payload),
    );
  }

  static Future<int> getPdfPageCount({required String path}) async {
    final count = await _channel.invokeMethod<int>('getPdfPageCount', {
      'path': path,
    });
    return count ?? 0;
  }

  static Future<Uint8List?> renderPdfPage({
    required String path,
    required int pageIndex,
    int targetWidth = 1440,
  }) async {
    final data = await _channel.invokeMethod<Uint8List>('renderPdfPage', {
      'path': path,
      'pageIndex': pageIndex,
      'targetWidth': targetWidth,
    });
    return data;
  }
}

class TurnaDocumentScanResult {
  const TurnaDocumentScanResult({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.pageCount,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int? pageCount;

  factory TurnaDocumentScanResult.fromMap(Map<String, dynamic> map) {
    return TurnaDocumentScanResult(
      path: (map['path'] ?? '').toString(),
      fileName: (map['fileName'] ?? '').toString(),
      mimeType: (map['mimeType'] ?? 'application/pdf').toString(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      pageCount: (map['pageCount'] as num?)?.toInt(),
    );
  }
}

class TurnaProcessedVideoResult {
  const TurnaProcessedVideoResult({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.durationSeconds,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationSeconds;

  factory TurnaProcessedVideoResult.fromMap(Map<String, dynamic> map) {
    return TurnaProcessedVideoResult(
      path: (map['path'] ?? '').toString(),
      fileName: (map['fileName'] ?? '').toString(),
      mimeType: (map['mimeType'] ?? 'video/mp4').toString(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
    );
  }
}

class TurnaLocalMediaCache {
  static const String _cacheDirName = 'turna-media-cache';
  static Directory? _cacheDir;
  static final Map<String, File> _resolvedFiles = {};
  static final Map<String, Future<File?>> _pendingFiles = {};
  static final Map<String, File> _preparedFiles = {};

  static File? peek(String cacheKey) {
    final file = _resolvedFiles[cacheKey];
    if (file == null) return null;
    if (!file.existsSync()) {
      _resolvedFiles.remove(cacheKey);
      return null;
    }
    return file;
  }

  static Future<File?> getOrDownloadFile({
    required String cacheKey,
    required String url,
    String? authToken,
  }) async {
    final cached = peek(cacheKey);
    if (cached != null) {
      return cached;
    }

    final pending = _pendingFiles[cacheKey];
    if (pending != null) {
      return pending;
    }

    final future = _resolveOrDownload(
      cacheKey: cacheKey,
      url: url,
      authToken: authToken,
    );
    _pendingFiles[cacheKey] = future;

    try {
      return await future;
    } finally {
      if (identical(_pendingFiles[cacheKey], future)) {
        _pendingFiles.remove(cacheKey);
      }
    }
  }

  static Future<void> remove(String cacheKey) async {
    _pendingFiles.remove(cacheKey);
    final file = _resolvedFiles.remove(cacheKey) ?? await _fileForKey(cacheKey);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final preparedKeys = _preparedFiles.keys
        .where((key) => key == cacheKey || key.startsWith('$cacheKey:'))
        .toList(growable: false);
    for (final key in preparedKeys) {
      final prepared = _preparedFiles.remove(key);
      if (prepared != null && await prepared.exists()) {
        try {
          await prepared.delete();
        } catch (_) {}
      }
    }
  }

  static Future<File> prepareMediaFile({
    required String cacheKey,
    required File sourceFile,
    String? mimeType,
    String? fileName,
  }) async {
    final preferredExtension = _preferredMediaExtension(
      mimeType: mimeType,
      fileName: fileName,
    );
    if (preferredExtension.isEmpty) {
      return sourceFile;
    }

    final currentExtension = sourceFile.path.split('.').last.toLowerCase();
    if (currentExtension == preferredExtension) {
      return sourceFile;
    }

    final preparedKey = '$cacheKey:$preferredExtension';
    final existing = _preparedFiles[preparedKey];
    if (existing != null && await existing.exists()) {
      final existingStat = await existing.stat();
      final sourceStat = await sourceFile.stat();
      if (existingStat.modified.isAfter(sourceStat.modified) ||
          existingStat.modified.isAtSameMomentAs(sourceStat.modified)) {
        return existing;
      }
    }

    final dir = await _ensureCacheDir();
    final target = File(
      '${dir.path}/${_hashKey(preparedKey)}.$preferredExtension',
    );
    try {
      if (await target.exists()) {
        await target.delete();
      }
    } catch (_) {}
    await sourceFile.copy(target.path);
    _preparedFiles[preparedKey] = target;
    return target;
  }

  static Future<File?> _resolveOrDownload({
    required String cacheKey,
    required String url,
    String? authToken,
  }) async {
    final normalizedUrl = normalizeTurnaRemoteUrl(url);
    try {
      final file = await _fileForKey(cacheKey);
      if (await file.exists()) {
        final length = await file.length();
        if (length > 0) {
          _resolvedFiles[cacheKey] = file;
          return file;
        }
        try {
          await file.delete();
        } catch (_) {}
      }

      Future<http.Response> request(String? token) {
        return http.get(
          Uri.parse(normalizedUrl),
          headers: buildTurnaAuthHeaders(token),
        );
      }

      var response = await request(authToken);
      if (response.statusCode >= 400 &&
          authToken != null &&
          authToken.trim().isNotEmpty) {
        response = await request(null);
      }

      if (response.statusCode >= 400) {
        turnaLog('media cache download failed', {
          'cacheKey': cacheKey,
          'statusCode': response.statusCode,
          'url': normalizedUrl,
        });
        return null;
      }

      if (response.bodyBytes.isEmpty) {
        turnaLog('media cache empty response', {
          'cacheKey': cacheKey,
          'url': normalizedUrl,
        });
        return null;
      }

      await file.writeAsBytes(response.bodyBytes, flush: true);
      _resolvedFiles[cacheKey] = file;
      return file;
    } catch (error) {
      turnaLog('media cache resolve failed', {
        'cacheKey': cacheKey,
        'url': normalizedUrl,
        'error': '$error',
      });
      return null;
    }
  }

  static Future<Directory> _ensureCacheDir() async {
    final existing = _cacheDir;
    if (existing != null) return existing;

    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory('${baseDir.path}/$_cacheDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  static Future<File> _fileForKey(String cacheKey) async {
    final dir = await _ensureCacheDir();
    return File('${dir.path}/${_hashKey(cacheKey)}.bin');
  }

  static String _hashKey(String value) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(value)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '${hash.toRadixString(16).padLeft(8, '0')}-${value.length}';
  }

  static String _preferredMediaExtension({String? mimeType, String? fileName}) {
    final lowerMime = (mimeType ?? '').toLowerCase();
    final lowerName = (fileName ?? '').toLowerCase();

    String? fromName() {
      if (!lowerName.contains('.')) return null;
      final ext = lowerName.split('.').last.trim();
      return ext.isEmpty ? null : ext;
    }

    final nameExt = fromName();
    if (nameExt != null && nameExt != 'bin') {
      return nameExt;
    }

    if (lowerMime.startsWith('video/')) {
      if (lowerMime.contains('quicktime')) return 'mov';
      if (lowerMime.contains('webm')) return 'webm';
      if (lowerMime.contains('x-matroska') || lowerMime.contains('mkv')) {
        return 'mkv';
      }
      return 'mp4';
    }

    if (lowerMime.startsWith('image/')) {
      if (lowerMime.contains('png')) return 'png';
      if (lowerMime.contains('webp')) return 'webp';
      if (lowerMime.contains('gif')) return 'gif';
      if (lowerMime.contains('heic') || lowerMime.contains('heif')) {
        return 'heic';
      }
      return 'jpg';
    }

    return '';
  }
}

class TurnaDeviceContext {
  static const MethodChannel _channel = MethodChannel('turna/device');
  static const String _deviceIdKey = 'turna_app_scoped_device_id';

  static Future<void>? _pendingLoad;
  static String? _deviceId;
  static String? _deviceModel;
  static String? _osVersion;
  static String? _appVersion;
  static String? _localeTag;
  static String? _regionCode;
  static String? _connectionType;
  static String? _countryIso;

  static Future<void> ensureLoaded({bool force = false}) async {
    if (!force && _deviceId != null) return;
    if (_pendingLoad != null) {
      await _pendingLoad;
      return;
    }

    final future = _load();
    _pendingLoad = future;
    try {
      await future;
    } finally {
      if (identical(_pendingLoad, future)) {
        _pendingLoad = null;
      }
    }
  }

  static Future<Map<String, String>> buildHeaders({
    String? authToken,
    bool includeJsonContentType = false,
  }) async {
    await ensureLoaded();

    final headers = <String, String>{};
    if (authToken != null && authToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    if (includeJsonContentType) {
      headers['Content-Type'] = 'application/json';
    }

    void putHeader(String key, String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return;
      headers[key] = text;
    }

    putHeader('x-turna-device-id', _deviceId);
    putHeader(
      'x-turna-platform',
      Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
          ? 'android'
          : Platform.operatingSystem,
    );
    putHeader('x-turna-device-model', _deviceModel);
    putHeader('x-turna-os-version', _osVersion);
    putHeader('x-turna-app-version', _appVersion);
    putHeader('x-turna-locale', _localeTag);
    putHeader('x-turna-region', _regionCode);
    putHeader('x-turna-connection-type', _connectionType);
    putHeader('x-turna-country-iso', _countryIso);

    return headers;
  }

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString(_deviceIdKey);
      if (deviceId == null || deviceId.trim().isEmpty) {
        deviceId = _generateDeviceId();
        await prefs.setString(_deviceIdKey, deviceId);
      }

      Map<String, dynamic> native = const <String, dynamic>{};
      try {
        final map = await _channel.invokeMapMethod<String, dynamic>(
          'getContextInfo',
        );
        native = map == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from(map);
      } catch (error) {
        turnaLog('device context native skipped', error);
      }

      List<ConnectivityResult> connectivityResults =
          const <ConnectivityResult>[];
      try {
        connectivityResults = await Connectivity().checkConnectivity();
      } catch (error) {
        turnaLog('connectivity load skipped', error);
      }

      final locale = ui.PlatformDispatcher.instance.locale;
      final localeTag =
          _readText(native['localeTag']) ?? locale.toLanguageTag();
      final regionCode =
          _normalizeCountryIso(_readText(native['regionCode'])) ??
          _normalizeCountryIso(_readText(native['localeCountryIso'])) ??
          _normalizeCountryIso(locale.countryCode);
      final countryIso =
          _normalizeCountryIso(_readText(native['simCountryIso'])) ??
          _normalizeCountryIso(_readText(native['networkCountryIso'])) ??
          regionCode;

      _deviceId = deviceId;
      _deviceModel = _readText(native['deviceModel']);
      _osVersion = _readText(native['osVersion']);
      _appVersion = _readText(native['appVersion']);
      _localeTag = localeTag;
      _regionCode = regionCode;
      _connectionType = _resolveConnectionType(connectivityResults);
      _countryIso = countryIso;
    } catch (error) {
      turnaLog('device context load failed', error);
    }
  }

  static String _generateDeviceId() {
    final random = math.Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  static String? _readText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static String? _normalizeCountryIso(String? value) {
    final text = value?.trim().toUpperCase();
    if (text == null || text.length != 2) return null;
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(text)) return null;
    return text;
  }

  static String _resolveConnectionType(List<ConnectivityResult> results) {
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      return 'none';
    }
    if (results.contains(ConnectivityResult.wifi)) return 'wifi';
    if (results.contains(ConnectivityResult.mobile)) return 'cellular';
    if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
    if (results.contains(ConnectivityResult.vpn)) return 'vpn';
    if (results.contains(ConnectivityResult.bluetooth)) return 'bluetooth';
    if (results.contains(ConnectivityResult.other)) return 'other';
    return results.map((item) => item.name).join(',');
  }
}

DateTime? parseTurnaLocalDateTime(String? raw) {
  final iso = raw?.trim();
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}

int compareTurnaTimestamps(String? left, String? right) {
  final leftDate = parseTurnaLocalDateTime(left);
  final rightDate = parseTurnaLocalDateTime(right);
  if (leftDate != null && rightDate != null) {
    return leftDate.compareTo(rightDate);
  }
  if (leftDate != null) return 1;
  if (rightDate != null) return -1;
  return (left ?? '').compareTo(right ?? '');
}

String formatTurnaLocalClock(String? raw) {
  final dt = parseTurnaLocalDateTime(raw);
  if (dt == null) return '';
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String formatTurnaDisplayPhone(String? raw) {
  final source = raw?.trim() ?? '';
  if (source.isEmpty || !source.startsWith('+')) return source;

  final digits = source.replaceAll(RegExp(r'\D+'), '');
  if (digits.length < 7) return source;

  if (digits.startsWith('90') && digits.length == 12) {
    final national = digits.substring(2);
    return '+90 ${national.substring(0, 3)} ${national.substring(3, 6)} ${national.substring(6, 8)} ${national.substring(8, 10)}';
  }

  if (digits.startsWith('44') && digits.length == 12) {
    final national = digits.substring(2);
    return '+44 ${national.substring(0, 4)} ${national.substring(4)}';
  }

  final countryLength = digits.length > 11 ? 3 : 2;
  final country = digits.substring(0, countryLength);
  final national = digits.substring(countryLength);
  final groups = <String>[];
  var cursor = 0;
  while (cursor < national.length) {
    final remaining = national.length - cursor;
    final take = remaining > 4
        ? 3
        : remaining > 2
        ? 2
        : remaining;
    groups.add(national.substring(cursor, cursor + take));
    cursor += take;
  }
  return '+$country ${groups.join(' ')}'.trim();
}

class TurnaContactsDirectory {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final List<String> _knownDialCodes =
      _kTurnaCountries
          .map((item) => item.dialCode.replaceAll(RegExp(r'\D+'), ''))
          .toSet()
          .toList()
        ..sort((left, right) => right.length.compareTo(left.length));

  static Future<void>? _pendingLoad;
  static Map<String, String> _labelsByPhoneKey = <String, String>{};
  static List<TurnaContactSyncEntry> _syncEntries =
      const <TurnaContactSyncEntry>[];
  static bool _permissionGranted = false;

  static bool get permissionGranted => _permissionGranted;

  static List<TurnaContactSyncEntry> snapshotForSync() {
    return List<TurnaContactSyncEntry>.unmodifiable(_syncEntries);
  }

  static Future<void> ensureLoaded({bool force = false}) async {
    if (!force && _permissionGranted) return;
    if (_pendingLoad != null) {
      await _pendingLoad;
      return;
    }

    final future = _loadContacts();
    _pendingLoad = future;
    try {
      await future;
    } finally {
      if (identical(_pendingLoad, future)) {
        _pendingLoad = null;
      }
    }
  }

  static String resolveDisplayLabel({
    String? phone,
    required String fallbackName,
  }) {
    final label = lookupLabel(phone);
    if (label == null || label.trim().isEmpty) return fallbackName;
    return label;
  }

  static String? lookupLabel(String? phone) {
    for (final key in _phoneLookupKeys(
      phone,
      defaultCountryIso: TurnaDeviceContext._countryIso,
    )) {
      final label = _labelsByPhoneKey[key];
      if (label != null && label.trim().isNotEmpty) {
        return label;
      }
    }
    return null;
  }

  static Future<void> _loadContacts() async {
    try {
      await TurnaDeviceContext.ensureLoaded();
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        _permissionGranted = false;
        return;
      }

      final defaultCountryIso = TurnaDeviceContext._countryIso;
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      final next = <String, String>{};
      final syncEntries = <TurnaContactSyncEntry>[];
      for (final contact in contacts) {
        final displayName = contact.displayName.trim();
        if (displayName.isEmpty) continue;
        final phones = <String>[];
        final canonicalPhones = <String>{};
        for (final phone in contact.phones) {
          final canonicalPhone = _canonicalPhoneLookupKey(
            phone.number,
            defaultCountryIso: defaultCountryIso,
          );
          if (canonicalPhone != null && canonicalPhones.add(canonicalPhone)) {
            phones.add(canonicalPhone);
          }
          for (final key in _phoneLookupKeys(
            phone.number,
            defaultCountryIso: defaultCountryIso,
          )) {
            next.putIfAbsent(key, () => displayName);
          }
        }
        if (phones.isNotEmpty) {
          syncEntries.add(
            TurnaContactSyncEntry(displayName: displayName, phones: phones),
          );
        }
      }

      final changed =
          next.length != _labelsByPhoneKey.length ||
          next.entries.any(
            (entry) => _labelsByPhoneKey[entry.key] != entry.value,
          ) ||
          syncEntries.length != _syncEntries.length ||
          !_permissionGranted;
      _permissionGranted = true;
      _labelsByPhoneKey = next;
      _syncEntries = syncEntries;
      if (changed) {
        revision.value++;
      }
    } catch (error) {
      turnaLog('contacts load failed', error);
    }
  }

  static String? _countryDialCodeDigits(String? countryIso) {
    final normalized = countryIso?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) return null;

    for (final country in _kTurnaCountries) {
      if (country.iso == normalized) {
        return country.dialCode.replaceAll(RegExp(r'\D+'), '');
      }
    }

    return null;
  }

  static String? _detectInternationalDialCode(String digits) {
    for (final dialCode in _knownDialCodes) {
      if (!digits.startsWith(dialCode)) continue;
      final national = digits.substring(dialCode.length);
      if (national.length >= 4) {
        return dialCode;
      }
    }

    return null;
  }

  static String? _canonicalPhoneLookupKey(
    String? raw, {
    String? defaultCountryIso,
  }) {
    final source = raw?.trim() ?? '';
    if (source.isEmpty) return null;

    final digits = source.replaceAll(RegExp(r'\D+'), '');
    if (digits.length < 7) return null;

    if (source.startsWith('+')) {
      return digits;
    }

    if (digits.startsWith('00') && digits.length > 2) {
      return digits.substring(2);
    }

    if (digits.length > 10) {
      final detectedDialCode = _detectInternationalDialCode(digits);
      if (detectedDialCode != null) {
        return digits;
      }
    }

    final defaultDialCode = _countryDialCodeDigits(defaultCountryIso);
    if (defaultDialCode == null || defaultDialCode.isEmpty) {
      return digits;
    }

    final nationalDigits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.startsWith('0')) {
      return nationalDigits.length >= 4
          ? '$defaultDialCode$nationalDigits'
          : null;
    }

    if (digits.length <= 10) {
      return nationalDigits.length >= 4
          ? '$defaultDialCode$nationalDigits'
          : null;
    }

    return digits;
  }

  static List<String> _phoneLookupKeys(
    String? raw, {
    String? defaultCountryIso,
  }) {
    final source = raw?.trim() ?? '';
    if (source.isEmpty) return const <String>[];

    final digits = source.replaceAll(RegExp(r'\D+'), '');
    if (digits.length < 7) return const <String>[];

    final keys = <String>[];
    void addKey(String value) {
      final normalized = value.trim();
      if (normalized.length < 7 || keys.contains(normalized)) return;
      keys.add(normalized);
    }

    final canonical = _canonicalPhoneLookupKey(
      raw,
      defaultCountryIso: defaultCountryIso,
    );
    if (canonical != null) {
      addKey(canonical);
    }
    addKey(digits);

    final internationalDigits = canonical ?? digits;
    final dialCode =
        _detectInternationalDialCode(internationalDigits) ??
        _countryDialCodeDigits(defaultCountryIso);
    if (dialCode != null && internationalDigits.startsWith(dialCode)) {
      final nationalDigits = internationalDigits
          .substring(dialCode.length)
          .replaceFirst(RegExp(r'^0+'), '');
      if (nationalDigits.length >= 4) {
        addKey(nationalDigits);
        addKey('0$nationalDigits');
      }
    }

    return keys;
  }
}

class TurnaContactSyncEntry {
  const TurnaContactSyncEntry({
    required this.displayName,
    required this.phones,
  });

  final String displayName;
  final List<String> phones;

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'phones': phones,
  };
}

Widget buildTurnaSessionExpiredRedirect(VoidCallback onSessionExpired) {
  WidgetsBinding.instance.addPostFrameCallback((_) => onSessionExpired());
  return const Center(child: CircularProgressIndicator());
}

class TurnaDisplayWakeLock {
  static const MethodChannel _channel = MethodChannel('turna/display');
  static final Set<String> _holders = <String>{};

  static Future<void> acquire(String reason) async {
    final wasEmpty = _holders.isEmpty;
    _holders.add(reason);
    if (!wasEmpty) return;
    await _setEnabled(true);
  }

  static Future<void> release(String reason) async {
    final removed = _holders.remove(reason);
    if (!removed || _holders.isNotEmpty) return;
    await _setEnabled(false);
  }

  static Future<void> _setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setKeepScreenOn', {'enabled': enabled});
    } catch (error) {
      turnaLog('display wake lock update skipped', error);
    }
  }
}

class TurnaProximityScreenLock {
  static const MethodChannel _channel = MethodChannel('turna/display');
  static final Set<String> _holders = <String>{};

  static Future<void> acquire(String reason) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final wasEmpty = _holders.isEmpty;
    _holders.add(reason);
    if (!wasEmpty) return;
    await _setEnabled(true);
  }

  static Future<void> release(String reason) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final removed = _holders.remove(reason);
    if (!removed || _holders.isNotEmpty) return;
    await _setEnabled(false);
  }

  static Future<void> _setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setProximityScreenLockEnabled', {
        'enabled': enabled,
      });
    } catch (error) {
      turnaLog('proximity screen lock update skipped', error);
    }
  }
}

class TurnaAppBadge {
  static const MethodChannel _channel = MethodChannel('turna/display');

  static Future<void> setCount(int count) async {
    final normalized = math.max(0, count);
    try {
      await _channel.invokeMethod('setAppBadgeCount', {'count': normalized});
    } catch (error) {
      turnaLog('app badge update skipped', error);
    }
  }
}

String? guessContentTypeForFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.m4v')) return 'video/x-m4v';
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.aac')) return 'audio/aac';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  if (lower.endsWith('.opus')) return 'audio/opus';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.txt')) return 'text/plain';
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.zip')) return 'application/zip';
  return 'application/octet-stream';
}

bool _isAudioAttachment(ChatAttachment attachment) {
  final contentType = attachment.contentType.toLowerCase();
  if (contentType.startsWith('audio/')) return true;
  final fileName = (attachment.fileName ?? '').toLowerCase();
  return fileName.endsWith('.m4a') ||
      fileName.endsWith('.aac') ||
      fileName.endsWith('.mp3') ||
      fileName.endsWith('.wav') ||
      fileName.endsWith('.ogg') ||
      fileName.endsWith('.opus');
}

String _attachmentFileExtension(ChatAttachment attachment) {
  final fileName = (attachment.fileName ?? '').trim();
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex >= 0 && dotIndex < fileName.length - 1) {
    return fileName.substring(dotIndex + 1).toLowerCase();
  }
  final contentType = attachment.contentType.toLowerCase().trim();
  if (contentType.contains('/')) {
    return contentType.split('/').last.toLowerCase();
  }
  return '';
}

bool _attachmentHasImageContent(ChatAttachment attachment) {
  if (attachment.kind == ChatAttachmentKind.image) return true;
  final contentType = attachment.contentType.toLowerCase();
  if (contentType.startsWith('image/')) return true;
  final extension = _attachmentFileExtension(attachment);
  return extension == 'jpg' ||
      extension == 'jpeg' ||
      extension == 'png' ||
      extension == 'webp' ||
      extension == 'gif' ||
      extension == 'heic' ||
      extension == 'heif';
}

bool _attachmentHasVideoContent(ChatAttachment attachment) {
  if (attachment.kind == ChatAttachmentKind.video) return true;
  final contentType = attachment.contentType.toLowerCase();
  if (contentType.startsWith('video/')) return true;
  final extension = _attachmentFileExtension(attachment);
  return extension == 'mp4' ||
      extension == 'mov' ||
      extension == 'm4v' ||
      extension == 'webm' ||
      extension == 'mkv' ||
      extension == 'avi';
}

bool _attachmentHasPdfContent(ChatAttachment attachment) {
  final contentType = attachment.contentType.toLowerCase();
  if (contentType == 'application/pdf') return true;
  return _attachmentFileExtension(attachment) == 'pdf';
}

bool _isImageAttachment(ChatAttachment attachment) {
  if (attachment.kind == ChatAttachmentKind.file) return false;
  return _attachmentHasImageContent(attachment);
}

bool _isVideoAttachment(ChatAttachment attachment) {
  if (attachment.kind == ChatAttachmentKind.file) return false;
  return _attachmentHasVideoContent(attachment);
}

String formatBytesLabel(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final display = value >= 10 || unitIndex == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$display ${units[unitIndex]}';
}

String replaceFileExtension(String fileName, String extension) {
  final dotIndex = fileName.lastIndexOf('.');
  final base = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
  return '$base.$extension';
}

Color composerColorForValue(double value) {
  final clamped = value.clamp(0.0, 1.0).toDouble();
  if (kComposerPaletteStops.length == 1) return kComposerPaletteStops.first;
  final scaled = clamped * (kComposerPaletteStops.length - 1);
  final lowerIndex = scaled.floor();
  final upperIndex = math.min(lowerIndex + 1, kComposerPaletteStops.length - 1);
  final t = scaled - lowerIndex;
  return Color.lerp(
        kComposerPaletteStops[lowerIndex],
        kComposerPaletteStops[upperIndex],
        t,
      ) ??
      kComposerPaletteStops[lowerIndex];
}

class TurnaActiveChatRegistry extends ChangeNotifier {
  ChatPreview? _currentChat;

  ChatPreview? get currentChat => _currentChat;

  bool isChatActive(String chatId) => _currentChat?.chatId == chatId;

  void setCurrent(ChatPreview chat) {
    if (_currentChat?.chatId == chat.chatId) return;
    _currentChat = chat;
    notifyListeners();
  }

  void clearCurrent(String chatId) {
    if (_currentChat?.chatId != chatId) return;
    _currentChat = null;
    notifyListeners();
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await TurnaFirebase.ensureInitialized();
  await TurnaNativeCallManager.handleBackgroundRemoteMessage(message.data);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TurnaAppConfig.load();
  await TurnaFirebase.ensureInitialized();
  await TurnaDeviceContext.ensureLoaded();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const TurnaApp());
}

class TurnaApp extends StatefulWidget {
  const TurnaApp({super.key});

  @override
  State<TurnaApp> createState() => _TurnaAppState();
}

class _TurnaAppState extends State<TurnaApp> with WidgetsBindingObserver {
  AuthSession? _session;
  bool _bootstrapping = true;
  bool _requestedContactsOnLaunch = false;
  static const Duration _minimumSplashDuration = Duration(milliseconds: 750);
  static const Duration _maximumBootstrapWait = Duration(seconds: 6);

  void _updateSession(AuthSession? session) {
    setState(() => _session = session);
    unawaited(TurnaLiveLocationManager.instance.bindSession(session));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    kTurnaLifecycleState.value = state;
    turnaLog('app lifecycle', state.name);
  }

  Future<void> _bootstrap() async {
    final startedAt = DateTime.now();
    final sessionFuture = _loadStoredSession();
    AuthSession? session;
    var timedOut = false;

    try {
      session = await sessionFuture.timeout(_maximumBootstrapWait);
    } catch (error) {
      if (error is TimeoutException) {
        timedOut = true;
        turnaLog('auth session load timeout', {
          'timeoutMs': _maximumBootstrapWait.inMilliseconds,
        });
      } else {
        turnaLog('auth session load skipped', error);
      }
    }

    final elapsed = DateTime.now().difference(startedAt);
    final remaining = _minimumSplashDuration - elapsed;
    if (!remaining.isNegative) {
      await Future<void>.delayed(remaining);
    }

    if (mounted) {
      setState(() {
        _session = session;
        _bootstrapping = false;
      });
      unawaited(TurnaLiveLocationManager.instance.bindSession(session));
      _requestContactsOnLaunch();
      turnaLog('app init', {
        'hasSession': _session != null,
        'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
        'timedOut': timedOut,
      });
    }

    if (session == null) {
      unawaited(TurnaAppBadge.setCount(0));
    }

    if (timedOut) {
      unawaited(
        sessionFuture
            .then((lateSession) {
              if (!mounted || lateSession == null) return;
              if (_session?.userId == lateSession.userId &&
                  _session?.token == lateSession.token) {
                return;
              }
              _updateSession(lateSession);
              turnaLog('auth session restored after timeout', {
                'hasSession': true,
              });
            })
            .catchError((Object error) {
              turnaLog('late auth session load skipped', error);
            }),
      );
    }

    unawaited(_initializeServices());
  }

  Future<AuthSession?> _loadStoredSession() async {
    return AuthSession.load();
  }

  Future<void> _initializeServices() async {
    try {
      await TurnaFirebase.ensureInitialized();
    } catch (error) {
      turnaLog('firebase boot init skipped', error);
    }

    try {
      await TurnaNativeCallManager.initialize();
    } catch (error) {
      turnaLog('native call init skipped', error);
    }

    try {
      await TurnaShareTargetBridge.initialize();
    } catch (error) {
      turnaLog('share target bridge init skipped', error);
    }
  }

  void _requestContactsOnLaunch() {
    if (_requestedContactsOnLaunch) {
      return;
    }
    _requestedContactsOnLaunch = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(TurnaContactsDirectory.ensureLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: TurnaColors.backgroundSoft,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TurnaColors.primary,
        primary: TurnaColors.primary,
        surface: TurnaColors.surface,
        onSurface: TurnaColors.text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TurnaColors.background,
        foregroundColor: TurnaColors.text,
        centerTitle: false,
      ),
      dividerColor: TurnaColors.divider,
    );

    return MaterialApp(
      title: 'Turna',
      debugShowCheckedModeBanner: false,
      navigatorKey: kTurnaNavigatorKey,
      navigatorObservers: [kTurnaRouteObserver],
      theme: theme,
      home: _bootstrapping
          ? const _TurnaLaunchPage()
          : _session == null
          ? TurnaPhoneAuthPage(onAuthenticated: _updateSession)
          : _session!.needsOnboarding
          ? TurnaProfileOnboardingPage(
              session: _session!,
              onCompleted: (session) {
                _updateSession(session);
              },
            )
          : TurnaShellHost(
              session: _session!,
              onSessionUpdated: (session) {
                _updateSession(session);
              },
              onLogout: () async {
                final activeSession = _session;
                if (activeSession != null) {
                  try {
                    await AuthApi.logout(activeSession);
                  } catch (_) {}
                }
                await AuthSession.clear();
                await TurnaAppBadge.setCount(0);
                _updateSession(null);
              },
            ),
    );
  }
}

class _TurnaLaunchPage extends StatelessWidget {
  const _TurnaLaunchPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14305788),
                      blurRadius: 30,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'ios/Runner/Assets.xcassets/AppIcon.appiconset/180x180.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Turnalar selam goturur.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: TurnaColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 18),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.onAuthenticated});

  final void Function(AuthSession session) onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _isRegisterMode = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty) {
      setState(() => _error = 'Username gir.');
      return;
    }
    if (password.length < 4) {
      setState(() => _error = 'Şifre en az 4 karakter olmalı.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final endpoint = _isRegisterMode ? 'register' : 'login';
      turnaLog('auth submit', {'mode': endpoint, 'username': username});
      final payload = <String, dynamic>{
        'username': username,
        'password': password,
      };

      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/auth/$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 400) {
        turnaLog('auth failed', {
          'statusCode': res.statusCode,
          'body': res.body,
        });
        final body = jsonDecode(res.body);
        setState(
          () => _error = 'İşlem başarısız: ${body['error'] ?? res.statusCode}',
        );
        return;
      }
      turnaLog('auth success', {'statusCode': res.statusCode});

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final token = map['accessToken']?.toString();
      final user = map['user'] as Map<String, dynamic>?;
      final userId = user?['id']?.toString();
      final displayName = user?['displayName']?.toString() ?? username;
      final avatarUrl = user?['avatarUrl']?.toString();
      if (token == null || userId == null) {
        setState(() => _error = 'Sunucu yanıtı geçersiz.');
        return;
      }

      final session = AuthSession(
        token: token,
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
      await session.save();
      widget.onAuthenticated(session);
    } catch (_) {
      turnaLog('auth exception');
      setState(() => _error = 'Sunucuya bağlanılamadı.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turna Giriş')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _isRegisterMode
                ? 'Username ve şifre ile kayıt ol.'
                : 'Username ve şifre ile giriş yap.',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Şifre',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Text(
              _loading
                  ? 'Bekleyin...'
                  : (_isRegisterMode ? 'Kayıt Ol' : 'Giriş Yap'),
            ),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _error = null;
                      _isRegisterMode = !_isRegisterMode;
                    });
                  },
            child: Text(
              _isRegisterMode
                  ? 'Hesabım var, giriş yap'
                  : 'Hesabım yok, kayıt ol',
            ),
          ),
        ],
      ),
    );
  }
}
