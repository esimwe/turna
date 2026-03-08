import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';

const String kBackendBaseUrl = 'http://178.104.8.155:4000';
const bool kTurnaDebugLogs = true;
const String kChatRoomRouteName = 'chat-room';
const int kComposerMediaLimit = 30;
const int kInlineAttachmentSoftLimitBytes = 64 * 1024 * 1024;
const int kInlineImagePickerQuality = 82;
const double kInlineImagePickerMaxDimension = 2200;
const double kInlineImageSdMaxDimension = 1280;
const double kInlineImageHdMaxDimension = 2048;
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
final TurnaActiveChatRegistry kTurnaActiveChatRegistry =
    TurnaActiveChatRegistry();
final TurnaCallUiController kTurnaCallUiController = TurnaCallUiController();

class TurnaColors {
  static const primary50 = Color(0xFFEEF7FF);
  static const primary100 = Color(0xFFD9EEFF);
  static const primary200 = Color(0xFFBCE0FF);
  static const primary400 = Color(0xFF5BB0FF);
  static const primary = Color(0xFF2F80ED);
  static const primaryStrong = Color(0xFF1F6FEB);
  static const primaryDeep = Color(0xFF1B4ED8);
  static const accent = Color(0xFF38BDF8);
  static const accentStrong = Color(0xFF00C2FF);

  static const background = Color(0xFFFFFFFF);
  static const backgroundSoft = Color(0xFFF7F9FC);
  static const backgroundMuted = Color(0xFFEEF4FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHover = Color(0xFFF3F8FF);
  static const border = Color(0xFFD8E6F5);
  static const divider = Color(0xFFE6EEF8);

  static const text = Color(0xFF0F172A);
  static const textSoft = Color(0xFF334155);
  static const textMuted = Color(0xFF64748B);

  static const chatOutgoing = Color(0xFF2F80ED);
  static const chatOutgoingText = Color(0xFFFFFFFF);
  static const chatIncoming = Color(0xFFE9F2FF);
  static const chatIncomingText = Color(0xFF0F172A);

  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const info = Color(0xFF38BDF8);
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
    this.deletedForEveryone = false,
  });

  final String text;
  final TurnaReplyPayload? reply;
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

  final match = _kTurnaReplyMarkerPattern.firstMatch(raw);
  if (match == null) {
    return ParsedTurnaMessageText(text: raw);
  }

  try {
    final encoded = match.group(1)!;
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    final payload = TurnaReplyPayload.fromMap(
      jsonDecode(decoded) as Map<String, dynamic>,
    );
    final cleaned = raw.substring(match.end);
    return ParsedTurnaMessageText(text: cleaned, reply: payload);
  } catch (_) {
    return ParsedTurnaMessageText(text: raw);
  }
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

String sanitizeTurnaChatPreviewText(String raw) {
  final parsed = parseTurnaMessageText(raw);
  if (parsed.deletedForEveryone) return parsed.text;
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
  await TurnaFirebase.ensureInitialized();
  await TurnaNativeCallManager.initialize();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final session = await AuthSession.load();
  runApp(TurnaApp(initialSession: session));
}

class TurnaApp extends StatefulWidget {
  const TurnaApp({super.key, required this.initialSession});

  final AuthSession? initialSession;

  @override
  State<TurnaApp> createState() => _TurnaAppState();
}

class _TurnaAppState extends State<TurnaApp> with WidgetsBindingObserver {
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.initialSession;
    turnaLog('app init', {'hasSession': _session != null});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    turnaLog('app lifecycle', state.name);
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
      home: _session == null
          ? AuthPage(
              onAuthenticated: (session) => setState(() => _session = session),
            )
          : MainTabs(
              session: _session!,
              onSessionUpdated: (session) {
                setState(() => _session = session);
              },
              onLogout: () async {
                await AuthSession.clear();
                setState(() => _session = null);
              },
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
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _isRegisterMode = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final phone = _phoneController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty && phone.isEmpty) {
      setState(() => _error = 'Username veya telefon gir.');
      return;
    }
    if (_isRegisterMode && name.length < 2) {
      setState(() => _error = 'Kayıt için ad soyad gir.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final endpoint = _isRegisterMode ? 'register' : 'login';
      turnaLog('auth submit', {
        'mode': endpoint,
        'username': username,
        'hasPhone': phone.isNotEmpty,
      });
      final payload = <String, dynamic>{
        if (username.isNotEmpty) 'username': username,
        if (phone.isNotEmpty) 'phone': phone,
        if (password.isNotEmpty) 'password': password,
        if (_isRegisterMode) 'displayName': name,
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
                ? 'Username/telefon ile kayıt ol.'
                : 'Username/telefon ile giriş yap.',
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
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Telefon (opsiyonel)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Ad Soyad (kayıtta zorunlu)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Şifre (opsiyonel)',
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

class MainTabs extends StatefulWidget {
  const MainTabs({
    super.key,
    required this.session,
    required this.onSessionUpdated,
    required this.onLogout,
  });

  final AuthSession session;
  final void Function(AuthSession session) onSessionUpdated;
  final VoidCallback onLogout;

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> with WidgetsBindingObserver {
  int _index = 0;
  int _totalUnreadChats = 0;
  late final PresenceSocketClient _presenceClient;
  final _inboxUpdateNotifier = ValueNotifier<int>(0);
  final _callCoordinator = TurnaCallCoordinator();
  String? _activeIncomingCallId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TurnaPushManager.syncSession(widget.session);
    TurnaNativeCallManager.bindSession(
      session: widget.session,
      coordinator: _callCoordinator,
      onSessionExpired: widget.onLogout,
    );
    TurnaAnalytics.logEvent('app_session_started', {
      'user_id': widget.session.userId,
    });
    _presenceClient = PresenceSocketClient(
      token: widget.session.token,
      onInboxUpdate: () {
        _inboxUpdateNotifier.value++;
      },
      onIncomingCall: _callCoordinator.handleIncoming,
      onCallAccepted: _callCoordinator.handleAccepted,
      onCallDeclined: _callCoordinator.handleDeclined,
      onCallMissed: _callCoordinator.handleMissed,
      onCallEnded: _callCoordinator.handleEnded,
    )..connect();
    _callCoordinator.addListener(_handleCallCoordinator);
  }

  @override
  void didUpdateWidget(covariant MainTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.session.userId != widget.session.userId) {
      TurnaPushManager.syncSession(widget.session);
      TurnaNativeCallManager.bindSession(
        session: widget.session,
        coordinator: _callCoordinator,
        onSessionExpired: widget.onLogout,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callCoordinator.removeListener(_handleCallCoordinator);
    _presenceClient.dispose();
    TurnaNativeCallManager.unbindSession(widget.session.userId);
    _callCoordinator.dispose();
    _inboxUpdateNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _presenceClient.refreshConnection();
      TurnaNativeCallManager.handleAppResumed();
      _inboxUpdateNotifier.value++;
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _presenceClient.disconnectForBackground();
    }
  }

  void _handleCallCoordinator() {
    final incoming = _callCoordinator.takeIncomingCall();
    if (incoming == null) return;
    if (_activeIncomingCallId == incoming.call.id) return;

    _activeIncomingCallId = incoming.call.id;
    final returnChat = buildDirectChatPreviewForCall(
      widget.session,
      incoming.call,
    );
    final shouldOpenChatOnExit = !kTurnaActiveChatRegistry.isChatActive(
      returnChat.chatId,
    );
    Future<void>(() async {
      final navigator = kTurnaNavigatorKey.currentState;
      if (!mounted || navigator == null) return;
      try {
        await navigator.push(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'incoming-call'),
            builder: (_) => IncomingCallPage(
              session: widget.session,
              coordinator: _callCoordinator,
              incoming: incoming,
              onSessionExpired: widget.onLogout,
              returnChatOnExit: shouldOpenChatOnExit ? returnChat : null,
            ),
          ),
        );
      } finally {
        if (mounted) {
          _activeIncomingCallId = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const PlaceholderPage(title: 'Durum'),
      CallsPage(
        session: widget.session,
        callCoordinator: _callCoordinator,
        onSessionExpired: widget.onLogout,
      ),
      const PlaceholderPage(title: 'Araclar'),
      ChatsPage(
        session: widget.session,
        inboxUpdateNotifier: _inboxUpdateNotifier,
        callCoordinator: _callCoordinator,
        onSessionExpired: widget.onLogout,
        onUnreadChanged: (count) {
          if (_totalUnreadChats == count || !mounted) return;
          setState(() => _totalUnreadChats = count);
        },
      ),
      SettingsPage(
        session: widget.session,
        onSessionUpdated: widget.onSessionUpdated,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: _TurnaBottomBar(
        selectedIndex: _index,
        unreadChats: _totalUnreadChats,
        session: widget.session,
        onSelect: (index) => setState(() => _index = index),
      ),
    );
  }
}

class ChatsPage extends StatefulWidget {
  const ChatsPage({
    super.key,
    required this.session,
    required this.onSessionExpired,
    required this.callCoordinator,
    this.inboxUpdateNotifier,
    this.onUnreadChanged,
  });

  final AuthSession session;
  final VoidCallback onSessionExpired;
  final TurnaCallCoordinator callCoordinator;
  final ValueNotifier<int>? inboxUpdateNotifier;
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  int _refreshTick = 0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.inboxUpdateNotifier?.addListener(_onInboxUpdate);
    _searchController.addListener(_onSearchChanged);
  }

  void _onInboxUpdate() {
    if (!mounted) return;
    setState(() => _refreshTick++);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    widget.inboxUpdateNotifier?.removeListener(_onInboxUpdate);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Turna',
          style: TextStyle(
            color: TurnaColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: const [
          Icon(Icons.qr_code_scanner_outlined),
          SizedBox(width: 12),
          Icon(Icons.camera_alt_outlined),
          SizedBox(width: 12),
          Icon(Icons.more_vert),
          SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<ChatPreview>>(
        future: ChatApi.fetchChats(widget.session, refreshTick: _refreshTick),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            final isAuthError = error is TurnaUnauthorizedException;
            return _CenteredState(
              icon: isAuthError ? Icons.lock_outline : Icons.cloud_off_outlined,
              title: isAuthError
                  ? 'Oturumun suresi doldu'
                  : 'Sohbetler yuklenemedi',
              message: error.toString(),
              primaryLabel: isAuthError ? 'Yeniden giris yap' : 'Tekrar dene',
              onPrimary: isAuthError
                  ? widget.onSessionExpired
                  : () => setState(() => _refreshTick++),
            );
          }

          final chats = snapshot.data ?? [];
          final unreadTotal = chats.fold<int>(
            0,
            (sum, chat) => sum + chat.unreadCount,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onUnreadChanged?.call(unreadTotal);
          });
          final query = _searchController.text.trim().toLowerCase();
          final filteredChats = chats.where((chat) {
            if (query.isEmpty) return true;
            return chat.name.toLowerCase().contains(query) ||
                chat.message.toLowerCase().contains(query);
          }).toList();

          return RefreshIndicator(
            onRefresh: () async => setState(() => _refreshTick++),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filteredChats.isEmpty ? 2 : filteredChats.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Sohbetlerde ara',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () => _searchController.clear(),
                                icon: const Icon(Icons.close),
                              ),
                        filled: true,
                        fillColor: TurnaColors.backgroundMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  );
                }

                if (filteredChats.isEmpty) {
                  if (chats.isEmpty) {
                    return const _CenteredListState(
                      icon: Icons.chat_bubble_outline,
                      title: 'Henuz sohbet yok',
                      message:
                          'Ilk konusmayi baslatmak icin sag alttaki butondan kisi sec.',
                    );
                  }
                  return _CenteredListState(
                    icon: Icons.search_off,
                    title: 'Sonuc bulunamadi',
                    message:
                        '"${_searchController.text.trim()}" icin eslesen sohbet yok.',
                  );
                }

                final chat = filteredChats[index - 1];
                return ListTile(
                  leading: _ProfileAvatar(
                    label: chat.name,
                    avatarUrl: chat.avatarUrl,
                    authToken: widget.session.token,
                    radius: 22,
                  ),
                  title: Text(
                    chat.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    chat.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        chat.time,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777C79),
                        ),
                      ),
                      if (chat.unreadCount > 0) ...[
                        const SizedBox(height: 6),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: const BoxDecoration(
                            color: TurnaColors.primary,
                            borderRadius: BorderRadius.all(
                              Radius.circular(999),
                            ),
                          ),
                          child: Text(
                            chat.unreadCount > 99
                                ? '99+'
                                : '${chat.unreadCount}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      buildChatRoomRoute(
                        chat: chat,
                        session: widget.session,
                        callCoordinator: widget.callCoordinator,
                        onSessionExpired: widget.onSessionExpired,
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: TurnaColors.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => NewChatPage(
                session: widget.session,
                callCoordinator: widget.callCoordinator,
                onSessionExpired: widget.onSessionExpired,
              ),
            ),
          );
          if (created == true && mounted) {
            setState(() => _refreshTick++);
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.chat,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final ChatPreview chat;
  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

PageRoute<void> buildChatRoomRoute({
  required ChatPreview chat,
  required AuthSession session,
  required TurnaCallCoordinator callCoordinator,
  required VoidCallback onSessionExpired,
}) {
  return MaterialPageRoute(
    settings: RouteSettings(
      name: kChatRoomRouteName,
      arguments: {'chatId': chat.chatId},
    ),
    builder: (_) => ChatRoomPage(
      chat: chat,
      session: session,
      callCoordinator: callCoordinator,
      onSessionExpired: onSessionExpired,
    ),
  );
}

ChatPreview buildDirectChatPreviewForCall(
  AuthSession session,
  TurnaCallSummary call,
) {
  return ChatPreview(
    chatId: ChatApi.buildDirectChatId(session.userId, call.peer.id),
    name: call.peer.displayName,
    message: '',
    time: '',
    avatarUrl: call.peer.avatarUrl,
  );
}

class _ChatTimelineEntry {
  const _ChatTimelineEntry._({
    required this.id,
    required this.createdAt,
    this.message,
    this.call,
  });

  factory _ChatTimelineEntry.message(ChatMessage message) {
    return _ChatTimelineEntry._(
      id: 'message:${message.id}',
      createdAt: message.createdAt,
      message: message,
    );
  }

  factory _ChatTimelineEntry.call(TurnaCallHistoryItem call) {
    return _ChatTimelineEntry._(
      id: 'call:${call.id}',
      createdAt: call.createdAt ?? '',
      call: call,
    );
  }

  final String id;
  final String createdAt;
  final ChatMessage? message;
  final TurnaCallHistoryItem? call;

  bool get isMessage => message != null;
}

class _ChatRoomPageState extends State<ChatRoomPage>
    with WidgetsBindingObserver, RouteAware {
  late final TurnaSocketClient _client;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _mediaPicker = ImagePicker();
  final FocusNode _composerFocusNode = FocusNode();
  bool _showScrollToBottom = false;
  bool _attachmentBusy = false;
  bool _hasComposerText = false;
  bool _loadingPeerCalls = false;
  TurnaReplyPayload? _replyDraft;
  _PinnedMessageDraft? _pinnedMessage;
  List<TurnaCallHistoryItem> _peerCalls = const [];
  Set<String> _starredMessageIds = <String>{};
  Set<String> _softDeletedMessageIds = <String>{};
  Set<String> _deletedMessageIds = <String>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  int _lastRenderedTimelineCount = 0;
  Timer? _messageHighlightTimer;
  String? _highlightedMessageId;
  PageRoute<dynamic>? _route;

  String? get _peerUserId =>
      ChatApi.extractPeerUserId(widget.chat.chatId, widget.session.userId);

  String get _pinnedMessageKey => 'turna_pinned_message_${widget.chat.chatId}';
  String get _starredMessagesKey =>
      'turna_starred_messages_${widget.chat.chatId}';
  String get _softDeletedMessagesKey =>
      'turna_soft_deleted_messages_${widget.chat.chatId}';
  String get _deletedMessagesKey =>
      'turna_deleted_messages_${widget.chat.chatId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    turnaLog('chat room init', {
      'chatId': widget.chat.chatId,
      'senderId': widget.session.userId,
    });
    TurnaAnalytics.logEvent('chat_opened', {'chat_id': widget.chat.chatId});
    _client = TurnaSocketClient(
      chatId: widget.chat.chatId,
      senderId: widget.session.userId,
      peerUserId: _peerUserId,
      token: widget.session.token,
      onSessionExpired: widget.onSessionExpired,
    )..connect();
    _client.addListener(_refresh);
    widget.callCoordinator.addListener(_handleCallCoordinatorChanged);
    _controller.addListener(_handleComposerChanged);
    _composerFocusNode.addListener(_refresh);
    _scrollController.addListener(_handleScroll);
    _loadPinnedMessage();
    _loadLocalMessageState();
    unawaited(_loadPeerCallHistory());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || identical(route, _route)) return;
    if (_route != null) {
      kTurnaRouteObserver.unsubscribe(this);
    }
    _route = route;
    kTurnaRouteObserver.subscribe(this, route);
  }

  @override
  void didPush() {
    kTurnaActiveChatRegistry.setCurrent(widget.chat);
    unawaited(_loadPeerCallHistory());
  }

  @override
  void didPopNext() {
    kTurnaActiveChatRegistry.setCurrent(widget.chat);
    unawaited(_loadPeerCallHistory());
  }

  @override
  void didPushNext() {
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
  }

  @override
  void didPop() {
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
  }

  void _refresh() {
    final shouldSnapToBottom =
        !_scrollController.hasClients || _scrollController.offset < 120;
    if (mounted) {
      setState(() {});
    }
    final timelineCount = _buildTimelineEntries().length;
    if (timelineCount != _lastRenderedTimelineCount) {
      _lastRenderedTimelineCount = timelineCount;
      if (shouldSnapToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    }
  }

  void _handleCallCoordinatorChanged() {
    unawaited(_loadPeerCallHistory());
  }

  void _handleComposerChanged() {
    final text = _controller.text;
    _client.updateComposerText(text);
    final hasComposerText = text.trim().isNotEmpty;
    if (hasComposerText != _hasComposerText && mounted) {
      setState(() => _hasComposerText = hasComposerText);
    }
  }

  String? _buildPeerStatusText() {
    if (_peerUserId == null) return null;
    if (_client.peerTyping) return 'yaziyor...';
    if (_client.peerOnline) return 'online';
    final lastSeenAt = _client.peerLastSeenAt;
    if (lastSeenAt == null || lastSeenAt.trim().isEmpty) return null;
    return 'son gorulme ${_formatPresenceTime(lastSeenAt)}';
  }

  String _formatPresenceTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final seenDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(seenDay).inDays;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (diffDays == 0) return 'bugun $hh:$mm';
    if (diffDays == 1) return 'dun $hh:$mm';

    final dd = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    if (dt.year == now.year) return '$dd.$month $hh:$mm';
    return '$dd.$month.${dt.year} $hh:$mm';
  }

  Future<void> _openPeerProfile() async {
    final peerUserId = _peerUserId;
    if (peerUserId == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          session: widget.session,
          userId: peerUserId,
          fallbackName: widget.chat.name,
          fallbackAvatarUrl: widget.chat.avatarUrl,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _startCall(TurnaCallType type) async {
    final peerUserId = _peerUserId;
    if (peerUserId == null) return;

    try {
      final started = await CallApi.startCall(
        widget.session,
        calleeId: peerUserId,
        type: type,
      );
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OutgoingCallPage(
            session: widget.session,
            coordinator: widget.callCoordinator,
            initialCall: started,
            onSessionExpired: widget.onSessionExpired,
          ),
        ),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 180;
    if (shouldShow != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = shouldShow);
    }

    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 220) {
      _client.loadOlderMessages();
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  String _formatMessageTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatDayLabel(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(messageDay).inDays;
    if (diffDays == 0) return 'Bugun';
    if (diffDays == 1) return 'Dun';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd.$mm.${dt.year}';
  }

  String _timelineCreatedAt(_ChatTimelineEntry entry) {
    if (entry.message != null) return entry.message!.createdAt;
    final call = entry.call;
    return call?.createdAt ?? call?.endedAt ?? call?.acceptedAt ?? '';
  }

  bool _shouldShowDayChip(List<_ChatTimelineEntry> entries, int index) {
    if (index == entries.length - 1) return true;
    final current = DateTime.tryParse(_timelineCreatedAt(entries[index]));
    final older = DateTime.tryParse(_timelineCreatedAt(entries[index + 1]));
    if (current == null || older == null) return false;
    return current.year != older.year ||
        current.month != older.month ||
        current.day != older.day;
  }

  String? _guessContentType(String fileName) =>
      guessContentTypeForFileName(fileName);

  String _formatFileSize(int bytes) => formatBytesLabel(bytes);

  Future<void> _loadPeerCallHistory() async {
    final peerUserId = _peerUserId;
    if (peerUserId == null || _loadingPeerCalls) return;

    _loadingPeerCalls = true;
    final shouldSnapToBottom =
        !_scrollController.hasClients || _scrollController.offset < 120;
    final previousCount = _buildTimelineEntries().length;
    try {
      final calls = await CallApi.fetchCalls(widget.session);
      if (!mounted) return;
      final filtered =
          calls.where((item) => item.peer.id == peerUserId).toList()
            ..sort((a, b) {
              final aTime = a.createdAt ?? a.endedAt ?? a.acceptedAt ?? '';
              final bTime = b.createdAt ?? b.endedAt ?? b.acceptedAt ?? '';
              return aTime.compareTo(bTime);
            });
      setState(() => _peerCalls = filtered);
      final nextCount = _buildTimelineEntries().length;
      _lastRenderedTimelineCount = nextCount;
      if (shouldSnapToBottom && nextCount != previousCount) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      turnaLog('chat call history load failed', error);
    } finally {
      _loadingPeerCalls = false;
    }
  }

  void _showVoiceMessagePlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sesli mesaj yakinda eklenecek.')),
    );
  }

  void _showAttachmentPlaceholder(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label yakinda eklenecek.')));
  }

  Future<void> _loadPinnedMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pinnedMessageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _pinnedMessage = _PinnedMessageDraft.fromMap(map);
      });
    } catch (error) {
      turnaLog('chat pinned message load failed', error);
    }
  }

  Future<void> _persistPinnedMessage(_PinnedMessageDraft? draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (draft == null) {
      await prefs.remove(_pinnedMessageKey);
      return;
    }
    await prefs.setString(_pinnedMessageKey, jsonEncode(draft.toMap()));
  }

  Future<void> _loadLocalMessageState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final starred = prefs.getStringList(_starredMessagesKey) ?? const [];
      final softDeleted =
          prefs.getStringList(_softDeletedMessagesKey) ?? const [];
      final deleted = prefs.getStringList(_deletedMessagesKey) ?? const [];
      if (!mounted) return;
      setState(() {
        _starredMessageIds = starred.toSet();
        _softDeletedMessageIds = softDeleted.toSet();
        _deletedMessageIds = deleted.toSet();
      });
    } catch (error) {
      turnaLog('chat local message state load failed', error);
    }
  }

  Future<void> _persistStarredMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_starredMessagesKey, _starredMessageIds.toList());
  }

  Future<void> _persistSoftDeletedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _softDeletedMessagesKey,
      _softDeletedMessageIds.toList(),
    );
  }

  Future<void> _persistDeletedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_deletedMessagesKey, _deletedMessageIds.toList());
  }

  bool _isMessageDeletedForMe(ChatMessage msg) =>
      _softDeletedMessageIds.contains(msg.id);

  bool _isMessageDeletedPlaceholder(
    ChatMessage msg, {
    ParsedTurnaMessageText? parsed,
  }) => _isMessageDeletedForMe(msg) || (parsed?.deletedForEveryone ?? false);

  bool _canDeleteForEveryone(
    ChatMessage msg, {
    ParsedTurnaMessageText? parsed,
  }) {
    if (msg.senderId != widget.session.userId) return false;
    if (msg.id.startsWith('local_')) return false;
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) return false;
    final createdAt = DateTime.tryParse(msg.createdAt)?.toLocal();
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt) <= const Duration(minutes: 10);
  }

  Future<bool> _showDestructiveConfirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: TurnaColors.error,
                foregroundColor: Colors.white,
              ),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return approved == true;
  }

  Future<void> _setPinnedPreviewIfNeeded(
    String messageId,
    String previewText,
  ) async {
    final current = _pinnedMessage;
    if (current == null || current.messageId != messageId) return;
    final next = _PinnedMessageDraft(
      messageId: current.messageId,
      senderLabel: current.senderLabel,
      previewText: previewText,
    );
    if (mounted) {
      setState(() => _pinnedMessage = next);
    }
    await _persistPinnedMessage(next);
  }

  String _previewSnippetForMessage(ChatMessage msg) {
    final parsed = parseTurnaMessageText(msg.text);
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      return 'Silindi.';
    }
    final text = parsed.text.trim();
    if (text.isNotEmpty) {
      return text.length > 72 ? '${text.substring(0, 72)}...' : text;
    }
    if (msg.attachments.isEmpty) return 'Mesaj';
    final first = msg.attachments.first;
    if (_isAudioAttachment(first)) return 'Sesli mesaj';
    if (first.kind == ChatAttachmentKind.image) return 'Fotograf';
    if (first.kind == ChatAttachmentKind.video) return 'Video';
    return 'Dosya';
  }

  TurnaReplyPayload _replyPayloadForMessage(ChatMessage msg) {
    final mine = msg.senderId == widget.session.userId;
    return TurnaReplyPayload(
      messageId: msg.id,
      senderLabel: mine ? 'Sen' : widget.chat.name,
      previewText: _previewSnippetForMessage(msg),
    );
  }

  Future<List<int>> _downloadAttachmentBytes(ChatAttachment attachment) async {
    final url = attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      throw TurnaApiException('Iletilecek ek icin link bulunamadi.');
    }
    final uri = Uri.parse(url);
    var response = await http.get(uri);
    if (response.statusCode >= 400) {
      response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${widget.session.token}'},
      );
    }
    if (response.statusCode >= 400) {
      throw TurnaApiException('Ek indirilemedi.');
    }
    return response.bodyBytes;
  }

  Future<void> _forwardMessage(ChatMessage msg) async {
    final targetChat = await Navigator.push<ChatPreview>(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardMessagePickerPage(
          session: widget.session,
          currentChatId: widget.chat.chatId,
        ),
      ),
    );
    if (!mounted || targetChat == null) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('${targetChat.name} sohbetine iletiliyor...')),
    );

    try {
      final parsed = parseTurnaMessageText(msg.text);
      final drafts = <OutgoingAttachmentDraft>[];
      for (final attachment in msg.attachments) {
        final bytes = await _downloadAttachmentBytes(attachment);
        final upload = await ChatApi.createAttachmentUpload(
          widget.session,
          chatId: targetChat.chatId,
          kind: attachment.kind,
          contentType: attachment.contentType,
          fileName: attachment.fileName ?? 'dosya',
        );
        final uploadRes = await http.put(
          Uri.parse(upload.uploadUrl),
          headers: upload.headers,
          body: bytes,
        );
        if (uploadRes.statusCode >= 400) {
          throw TurnaApiException('Iletilecek ek yuklenemedi.');
        }
        drafts.add(
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: attachment.kind,
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            sizeBytes: attachment.sizeBytes > 0
                ? attachment.sizeBytes
                : bytes.length,
            width: attachment.width,
            height: attachment.height,
            durationSeconds: attachment.durationSeconds,
          ),
        );
      }

      await ChatApi.sendMessage(
        widget.session,
        chatId: targetChat.chatId,
        text: parsed.text.trim().isEmpty ? null : parsed.text.trim(),
        attachments: drafts,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${targetChat.name} sohbetine iletildi.')),
        );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleStarMessage(ChatMessage msg) async {
    final next = Set<String>.from(_starredMessageIds);
    final nowStarred = !next.contains(msg.id);
    if (nowStarred) {
      next.add(msg.id);
    } else {
      next.remove(msg.id);
    }
    setState(() => _starredMessageIds = next);
    await _persistStarredMessages();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nowStarred ? 'Mesaja yildiz eklendi.' : 'Yildiz kaldirildi.',
        ),
      ),
    );
  }

  Future<void> _deleteMessageLocally(ChatMessage msg) async {
    final wasPinned = _pinnedMessage?.messageId == msg.id;
    final next = Set<String>.from(_deletedMessageIds)..add(msg.id);
    final nextStarred = Set<String>.from(_starredMessageIds)..remove(msg.id);
    final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
      ..remove(msg.id);
    setState(() {
      _deletedMessageIds = next;
      _starredMessageIds = nextStarred;
      _softDeletedMessageIds = nextSoftDeleted;
      if (wasPinned) {
        _pinnedMessage = null;
      }
    });
    await _persistSoftDeletedMessages();
    await _persistDeletedMessages();
    await _persistStarredMessages();
    if (wasPinned) {
      await _persistPinnedMessage(null);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mesaj bu cihazdan silindi.')));
  }

  Future<void> _deleteMessageForMe(ChatMessage msg) async {
    final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
      ..add(msg.id);
    final nextStarred = Set<String>.from(_starredMessageIds)..remove(msg.id);
    setState(() {
      _softDeletedMessageIds = nextSoftDeleted;
      _starredMessageIds = nextStarred;
    });
    await _persistSoftDeletedMessages();
    await _persistStarredMessages();
    await _setPinnedPreviewIfNeeded(msg.id, 'Silindi.');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mesaj sende Silindi. olarak gosteriliyor.'),
      ),
    );
  }

  Future<void> _deleteMessageForEveryone(ChatMessage msg) async {
    try {
      final updated = await ChatApi.deleteMessageForEveryone(
        widget.session,
        messageId: msg.id,
      );
      final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
        ..remove(msg.id);
      if (mounted) {
        setState(() => _softDeletedMessageIds = nextSoftDeleted);
      }
      await _persistSoftDeletedMessages();
      await _setPinnedPreviewIfNeeded(msg.id, 'Silindi.');
      _client.mergeServerMessage(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mesaj herkesten silindi.')));
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _confirmRemoveDeletedPlaceholder(ChatMessage msg) async {
    final confirmed = await _showDestructiveConfirm(
      title: 'Mesajı kaldir',
      message: 'Bu Silindi. mesajı cihazından tamamen kaldirilsin mi?',
      confirmLabel: 'Kaldir',
    );
    if (!confirmed) return;
    await _deleteMessageLocally(msg);
  }

  Future<void> _showDeleteMessageOptions(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    final canDeleteForEveryone = _canDeleteForEveryone(msg, parsed: parsed);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Benden sil'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final confirmed = await _showDestructiveConfirm(
                    title: 'Mesajı senden sil',
                    message:
                        'Bu mesaj sadece senin tarafinda Silindi. olarak gosterilecek.',
                    confirmLabel: 'Benden sil',
                  );
                  if (!confirmed) return;
                  await _deleteMessageForMe(msg);
                },
              ),
              if (canDeleteForEveryone)
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Herkesten sil'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirmed = await _showDestructiveConfirm(
                      title: 'Mesajı herkesten sil',
                      message:
                          'Bu mesaj iki taraf icin de Silindi. olarak degisecek.',
                      confirmLabel: 'Herkesten sil',
                    );
                    if (!confirmed) return;
                    await _deleteMessageForEveryone(msg);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _translateMessage(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    final text = parsed.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cevrilecek metin bulunamadi.')),
      );
      return;
    }

    final uri = Uri.parse(
      'https://translate.google.com/?sl=auto&tl=tr&text=${Uri.encodeComponent(text)}&op=translate',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ceviri acilamadi.')));
    }
  }

  Future<void> _reportMessage(ChatMessage msg) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        const reasons = ['Spam', 'Taciz', 'Uygunsuz icerik', 'Sahte hesap'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final reason in reasons)
                ListTile(
                  title: Text(reason),
                  onTap: () => Navigator.pop(sheetContext, reason),
                ),
            ],
          ),
        );
      },
    );

    if (reason == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Sikayet kaydedildi: $reason')));
  }

  Future<void> _showMoreMessageActions(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      await _confirmRemoveDeletedPlaceholder(msg);
      return;
    }
    final isPinned = _pinnedMessage?.messageId == msg.id;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                ),
                title: Text(isPinned ? 'Sabitlemeyi kaldir' : 'Sabitle'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final next = isPinned
                      ? null
                      : _PinnedMessageDraft(
                          messageId: msg.id,
                          senderLabel: _replyPayloadForMessage(msg).senderLabel,
                          previewText: _previewSnippetForMessage(msg),
                        );
                  if (!mounted) return;
                  setState(() => _pinnedMessage = next);
                  await _persistPinnedMessage(next);
                },
              ),
              ListTile(
                leading: const Icon(Icons.translate_rounded),
                title: const Text('Cevir'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _translateMessage(msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Sikayet Et'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _reportMessage(msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Sil'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteMessageOptions(msg);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleMessageLongPress(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      await _confirmRemoveDeletedPlaceholder(msg);
      return;
    }
    final replyPayload = _replyPayloadForMessage(msg);
    final isStarred = _starredMessageIds.contains(msg.id);
    final textOnly = parsed.text.trim();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    _MessageQuickAction(
                      icon: Icons.reply_rounded,
                      label: 'Cevapla',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() => _replyDraft = replyPayload);
                        _composerFocusNode.requestFocus();
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.forward_rounded,
                      label: 'Ilet',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _forwardMessage(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.copy_all_outlined,
                      label: 'Kopyala',
                      enabled: textOnly.isNotEmpty,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await Clipboard.setData(ClipboardData(text: textOnly));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Mesaj kopyalandi.')),
                        );
                      },
                    ),
                    _MessageQuickAction(
                      icon: isStarred
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      label: isStarred ? 'Yildizi kaldir' : 'Yildiz ekle',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _toggleStarMessage(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Sil',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showDeleteMessageOptions(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.more_horiz_rounded,
                      label: 'Daha fazla',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showMoreMessageActions(msg);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isSameMessageGroup(
    List<_ChatTimelineEntry> displayEntries,
    int currentIndex,
    int neighborIndex,
  ) {
    if (neighborIndex < 0 || neighborIndex >= displayEntries.length) {
      return false;
    }
    final currentEntry = displayEntries[currentIndex];
    final neighborEntry = displayEntries[neighborIndex];
    final current = currentEntry.message;
    final neighbor = neighborEntry.message;
    if (current == null || neighbor == null) return false;
    if (current.senderId != neighbor.senderId) return false;
    final currentDate = DateTime.tryParse(current.createdAt);
    final neighborDate = DateTime.tryParse(neighbor.createdAt);
    if (currentDate == null || neighborDate == null) return false;
    return currentDate.year == neighborDate.year &&
        currentDate.month == neighborDate.month &&
        currentDate.day == neighborDate.day;
  }

  EdgeInsets _bubbleMarginFor(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    bool mine,
  ) {
    final joinsOlder = _isSameMessageGroup(displayEntries, index, index + 1);
    final joinsNewer = _isSameMessageGroup(displayEntries, index, index - 1);
    return EdgeInsets.only(
      left: mine ? 56 : 8,
      right: mine ? 8 : 56,
      top: joinsOlder ? TurnaChatTokens.stackGap / 2 : TurnaChatTokens.groupGap,
      bottom: joinsNewer
          ? TurnaChatTokens.stackGap / 2
          : TurnaChatTokens.groupGap / 2,
    );
  }

  List<ChatMessage> _currentDisplayMessages() => _client.messages.reversed
      .where((message) => !_deletedMessageIds.contains(message.id))
      .toList();

  List<_ChatTimelineEntry> _buildTimelineEntries() {
    final entries = <_ChatTimelineEntry>[
      ..._currentDisplayMessages().map(_ChatTimelineEntry.message),
      ..._peerCalls.map(_ChatTimelineEntry.call),
    ];
    entries.sort(
      (a, b) => _timelineCreatedAt(a).compareTo(_timelineCreatedAt(b)),
    );
    return entries;
  }

  GlobalKey _messageKeyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, GlobalKey.new);

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    return completer.future;
  }

  void _highlightMessage(String messageId) {
    _messageHighlightTimer?.cancel();
    if (mounted) {
      setState(() => _highlightedMessageId = messageId);
    }
    _messageHighlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || _highlightedMessageId != messageId) return;
      setState(() => _highlightedMessageId = null);
    });
  }

  Future<void> _scrollToReplyTarget(String messageId) async {
    var displayMessages = _currentDisplayMessages();
    var targetIndex = displayMessages.indexWhere(
      (message) => message.id == messageId,
    );

    var loadAttempt = 0;
    while (targetIndex == -1 && _client.hasMore && loadAttempt < 8) {
      await _client.loadOlderMessages();
      loadAttempt += 1;
      await _waitForNextFrame();
      displayMessages = _currentDisplayMessages();
      targetIndex = displayMessages.indexWhere(
        (message) => message.id == messageId,
      );
    }

    if (targetIndex == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yanitlanan mesaj bulunamadi.')),
      );
      return;
    }

    _highlightMessage(messageId);
    await _waitForNextFrame();
    if (!mounted) return;

    var targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext != null) {
      if (!targetContext.mounted) return;
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.34,
      );
      return;
    }

    if (!_scrollController.hasClients) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final ratio = displayMessages.length <= 1
        ? 0.0
        : targetIndex / (displayMessages.length - 1);
    final viewport = _scrollController.position.viewportDimension;
    final offsets = <double>[
      (maxExtent * ratio).clamp(0.0, maxExtent).toDouble(),
      (maxExtent * ratio + viewport * 0.5).clamp(0.0, maxExtent).toDouble(),
    ];

    for (final offset in offsets) {
      await _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      await _waitForNextFrame();
      if (!mounted) return;
      targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null) {
        if (!targetContext.mounted) return;
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.34,
        );
        return;
      }
    }
  }

  Future<void> _handleSendPressed() async {
    if (_attachmentBusy) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final outboundText = _replyDraft == null
        ? text
        : buildTurnaReplyEncodedText(reply: _replyDraft!, text: text);
    _client.send(outboundText);
    TurnaAnalytics.logEvent('message_sent', {
      'chat_id': widget.chat.chatId,
      'kind': 'text',
    });
    _controller.clear();
    if (mounted) {
      setState(() => _replyDraft = null);
    }
    _jumpToBottom();
  }

  String _formatCallTimelineSubtitle(TurnaCallHistoryItem item) {
    final duration = item.durationSeconds;
    if (duration != null && duration > 0) {
      final hours = duration ~/ 3600;
      final minutes = (duration % 3600) ~/ 60;
      final seconds = duration % 60;
      if (hours > 0) {
        return minutes > 0 ? '$hours sa $minutes dk' : '$hours sa';
      }
      if (minutes > 0) return '$minutes dk';
      return '$seconds sn';
    }

    switch (item.status) {
      case TurnaCallStatus.declined:
        return 'Reddedildi';
      case TurnaCallStatus.missed:
        return 'Cevapsiz';
      case TurnaCallStatus.cancelled:
        return 'Iptal edildi';
      case TurnaCallStatus.ringing:
        return 'Caliyor';
      case TurnaCallStatus.accepted:
      case TurnaCallStatus.ended:
        return 'Baglandi';
    }
  }

  Widget _buildCallBubble(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    TurnaCallHistoryItem item,
  ) {
    final mine = item.direction == 'outgoing';
    final bubbleColor = mine
        ? TurnaColors.chatOutgoing.withValues(alpha: 0.14)
        : TurnaColors.chatIncoming;
    final iconBackground = mine
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white;
    final iconColor = item.status == TurnaCallStatus.missed
        ? TurnaColors.error
        : mine
        ? TurnaColors.chatOutgoingText
        : TurnaColors.primary;
    final textColor = mine ? TurnaColors.text : TurnaColors.chatIncomingText;
    final title = item.type == TurnaCallType.video
        ? 'Goruntulu arama'
        : 'Sesli arama';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
              TurnaChatTokens.messageMaxWidthFactor,
        ),
        margin: _bubbleMarginFor(displayEntries, index, mine),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(TurnaChatTokens.bubbleRadius),
            topRight: const Radius.circular(TurnaChatTokens.bubbleRadius),
            bottomLeft: Radius.circular(
              mine
                  ? TurnaChatTokens.bubbleRadiusTail
                  : TurnaChatTokens.bubbleRadius,
            ),
            bottomRight: Radius.circular(
              mine
                  ? TurnaChatTokens.bubbleRadius
                  : TurnaChatTokens.bubbleRadiusTail,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                item.type == TurnaCallType.video
                    ? Icons.videocam_rounded
                    : Icons.call_rounded,
                color: iconColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 44),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          _formatCallTimelineSubtitle(item),
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.82),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatMessageTime(
                          item.createdAt ??
                              item.endedAt ??
                              item.acceptedAt ??
                              '',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: textColor.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    ChatMessage msg,
    bool mine,
  ) {
    final parsed = parseTurnaMessageText(msg.text);
    final isDeletedPlaceholder = _isMessageDeletedPlaceholder(
      msg,
      parsed: parsed,
    );
    final displayText = isDeletedPlaceholder ? 'Silindi.' : parsed.text.trim();
    final visibleAttachments = isDeletedPlaceholder
        ? const <ChatAttachment>[]
        : msg.attachments;
    final hasText = displayText.isNotEmpty;
    final hasError =
        !isDeletedPlaceholder &&
        msg.errorText != null &&
        msg.errorText!.trim().isNotEmpty;
    final isHighlighted = _highlightedMessageId == msg.id;
    final footer = _MessageMetaFooter(
      timeLabel: _formatMessageTime(msg.createdAt),
      mine: mine,
      status: msg.status,
      starred: _starredMessageIds.contains(msg.id),
    );
    final bubbleColor = mine
        ? TurnaColors.chatOutgoing
        : TurnaColors.chatIncoming;
    final resolvedBubbleColor = isHighlighted
        ? Color.alphaBlend(
            TurnaColors.accent.withValues(alpha: mine ? 0.18 : 0.12),
            bubbleColor,
          )
        : bubbleColor;
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(TurnaChatTokens.bubbleRadius),
      topRight: const Radius.circular(TurnaChatTokens.bubbleRadius),
      bottomLeft: Radius.circular(
        mine ? TurnaChatTokens.bubbleRadiusTail : TurnaChatTokens.bubbleRadius,
      ),
      bottomRight: Radius.circular(
        mine ? TurnaChatTokens.bubbleRadius : TurnaChatTokens.bubbleRadiusTail,
      ),
    );
    final bubbleBorder = msg.status == ChatMessageStatus.failed
        ? Border.all(color: Colors.red.shade200)
        : isHighlighted
        ? Border.all(
            color: TurnaColors.accentStrong.withValues(alpha: 0.72),
            width: 1.2,
          )
        : null;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _handleMessageLongPress(msg),
        onTap: isDeletedPlaceholder
            ? () => _confirmRemoveDeletedPlaceholder(msg)
            : mine &&
                  (msg.status == ChatMessageStatus.failed ||
                      msg.status == ChatMessageStatus.queued)
            ? () => _client.retryMessage(msg)
            : null,
        child: AnimatedContainer(
          key: _messageKeyFor(msg.id),
          duration: const Duration(milliseconds: 180),
          constraints: BoxConstraints(
            maxWidth:
                MediaQuery.of(context).size.width *
                TurnaChatTokens.messageMaxWidthFactor,
          ),
          margin: _bubbleMarginFor(displayEntries, index, mine),
          padding: EdgeInsets.fromLTRB(
            12,
            9,
            12,
            msg.attachments.isEmpty && !hasError ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: resolvedBubbleColor,
            borderRadius: bubbleRadius,
            border: bubbleBorder,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: mine ? 0.04 : 0.08),
                blurRadius: mine ? 4 : 10,
                offset: const Offset(0, 1),
              ),
              if (isHighlighted)
                BoxShadow(
                  color: TurnaColors.accent.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 0),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    msg.errorText!,
                    style: TextStyle(
                      fontSize: 11,
                      color: msg.status == ChatMessageStatus.failed
                          ? TurnaColors.error
                          : TurnaColors.textMuted,
                    ),
                  ),
                ),
              if (parsed.reply != null && !isDeletedPlaceholder) ...[
                _ReplySnippetCard(
                  reply: parsed.reply!,
                  mine: mine,
                  onTap: () => _scrollToReplyTarget(parsed.reply!.messageId),
                ),
                if (hasText || msg.attachments.isNotEmpty)
                  const SizedBox(height: 8),
              ],
              if (visibleAttachments.isNotEmpty) ...[
                _ChatAttachmentList(
                  attachments: visibleAttachments,
                  onTap: _openAttachment,
                  formatFileSize: _formatFileSize,
                ),
                if (hasText) const SizedBox(height: 8),
              ],
              if (hasText)
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        right: mine ? 64 : 54,
                        bottom: 4,
                      ),
                      child: Text(
                        displayText,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.28,
                          color: mine
                              ? TurnaColors.chatOutgoingText
                              : TurnaColors.chatIncomingText,
                        ),
                      ),
                    ),
                    footer,
                  ],
                )
              else if (visibleAttachments.isNotEmpty || hasError)
                Align(alignment: Alignment.bottomRight, child: footer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final focused = _composerFocusNode.hasFocus;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyDraft != null)
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 54, bottom: 8),
                child: _ComposerReplyBanner(
                  reply: _replyDraft!,
                  onClose: () => setState(() => _replyDraft = null),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _attachmentBusy ? null : _showAttachmentSheet,
                  icon: _attachmentBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add, size: 28),
                  color: TurnaColors.textSoft,
                ),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: TurnaColors.backgroundSoft,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: focused
                            ? TurnaColors.primary
                            : TurnaColors.border,
                        width: focused ? 1.4 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: TurnaColors.primary.withValues(
                            alpha: focused ? 0.08 : 0.03,
                          ),
                          blurRadius: focused ? 16 : 8,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _composerFocusNode,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Mesaj',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        if (!_hasComposerText)
                          IconButton(
                            onPressed: _attachmentBusy
                                ? null
                                : _pickCameraImage,
                            icon: const Icon(Icons.camera_alt_outlined),
                            color: TurnaColors.textSoft,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _hasComposerText
                      ? Container(
                          key: const ValueKey('send'),
                          width: 46,
                          height: 46,
                          decoration: const BoxDecoration(
                            color: TurnaColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: _attachmentBusy
                                ? null
                                : _handleSendPressed,
                            icon: const Icon(Icons.send_rounded),
                            color: TurnaColors.surface,
                          ),
                        )
                      : Container(
                          key: const ValueKey('mic'),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _attachmentBusy
                                ? null
                                : _showVoiceMessagePlaceholder,
                            icon: const Icon(Icons.mic_none_rounded),
                            color: TurnaColors.textSoft,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPickedAttachment({
    required ChatAttachmentKind kind,
    required String fileName,
    required String contentType,
    required Future<List<int>> Function() readBytes,
    int? sizeBytes,
  }) async {
    setState(() => _attachmentBusy = true);

    try {
      final upload = await ChatApi.createAttachmentUpload(
        widget.session,
        chatId: widget.chat.chatId,
        kind: kind,
        contentType: contentType,
        fileName: fileName,
      );

      final bytes = await readBytes();
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Dosya yuklenemedi.');
      }

      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: widget.chat.chatId,
        text: _controller.text.trim().isEmpty
            ? null
            : (_replyDraft == null
                  ? _controller.text.trim()
                  : buildTurnaReplyEncodedText(
                      reply: _replyDraft!,
                      text: _controller.text.trim(),
                    )),
        attachments: [
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: kind,
            fileName: fileName,
            contentType: contentType,
            sizeBytes: sizeBytes ?? bytes.length,
          ),
        ],
      );

      if (!mounted) return;
      _client.mergeServerMessage(message);
      _controller.clear();
      setState(() => _replyDraft = null);
      _jumpToBottom();
      await TurnaAnalytics.logEvent('attachment_sent', {
        'chat_id': widget.chat.chatId,
        'kind': kind.name,
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Future<void> _openMediaComposerFromFiles(List<XFile> files) async {
    final seeds = <MediaComposerSeed>[];

    for (final file in files.take(kComposerMediaLimit)) {
      final contentType = _guessContentType(file.name);
      if (contentType == null) continue;

      late final ChatAttachmentKind kind;
      if (contentType.startsWith('image/')) {
        kind = ChatAttachmentKind.image;
      } else if (contentType.startsWith('video/')) {
        kind = ChatAttachmentKind.video;
      } else {
        continue;
      }

      final sizeBytes = await file.length();
      if (sizeBytes > kInlineAttachmentSoftLimitBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${file.name} 64 MB ustu oldugu icin inline medya olarak gonderilemiyor.',
            ),
          ),
        );
        continue;
      }

      seeds.add(
        MediaComposerSeed(
          kind: kind,
          file: file,
          fileName: file.name,
          contentType: contentType,
          sizeBytes: sizeBytes,
        ),
      );
    }

    if (seeds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gonderilebilir medya bulunamadi.')),
      );
      return;
    }

    if (!mounted) return;
    final message = await Navigator.push<ChatMessage>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaComposerPage(
          session: widget.session,
          chat: widget.chat,
          items: seeds,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );

    if (!mounted || message == null) return;
    _client.mergeServerMessage(message);
    _jumpToBottom();
  }

  Future<void> _pickGalleryMedia() async {
    final files = await _mediaPicker.pickMultipleMedia(
      limit: kComposerMediaLimit,
      imageQuality: kInlineImagePickerQuality,
      maxWidth: kInlineImagePickerMaxDimension,
      maxHeight: kInlineImagePickerMaxDimension,
    );
    if (files.isEmpty) return;
    await _openMediaComposerFromFiles(files);
  }

  Future<void> _pickCameraImage() async {
    final file = await _mediaPicker.pickImage(
      source: ImageSource.camera,
      imageQuality: kInlineImagePickerQuality,
      maxWidth: kInlineImagePickerMaxDimension,
      maxHeight: kInlineImagePickerMaxDimension,
    );
    if (file == null) return;
    await _openMediaComposerFromFiles([file]);
  }

  Future<void> _pickCameraVideo() async {
    final file = await _mediaPicker.pickVideo(source: ImageSource.camera);
    if (file == null) return;
    await _openMediaComposerFromFiles([file]);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final filePath = file.path;
    if (filePath == null || filePath.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Secilen dosya okunamadi.')));
      return;
    }

    final fileName = file.name.trim().isEmpty
        ? filePath.split('/').last
        : file.name.trim();
    await _sendPickedAttachment(
      kind: ChatAttachmentKind.file,
      fileName: fileName,
      contentType:
          guessContentTypeForFileName(fileName) ?? 'application/octet-stream',
      readBytes: () => File(filePath).readAsBytes(),
      sizeBytes: file.size,
    );
  }

  Future<void> _showAttachmentSheet() async {
    if (_attachmentBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            decoration: BoxDecoration(
              color: TurnaColors.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paylas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: TurnaColors.text,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    _AttachmentQuickAction(
                      icon: Icons.photo_camera_outlined,
                      label: 'Kamera',
                      backgroundColor: TurnaColors.primary,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickCameraImage();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.photo_library_outlined,
                      label: 'Galeri',
                      backgroundColor: TurnaColors.accent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickGalleryMedia();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      backgroundColor: TurnaColors.primaryStrong,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickCameraVideo();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.insert_drive_file_outlined,
                      label: 'Belge',
                      backgroundColor: TurnaColors.primaryDeep,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickFile();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.location_on_outlined,
                      label: 'Konum',
                      backgroundColor: TurnaColors.primary400,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showAttachmentPlaceholder('Konum');
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.perm_contact_calendar_outlined,
                      label: 'Kisi',
                      backgroundColor: TurnaColors.accentStrong,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showAttachmentPlaceholder('Kisi');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAttachment(ChatAttachment attachment) async {
    final url = attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya linki hazir degil.')));
      return;
    }

    if (attachment.kind == ChatAttachmentKind.image) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatAttachmentViewerPage(
            imageUrl: url,
            title: attachment.fileName ?? 'Gorsel',
          ),
        ),
      );
      return;
    }

    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya acilamadi.')));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    turnaLog('chat room dispose', {'chatId': widget.chat.chatId});
    if (_route != null) {
      kTurnaRouteObserver.unsubscribe(this);
    }
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
    _client.removeListener(_refresh);
    _client.dispose();
    widget.callCoordinator.removeListener(_handleCallCoordinatorChanged);
    _controller.removeListener(_handleComposerChanged);
    _controller.dispose();
    _composerFocusNode.removeListener(_refresh);
    _composerFocusNode.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _messageHighlightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _client.refreshConnection();
      unawaited(_loadPeerCallHistory());
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _client.disconnectForBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final timelineEntries = _buildTimelineEntries();
    final peerStatusText = _buildPeerStatusText();

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        title: GestureDetector(
          onTap: _peerUserId == null ? null : _openPeerProfile,
          child: Row(
            children: [
              _ProfileAvatar(
                label: widget.chat.name,
                avatarUrl: widget.chat.avatarUrl,
                authToken: widget.session.token,
                radius: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.chat.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (peerStatusText != null)
                      Text(
                        peerStatusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _client.peerTyping
                              ? TurnaColors.primary
                              : TurnaColors.textMuted,
                          fontWeight: _client.peerTyping
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Goruntulu ara',
            onPressed: _peerUserId == null
                ? null
                : () => _startCall(TurnaCallType.video),
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            tooltip: 'Sesli ara',
            onPressed: _peerUserId == null
                ? null
                : () => _startCall(TurnaCallType.audio),
            icon: const Icon(Icons.call_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_client.error != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF1E6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _client.error!,
                style: const TextStyle(color: Color(0xFF7A4B00)),
              ),
            ),
          if (!_client.isConnected)
            Container(
              width: double.infinity,
              color: const Color(0xFFEAF2FF),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Canli baglanti yok. Yazdiklarin siraya alinip tekrar denenecek.',
                style: TextStyle(color: Color(0xFF234B8F)),
              ),
            ),
          if (_attachmentBusy)
            Container(
              width: double.infinity,
              color: TurnaColors.primary50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Medya yukleniyor. Mesaj hazirlaniyor...',
                style: TextStyle(color: TurnaColors.primaryStrong),
              ),
            ),
          if (_pinnedMessage != null)
            _PinnedMessageBar(
              pinned: _pinnedMessage!,
              onClear: () async {
                setState(() => _pinnedMessage = null);
                await _persistPinnedMessage(null);
              },
            ),
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: _ChatWallpaper()),
                if (_client.loadingInitial && timelineEntries.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (timelineEntries.isEmpty)
                  const _CenteredState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Henuz mesaj yok',
                    message: 'Ilk mesaji gondererek sohbeti baslat.',
                  )
                else
                  ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 18),
                    itemCount: timelineEntries.length + 1,
                    itemBuilder: (context, index) {
                      if (index == timelineEntries.length) {
                        if (_client.loadingMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (_client.hasMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                'Eski mesajlar yukleniyor...',
                                style: TextStyle(color: Color(0xFF777C79)),
                              ),
                            ),
                          );
                        }
                        return const SizedBox(height: 24);
                      }

                      final entry = timelineEntries[index];
                      final msg = entry.message;
                      final call = entry.call;
                      return Column(
                        children: [
                          if (_shouldShowDayChip(timelineEntries, index))
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: TurnaChatTokens.dateGap / 2,
                              ),
                              child: _DateSeparatorChip(
                                label: _formatDayLabel(
                                  _timelineCreatedAt(entry),
                                ),
                              ),
                            ),
                          if (msg != null)
                            _buildMessageBubble(
                              timelineEntries,
                              index,
                              msg,
                              msg.senderId == widget.session.userId,
                            )
                          else if (call != null)
                            _buildCallBubble(timelineEntries, index, call),
                        ],
                      );
                    },
                  ),
                if (_client.peerTyping)
                  const Positioned(
                    left: 14,
                    bottom: 12,
                    child: _TypingIndicatorPill(),
                  ),
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.white,
                      foregroundColor: TurnaColors.primary,
                      onPressed: _jumpToBottom,
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
              ],
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }
}

class _MessageMetaFooter extends StatelessWidget {
  const _MessageMetaFooter({
    required this.timeLabel,
    required this.mine,
    required this.status,
    this.starred = false,
  });

  final String timeLabel;
  final bool mine;
  final ChatMessageStatus status;
  final bool starred;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (starred) ...[
          Icon(
            Icons.star_rounded,
            size: 13,
            color: mine
                ? Colors.white.withValues(alpha: 0.86)
                : TurnaColors.warning,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          timeLabel,
          style: TextStyle(
            fontSize: 11,
            color: mine
                ? Colors.white.withValues(alpha: 0.8)
                : TurnaColors.textMuted,
          ),
        ),
        if (mine) ...[
          const SizedBox(width: 6),
          _StatusTick(status: status, mine: mine),
        ],
      ],
    );
  }
}

class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status, this.mine = false});

  final ChatMessageStatus status;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.done;
    Color color = mine
        ? Colors.white.withValues(alpha: 0.82)
        : TurnaColors.textMuted;

    if (status == ChatMessageStatus.sending) {
      icon = Icons.schedule;
    } else if (status == ChatMessageStatus.queued) {
      icon = Icons.cloud_off_outlined;
    } else if (status == ChatMessageStatus.failed) {
      icon = Icons.error_outline;
      color = TurnaColors.error;
    } else if (status == ChatMessageStatus.delivered) {
      icon = Icons.done_all;
    } else if (status == ChatMessageStatus.read) {
      icon = Icons.done_all;
      color = mine ? TurnaColors.accent : TurnaColors.info;
    }

    return Icon(icon, size: 16, color: color);
  }
}

class _DateSeparatorChip extends StatelessWidget {
  const _DateSeparatorChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TurnaColors.surfaceHover,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TurnaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: TurnaColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicatorPill extends StatefulWidget {
  const _TypingIndicatorPill();

  @override
  State<_TypingIndicatorPill> createState() => _TypingIndicatorPillState();
}

class _TypingIndicatorPillState extends State<_TypingIndicatorPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacityForDot(int index) {
    final progress = (_controller.value + (index * 0.16)) % 1.0;
    if (progress < 0.5) {
      return 0.32 + (progress / 0.5) * 0.68;
    }
    return 1 - ((progress - 0.5) / 0.5) * 0.68;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: TurnaColors.chatIncoming,
        borderRadius: BorderRadius.circular(TurnaChatTokens.bubbleRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              return Container(
                width: 7,
                height: 7,
                margin: EdgeInsets.only(right: index == 2 ? 0 : 4),
                decoration: BoxDecoration(
                  color: TurnaColors.textMuted.withValues(
                    alpha: _opacityForDot(index),
                  ),
                  shape: BoxShape.circle,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _ChatWallpaper extends StatelessWidget {
  const _ChatWallpaper();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ChatWallpaperPainter());
  }
}

class _ChatWallpaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = TurnaColors.border.withValues(alpha: 0.45);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = TurnaColors.primary50.withValues(alpha: 0.22);

    const stepX = 72.0;
    const stepY = 78.0;
    for (double y = -10; y < size.height + stepY; y += stepY) {
      final row = (y / stepY).round();
      for (double x = 0; x < size.width + stepX; x += stepX) {
        final offsetX = row.isEven ? 10.0 : 36.0;
        final origin = Offset(x + offsetX, y + 16);

        canvas.drawCircle(origin, 6, stroke);
        canvas.drawCircle(origin, 3, fill);

        final rounded = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: origin + const Offset(22, 18),
            width: 18,
            height: 13,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(rounded, stroke);

        final path = Path()
          ..moveTo(origin.dx - 4, origin.dy + 26)
          ..quadraticBezierTo(
            origin.dx + 2,
            origin.dy + 18,
            origin.dx + 8,
            origin.dy + 26,
          )
          ..quadraticBezierTo(
            origin.dx + 14,
            origin.dy + 34,
            origin.dx + 20,
            origin.dy + 26,
          );
        canvas.drawPath(path, stroke);

        canvas.drawArc(
          Rect.fromCircle(center: origin + const Offset(44, 42), radius: 7),
          -math.pi / 6,
          math.pi * 1.2,
          false,
          stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AttachmentQuickAction extends StatelessWidget {
  const _AttachmentQuickAction({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: Colors.white, size: 25),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: TurnaColors.textSoft,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageQuickAction extends StatelessWidget {
  const _MessageQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? TurnaColors.text : TurnaColors.textMuted;
    return SizedBox(
      width: 82,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: TurnaColors.backgroundMuted,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: iconColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplySnippetCard extends StatelessWidget {
  const _ReplySnippetCard({
    required this.reply,
    required this.mine,
    this.onTap,
  });

  final TurnaReplyPayload reply;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = mine
        ? Colors.white.withValues(alpha: 0.85)
        : TurnaColors.primary;
    final background = mine
        ? Colors.white.withValues(alpha: 0.14)
        : TurnaColors.primary50;
    final textColor = mine
        ? Colors.white.withValues(alpha: 0.95)
        : TurnaColors.text;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reply.senderLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reply.previewText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.92),
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerReplyBanner extends StatelessWidget {
  const _ComposerReplyBanner({required this.reply, required this.onClose});

  final TurnaReplyPayload reply;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: TurnaColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TurnaColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: TurnaColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yanitlaniyor: ${reply.senderLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: TurnaColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _PinnedMessageBar extends StatelessWidget {
  const _PinnedMessageBar({required this.pinned, required this.onClear});

  final _PinnedMessageDraft pinned;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: const BoxDecoration(
        color: TurnaColors.surface,
        border: Border(bottom: BorderSide(color: TurnaColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.push_pin_rounded,
            size: 17,
            color: TurnaColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sabitlenen mesaj',
                  style: TextStyle(
                    color: TurnaColors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${pinned.senderLabel}: ${pinned.previewText}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.textSoft,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: TurnaColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _VoiceMessageBubbleSkeleton extends StatelessWidget {
  const _VoiceMessageBubbleSkeleton({
    required this.attachment,
    required this.onTap,
  });

  final ChatAttachment attachment;
  final VoidCallback onTap;

  String _formatDuration() {
    final duration = attachment.durationSeconds;
    if (duration == null || duration <= 0) return '--:--';
    final minutes = (duration ~/ 60).toString().padLeft(2, '0');
    final seconds = (duration % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    const bars = [10, 16, 12, 20, 13, 17, 9, 19, 11, 15, 18, 12];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 236,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: TurnaColors.primary50,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: TurnaColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: bars
                          .map(
                            (height) => Container(
                              width: 3,
                              height: height.toDouble(),
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: TurnaColors.primary.withValues(
                                  alpha: 0.78,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDuration(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: TurnaColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForwardMessagePickerPage extends StatefulWidget {
  const ForwardMessagePickerPage({
    super.key,
    required this.session,
    required this.currentChatId,
  });

  final AuthSession session;
  final String currentChatId;

  @override
  State<ForwardMessagePickerPage> createState() =>
      _ForwardMessagePickerPageState();
}

class _ForwardMessagePickerPageState extends State<ForwardMessagePickerPage> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<ChatPreview>> _chatsFuture;

  @override
  void initState() {
    super.initState();
    _chatsFuture = ChatApi.fetchChats(widget.session);
    _searchController.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Ilet')),
      body: FutureBuilder<List<ChatPreview>>(
        future: _chatsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CenteredState(
              icon: Icons.forward_to_inbox_outlined,
              title: 'Sohbetler yuklenemedi',
              message: snapshot.error.toString(),
            );
          }

          final chats = (snapshot.data ?? const <ChatPreview>[])
              .where((chat) => chat.chatId != widget.currentChatId)
              .where((chat) {
                if (query.isEmpty) return true;
                return chat.name.toLowerCase().contains(query) ||
                    chat.message.toLowerCase().contains(query);
              })
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Sohbet ara',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: TurnaColors.backgroundMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: chats.isEmpty
                    ? const _CenteredState(
                        icon: Icons.chat_bubble_outline,
                        title: 'Sohbet bulunamadi',
                        message: 'Iletilecek baska sohbet bulunmuyor.',
                      )
                    : ListView.builder(
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          return ListTile(
                            leading: _ProfileAvatar(
                              label: chat.name,
                              avatarUrl: chat.avatarUrl,
                              authToken: widget.session.token,
                              radius: 22,
                            ),
                            title: Text(
                              chat.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: chat.message.trim().isEmpty
                                ? null
                                : Text(
                                    chat.message,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => Navigator.pop(context, chat),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChatAttachmentList extends StatelessWidget {
  const _ChatAttachmentList({
    required this.attachments,
    required this.onTap,
    required this.formatFileSize,
  });

  final List<ChatAttachment> attachments;
  final Future<void> Function(ChatAttachment attachment) onTap;
  final String Function(int bytes) formatFileSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: attachments.map((attachment) {
        if (_isAudioAttachment(attachment)) {
          return _VoiceMessageBubbleSkeleton(
            attachment: attachment,
            onTap: () => onTap(attachment),
          );
        }
        if (attachment.kind == ChatAttachmentKind.image) {
          final imageUrl = attachment.url?.trim() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onTap(attachment),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 220,
                  height: 220,
                  color: TurnaColors.backgroundMuted,
                  child: imageUrl.isEmpty
                      ? const Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              ),
            ),
          );
        }

        final isVideo = attachment.kind == ChatAttachmentKind.video;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onTap(attachment),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TurnaColors.backgroundMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: TurnaColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.play_circle_outline
                          : Icons.insert_drive_file_outlined,
                      color: TurnaColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName ?? (isVideo ? 'Video' : 'Dosya'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${isVideo ? 'Video' : 'Dosya'} • ${formatFileSize(attachment.sizeBytes)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TurnaColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class ChatAttachmentViewerPage extends StatelessWidget {
  const ChatAttachmentViewerPage({
    super.key,
    required this.imageUrl,
    required this.title,
  });

  final String imageUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Gorsel yuklenemedi.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum MediaComposerQuality { sd, hd }

extension MediaComposerQualityX on MediaComposerQuality {
  String get label => name.toUpperCase();

  double get imageMaxDimension {
    switch (this) {
      case MediaComposerQuality.sd:
        return kInlineImageSdMaxDimension;
      case MediaComposerQuality.hd:
        return kInlineImageHdMaxDimension;
    }
  }

  int get jpegQuality {
    switch (this) {
      case MediaComposerQuality.sd:
        return 74;
      case MediaComposerQuality.hd:
        return 86;
    }
  }
}

class MediaComposerSeed {
  MediaComposerSeed({
    required this.kind,
    required this.file,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
  });

  final ChatAttachmentKind kind;
  final XFile file;
  final String fileName;
  final String contentType;
  final int sizeBytes;
}

class _MediaCropPreset {
  const _MediaCropPreset({
    required this.id,
    required this.label,
    this.aspectRatio,
    this.useOriginalAspect = false,
    this.fullImage = false,
    this.freeform = false,
  });

  final String id;
  final String label;
  final double? aspectRatio;
  final bool useOriginalAspect;
  final bool fullImage;
  final bool freeform;
}

enum _MediaComposerCropHandle { topLeft, topRight, bottomLeft, bottomRight }

class MediaComposerPage extends StatefulWidget {
  const MediaComposerPage({
    super.key,
    required this.session,
    required this.chat,
    required this.items,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final ChatPreview chat;
  final List<MediaComposerSeed> items;
  final VoidCallback onSessionExpired;

  @override
  State<MediaComposerPage> createState() => _MediaComposerPageState();
}

class _MediaComposerPageState extends State<MediaComposerPage> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _inlineTextController = TextEditingController();
  final FocusNode _inlineTextFocusNode = FocusNode();
  late final PageController _pageController;
  late final List<_MediaComposerItem> _items;
  int _selectedIndex = 0;
  bool _cropMode = false;
  bool _drawMode = false;
  bool _sending = false;
  String? _sendingLabel;
  String? _activeTextOverlayId;
  MediaComposerQuality _quality = MediaComposerQuality.sd;
  double _overlayInteractionBaseScale = 1;
  double _brushSizeFactor = 0.011;
  bool _eraserMode = false;

  _MediaComposerItem get _currentItem => _items[_selectedIndex];

  _MediaComposerTextOverlay? get _activeTextOverlay {
    final overlayId = _activeTextOverlayId;
    if (overlayId == null) return null;
    for (final overlay in _currentItem.textOverlays) {
      if (overlay.id == overlayId) return overlay;
    }
    return null;
  }

  Rect get _currentWorkingCropRect =>
      _currentItem.draftCropRectNormalized ??
      _currentItem.cropRectNormalized ??
      _defaultCropRectFor(_currentItem);

  String get _currentWorkingCropPresetId =>
      _currentItem.draftCropPresetId ?? _currentItem.cropPresetId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _items = widget.items.map(_MediaComposerItem.fromSeed).toList();
    for (final item in _items.where((item) => item.isImage)) {
      unawaited(_primeImageSize(item));
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _inlineTextController.dispose();
    _inlineTextFocusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _primeImageSize(_MediaComposerItem item) async {
    if (!item.isImage || item.sourceSize != null) return;
    final bytes = await item.file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    if (!mounted) return;
    setState(() => item.sourceSize = size);
  }

  Future<void> _showComingSoon(String text) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Rect _displayCropRectFor(_MediaComposerItem item) {
    if (identical(item, _currentItem) && _cropMode) {
      return kComposerFullCropRectNormalized;
    }
    return item.cropRectNormalized ?? kComposerFullCropRectNormalized;
  }

  double _effectiveAspectRatioFor(_MediaComposerItem item, Rect displayCrop) {
    final base = item.sourceSize ?? const Size(1, 1);
    final rotatedWidth = item.rotationTurns.isOdd ? base.height : base.width;
    final rotatedHeight = item.rotationTurns.isOdd ? base.width : base.height;
    return math.max(
      0.1,
      (rotatedWidth * displayCrop.width) /
          math.max(0.1, rotatedHeight * displayCrop.height),
    );
  }

  Size _rotatedSourceSize(_MediaComposerItem item) {
    final base = item.sourceSize ?? const Size(1, 1);
    return item.rotationTurns.isOdd
        ? Size(base.height, base.width)
        : Size(base.width, base.height);
  }

  _MediaCropPreset _cropPresetForId(String id) {
    return _kComposerCropPresets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => _kComposerCropPresets.first,
    );
  }

  double _resolvedCropAspectRatio(
    _MediaComposerItem item,
    _MediaCropPreset preset,
  ) {
    if (preset.useOriginalAspect) {
      final size = _rotatedSourceSize(item);
      return size.width / math.max(0.1, size.height);
    }
    return preset.aspectRatio ?? 1;
  }

  Rect _cropRectForPreset(
    _MediaComposerItem item,
    _MediaCropPreset preset, {
    Offset? center,
  }) {
    if (preset.fullImage) return kComposerFullCropRectNormalized;
    if (preset.freeform) {
      final existing = item.cropRectNormalized;
      if (existing != null &&
          existing != kComposerFullCropRectNormalized &&
          existing.width < 1 &&
          existing.height < 1) {
        return _clampCropRect(existing);
      }
      return Rect.fromLTWH(
        kComposerCropInitialInset,
        kComposerCropInitialInset,
        1 - (kComposerCropInitialInset * 2),
        1 - (kComposerCropInitialInset * 2),
      );
    }

    final imageSize = _rotatedSourceSize(item);
    final imageAspect = imageSize.width / math.max(0.1, imageSize.height);
    final targetAspect = _resolvedCropAspectRatio(item, preset);
    final normalizedAspect = targetAspect / math.max(0.1, imageAspect);
    final available = 1 - (kComposerCropInitialInset * 2);

    var width = available;
    var height = width / math.max(0.1, normalizedAspect);
    if (height > available) {
      height = available;
      width = height * normalizedAspect;
    }

    width = width.clamp(kComposerCropMinSide, 1.0).toDouble();
    height = height.clamp(kComposerCropMinSide, 1.0).toDouble();

    final anchor =
        center ?? item.cropRectNormalized?.center ?? const Offset(0.5, 0.5);
    return _clampCropRect(
      Rect.fromCenter(center: anchor, width: width, height: height),
    );
  }

  double? _lockedNormalizedCropAspectRatio(_MediaComposerItem item) {
    final preset = identical(item, _currentItem) && _cropMode
        ? _cropPresetForId(_currentWorkingCropPresetId)
        : _cropPresetForId(item.cropPresetId);
    if (preset.freeform || preset.fullImage) return null;
    final imageSize = _rotatedSourceSize(item);
    final imageAspect = imageSize.width / math.max(0.1, imageSize.height);
    final targetAspect = _resolvedCropAspectRatio(item, preset);
    return targetAspect / math.max(0.1, imageAspect);
  }

  Rect _normalizedCropToRect(Rect normalizedCrop, Size size) {
    return Rect.fromLTWH(
      normalizedCrop.left * size.width,
      normalizedCrop.top * size.height,
      normalizedCrop.width * size.width,
      normalizedCrop.height * size.height,
    );
  }

  Rect _clampCropRect(Rect rect) {
    final minSide = kComposerCropMinSide;
    var left = rect.left;
    var top = rect.top;
    var right = rect.right;
    var bottom = rect.bottom;

    if ((right - left) < minSide) {
      right = left + minSide;
    }
    if ((bottom - top) < minSide) {
      bottom = top + minSide;
    }

    if (left < 0) {
      right -= left;
      left = 0;
    }
    if (top < 0) {
      bottom -= top;
      top = 0;
    }
    if (right > 1) {
      left -= right - 1;
      right = 1;
    }
    if (bottom > 1) {
      top -= bottom - 1;
      bottom = 1;
    }

    left = left.clamp(0.0, 1.0 - minSide).toDouble();
    top = top.clamp(0.0, 1.0 - minSide).toDouble();
    right = right.clamp(left + minSide, 1.0).toDouble();
    bottom = bottom.clamp(top + minSide, 1.0).toDouble();

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _defaultCropRectFor(_MediaComposerItem item) {
    return _cropRectForPreset(item, _cropPresetForId(item.cropPresetId));
  }

  void _beginCropEditing() {
    _currentItem.draftCropPresetId = _currentItem.cropPresetId;
    _currentItem.draftCropRectNormalized =
        _currentItem.cropRectNormalized ?? _defaultCropRectFor(_currentItem);
    _cropMode = true;
  }

  void _cancelCropEditing() {
    setState(() {
      _currentItem.draftCropRectNormalized = null;
      _currentItem.draftCropPresetId = null;
      _cropMode = false;
    });
  }

  void _applyCropEditing() {
    setState(() {
      _currentItem.cropPresetId = _currentWorkingCropPresetId;
      _currentItem.cropRectNormalized = _currentWorkingCropRect;
      _currentItem.draftCropRectNormalized = null;
      _currentItem.draftCropPresetId = null;
      _cropMode = false;
    });
  }

  void _applyCropPreset(_MediaCropPreset preset) {
    if (!_currentItem.isImage) return;
    final currentCenter = _currentWorkingCropRect.center;
    setState(() {
      _currentItem.draftCropPresetId = preset.id;
      _currentItem.draftCropRectNormalized = _cropRectForPreset(
        _currentItem,
        preset,
        center: currentCenter,
      );
    });
  }

  void _toggleQuality() {
    setState(() {
      _quality = _quality == MediaComposerQuality.sd
          ? MediaComposerQuality.hd
          : MediaComposerQuality.sd;
    });
  }

  Future<void> _toggleCropMode() async {
    if (_currentItem.kind == ChatAttachmentKind.video) {
      await _showComingSoon(
        'Kirpma su an sadece fotograflarda acik. Video kirpmaya sonra gececegiz.',
      );
      return;
    }

    _finishTextEditing();
    if (_cropMode) {
      _applyCropEditing();
      return;
    }

    setState(() {
      _drawMode = false;
      _eraserMode = false;
      if (_currentItem.cropRectNormalized == null) {
        _currentItem.cropPresetId = 'free';
      }
      _beginCropEditing();
    });
  }

  String _nextTextOverlayId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_currentItem.textOverlays.length + 1}';
  }

  void _requestInlineTextFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inlineTextFocusNode.requestFocus();
    });
  }

  void _finishTextEditing() {
    final overlayId = _activeTextOverlayId;
    if (overlayId == null) return;

    final overlay = _activeTextOverlay;
    if (overlay == null) {
      if (mounted) {
        setState(() => _activeTextOverlayId = null);
      }
      _inlineTextController.clear();
      _inlineTextFocusNode.unfocus();
      return;
    }

    final nextText = _inlineTextController.text.trim();
    setState(() {
      if (nextText.isEmpty) {
        _currentItem.textOverlays.removeWhere((item) => item.id == overlayId);
      } else {
        overlay.text = nextText;
      }
      _activeTextOverlayId = null;
    });
    _inlineTextController.clear();
    _inlineTextFocusNode.unfocus();
  }

  void _beginNewTextOverlay({
    required String initialText,
    required bool requestKeyboard,
    bool activateOverlay = true,
  }) {
    if (!_currentItem.isImage) return;
    _finishTextEditing();

    final overlay = _MediaComposerTextOverlay(
      id: _nextTextOverlayId(),
      text: initialText,
      position: kComposerOverlayDefaultPosition,
      scale: 1,
      colorValue: _currentItem.markupColorValue,
    );

    setState(() {
      _cropMode = false;
      _drawMode = false;
      _currentItem.textOverlays.add(overlay);
      _activeTextOverlayId = activateOverlay ? overlay.id : null;
      _inlineTextController.value = activateOverlay
          ? TextEditingValue(
              text: initialText,
              selection: TextSelection.collapsed(offset: initialText.length),
            )
          : const TextEditingValue();
    });

    if (requestKeyboard && activateOverlay) {
      _requestInlineTextFocus();
    } else {
      _inlineTextFocusNode.unfocus();
    }
  }

  void _beginEditingTextOverlay(
    _MediaComposerTextOverlay overlay, {
    required bool requestKeyboard,
  }) {
    if (!_currentItem.isImage) return;
    setState(() {
      _cropMode = false;
      _drawMode = false;
      _activeTextOverlayId = overlay.id;
      _inlineTextController.value = TextEditingValue(
        text: overlay.text,
        selection: TextSelection.collapsed(offset: overlay.text.length),
      );
    });

    if (requestKeyboard) {
      _requestInlineTextFocus();
    } else {
      _inlineTextFocusNode.unfocus();
    }
  }

  Future<void> _editOverlayText({required bool emojiMode}) async {
    if (!_currentItem.isImage) {
      await _showComingSoon('Bu duzenleme su an sadece fotograflarda acik.');
      return;
    }

    if (emojiMode) {
      final selectedEmoji = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF171A19),
        builder: (sheetContext) {
          const emojis = [
            '🙂',
            '😍',
            '🔥',
            '❤️',
            '👏',
            '🎉',
            '😂',
            '😎',
            '🚀',
            '✨',
            '🤝',
            '🫶',
          ];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final emoji in emojis)
                    InkWell(
                      onTap: () => Navigator.pop(sheetContext, emoji),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF222725),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
      if (selectedEmoji == null || !mounted) return;
      _beginNewTextOverlay(
        initialText: selectedEmoji,
        requestKeyboard: false,
        activateOverlay: false,
      );
      return;
    }

    _beginNewTextOverlay(initialText: '', requestKeyboard: true);
  }

  void _syncActiveTextOverlay(String value) {
    final overlay = _activeTextOverlay;
    if (overlay == null) return;
    setState(() {
      overlay.text = value;
    });
  }

  void _toggleDrawMode() {
    if (!_currentItem.isImage) {
      _showComingSoon('Cizim modu su an sadece fotograflarda acik.');
      return;
    }
    _finishTextEditing();
    setState(() {
      _cropMode = false;
      _drawMode = !_drawMode;
      if (!_drawMode) {
        _eraserMode = false;
      }
    });
  }

  void _setBrushSize(double widthFactor) {
    setState(() {
      _eraserMode = false;
      _brushSizeFactor = widthFactor;
    });
  }

  void _toggleEraser() {
    setState(() {
      _eraserMode = !_eraserMode;
    });
  }

  void _rotateCurrent() {
    if (!_currentItem.isImage) {
      _showComingSoon('Dondurme su an sadece fotograflarda acik.');
      return;
    }
    _finishTextEditing();
    setState(() {
      _currentItem.rotationTurns = (_currentItem.rotationTurns + 1) % 4;
      final preset = _cropPresetForId(_currentWorkingCropPresetId);
      final nextCrop = _cropMode
          ? _cropRectForPreset(
              _currentItem,
              preset,
              center: _currentWorkingCropRect.center,
            )
          : null;
      if (_cropMode) {
        _currentItem.draftCropRectNormalized = nextCrop;
      } else {
        _currentItem.cropRectNormalized = nextCrop;
      }
    });
  }

  void _undoCurrentStroke() {
    if (!_currentItem.isImage || _currentItem.strokes.isEmpty) return;
    setState(() {
      _currentItem.strokes.removeLast();
    });
  }

  Offset _normalizePoint(Offset point, Size size, Rect displayCrop) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx =
        displayCrop.left +
        ((point.dx.clamp(0.0, safeWidth) / safeWidth) * displayCrop.width);
    final dy =
        displayCrop.top +
        ((point.dy.clamp(0.0, safeHeight) / safeHeight) * displayCrop.height);
    return Offset(dx, dy);
  }

  Offset _projectPointToDisplay(Offset point, Rect displayCrop) {
    return Offset(
      ((point.dx - displayCrop.left) / displayCrop.width).toDouble(),
      ((point.dy - displayCrop.top) / displayCrop.height).toDouble(),
    );
  }

  Offset _clampOverlayPosition(Offset position, {Rect? bounds}) {
    final rect = bounds ?? kComposerFullCropRectNormalized;
    final marginX = math.min(0.14, rect.width * 0.14);
    final marginY = math.min(0.12, rect.height * 0.12);
    return Offset(
      position.dx.clamp(rect.left + marginX, rect.right - marginX).toDouble(),
      position.dy.clamp(rect.top + marginY, rect.bottom - marginY).toDouble(),
    );
  }

  void _setMarkupColor(double value) {
    if (!_currentItem.isImage) return;
    final clampedValue = value.clamp(0.0, 1.0).toDouble();
    setState(() {
      _currentItem.markupColorValue = clampedValue;
      final activeOverlay = _activeTextOverlay;
      if (activeOverlay != null) {
        activeOverlay.colorValue = clampedValue;
      }
    });
  }

  void _handleOverlayScaleStart(_MediaComposerTextOverlay overlay) {
    _overlayInteractionBaseScale = overlay.scale;
  }

  void _handleOverlayScaleUpdate(
    _MediaComposerTextOverlay overlay,
    ScaleUpdateDetails details,
    Size size,
    Rect displayCrop,
  ) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final movedPosition = Offset(
      overlay.position.dx +
          ((details.focalPointDelta.dx / safeWidth) * displayCrop.width),
      overlay.position.dy +
          ((details.focalPointDelta.dy / safeHeight) * displayCrop.height),
    );

    setState(() {
      overlay.position = _clampOverlayPosition(
        movedPosition,
        bounds: displayCrop,
      );
      overlay.scale = (_overlayInteractionBaseScale * details.scale)
          .clamp(0.7, 3.2)
          .toDouble();
    });
  }

  void _startStroke(Offset point, Size size, Rect displayCrop) {
    if (!_drawMode || !_currentItem.isImage) return;
    if (_eraserMode) {
      _eraseAtPoint(point, size, displayCrop);
      return;
    }
    setState(() {
      _currentItem.strokes.add(
        _MediaComposerStroke(
          color: _currentItem.markupColor,
          widthFactor: _brushSizeFactor,
          points: [_normalizePoint(point, size, displayCrop)],
        ),
      );
    });
  }

  void _appendStroke(Offset point, Size size, Rect displayCrop) {
    if (!_drawMode || !_currentItem.isImage || _currentItem.strokes.isEmpty) {
      if (_drawMode && _eraserMode && _currentItem.isImage) {
        _eraseAtPoint(point, size, displayCrop);
      }
      return;
    }
    if (_eraserMode) {
      _eraseAtPoint(point, size, displayCrop);
      return;
    }
    setState(() {
      _currentItem.strokes.last.points.add(
        _normalizePoint(point, size, displayCrop),
      );
    });
  }

  void _eraseAtPoint(Offset point, Size size, Rect displayCrop) {
    final target = _normalizePoint(point, size, displayCrop);
    final radius = _brushSizeFactor * 2.2;
    final nextStrokes = <_MediaComposerStroke>[];

    for (final stroke in _currentItem.strokes) {
      final nextSegments = <List<Offset>>[];
      var currentSegment = <Offset>[];
      for (final itemPoint in stroke.points) {
        final shouldErase = (itemPoint - target).distance <= radius;
        if (shouldErase) {
          if (currentSegment.length > 1) {
            nextSegments.add(List<Offset>.from(currentSegment));
          } else if (currentSegment.length == 1) {
            nextSegments.add(List<Offset>.from(currentSegment));
          }
          currentSegment = <Offset>[];
          continue;
        }
        currentSegment.add(itemPoint);
      }

      if (currentSegment.isNotEmpty) {
        nextSegments.add(List<Offset>.from(currentSegment));
      }

      for (final segment in nextSegments) {
        if (segment.isEmpty) continue;
        nextStrokes.add(
          _MediaComposerStroke(
            color: stroke.color,
            widthFactor: stroke.widthFactor,
            points: segment,
          ),
        );
      }
    }

    setState(() {
      _currentItem.strokes
        ..clear()
        ..addAll(nextStrokes);
    });
  }

  void _moveCropRect(DragUpdateDetails details, Size size) {
    final currentCrop = _currentWorkingCropRect;
    if (!_cropMode) return;
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx = details.delta.dx / safeWidth;
    final dy = details.delta.dy / safeHeight;

    setState(() {
      _currentItem.draftCropRectNormalized = _clampCropRect(
        currentCrop.shift(Offset(dx, dy)),
      );
    });
  }

  Rect _buildLockedCropRect({
    required _MediaComposerCropHandle handle,
    required Offset anchor,
    required double width,
    required double aspectRatio,
  }) {
    final height = width / math.max(0.1, aspectRatio);
    switch (handle) {
      case _MediaComposerCropHandle.topLeft:
        return Rect.fromLTRB(
          anchor.dx - width,
          anchor.dy - height,
          anchor.dx,
          anchor.dy,
        );
      case _MediaComposerCropHandle.topRight:
        return Rect.fromLTRB(
          anchor.dx,
          anchor.dy - height,
          anchor.dx + width,
          anchor.dy,
        );
      case _MediaComposerCropHandle.bottomLeft:
        return Rect.fromLTRB(
          anchor.dx - width,
          anchor.dy,
          anchor.dx,
          anchor.dy + height,
        );
      case _MediaComposerCropHandle.bottomRight:
        return Rect.fromLTRB(
          anchor.dx,
          anchor.dy,
          anchor.dx + width,
          anchor.dy + height,
        );
    }
  }

  Rect _clampLockedCropRect({
    required _MediaComposerCropHandle handle,
    required Offset anchor,
    required double desiredWidth,
    required double aspectRatio,
  }) {
    final minHeight = math.max(
      kComposerCropMinSide,
      kComposerCropMinSide / aspectRatio,
    );
    final minWidth = math.max(kComposerCropMinSide, minHeight * aspectRatio);

    late final double maxWidth;
    late final double maxHeight;
    switch (handle) {
      case _MediaComposerCropHandle.topLeft:
        maxWidth = anchor.dx;
        maxHeight = anchor.dy;
        break;
      case _MediaComposerCropHandle.topRight:
        maxWidth = 1 - anchor.dx;
        maxHeight = anchor.dy;
        break;
      case _MediaComposerCropHandle.bottomLeft:
        maxWidth = anchor.dx;
        maxHeight = 1 - anchor.dy;
        break;
      case _MediaComposerCropHandle.bottomRight:
        maxWidth = 1 - anchor.dx;
        maxHeight = 1 - anchor.dy;
        break;
    }

    var width = desiredWidth
        .clamp(minWidth, math.max(minWidth, maxWidth))
        .toDouble();
    var height = width / aspectRatio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspectRatio;
    }
    if (height < minHeight) {
      height = minHeight;
      width = height * aspectRatio;
    }
    width = width.clamp(minWidth, math.max(minWidth, maxWidth)).toDouble();
    height = height.clamp(minHeight, math.max(minHeight, maxHeight)).toDouble();
    return _buildLockedCropRect(
      handle: handle,
      anchor: anchor,
      width: width,
      aspectRatio: aspectRatio,
    );
  }

  void _resizeCropRect(
    _MediaComposerCropHandle handle,
    DragUpdateDetails details,
    Size size,
  ) {
    final currentCrop = _currentWorkingCropRect;
    if (!_cropMode) return;
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx = details.delta.dx / safeWidth;
    final dy = details.delta.dy / safeHeight;
    final lockedAspectRatio = _lockedNormalizedCropAspectRatio(_currentItem);

    if (lockedAspectRatio == null) {
      var next = currentCrop;
      switch (handle) {
        case _MediaComposerCropHandle.topLeft:
          next = Rect.fromLTRB(
            currentCrop.left + dx,
            currentCrop.top + dy,
            currentCrop.right,
            currentCrop.bottom,
          );
          break;
        case _MediaComposerCropHandle.topRight:
          next = Rect.fromLTRB(
            currentCrop.left,
            currentCrop.top + dy,
            currentCrop.right + dx,
            currentCrop.bottom,
          );
          break;
        case _MediaComposerCropHandle.bottomLeft:
          next = Rect.fromLTRB(
            currentCrop.left + dx,
            currentCrop.top,
            currentCrop.right,
            currentCrop.bottom + dy,
          );
          break;
        case _MediaComposerCropHandle.bottomRight:
          next = Rect.fromLTRB(
            currentCrop.left,
            currentCrop.top,
            currentCrop.right + dx,
            currentCrop.bottom + dy,
          );
          break;
      }

      setState(() {
        _currentItem.draftCropRectNormalized = _clampCropRect(next);
      });
      return;
    }

    late final Offset anchor;
    late final double desiredWidth;
    switch (handle) {
      case _MediaComposerCropHandle.topLeft:
        anchor = currentCrop.bottomRight;
        desiredWidth = math.max(
          currentCrop.width - dx,
          (currentCrop.height - dy) * lockedAspectRatio,
        );
        break;
      case _MediaComposerCropHandle.topRight:
        anchor = currentCrop.bottomLeft;
        desiredWidth = math.max(
          currentCrop.width + dx,
          (currentCrop.height - dy) * lockedAspectRatio,
        );
        break;
      case _MediaComposerCropHandle.bottomLeft:
        anchor = currentCrop.topRight;
        desiredWidth = math.max(
          currentCrop.width - dx,
          (currentCrop.height + dy) * lockedAspectRatio,
        );
        break;
      case _MediaComposerCropHandle.bottomRight:
        anchor = currentCrop.topLeft;
        desiredWidth = math.max(
          currentCrop.width + dx,
          (currentCrop.height + dy) * lockedAspectRatio,
        );
        break;
    }

    setState(() {
      _currentItem.draftCropRectNormalized = _clampLockedCropRect(
        handle: handle,
        anchor: anchor,
        desiredWidth: desiredWidth,
        aspectRatio: lockedAspectRatio,
      );
    });
  }

  Future<void> _send() async {
    if (_sending || _items.isEmpty) return;
    if (_cropMode) {
      _applyCropEditing();
    }
    _finishTextEditing();

    setState(() {
      _sending = true;
      _sendingLabel = 'Hazirlaniyor...';
    });

    try {
      final attachments = <OutgoingAttachmentDraft>[];
      for (var index = 0; index < _items.length; index++) {
        final item = _items[index];
        if (mounted) {
          setState(() {
            _sendingLabel = '${index + 1}/${_items.length} yukleniyor';
          });
        }

        final prepared = await _prepareAttachment(item);
        final upload = await ChatApi.createAttachmentUpload(
          widget.session,
          chatId: widget.chat.chatId,
          kind: prepared.kind,
          contentType: prepared.contentType,
          fileName: prepared.fileName,
        );

        final uploadRes = await http.put(
          Uri.parse(upload.uploadUrl),
          headers: upload.headers,
          body: prepared.bytes,
        );
        if (uploadRes.statusCode >= 400) {
          throw TurnaApiException('Dosya yuklenemedi.');
        }

        attachments.add(
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: prepared.kind,
            fileName: prepared.fileName,
            contentType: prepared.contentType,
            sizeBytes: prepared.bytes.length,
            width: prepared.width,
            height: prepared.height,
          ),
        );
      }

      final caption = _captionController.text.trim();
      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: widget.chat.chatId,
        text: caption.isEmpty ? null : caption,
        attachments: attachments,
      );

      await TurnaAnalytics.logEvent('attachment_sent', {
        'chat_id': widget.chat.chatId,
        'quality': _quality.name,
        'count': attachments.length,
        'kind': attachments.length == 1 ? attachments.first.kind.name : 'album',
      });

      if (!mounted) return;
      Navigator.pop(context, message);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingLabel = null;
        });
      }
    }
  }

  Future<_PreparedComposerAttachment> _prepareAttachment(
    _MediaComposerItem item,
  ) async {
    final sourceBytes = await item.file.readAsBytes();

    if (!item.isImage) {
      return _PreparedComposerAttachment(
        kind: item.kind,
        fileName: item.fileName,
        contentType: item.contentType,
        bytes: sourceBytes,
      );
    }

    await _primeImageSize(item);
    return _renderImageAttachment(item, sourceBytes);
  }

  List<_MediaComposerStroke> _transformStrokesForCrop(
    List<_MediaComposerStroke> strokes,
    Rect cropRect,
  ) {
    if (cropRect == kComposerFullCropRectNormalized) return strokes;
    return strokes
        .map(
          (stroke) => _MediaComposerStroke(
            color: stroke.color,
            widthFactor: stroke.widthFactor,
            points: stroke.points
                .map(
                  (point) => Offset(
                    (point.dx - cropRect.left) / cropRect.width,
                    (point.dy - cropRect.top) / cropRect.height,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  List<_MediaComposerTextOverlay> _transformTextOverlaysForCrop(
    List<_MediaComposerTextOverlay> overlays,
    Rect cropRect,
  ) {
    if (cropRect == kComposerFullCropRectNormalized) return overlays;
    return overlays
        .map(
          (overlay) => _MediaComposerTextOverlay(
            id: overlay.id,
            text: overlay.text,
            position: Offset(
              (overlay.position.dx - cropRect.left) / cropRect.width,
              (overlay.position.dy - cropRect.top) / cropRect.height,
            ),
            scale: overlay.scale,
            colorValue: overlay.colorValue,
          ),
        )
        .toList();
  }

  Future<ui.Image> _renderRotatedImage(
    ui.Image sourceImage, {
    required int rotationTurns,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final srcRect = Rect.fromLTWH(
      0,
      0,
      sourceImage.width.toDouble(),
      sourceImage.height.toDouble(),
    );
    final paint = Paint()..isAntiAlias = true;

    switch (rotationTurns % 4) {
      case 1:
        canvas.save();
        canvas.translate(width.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, height.toDouble(), width.toDouble()),
          paint,
        );
        canvas.restore();
        break;
      case 2:
        canvas.save();
        canvas.translate(width.toDouble(), height.toDouble());
        canvas.rotate(math.pi);
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          paint,
        );
        canvas.restore();
        break;
      case 3:
        canvas.save();
        canvas.translate(0, height.toDouble());
        canvas.rotate(-math.pi / 2);
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, height.toDouble(), width.toDouble()),
          paint,
        );
        canvas.restore();
        break;
      default:
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          paint,
        );
    }

    return recorder.endRecording().toImage(width, height);
  }

  Future<_PreparedComposerAttachment> _renderImageAttachment(
    _MediaComposerItem item,
    Uint8List sourceBytes,
  ) async {
    final codec = await ui.instantiateImageCodec(sourceBytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final inputSize = Size(
      sourceImage.width.toDouble(),
      sourceImage.height.toDouble(),
    );
    final rotatedInputSize = item.rotationTurns.isOdd
        ? Size(inputSize.height, inputSize.width)
        : inputSize;
    final rotatedWidth = math.max(1, rotatedInputSize.width.round());
    final rotatedHeight = math.max(1, rotatedInputSize.height.round());
    final rotatedImage = await _renderRotatedImage(
      sourceImage,
      rotationTurns: item.rotationTurns,
      width: rotatedWidth,
      height: rotatedHeight,
    );
    final cropRect = item.cropRectNormalized ?? kComposerFullCropRectNormalized;
    final cropSrcRect = Rect.fromLTWH(
      cropRect.left * rotatedWidth,
      cropRect.top * rotatedHeight,
      cropRect.width * rotatedWidth,
      cropRect.height * rotatedHeight,
    );
    final scaledSize = _scaleToMax(
      cropSrcRect.size,
      _quality.imageMaxDimension,
    );
    final outputWidth = math.max(1, scaledSize.width.round());
    final outputHeight = math.max(1, scaledSize.height.round());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawImageRect(
      rotatedImage,
      cropSrcRect,
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
      paint,
    );

    _paintComposerStrokes(
      canvas,
      size: Size(outputWidth.toDouble(), outputHeight.toDouble()),
      strokes: _transformStrokesForCrop(item.strokes, cropRect),
    );
    _paintComposerTextOverlays(
      canvas,
      size: Size(outputWidth.toDouble(), outputHeight.toDouble()),
      overlays: _transformTextOverlaysForCrop(item.textOverlays, cropRect),
    );

    final rendered = await recorder.endRecording().toImage(
      outputWidth,
      outputHeight,
    );
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw TurnaApiException('Gorsel hazirlanamadi.');
    }
    final encodedImage = img.Image.fromBytes(
      width: outputWidth,
      height: outputHeight,
      bytes: data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final jpgBytes = Uint8List.fromList(
      img.encodeJpg(encodedImage, quality: _quality.jpegQuality),
    );

    return _PreparedComposerAttachment(
      kind: item.kind,
      fileName: replaceFileExtension(item.fileName, 'jpg'),
      contentType: 'image/jpeg',
      bytes: jpgBytes,
      width: outputWidth,
      height: outputHeight,
    );
  }

  Size _scaleToMax(Size size, double maxDimension) {
    final longestSide = math.max(size.width, size.height);
    if (longestSide <= maxDimension) return size;
    final scale = maxDimension / longestSide;
    return Size(size.width * scale, size.height * scale);
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentItem;

    return Scaffold(
      backgroundColor: const Color(0xFF101312),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101312),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _toggleQuality,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: TurnaColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _quality.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Kirp',
            onPressed: _toggleCropMode,
            color: _cropMode ? TurnaColors.primary : null,
            icon: const Icon(Icons.crop_outlined),
          ),
          IconButton(
            tooltip: 'Yazi',
            onPressed: _cropMode
                ? null
                : () => _editOverlayText(emojiMode: false),
            icon: const Icon(Icons.text_fields_outlined),
          ),
          IconButton(
            tooltip: 'Ciz',
            onPressed: _cropMode ? null : _toggleDrawMode,
            color: _drawMode ? TurnaColors.primary : null,
            icon: const Icon(Icons.draw_outlined),
          ),
          IconButton(
            tooltip: 'Emoji',
            onPressed: _cropMode
                ? null
                : () => _editOverlayText(emojiMode: true),
            icon: const Icon(Icons.emoji_emotions_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  children: [
                    if (_drawMode && current.isImage)
                      Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ComposerToolChip(
                                label: 'Ince',
                                selected:
                                    !_eraserMode && _brushSizeFactor == 0.008,
                                onTap: () => _setBrushSize(0.008),
                              ),
                              const SizedBox(width: 8),
                              _ComposerToolChip(
                                label: 'Orta',
                                selected:
                                    !_eraserMode && _brushSizeFactor == 0.011,
                                onTap: () => _setBrushSize(0.011),
                              ),
                              const SizedBox(width: 8),
                              _ComposerToolChip(
                                label: 'Kalin',
                                selected:
                                    !_eraserMode && _brushSizeFactor == 0.016,
                                onTap: () => _setBrushSize(0.016),
                              ),
                              const SizedBox(width: 8),
                              _ComposerToolChip(
                                label: 'Silgi',
                                selected: _eraserMode,
                                onTap: _toggleEraser,
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _undoCurrentStroke,
                                child: const Text('Geri al'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        physics: _cropMode
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        itemCount: _items.length,
                        onPageChanged: (index) {
                          _finishTextEditing();
                          setState(() {
                            _selectedIndex = index;
                            _cropMode = false;
                            _drawMode = false;
                            _eraserMode = false;
                            for (final item in _items) {
                              item.draftCropRectNormalized = null;
                              item.draftCropPresetId = null;
                            }
                          });
                        },
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _buildPreviewPage(item);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_items.length > 1)
              SizedBox(
                height: 92,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  scrollDirection: Axis.horizontal,
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final selected = index == _selectedIndex;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: item.isImage
                              ? Image.file(
                                  File(item.file.path),
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: const Color(0xFF1F2322),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.videocam_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_cropMode && current.isImage)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 16, 10),
                child: Row(
                  children: [
                    _ComposerOverlayPillButton(
                      icon: Icons.rotate_90_degrees_ccw_outlined,
                      onTap: _rotateCurrent,
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<String>(
                      initialValue: _currentWorkingCropPresetId,
                      onSelected: (value) =>
                          _applyCropPreset(_cropPresetForId(value)),
                      color: const Color(0xFF1A1F1D),
                      itemBuilder: (_) => _kComposerCropPresets
                          .map(
                            (preset) => PopupMenuItem<String>(
                              value: preset.id,
                              child: Text(
                                preset.label,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC1A1F1D),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.crop_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _cropPresetForId(
                                _currentWorkingCropPresetId,
                              ).label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _cancelCropEditing,
                      child: const Text(
                        'Iptal',
                        style: TextStyle(color: Color(0xFFB7BCB9)),
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: TurnaColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _applyCropEditing,
                      child: const Text('Tamam'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Aciklama ekle',
                        hintStyle: const TextStyle(color: Color(0xFF7C8380)),
                        filled: true,
                        fillColor: const Color(0xFF162033),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_sendingLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _sendingLabel!,
                            style: const TextStyle(
                              color: Color(0xFFB8BFBC),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      FloatingActionButton.small(
                        backgroundColor: TurnaColors.primary,
                        onPressed: _sending ? null : _send,
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPage(_MediaComposerItem item) {
    if (!item.isImage) {
      return Center(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF181D1C),
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.videocam_outlined,
                size: 56,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(
                item.fileName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatBytesLabel(item.sizeBytes),
                style: const TextStyle(color: Color(0xFFB8BFBC), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCurrent = identical(item, _currentItem);
        final isCropingCurrent = isCurrent && _cropMode;
        final activeOverlay = isCurrent ? _activeTextOverlay : null;
        final displayCrop = isCropingCurrent
            ? kComposerFullCropRectNormalized
            : _displayCropRectFor(item);
        final aspectRatio = _effectiveAspectRatioFor(item, displayCrop);
        var width = constraints.maxWidth;
        var height = width / aspectRatio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * aspectRatio;
        }
        final canvasSize = Size(width, height);
        final transformedStrokes = _transformStrokesForCrop(
          item.strokes,
          displayCrop,
        );
        final cropRect = isCropingCurrent
            ? _currentWorkingCropRect
            : (item.cropRectNormalized ?? _defaultCropRectFor(item));
        final cropFrame = _normalizedCropToRect(cropRect, canvasSize);

        final Widget imageLayer;
        if (displayCrop == kComposerFullCropRectNormalized) {
          imageLayer = RotatedBox(
            quarterTurns: item.rotationTurns,
            child: Image.file(File(item.file.path), fit: BoxFit.fill),
          );
        } else {
          final expandedWidth = width / displayCrop.width;
          final expandedHeight = height / displayCrop.height;
          imageLayer = ClipRect(
            child: Transform.translate(
              offset: Offset(
                -(displayCrop.left * expandedWidth),
                -(displayCrop.top * expandedHeight),
              ),
              child: SizedBox(
                width: expandedWidth,
                height: expandedHeight,
                child: RotatedBox(
                  quarterTurns: item.rotationTurns,
                  child: Image.file(File(item.file.path), fit: BoxFit.fill),
                ),
              ),
            ),
          );
        }

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _drawMode
                ? (details) => _startStroke(
                    details.localPosition,
                    canvasSize,
                    displayCrop,
                  )
                : null,
            onPanUpdate: _drawMode
                ? (details) => _appendStroke(
                    details.localPosition,
                    canvasSize,
                    displayCrop,
                  )
                : null,
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageLayer,
                    if (isCurrent && _activeTextOverlay != null)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _finishTextEditing,
                          child: Container(color: Colors.black45),
                        ),
                      ),
                    for (final overlay in item.textOverlays)
                      Builder(
                        builder: (_) {
                          final displayPosition = _projectPointToDisplay(
                            overlay.position,
                            displayCrop,
                          );
                          return Align(
                            alignment: Alignment(
                              (displayPosition.dx * 2) - 1,
                              (displayPosition.dy * 2) - 1,
                            ),
                            child:
                                isCurrent && overlay.id == _activeTextOverlayId
                                ? ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: width * 0.82,
                                    ),
                                    child: TextField(
                                      controller: _inlineTextController,
                                      focusNode: _inlineTextFocusNode,
                                      autofocus: false,
                                      maxLines: 4,
                                      minLines: 1,
                                      textAlign: TextAlign.center,
                                      cursorColor: overlay.color,
                                      style: TextStyle(
                                        color: overlay.color,
                                        fontWeight: FontWeight.w700,
                                        fontSize:
                                            math.max(18, width * 0.06) *
                                            overlay.scale,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 10,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onChanged: _syncActiveTextOverlay,
                                      onSubmitted: (_) => _finishTextEditing(),
                                    ),
                                  )
                                : GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: _drawMode || _cropMode
                                        ? null
                                        : () => _beginEditingTextOverlay(
                                            overlay,
                                            requestKeyboard: true,
                                          ),
                                    onScaleStart: _drawMode || _cropMode
                                        ? null
                                        : (_) =>
                                              _handleOverlayScaleStart(overlay),
                                    onScaleUpdate: _drawMode || _cropMode
                                        ? null
                                        : (details) =>
                                              _handleOverlayScaleUpdate(
                                                overlay,
                                                details,
                                                canvasSize,
                                                displayCrop,
                                              ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: width * 0.82,
                                      ),
                                      child: Text(
                                        overlay.text,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: overlay.color,
                                          fontWeight: FontWeight.w700,
                                          fontSize:
                                              math.max(18, width * 0.06) *
                                              overlay.scale,
                                          shadows: const [
                                            Shadow(
                                              color: Colors.black54,
                                              blurRadius: 10,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _MediaComposerStrokePainter(
                          strokes: transformedStrokes,
                        ),
                      ),
                    ),
                    if (isCurrent && _cropMode)
                      Positioned.fill(
                        child: _ComposerCropOverlay(
                          cropFrame: cropFrame,
                          onMove: (details) =>
                              _moveCropRect(details, canvasSize),
                          onResize: (handle, details) =>
                              _resizeCropRect(handle, details, canvasSize),
                        ),
                      ),
                    if (isCurrent && (_drawMode || activeOverlay != null))
                      Positioned(
                        right: 12,
                        top: 16,
                        bottom: 16,
                        child: _ComposerColorSlider(
                          value:
                              activeOverlay?.colorValue ??
                              item.markupColorValue,
                          color: activeOverlay?.color ?? item.markupColor,
                          onChanged: _setMarkupColor,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ComposerColorSlider extends StatelessWidget {
  const _ComposerColorSlider({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  void _updateFromOffset(Offset localPosition, double height) {
    final safeHeight = height <= 0 ? 1.0 : height;
    onChanged((localPosition.dy / safeHeight).clamp(0.0, 1.0).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _updateFromOffset(details.localPosition, trackHeight),
          onVerticalDragStart: (details) =>
              _updateFromOffset(details.localPosition, trackHeight),
          onVerticalDragUpdate: (details) =>
              _updateFromOffset(details.localPosition, trackHeight),
          child: SizedBox(
            width: 34,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: 16,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: kComposerPaletteStops,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                ),
                Positioned(
                  top: (trackHeight - 24) * value.clamp(0.0, 1.0).toDouble(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ComposerCropOverlay extends StatelessWidget {
  const _ComposerCropOverlay({
    required this.cropFrame,
    required this.onMove,
    required this.onResize,
  });

  final Rect cropFrame;
  final ValueChanged<DragUpdateDetails> onMove;
  final void Function(
    _MediaComposerCropHandle handle,
    DragUpdateDetails details,
  )
  onResize;

  @override
  Widget build(BuildContext context) {
    const handleSize = 30.0;
    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ComposerCropOverlayPainter(cropFrame: cropFrame),
          ),
        ),
        Positioned.fromRect(
          rect: cropFrame,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: onMove,
            child: const SizedBox.expand(),
          ),
        ),
        _buildHandle(
          center: cropFrame.topLeft,
          handle: _MediaComposerCropHandle.topLeft,
          handleSize: handleSize,
        ),
        _buildHandle(
          center: cropFrame.topRight,
          handle: _MediaComposerCropHandle.topRight,
          handleSize: handleSize,
        ),
        _buildHandle(
          center: cropFrame.bottomLeft,
          handle: _MediaComposerCropHandle.bottomLeft,
          handleSize: handleSize,
        ),
        _buildHandle(
          center: cropFrame.bottomRight,
          handle: _MediaComposerCropHandle.bottomRight,
          handleSize: handleSize,
        ),
      ],
    );
  }

  Widget _buildHandle({
    required Offset center,
    required _MediaComposerCropHandle handle,
    required double handleSize,
  }) {
    return Positioned(
      left: center.dx - (handleSize / 2),
      top: center.dy - (handleSize / 2),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) => onResize(handle, details),
        child: Container(
          width: handleSize,
          height: handleSize,
          alignment: Alignment.center,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF101312), width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerCropOverlayPainter extends CustomPainter {
  const _ComposerCropOverlayPainter({required this.cropFrame});

  final Rect cropFrame;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(cropFrame);
    final overlay = Path.combine(PathOperation.difference, outer, inner);

    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );
    canvas.drawRect(
      cropFrame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final thirdWidth = cropFrame.width / 3;
    final thirdHeight = cropFrame.height / 3;

    for (var index = 1; index <= 2; index++) {
      final dx = cropFrame.left + (thirdWidth * index);
      canvas.drawLine(
        Offset(dx, cropFrame.top),
        Offset(dx, cropFrame.bottom),
        gridPaint,
      );

      final dy = cropFrame.top + (thirdHeight * index);
      canvas.drawLine(
        Offset(cropFrame.left, dy),
        Offset(cropFrame.right, dy),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ComposerCropOverlayPainter oldDelegate) {
    return oldDelegate.cropFrame != cropFrame;
  }
}

class _ComposerOverlayPillButton extends StatelessWidget {
  const _ComposerOverlayPillButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB81A1F1D),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _ComposerToolChip extends StatelessWidget {
  const _ComposerToolChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? TurnaColors.primary : const Color(0xFF162033),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaComposerItem {
  _MediaComposerItem({
    required this.kind,
    required this.file,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
  });

  factory _MediaComposerItem.fromSeed(MediaComposerSeed seed) {
    return _MediaComposerItem(
      kind: seed.kind,
      file: seed.file,
      fileName: seed.fileName,
      contentType: seed.contentType,
      sizeBytes: seed.sizeBytes,
    );
  }

  final ChatAttachmentKind kind;
  final XFile file;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final List<_MediaComposerStroke> strokes = [];
  final List<_MediaComposerTextOverlay> textOverlays = [];
  Rect? cropRectNormalized;
  Rect? draftCropRectNormalized;
  String cropPresetId = 'original';
  String? draftCropPresetId;
  double markupColorValue = 0;
  int rotationTurns = 0;
  Size? sourceSize;

  bool get isImage => kind == ChatAttachmentKind.image;

  Color get markupColor => composerColorForValue(markupColorValue);

  bool get hasMarkup =>
      rotationTurns != 0 ||
      strokes.isNotEmpty ||
      textOverlays.isNotEmpty ||
      (cropRectNormalized != null &&
          cropRectNormalized != kComposerFullCropRectNormalized);

  double get effectiveAspectRatio {
    final base = sourceSize ?? const Size(1, 1);
    final width = rotationTurns.isOdd ? base.height : base.width;
    final height = rotationTurns.isOdd ? base.width : base.height;
    return math.max(0.1, width / math.max(0.1, height));
  }
}

class _MediaComposerTextOverlay {
  _MediaComposerTextOverlay({
    required this.id,
    required this.text,
    required this.position,
    required this.scale,
    required this.colorValue,
  });

  final String id;
  String text;
  Offset position;
  double scale;
  double colorValue;

  Color get color => composerColorForValue(colorValue);
}

class _MediaComposerStroke {
  _MediaComposerStroke({
    required this.color,
    required this.points,
    required this.widthFactor,
  });

  final Color color;
  final List<Offset> points;
  final double widthFactor;
}

class _PreparedComposerAttachment {
  _PreparedComposerAttachment({
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.bytes,
    this.width,
    this.height,
  });

  final ChatAttachmentKind kind;
  final String fileName;
  final String contentType;
  final Uint8List bytes;
  final int? width;
  final int? height;
}

class _MediaComposerStrokePainter extends CustomPainter {
  const _MediaComposerStrokePainter({required this.strokes});

  final List<_MediaComposerStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    _paintComposerStrokes(canvas, size: size, strokes: strokes);
  }

  @override
  bool shouldRepaint(covariant _MediaComposerStrokePainter oldDelegate) {
    return true;
  }
}

void _paintComposerStrokes(
  Canvas canvas, {
  required Size size,
  required List<_MediaComposerStroke> strokes,
}) {
  for (final stroke in strokes) {
    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3, size.shortestSide * stroke.widthFactor);
    if (stroke.points.isEmpty) continue;
    if (stroke.points.length == 1) {
      final point = Offset(
        stroke.points.first.dx * size.width,
        stroke.points.first.dy * size.height,
      );
      canvas.drawCircle(point, paint.strokeWidth * 0.5, paint);
      continue;
    }

    final path = Path();
    final first = stroke.points.first;
    path.moveTo(first.dx * size.width, first.dy * size.height);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }
}

void _paintComposerTextOverlays(
  Canvas canvas, {
  required Size size,
  required List<_MediaComposerTextOverlay> overlays,
}) {
  for (final overlay in overlays) {
    final value = overlay.text.trim();
    if (value.isEmpty) continue;

    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: overlay.color,
          fontWeight: FontWeight.w700,
          fontSize: math.max(28, size.width * 0.06) * overlay.scale,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2)),
          ],
        ),
      ),
    )..layout(maxWidth: size.width * 0.82);

    final marginX = size.width * 0.04;
    final marginY = size.height * 0.04;
    final left = (size.width * overlay.position.dx) - (painter.width / 2);
    final top = (size.height * overlay.position.dy) - (painter.height / 2);

    painter.paint(
      canvas,
      Offset(
        left.clamp(marginX, size.width - painter.width - marginX).toDouble(),
        top.clamp(marginY, size.height - painter.height - marginY).toDouble(),
      ),
    );
  }
}

class NewChatPage extends StatefulWidget {
  const NewChatPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatUser> _users = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await ChatApi.fetchDirectory(widget.session);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchController.text.trim().toLowerCase();
    final filtered = _users.where((u) {
      if (q.isEmpty) return true;
      return u.displayName.toLowerCase().contains(q) ||
          u.id.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Sohbet')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Isim veya kullanici ID ara',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: TurnaColors.backgroundMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _CenteredState(
                    icon: _error!.contains('Oturum')
                        ? Icons.lock_outline
                        : Icons.person_search_outlined,
                    title: _error!.contains('Oturum')
                        ? 'Oturumun suresi doldu'
                        : 'Kisi listesi yuklenemedi',
                    message: _error!,
                    primaryLabel: _error!.contains('Oturum')
                        ? 'Yeniden giris yap'
                        : 'Tekrar dene',
                    onPrimary: _error!.contains('Oturum')
                        ? widget.onSessionExpired
                        : _loadDirectory,
                  )
                : filtered.isEmpty
                ? _CenteredState(
                    icon: _users.isEmpty
                        ? Icons.group_outlined
                        : Icons.search_off,
                    title: _users.isEmpty
                        ? 'Henuz baska kullanici yok'
                        : 'Sonuc bulunamadi',
                    message: _users.isEmpty
                        ? 'Diger kullanicilar kayit oldukca burada listelenecek.'
                        : '"${_searchController.text.trim()}" icin eslesen kisi yok.',
                    primaryLabel: _users.isEmpty ? 'Yenile' : 'Aramayi temizle',
                    onPrimary: _users.isEmpty
                        ? _loadDirectory
                        : _searchController.clear,
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      return ListTile(
                        leading: _ProfileAvatar(
                          label: user.displayName,
                          avatarUrl: user.avatarUrl,
                          authToken: widget.session.token,
                          radius: 22,
                        ),
                        title: Text(user.displayName),
                        subtitle: Text(user.id),
                        onTap: () async {
                          final chat = ChatPreview(
                            chatId: ChatApi.buildDirectChatId(
                              widget.session.userId,
                              user.id,
                            ),
                            name: user.displayName,
                            message: '',
                            time: '',
                            avatarUrl: user.avatarUrl,
                          );
                          await Navigator.push(
                            context,
                            buildChatRoomRoute(
                              chat: chat,
                              session: widget.session,
                              callCoordinator: widget.callCoordinator,
                              onSessionExpired: widget.onSessionExpired,
                            ),
                          );
                          if (!mounted) return;
                          Navigator.of(this.context).pop(true);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.session,
    required this.onSessionUpdated,
    required this.onLogout,
  });

  final AuthSession session;
  final void Function(AuthSession session) onSessionUpdated;
  final VoidCallback onLogout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<TurnaUserProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = ProfileApi.fetchMe(widget.session);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.userId != widget.session.userId ||
        oldWidget.session.token != widget.session.token) {
      _profileFuture = ProfileApi.fetchMe(widget.session);
    }
  }

  void _reloadProfile() {
    setState(() {
      _profileFuture = ProfileApi.fetchMe(widget.session);
    });
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    _reloadProfile();
  }

  Future<void> _openProfileEditor() async {
    await _openPage(
      ProfilePage(
        session: widget.session,
        onProfileUpdated: widget.onSessionUpdated,
      ),
    );
  }

  Widget _buildSectionPanel(List<_SettingsMenuAction> actions) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 0,
              ),
              leading: Icon(
                actions[index].icon,
                color: TurnaColors.textMuted,
                size: 21,
              ),
              title: Text(
                actions[index].label,
                style: TextStyle(
                  color: TurnaColors.text,
                  fontSize: 16.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: Colors.black.withValues(alpha: 0.34),
              ),
              onTap: actions[index].onTap,
            ),
            if (index != actions.length - 1)
              const Divider(height: 1, indent: 58, endIndent: 18),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      body: SafeArea(
        child: FutureBuilder<TurnaUserProfile>(
          future: _profileFuture,
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final about = profile?.about?.trim();
            final subtitle = (about != null && about.isNotEmpty)
                ? about
                : '@${widget.session.userId}';

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.search_rounded, size: 23),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ayarlar',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: TurnaColors.text,
                  ),
                ),
                const SizedBox(height: 14),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: _openProfileEditor,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _SessionAvatar(session: widget.session, radius: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.session.displayName,
                                  style: const TextStyle(
                                    fontSize: 17.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF131716),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: TurnaColors.backgroundSoft,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.edit_note_rounded,
                                        size: 14,
                                        color: TurnaColors.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: TurnaColors.textMuted,
                                            fontSize: 13.2,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.black.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (snapshot.hasError) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      snapshot.error.toString(),
                      style: const TextStyle(
                        color: Color(0xFFC0392B),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _buildSectionPanel([
                  _SettingsMenuAction(
                    icon: Icons.campaign_outlined,
                    label: 'Reklam yayinlayin',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Reklam yayinlayin'),
                    ),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.storefront_outlined,
                    label: 'Isletme araclari',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Isletme araclari'),
                    ),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.verified_outlined,
                    label: 'Meta Verified',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Meta Verified'),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _buildSectionPanel([
                  _SettingsMenuAction(
                    icon: Icons.star_border_rounded,
                    label: 'Yildizli',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Yildizli')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.campaign_outlined,
                    label: 'Toplu mesaj listeleri',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Toplu mesaj listeleri'),
                    ),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.groups_outlined,
                    label: 'Topluluklar',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Topluluklar')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.devices_outlined,
                    label: 'Bagli cihazlar',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Bagli cihazlar'),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _buildSectionPanel([
                  _SettingsMenuAction(
                    icon: Icons.key_outlined,
                    label: 'Hesap',
                    onTap: () => _openPage(const AccountPage()),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.lock_outline_rounded,
                    label: 'Gizlilik',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Gizlilik')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Sohbetler',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Sohbetler')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.notifications_none_rounded,
                    label: 'Bildirimler',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Bildirimler')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.receipt_long_outlined,
                    label: 'Siparisler',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Siparisler')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.swap_vert_rounded,
                    label: 'Depolama ve veriler',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Depolama ve veriler'),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _buildSectionPanel([
                  _SettingsMenuAction(
                    icon: Icons.help_outline_rounded,
                    label: 'Yardim ve geri bildirim',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Yardim ve geri bildirim'),
                    ),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'Kisileri davet edin',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Kisileri davet edin'),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cikis yap'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE25241),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SessionAvatar extends StatelessWidget {
  const _SessionAvatar({required this.session, this.radius = 25});

  final AuthSession session;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return _ProfileAvatar(
      label: session.displayName,
      avatarUrl: session.avatarUrl,
      authToken: session.token,
      radius: radius,
    );
  }
}

class _BottomProfileTabIcon extends StatelessWidget {
  const _BottomProfileTabIcon({required this.session, this.selected = false});

  final AuthSession session;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? TurnaColors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: _SessionAvatar(session: session, radius: 11),
    );
  }
}

class _SettingsMenuAction {
  const _SettingsMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _TurnaBottomBar extends StatelessWidget {
  const _TurnaBottomBar({
    required this.selectedIndex,
    required this.unreadChats,
    required this.session,
    required this.onSelect,
  });

  final int selectedIndex;
  final int unreadChats;
  final AuthSession session;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Durum',
                selected: selectedIndex == 0,
                iconBuilder: (selected) => Icon(
                  Icons.circle_outlined,
                  size: 22,
                  color: selected ? TurnaColors.primary : TurnaColors.textMuted,
                ),
                onTap: () => onSelect(0),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Aramalar',
                selected: selectedIndex == 1,
                iconBuilder: (selected) => Icon(
                  Icons.call_outlined,
                  size: 22,
                  color: selected ? TurnaColors.primary : TurnaColors.textMuted,
                ),
                onTap: () => onSelect(1),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Araçlar',
                selected: selectedIndex == 2,
                iconBuilder: (selected) => Icon(
                  Icons.business_center_outlined,
                  size: 22,
                  color: selected ? TurnaColors.primary : TurnaColors.textMuted,
                ),
                onTap: () => onSelect(2),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Sohbetler',
                selected: selectedIndex == 3,
                iconBuilder: (selected) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 22,
                      color: selected
                          ? TurnaColors.primary
                          : TurnaColors.textMuted,
                    ),
                    if (unreadChats > 0)
                      Positioned(
                        right: -18,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          constraints: const BoxConstraints(minWidth: 24),
                          decoration: BoxDecoration(
                            color: TurnaColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unreadChats > 999 ? '999+' : '$unreadChats',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () => onSelect(3),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Siz',
                selected: selectedIndex == 4,
                iconBuilder: (selected) =>
                    _BottomProfileTabIcon(session: session, selected: selected),
                onTap: () => onSelect(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnaBottomBarItem extends StatelessWidget {
  const _TurnaBottomBarItem({
    required this.label,
    required this.selected,
    required this.iconBuilder,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Widget Function(bool selected) iconBuilder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? TurnaColors.primary : TurnaColors.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 28, child: Center(child: iconBuilder(selected))),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.label,
    required this.radius,
    this.avatarUrl,
    this.authToken,
  });

  final String label;
  final String? avatarUrl;
  final String? authToken;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = avatarUrl?.trim() ?? '';
    if (trimmedUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: TurnaColors.primary100,
        backgroundImage: NetworkImage(
          trimmedUrl,
          headers: authToken == null || authToken!.trim().isEmpty
              ? null
              : {'Authorization': 'Bearer ${authToken!.trim()}'},
        ),
      );
    }

    final safeLabel = label.trim();
    final initial = safeLabel.isEmpty
        ? '?'
        : safeLabel.characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: TurnaColors.primary100,
      child: Text(
        initial,
        style: TextStyle(
          color: TurnaColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.65,
        ),
      ),
    );
  }
}

Future<void> _openAvatarViewer(
  BuildContext context, {
  required String imageUrl,
  required String title,
  required String token,
}) async {
  final trimmedUrl = imageUrl.trim();
  if (trimmedUrl.isEmpty) return;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          AvatarViewerPage(imageUrl: trimmedUrl, title: title, token: token),
    ),
  );
}

class AvatarViewerPage extends StatelessWidget {
  const AvatarViewerPage({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.token,
  });

  final String imageUrl;
  final String title;
  final String token;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(
          child: Image.network(
            imageUrl,
            headers: {'Authorization': 'Bearer $token'},
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Gorsel yuklenemedi.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.session,
    required this.onProfileUpdated,
  });

  final AuthSession session;
  final void Function(AuthSession session) onProfileUpdated;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _displayNameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  TurnaUserProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _avatarBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_refreshPreview);
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.removeListener(_refreshPreview);
    _displayNameController.dispose();
    _aboutController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await ProfileApi.fetchMe(widget.session);
      final updatedSession = widget.session.copyWith(
        displayName: profile.displayName,
        avatarUrl: profile.avatarUrl,
        clearAvatarUrl: profile.avatarUrl == null,
      );
      await updatedSession.save();
      if (!mounted) return;
      _applyProfile(profile);
      setState(() {
        _profile = profile;
        _loading = false;
      });
      widget.onProfileUpdated(updatedSession);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _applyProfile(TurnaUserProfile profile) {
    _displayNameController.text = profile.displayName;
    _aboutController.text = profile.about ?? '';
    _phoneController.text = profile.phone ?? '';
    _emailController.text = profile.email ?? '';
  }

  Future<void> _commitProfile(
    TurnaUserProfile updatedProfile, {
    String? successMessage,
  }) async {
    _applyProfile(updatedProfile);
    setState(() {
      _profile = updatedProfile;
    });

    final updatedSession = widget.session.copyWith(
      displayName: updatedProfile.displayName,
      avatarUrl: updatedProfile.avatarUrl,
      clearAvatarUrl: updatedProfile.avatarUrl == null,
    );
    await updatedSession.save();
    widget.onProfileUpdated(updatedSession);
    await TurnaAnalytics.logEvent('profile_updated', {
      'user_id': updatedSession.userId,
    });

    if (!mounted || successMessage == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  String? _guessImageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return null;
  }

  Future<void> _pickAvatar() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1400,
    );
    if (file == null) return;

    final contentType = _guessImageContentType(file.name);
    if (contentType == null) {
      setState(() => _error = 'Desteklenmeyen görsel formatı.');
      return;
    }

    setState(() {
      _avatarBusy = true;
      _error = null;
    });

    try {
      final upload = await ProfileApi.createAvatarUpload(
        widget.session,
        contentType: contentType,
        fileName: file.name,
      );

      final bytes = await file.readAsBytes();
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Avatar yüklenemedi.');
      }

      final updatedProfile = await ProfileApi.completeAvatarUpload(
        widget.session,
        objectKey: upload.objectKey,
      );
      if (!mounted) return;
      await _commitProfile(
        updatedProfile,
        successMessage: 'Avatar güncellendi.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    setState(() {
      _avatarBusy = true;
      _error = null;
    });

    try {
      final updatedProfile = await ProfileApi.deleteAvatar(widget.session);
      if (!mounted) return;
      await _commitProfile(
        updatedProfile,
        successMessage: 'Avatar kaldırıldı.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.length < 2) {
      setState(() => _error = 'Ad en az 2 karakter olmalı.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updatedProfile = await ProfileApi.updateMe(
        widget.session,
        displayName: displayName,
        about: _aboutController.text,
        phone: _phoneController.text,
        email: _emailController.text,
      );
      if (!mounted) return;

      await _commitProfile(
        updatedProfile,
        successMessage: 'Profil güncellendi.',
      );
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (_loading && profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Profil yüklenemedi.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadProfile,
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: () {
                final avatarUrl = profile.avatarUrl ?? widget.session.avatarUrl;
                if (avatarUrl == null || avatarUrl.trim().isEmpty) return;
                _openAvatarViewer(
                  context,
                  imageUrl: avatarUrl,
                  title: _displayNameController.text.trim().isEmpty
                      ? widget.session.displayName
                      : _displayNameController.text.trim(),
                  token: widget.session.token,
                );
              },
              child: _ProfileAvatar(
                label: _displayNameController.text.trim().isEmpty
                    ? widget.session.displayName
                    : _displayNameController.text.trim(),
                avatarUrl: profile.avatarUrl ?? widget.session.avatarUrl,
                authToken: widget.session.token,
                radius: 58,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: (_saving || _avatarBusy) ? null : _pickAvatar,
                icon: _avatarBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(_avatarBusy ? 'Yükleniyor...' : 'Galeriden seç'),
              ),
              if ((profile.avatarUrl ?? widget.session.avatarUrl) != null)
                OutlinedButton.icon(
                  onPressed: (_saving || _avatarBusy) ? null : _removeAvatar,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Fotoğrafı kaldır'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _displayNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Ad',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _aboutController,
            maxLines: 3,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: 'Hakkında',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Telefon',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: (_saving || _avatarBusy) ? null : _saveProfile,
            child: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: (_saving || _avatarBusy) ? null : _loadProfile,
            child: const Text('Sunucudan yenile'),
          ),
        ],
      ),
    );
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.session,
    required this.userId,
    required this.fallbackName,
    this.fallbackAvatarUrl,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String userId;
  final String fallbackName;
  final String? fallbackAvatarUrl;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  TurnaUserProfile? _profile;
  _UserConversationStats? _conversationStats;
  bool _loading = true;
  bool _statsLoading = true;
  bool _chatLockEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    await Future.wait([_loadProfile(), _loadConversationStats()]);
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await ProfileApi.fetchUser(widget.session, widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadConversationStats() async {
    final chatId = ChatApi.buildDirectChatId(
      widget.session.userId,
      widget.userId,
    );
    if (mounted) {
      setState(() {
        _statsLoading = true;
      });
    }

    try {
      final allMessages = <ChatMessage>[];
      String? before;
      var hasMore = true;

      while (hasMore) {
        final page = await ChatApi.fetchMessagesPage(
          widget.session.token,
          chatId,
          before: before,
          limit: 100,
        );
        allMessages.addAll(page.items);
        hasMore = page.hasMore;
        before = page.nextBefore;
        if (page.items.isEmpty) break;
      }

      var attachmentCount = 0;
      var totalBytes = 0;
      for (final message in allMessages) {
        totalBytes += utf8.encode(message.text).length;
        for (final attachment in message.attachments) {
          attachmentCount += 1;
          totalBytes += attachment.sizeBytes;
        }
      }

      if (!mounted) return;
      setState(() {
        _conversationStats = _UserConversationStats(
          attachmentCount: attachmentCount,
          totalBytes: totalBytes,
        );
        _statsLoading = false;
      });
    } catch (error) {
      turnaLog('user profile conversation stats failed', {
        'userId': widget.userId,
        'error': error.toString(),
      });
      if (!mounted) return;
      setState(() {
        _statsLoading = false;
      });
    }
  }

  Future<void> _startCall(TurnaCallType type) async {
    try {
      final started = await CallApi.startCall(
        widget.session,
        calleeId: widget.userId,
        type: type,
      );
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OutgoingCallPage(
            session: widget.session,
            coordinator: widget.callCoordinator,
            initialCall: started,
            onSessionExpired: widget.onSessionExpired,
          ),
        ),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showPlaceholderAction(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label yakinda eklenecek.')));
  }

  String _formatConversationCount() {
    if (_statsLoading) return '...';
    return '${_conversationStats?.attachmentCount ?? 0}';
  }

  String _formatConversationStorage() {
    if (_statsLoading) return '...';
    final bytes = _conversationStats?.totalBytes ?? 0;
    return formatBytesLabel(bytes).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final name = profile?.displayName ?? widget.fallbackName;
    final avatarUrl = profile?.avatarUrl ?? widget.fallbackAvatarUrl;

    if (_loading && profile == null) {
      return Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          backgroundColor: TurnaColors.backgroundSoft,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('Kisi bilgisi'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          backgroundColor: TurnaColors.backgroundSoft,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('Kisi bilgisi'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Kullanici profili yuklenemedi.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadProfile,
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final about = profile.about?.trim();
    final phone = profile.phone?.trim();
    final subtitle = about == null || about.isEmpty
        ? 'Merhaba! Ben Turna kullaniyorum.'
        : about;
    final displayedPhone = phone == null || phone.isEmpty
        ? widget.userId
        : phone;

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.backgroundSoft,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Kisi bilgisi',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => _showPlaceholderAction('Duzenle'),
            child: const Text(
              'Duzenle',
              style: TextStyle(
                color: Color(0xFF202124),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Center(
            child: GestureDetector(
              onTap: avatarUrl == null || avatarUrl.trim().isEmpty
                  ? null
                  : () => _openAvatarViewer(
                      context,
                      imageUrl: avatarUrl,
                      title: name,
                      token: widget.session.token,
                    ),
              child: _ProfileAvatar(
                label: name,
                avatarUrl: avatarUrl,
                authToken: widget.session.token,
                radius: 56,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              displayedPhone,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF68706C),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF727A76),
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _UserProfileActionButton(
                  icon: Icons.call_outlined,
                  label: 'Sesli',
                  onTap: () => _startCall(TurnaCallType.audio),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UserProfileActionButton(
                  icon: Icons.videocam_outlined,
                  label: 'Goruntulu',
                  onTap: () => _startCall(TurnaCallType.video),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UserProfileActionButton(
                  icon: Icons.search_outlined,
                  label: 'Ara',
                  onTap: () => _showPlaceholderAction('Sohbet ici arama'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _UserProfileGroupCard(
            children: [
              _UserProfileRow(
                icon: Icons.photo_library_outlined,
                title: 'Medya, baglanti ve belgeler',
                trailingText: _formatConversationCount(),
                onTap: () => _showPlaceholderAction('Medya listesi'),
              ),
              _UserProfileRow(
                icon: Icons.folder_outlined,
                title: 'Depolama alanini yonet',
                trailingText: _formatConversationStorage(),
                onTap: () => _showPlaceholderAction('Depolama alani'),
              ),
              _UserProfileRow(
                icon: Icons.star_border_rounded,
                title: 'Yildizli',
                trailingText: 'Yok',
                onTap: () => _showPlaceholderAction('Yildizli mesajlar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UserProfileGroupCard(
            children: [
              _UserProfileRow(
                icon: Icons.notifications_none_outlined,
                title: 'Bildirimler',
                onTap: () => _showPlaceholderAction('Bildirim ayarlari'),
              ),
              _UserProfileRow(
                icon: Icons.palette_outlined,
                title: 'Sohbet temasi',
                onTap: () => _showPlaceholderAction('Sohbet temasi'),
              ),
              _UserProfileRow(
                icon: Icons.photo_outlined,
                title: "Fotograflar'a Kaydet",
                trailingText: 'Varsayilan',
                onTap: () => _showPlaceholderAction("Fotograflar'a kaydet"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UserProfileGroupCard(
            children: [
              _UserProfileRow(
                icon: Icons.timer_outlined,
                title: 'Sureli mesajlar',
                trailingText: 'Kapali',
                onTap: () => _showPlaceholderAction('Sureli mesajlar'),
              ),
              _UserProfileSwitchRow(
                icon: Icons.lock_outline_rounded,
                title: 'Sohbeti kilitle',
                subtitle: 'Bu sohbeti bu cihazda kilitleyin ve gizleyin.',
                value: _chatLockEnabled,
                onChanged: (value) => setState(() => _chatLockEnabled = value),
              ),
              _UserProfileRow(
                icon: Icons.shield_outlined,
                title: 'Gelismis sohbet gizliligi',
                trailingText: 'Kapali',
                onTap: () =>
                    _showPlaceholderAction('Gelismis sohbet gizliligi'),
              ),
              _UserProfileRow(
                icon: Icons.lock_person_outlined,
                title: 'Sifreleme',
                subtitle: 'Kisisel mesajlar ve aramalar uctan uca sifrelidir.',
                onTap: () => _showPlaceholderAction('Sifreleme bilgisi'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _refreshData,
            style: OutlinedButton.styleFrom(
              foregroundColor: TurnaColors.primary,
              side: const BorderSide(color: Color(0xFFB7D9C4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text('Sunucudan yenile'),
          ),
        ],
      ),
    );
  }
}

class _UserProfileActionButton extends StatelessWidget {
  const _UserProfileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: TurnaColors.primary, size: 23),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF202124),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserConversationStats {
  const _UserConversationStats({
    required this.attachmentCount,
    required this.totalBytes,
  });

  final int attachmentCount;
  final int totalBytes;
}

class _UserProfileGroupCard extends StatelessWidget {
  const _UserProfileGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 54, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _UserProfileRow extends StatelessWidget {
  const _UserProfileRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, size: 22, color: const Color(0xFF2B2F2D)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF202124),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.22,
                  color: Color(0xFF7A817D),
                ),
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(
              trailingText!,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF7A817D),
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF979D99)),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _UserProfileSwitchRow extends StatelessWidget {
  const _UserProfileSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 22, color: const Color(0xFF2B2F2D)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF202124),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.22,
                    color: Color(0xFF7A817D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: TurnaColors.primary,
            activeTrackColor: TurnaColors.primary100,
          ),
        ],
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Security notifications'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SecurityNotificationsPage(),
              ),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.key_outlined),
            title: Text('Passkeys'),
          ),
          const ListTile(
            leading: Icon(Icons.email_outlined),
            title: Text('Email address'),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Two-step verification'),
          ),
          const ListTile(
            leading: Icon(Icons.numbers_outlined),
            title: Text('Change number'),
          ),
          const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('Request account info'),
          ),
          const ListTile(
            leading: Icon(Icons.person_add_alt_outlined),
            title: Text('Add account'),
          ),
          const ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete account'),
          ),
        ],
      ),
    );
  }
}

class SecurityNotificationsPage extends StatefulWidget {
  const SecurityNotificationsPage({super.key});

  @override
  State<SecurityNotificationsPage> createState() =>
      _SecurityNotificationsPageState();
}

class _SecurityNotificationsPageState extends State<SecurityNotificationsPage> {
  bool enabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.lock, size: 54, color: TurnaColors.primary),
          const SizedBox(height: 12),
          const Text(
            'Your chats and calls are private',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'End-to-end encryption keeps your personal messages and calls private between you and your contacts.',
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.message_outlined),
            title: Text('Text and voice messages'),
          ),
          const ListTile(
            leading: Icon(Icons.call_outlined),
            title: Text('Audio and video calls'),
          ),
          const ListTile(
            leading: Icon(Icons.photo_outlined),
            title: Text('photos, videos and documents'),
          ),
          const ListTile(
            leading: Icon(Icons.location_on_outlined),
            title: Text('Location sharing'),
          ),
          const ListTile(
            leading: Icon(Icons.circle_outlined),
            title: Text('Status updates'),
          ),
          SwitchListTile(
            value: enabled,
            onChanged: (v) => setState(() => enabled = v),
            title: const Text('Show Security notifications on this device'),
          ),
        ],
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title is coming in V1 build.')),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF7D8380)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF5C625F)),
            ),
            if (primaryLabel != null && onPrimary != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CenteredListState extends StatelessWidget {
  const _CenteredListState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF7D8380)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5C625F)),
          ),
        ],
      ),
    );
  }
}

class ChatPreview {
  ChatPreview({
    required this.chatId,
    required this.name,
    required this.message,
    required this.time,
    this.avatarUrl,
    this.unreadCount = 0,
  });

  final String chatId;
  final String name;
  final String message;
  final String time;
  final String? avatarUrl;
  final int unreadCount;
}

class ChatUser {
  ChatUser({required this.id, required this.displayName, this.avatarUrl});

  final String id;
  final String displayName;
  final String? avatarUrl;
}

class TurnaUserProfile {
  TurnaUserProfile({
    required this.id,
    required this.displayName,
    this.phone,
    this.email,
    this.about,
    this.avatarUrl,
    this.createdAt,
  });

  final String id;
  final String displayName;
  final String? phone;
  final String? email;
  final String? about;
  final String? avatarUrl;
  final String? createdAt;

  factory TurnaUserProfile.fromMap(Map<String, dynamic> map) {
    return TurnaUserProfile(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      phone: _nullableString(map['phone']),
      email: _nullableString(map['email']),
      about: _nullableString(map['about']),
      avatarUrl: _nullableString(map['avatarUrl']),
      createdAt: _nullableString(map['createdAt']),
    );
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}

enum ChatAttachmentKind { image, video, file }

class ChatAttachment {
  ChatAttachment({
    required this.id,
    required this.objectKey,
    required this.kind,
    required this.contentType,
    required this.sizeBytes,
    this.fileName,
    this.width,
    this.height,
    this.durationSeconds,
    this.url,
  });

  final String id;
  final String objectKey;
  final ChatAttachmentKind kind;
  final String? fileName;
  final String contentType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final String? url;

  factory ChatAttachment.fromMap(Map<String, dynamic> map) {
    final kindText = (map['kind'] ?? '').toString().toLowerCase();
    final kind = switch (kindText) {
      'image' => ChatAttachmentKind.image,
      'video' => ChatAttachmentKind.video,
      _ => ChatAttachmentKind.file,
    };

    return ChatAttachment(
      id: (map['id'] ?? '').toString(),
      objectKey: (map['objectKey'] ?? '').toString(),
      kind: kind,
      fileName: TurnaUserProfile._nullableString(map['fileName']),
      contentType: (map['contentType'] ?? '').toString(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      url: TurnaUserProfile._nullableString(map['url']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'objectKey': objectKey,
      'kind': kind.name,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'width': width,
      'height': height,
      'durationSeconds': durationSeconds,
      'url': url,
    };
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.status,
    required this.createdAt,
    this.attachments = const [],
    this.errorText,
  });

  final String id;
  final String senderId;
  final String text;
  final ChatMessageStatus status;
  final String createdAt;
  final List<ChatAttachment> attachments;
  final String? errorText;

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? text,
    ChatMessageStatus? status,
    String? createdAt,
    List<ChatAttachment>? attachments,
    String? errorText,
    bool clearErrorText = false,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      attachments: attachments ?? this.attachments,
      errorText: clearErrorText ? null : (errorText ?? this.errorText),
    );
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: (map['id'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      status: ChatMessageStatusX.fromWire((map['status'] ?? '').toString()),
      createdAt: (map['createdAt'] ?? '').toString(),
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChatAttachment.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toPendingMap() {
    return {
      'id': id,
      'senderId': senderId,
      'text': text,
      'status': status.name,
      'createdAt': createdAt,
      'attachments': attachments
          .map((attachment) => attachment.toMap())
          .toList(),
      'errorText': errorText,
    };
  }

  factory ChatMessage.fromPendingMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: (map['id'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      status: ChatMessageStatusX.fromLocal((map['status'] ?? '').toString()),
      createdAt: (map['createdAt'] ?? '').toString(),
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChatAttachment.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      errorText: TurnaUserProfile._nullableString(map['errorText']),
    );
  }
}

enum ChatMessageStatus { sending, queued, failed, sent, delivered, read }

extension ChatMessageStatusX on ChatMessageStatus {
  static ChatMessageStatus fromWire(String value) {
    switch (value) {
      case 'delivered':
        return ChatMessageStatus.delivered;
      case 'read':
        return ChatMessageStatus.read;
      default:
        return ChatMessageStatus.sent;
    }
  }

  static ChatMessageStatus fromLocal(String value) {
    switch (value) {
      case 'sending':
        return ChatMessageStatus.sending;
      case 'queued':
        return ChatMessageStatus.queued;
      case 'failed':
        return ChatMessageStatus.failed;
      case 'delivered':
        return ChatMessageStatus.delivered;
      case 'read':
        return ChatMessageStatus.read;
      default:
        return ChatMessageStatus.sent;
    }
  }
}

class ChatMessagesPage {
  ChatMessagesPage({
    required this.items,
    required this.hasMore,
    required this.nextBefore,
  });

  final List<ChatMessage> items;
  final bool hasMore;
  final String? nextBefore;
}

class TurnaSocketClient extends ChangeNotifier {
  TurnaSocketClient({
    required this.chatId,
    required this.senderId,
    this.peerUserId,
    required this.token,
    this.onSessionExpired,
  });

  final String chatId;
  final String senderId;
  final String? peerUserId;
  final String token;
  final VoidCallback? onSessionExpired;

  static const int _pageSize = 30;
  final List<ChatMessage> messages = [];
  final Map<String, Timer> _messageTimeouts = {};
  final Map<String, ChatMessageStatus> _pendingStatusByMessageId = {};
  io.Socket? _socket;
  Timer? _typingPauseTimer;
  Timer? _peerTypingTimeout;
  bool _historyLoadedFromSocket = false;
  bool _restoredPendingMessages = false;
  bool _isFlushingQueue = false;
  bool _localTyping = false;
  int _localMessageSeq = 0;
  bool isConnected = false;
  bool loadingInitial = true;
  bool loadingMore = false;
  bool hasMore = true;
  bool peerOnline = false;
  bool peerTyping = false;
  String? nextBefore;
  String? error;
  String? peerLastSeenAt;

  Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  void connect() {
    loadingInitial = true;
    error = null;
    turnaLog('socket connect start', {
      'chatId': chatId,
      'senderId': senderId,
      'url': kBackendBaseUrl,
    });
    _socket = io.io(
      kBackendBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableForceNew()
          .disableMultiplex()
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      isConnected = true;
      turnaLog('socket connected', {'id': _socket?.id, 'chatId': chatId});
      _socket!.emit('chat:join', {'chatId': chatId});
      if (_localTyping) {
        _emitTyping(true);
      }
      _flushQueuedMessages();
      notifyListeners();
    });

    _socket!.onConnectError((data) {
      isConnected = false;
      turnaLog('socket connect_error', data);
      final raw = '$data';
      if (raw.contains('invalid_token') || raw.contains('unauthorized')) {
        error = 'Oturumun suresi doldu.';
        notifyListeners();
        onSessionExpired?.call();
        return;
      }
      if (messages.isEmpty) {
        error = 'Canli baglanti kurulamadi.';
        loadingInitial = false;
        notifyListeners();
      }
    });

    _socket!.onError((data) {
      turnaLog('socket error', data);
    });

    _socket!.on('error:validation', (data) {
      turnaLog('socket error:validation', data);
    });

    _socket!.on('error:internal', (data) {
      turnaLog('socket error:internal', data);
    });
    _socket!.on('error:forbidden', (data) {
      turnaLog('socket error:forbidden', data);
    });

    _socket!.on('chat:history', (data) {
      if (data is List) {
        _historyLoadedFromSocket = true;
        turnaLog('socket chat:history', {
          'count': data.length,
          'chatId': chatId,
        });
        messages
          ..clear()
          ..addAll(
            data.whereType<Map>().map(
              (e) => _applyPendingStatus(
                ChatMessage.fromMap(Map<String, dynamic>.from(e)),
              ),
            ),
          );
        _sortMessages();
        hasMore = data.length >= _pageSize;
        nextBefore = messages.isEmpty ? null : messages.first.createdAt;
        loadingInitial = false;
        error = null;
        _markSeen();
        _persistPendingMessages();
        notifyListeners();
      }
    });

    _socket!.on('chat:inbox:update', (_) {
      _syncMessagesFromHttp();
    });

    _socket!.on('chat:message', (data) {
      if (data is Map) {
        turnaLog('socket chat:message', data);
        final message = ChatMessage.fromMap(Map<String, dynamic>.from(data));
        final resolvedMessage = _applyPendingStatus(message);
        final existingIndex = messages.indexWhere((m) => m.id == message.id);
        if (existingIndex >= 0) {
          messages[existingIndex] = resolvedMessage;
        } else {
          final index = messages.indexWhere(
            (m) =>
                m.senderId == resolvedMessage.senderId &&
                m.text == resolvedMessage.text &&
                m.id.startsWith('local_'),
          );
          if (index >= 0) {
            _cancelMessageTimeout(messages[index].id);
            messages[index] = resolvedMessage;
          } else {
            messages.add(resolvedMessage);
          }
        }
        _sortMessages();
        _persistPendingMessages();
        if (resolvedMessage.senderId != senderId) {
          _markSeen();
        }
        notifyListeners();
      }
    });

    _socket!.on('chat:status', (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final messageIds = (payload['messageIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toSet();
      if (messageIds.isEmpty) return;

      final status = ChatMessageStatusX.fromWire(
        (payload['status'] ?? '').toString(),
      );
      var changed = false;
      final unresolvedIds = <String>{};
      for (var i = 0; i < messages.length; i++) {
        final current = messages[i];
        if (!messageIds.contains(current.id)) continue;
        final nextStatus = _pickHigherStatus(current.status, status);
        if (current.status == nextStatus) continue;
        messages[i] = current.copyWith(status: nextStatus);
        changed = true;
      }
      for (final messageId in messageIds) {
        if (messages.any((message) => message.id == messageId)) continue;
        unresolvedIds.add(messageId);
      }
      for (final messageId in unresolvedIds) {
        _pendingStatusByMessageId[messageId] = _pickHigherStatus(
          _pendingStatusByMessageId[messageId] ?? ChatMessageStatus.sent,
          status,
        );
      }
      if (changed) {
        turnaLog('socket chat:status', {
          'count': messageIds.length,
          'status': payload['status'],
        });
        notifyListeners();
      }
    });

    _socket!.on('user:presence', (data) {
      final payload = _asMap(data);
      if (payload == null || peerUserId == null) return;

      final userId = (payload['userId'] ?? '').toString();
      if (userId != peerUserId) return;

      final online = payload['online'] == true;
      final lastSeenAt = _nullableString(payload['lastSeenAt']);
      var changed = false;
      if (peerOnline != online) {
        peerOnline = online;
        changed = true;
      }
      if (peerLastSeenAt != lastSeenAt) {
        peerLastSeenAt = lastSeenAt;
        changed = true;
      }
      if (!online && peerTyping) {
        _cancelPeerTypingTimeout();
        peerTyping = false;
        changed = true;
      }
      if (changed) {
        turnaLog('socket user:presence', {
          'chatId': chatId,
          'userId': userId,
          'online': online,
        });
        notifyListeners();
      }
    });

    _socket!.on('chat:typing', (data) {
      final payload = _asMap(data);
      if (payload == null) return;
      if ((payload['chatId'] ?? '').toString() != chatId) return;

      final userId = (payload['userId'] ?? '').toString();
      if (userId.isEmpty || userId == senderId) return;
      if (peerUserId != null && userId != peerUserId) return;

      _setPeerTyping(payload['isTyping'] == true);
    });

    _socket!.onDisconnect((reason) {
      isConnected = false;
      _cancelPeerTypingTimeout();
      peerTyping = false;
      turnaLog('socket disconnected', {'reason': reason, 'chatId': chatId});
      notifyListeners();
    });

    _restorePendingMessages();
    _syncMessagesFromHttp(onlyIfEmpty: true);
    _socket!.connect();
  }

  Future<void> _syncMessagesFromHttp({bool onlyIfEmpty = false}) async {
    try {
      if (_historyLoadedFromSocket && onlyIfEmpty) return;
      final page = await ChatApi.fetchMessagesPage(
        token,
        chatId,
        limit: _pageSize,
      );

      final byId = <String, ChatMessage>{};
      for (final current in messages) {
        byId[current.id] = current;
      }
      for (final serverMessage in page.items) {
        byId[serverMessage.id] = _applyPendingStatus(serverMessage);
      }

      final merged = byId.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      messages
        ..clear()
        ..addAll(merged);
      hasMore = page.hasMore;
      nextBefore =
          page.nextBefore ??
          (messages.isEmpty ? null : messages.first.createdAt);
      loadingInitial = false;
      error = null;
      _markSeen();
      _persistPendingMessages();
      notifyListeners();
    } on TurnaUnauthorizedException catch (authError) {
      loadingInitial = false;
      error = authError.toString();
      notifyListeners();
      onSessionExpired?.call();
    } catch (_) {
      loadingInitial = false;
      if (messages.isEmpty) {
        error = 'Mesajlar yuklenemedi.';
      }
      notifyListeners();
    }
  }

  Future<void> loadOlderMessages() async {
    if (loadingMore || !hasMore || messages.isEmpty) return;

    loadingMore = true;
    notifyListeners();

    try {
      final page = await ChatApi.fetchMessagesPage(
        token,
        chatId,
        before: nextBefore ?? messages.first.createdAt,
        limit: _pageSize,
      );

      final byId = <String, ChatMessage>{};
      for (final current in messages) {
        byId[current.id] = current;
      }
      for (final serverMessage in page.items) {
        byId[serverMessage.id] = _applyPendingStatus(serverMessage);
      }
      final merged = byId.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      messages
        ..clear()
        ..addAll(merged);
      hasMore = page.hasMore;
      nextBefore = page.nextBefore;
    } on TurnaUnauthorizedException catch (authError) {
      error = authError.toString();
      onSessionExpired?.call();
    } catch (_) {
      error = 'Eski mesajlar yuklenemedi.';
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  void _markSeen() {
    _socket?.emit('chat:seen', {'chatId': chatId});
  }

  void updateComposerText(String text) {
    final shouldShowTyping = text.trim().isNotEmpty;
    if (shouldShowTyping) {
      if (!_localTyping) {
        _localTyping = true;
        _emitTyping(true);
      }
      _typingPauseTimer?.cancel();
      _typingPauseTimer = Timer(const Duration(seconds: 2), () {
        _localTyping = false;
        _emitTyping(false);
      });
      return;
    }

    _typingPauseTimer?.cancel();
    if (_localTyping) {
      _localTyping = false;
      _emitTyping(false);
    }
  }

  void mergeServerMessage(ChatMessage message) {
    final resolvedMessage = _applyPendingStatus(message);
    final existingIndex = messages.indexWhere((item) => item.id == message.id);
    if (existingIndex >= 0) {
      messages[existingIndex] = resolvedMessage;
    } else {
      messages.add(resolvedMessage);
    }
    _sortMessages();
    _persistPendingMessages();
    notifyListeners();
  }

  void refreshConnection() {
    final socket = _socket;
    if (socket == null) return;
    turnaLog('socket refresh requested', {
      'chatId': chatId,
      'connected': socket.connected,
    });
    if (socket.connected) {
      socket.emit('chat:join', {'chatId': chatId});
      _syncMessagesFromHttp();
      return;
    }
    socket.connect();
  }

  void disconnectForBackground() {
    final socket = _socket;
    _typingPauseTimer?.cancel();
    if (_localTyping && socket?.connected == true) {
      _emitTyping(false);
    }
    _localTyping = false;
    if (socket == null) return;

    turnaLog('socket background disconnect', {
      'chatId': chatId,
      'connected': socket.connected,
    });
    if (socket.connected) {
      socket.disconnect();
    }
    if (isConnected || peerTyping) {
      isConnected = false;
      _cancelPeerTypingTimeout();
      peerTyping = false;
      notifyListeners();
    }
  }

  Future<void> send(String text) async {
    final nowIso = DateTime.now().toIso8601String();
    final localMessage = ChatMessage(
      id: 'local_${senderId}_${_localMessageSeq++}',
      senderId: senderId,
      text: text,
      status: isConnected
          ? ChatMessageStatus.sending
          : ChatMessageStatus.queued,
      createdAt: nowIso,
      errorText: isConnected
          ? null
          : 'Baglanti yok. Geri gelince otomatik gonderilecek.',
    );
    messages.add(localMessage);
    _sortMessages();
    await _persistPendingMessages();
    notifyListeners();

    turnaLog('socket chat:send', {
      'chatId': chatId,
      'senderId': senderId,
      'textLen': text.length,
    });
    if (isConnected) {
      _emitQueuedMessage(localMessage.id);
    }
  }

  Future<void> retryMessage(ChatMessage message) async {
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index < 0 || !messages[index].id.startsWith('local_')) return;

    messages[index] = messages[index].copyWith(
      status: isConnected
          ? ChatMessageStatus.sending
          : ChatMessageStatus.queued,
      errorText: isConnected
          ? null
          : 'Baglanti yok. Geri gelince otomatik gonderilecek.',
      clearErrorText: isConnected,
    );
    await _persistPendingMessages();
    notifyListeners();

    if (isConnected) {
      _emitQueuedMessage(messages[index].id);
    }
  }

  String _pendingMessagesKey() => 'turna_pending_chat_${senderId}_$chatId';

  Future<void> _restorePendingMessages() async {
    if (_restoredPendingMessages) return;
    _restoredPendingMessages = true;

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_pendingMessagesKey()) ?? const [];
    if (rawList.isEmpty) return;

    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final pending = ChatMessage.fromPendingMap(decoded);
        if (messages.any((message) => message.id == pending.id)) continue;
        messages.add(pending);
      } catch (_) {}
    }

    _sortMessages();
    notifyListeners();
    _flushQueuedMessages();
  }

  Future<void> _persistPendingMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = messages
        .where(
          (message) =>
              message.id.startsWith('local_') &&
              (message.status == ChatMessageStatus.queued ||
                  message.status == ChatMessageStatus.failed ||
                  message.status == ChatMessageStatus.sending),
        )
        .map((message) => jsonEncode(message.toPendingMap()))
        .toList();
    await prefs.setStringList(_pendingMessagesKey(), pending);
  }

  void _emitQueuedMessage(String localId) {
    final index = messages.indexWhere((message) => message.id == localId);
    if (index < 0) return;
    final message = messages[index];
    if (!message.id.startsWith('local_')) return;

    _cancelMessageTimeout(localId);
    _socket?.emit('chat:send', {'chatId': chatId, 'text': message.text});
    _messageTimeouts[localId] = Timer(const Duration(seconds: 12), () async {
      final currentIndex = messages.indexWhere((item) => item.id == localId);
      if (currentIndex < 0) return;
      final current = messages[currentIndex];
      if (current.status != ChatMessageStatus.sending) return;

      messages[currentIndex] = current.copyWith(
        status: isConnected
            ? ChatMessageStatus.failed
            : ChatMessageStatus.queued,
        errorText: isConnected
            ? 'Mesaj gonderilemedi. Tekrar dene.'
            : 'Baglanti yok. Geri gelince otomatik gonderilecek.',
      );
      await _persistPendingMessages();
      notifyListeners();
    });
  }

  void _emitTyping(bool isTyping) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    turnaLog('socket chat:typing', {'chatId': chatId, 'isTyping': isTyping});
    socket.emit('chat:typing', {'chatId': chatId, 'isTyping': isTyping});
  }

  Future<void> _flushQueuedMessages() async {
    if (_isFlushingQueue || !isConnected) return;
    _isFlushingQueue = true;
    try {
      final pendingIds = messages
          .where(
            (message) =>
                message.id.startsWith('local_') &&
                (message.status == ChatMessageStatus.queued ||
                    message.status == ChatMessageStatus.failed),
          )
          .map((message) => message.id)
          .toList();

      for (final pendingId in pendingIds) {
        final index = messages.indexWhere((message) => message.id == pendingId);
        if (index < 0) continue;
        messages[index] = messages[index].copyWith(
          status: ChatMessageStatus.sending,
          clearErrorText: true,
        );
        notifyListeners();
        _emitQueuedMessage(pendingId);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await _persistPendingMessages();
    } finally {
      _isFlushingQueue = false;
    }
  }

  void _cancelMessageTimeout(String localId) {
    _messageTimeouts.remove(localId)?.cancel();
  }

  void _cancelPeerTypingTimeout() {
    _peerTypingTimeout?.cancel();
    _peerTypingTimeout = null;
  }

  void _setPeerTyping(bool isTyping) {
    _cancelPeerTypingTimeout();
    if (peerTyping != isTyping) {
      peerTyping = isTyping;
      notifyListeners();
    }
    if (!isTyping) return;

    _peerTypingTimeout = Timer(const Duration(seconds: 4), () {
      _setPeerTyping(false);
    });
  }

  ChatMessage _applyPendingStatus(ChatMessage message) {
    final pendingStatus = _pendingStatusByMessageId.remove(message.id);
    if (pendingStatus == null) return message;
    final mergedStatus = _pickHigherStatus(message.status, pendingStatus);
    if (mergedStatus == message.status) return message;
    return message.copyWith(status: mergedStatus);
  }

  ChatMessageStatus _pickHigherStatus(
    ChatMessageStatus current,
    ChatMessageStatus incoming,
  ) {
    return _statusRank(incoming) > _statusRank(current) ? incoming : current;
  }

  int _statusRank(ChatMessageStatus status) {
    switch (status) {
      case ChatMessageStatus.sending:
        return 0;
      case ChatMessageStatus.queued:
        return 1;
      case ChatMessageStatus.failed:
        return 2;
      case ChatMessageStatus.sent:
        return 3;
      case ChatMessageStatus.delivered:
        return 4;
      case ChatMessageStatus.read:
        return 5;
    }
  }

  void _sortMessages() {
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  void dispose() {
    turnaLog('socket dispose', {'chatId': chatId, 'senderId': senderId});
    if (_localTyping && _socket?.connected == true) {
      _socket?.emit('chat:typing', {'chatId': chatId, 'isTyping': false});
    }
    for (final timer in _messageTimeouts.values) {
      timer.cancel();
    }
    _messageTimeouts.clear();
    _typingPauseTimer?.cancel();
    _cancelPeerTypingTimeout();
    _socket?.dispose();
    super.dispose();
  }
}

class PresenceSocketClient {
  PresenceSocketClient({
    required this.token,
    this.onInboxUpdate,
    this.onIncomingCall,
    this.onCallAccepted,
    this.onCallDeclined,
    this.onCallMissed,
    this.onCallEnded,
  });

  final String token;
  final VoidCallback? onInboxUpdate;
  final void Function(Map<String, dynamic> payload)? onIncomingCall;
  final void Function(Map<String, dynamic> payload)? onCallAccepted;
  final void Function(Map<String, dynamic> payload)? onCallDeclined;
  final void Function(Map<String, dynamic> payload)? onCallMissed;
  final void Function(Map<String, dynamic> payload)? onCallEnded;
  io.Socket? _socket;
  Timer? _refreshDebounce;

  Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  void connect() {
    _socket = io.io(
      kBackendBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableForceNew()
          .disableMultiplex()
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect(
      (_) => turnaLog('presence connected', {'id': _socket?.id}),
    );
    _socket!.onDisconnect(
      (reason) => turnaLog('presence disconnected', {'reason': reason}),
    );
    _socket!.onConnectError((data) => turnaLog('presence connect_error', data));

    _socket!.on('chat:inbox:update', (_) {
      turnaLog('presence inbox:update received');
      _scheduleInboxRefresh();
    });
    _socket!.on('chat:message', (_) {
      turnaLog('presence chat:message received');
      _scheduleInboxRefresh();
    });
    _socket!.on('chat:status', (_) {
      turnaLog('presence chat:status received');
      _scheduleInboxRefresh();
    });
    _socket!.on('call:incoming', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:incoming received', map);
      onIncomingCall?.call(map);
    });
    _socket!.on('call:accepted', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:accepted received', map);
      onCallAccepted?.call(map);
    });
    _socket!.on('call:declined', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:declined received', map);
      onCallDeclined?.call(map);
    });
    _socket!.on('call:missed', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:missed received', map);
      onCallMissed?.call(map);
    });
    _socket!.on('call:ended', (data) {
      final map = _asMap(data);
      if (map == null) return;
      turnaLog('presence call:ended received', map);
      onCallEnded?.call(map);
    });

    _socket!.connect();
  }

  void refreshConnection() {
    final socket = _socket;
    if (socket == null) return;
    turnaLog('presence refresh requested', {'connected': socket.connected});
    if (socket.connected) {
      _scheduleInboxRefresh();
      return;
    }
    socket.connect();
    _scheduleInboxRefresh();
  }

  void disconnectForBackground() {
    final socket = _socket;
    if (socket == null) return;
    turnaLog('presence background disconnect', {'connected': socket.connected});
    if (socket.connected) {
      socket.disconnect();
    }
  }

  void _scheduleInboxRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 120), () {
      onInboxUpdate?.call();
    });
  }

  void dispose() {
    _refreshDebounce?.cancel();
    _socket?.dispose();
  }
}

class AuthSession {
  AuthSession({
    required this.token,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String token;
  final String userId;
  final String displayName;
  final String? avatarUrl;

  static const _tokenKey = 'turna_auth_token';
  static const _userIdKey = 'turna_auth_user_id';
  static const _displayNameKey = 'turna_auth_display_name';
  static const _avatarUrlKey = 'turna_auth_avatar_url';

  static Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userId = prefs.getString(_userIdKey);
    final displayName = prefs.getString(_displayNameKey);
    final avatarUrl = prefs.getString(_avatarUrlKey);
    if (token == null || userId == null || displayName == null) {
      return null;
    }

    return AuthSession(
      token: token,
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }

  AuthSession copyWith({
    String? token,
    String? userId,
    String? displayName,
    String? avatarUrl,
    bool clearAvatarUrl = false,
  }) {
    return AuthSession(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_displayNameKey, displayName);
    if (avatarUrl == null || avatarUrl!.trim().isEmpty) {
      await prefs.remove(_avatarUrlKey);
    } else {
      await prefs.setString(_avatarUrlKey, avatarUrl!);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_avatarUrlKey);
  }
}

class TurnaApiException implements Exception {
  TurnaApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TurnaUnauthorizedException extends TurnaApiException {
  TurnaUnauthorizedException([super.message = 'Oturumun suresi doldu.']);
}

class TurnaFirebase {
  static bool _attempted = false;
  static bool _enabled = false;
  static FirebaseAnalytics? _analytics;

  static Future<bool> ensureInitialized() async {
    if (_attempted) return _enabled;
    _attempted = true;

    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
      _enabled = true;
    } catch (error) {
      turnaLog('firebase init skipped', error);
      _enabled = false;
    }

    return _enabled;
  }

  static FirebaseAnalytics? get analytics => _enabled ? _analytics : null;
}

class TurnaAnalytics {
  static Future<void> logEvent(
    String name, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final ready = await TurnaFirebase.ensureInitialized();
    if (!ready) return;

    try {
      await TurnaFirebase.analytics?.logEvent(
        name: name,
        parameters: parameters.map(
          (key, value) => MapEntry<String, Object>(
            key,
            value is String || value is num || value is bool
                ? value as Object
                : (value?.toString() ?? ''),
          ),
        ),
      );
    } catch (error) {
      turnaLog('analytics log skipped', error);
    }
  }
}

class PushApi {
  static Future<void> registerDevice(
    AuthSession session, {
    required String token,
    required String platform,
    String tokenKind = 'standard',
    String? deviceLabel,
  }) async {
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/push/devices'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'token': token,
        'platform': platform,
        'tokenKind': tokenKind,
        'deviceLabel': deviceLabel,
      }),
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(
        ProfileApi._extractApiError(res.body, res.statusCode),
      );
    }
  }

  static Future<void> unregisterDevice(
    AuthSession session, {
    required String token,
  }) async {
    final res = await http.delete(
      Uri.parse('$kBackendBaseUrl/api/push/devices'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'token': token}),
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(
        ProfileApi._extractApiError(res.body, res.statusCode),
      );
    }
  }
}

class TurnaPushManager {
  static const _lastPushTokenKey = 'turna_last_push_token';
  static AuthSession? _session;
  static bool _listenersAttached = false;

  static Future<void> syncSession(AuthSession session) async {
    _session = session;
    final ready = await TurnaFirebase.ensureInitialized();
    if (!ready) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token == null || token.trim().isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final previousToken = prefs.getString(_lastPushTokenKey);
      if (previousToken != token) {
        await PushApi.registerDevice(
          session,
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
          tokenKind: 'standard',
          deviceLabel: Platform.isIOS ? 'ios-device' : 'android-device',
        );
        await prefs.setString(_lastPushTokenKey, token);
      }
      await TurnaNativeCallManager.syncVoipToken(session);

      if (!_listenersAttached) {
        _listenersAttached = true;
        FirebaseMessaging.onMessage.listen((message) async {
          turnaLog('push foreground', message.data);
          await TurnaNativeCallManager.handleForegroundRemoteMessage(
            message.data,
          );
        });
        FirebaseMessaging.onMessageOpenedApp.listen((message) async {
          turnaLog('push opened', message.data);
          await TurnaNativeCallManager.handleForegroundRemoteMessage(
            message.data,
          );
        });
        messaging.onTokenRefresh.listen((freshToken) async {
          if (freshToken.trim().isEmpty) return;
          final activeSession = _session;
          if (activeSession == null) return;
          try {
            await PushApi.registerDevice(
              activeSession,
              token: freshToken,
              platform: Platform.isIOS ? 'ios' : 'android',
              tokenKind: 'standard',
              deviceLabel: Platform.isIOS ? 'ios-device' : 'android-device',
            );
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_lastPushTokenKey, freshToken);
          } catch (error) {
            turnaLog('push token refresh register failed', error);
          }
        });
      }
    } catch (error) {
      turnaLog('push sync skipped', error);
    }
  }
}

class _TurnaPendingNativeAction {
  const _TurnaPendingNativeAction({required this.action, required this.body});

  final String action;
  final Map<String, dynamic> body;

  Map<String, dynamic> toMap() => {'action': action, 'body': body};

  factory _TurnaPendingNativeAction.fromMap(Map<String, dynamic> map) {
    return _TurnaPendingNativeAction(
      action: (map['action'] ?? '').toString(),
      body: Map<String, dynamic>.from(map['body'] as Map? ?? const {}),
    );
  }
}

class TurnaNativeCallManager {
  static const _pendingActionKey = 'turna_pending_native_call_action';
  static const _lastVoipPushTokenKey = 'turna_last_voip_push_token';
  static bool _initialized = false;
  static bool _androidPermissionsRequested = false;
  static AuthSession? _session;
  static TurnaCallCoordinator? _coordinator;
  static VoidCallback? _onSessionExpired;
  static final Set<String> _handledActionKeys = <String>{};
  static final Set<String> _suppressedEndEvents = <String>{};
  static final Set<String> _shownIncomingCalls = <String>{};
  static String? _activeCallId;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      Future<void>(() async {
        await _handleCallkitEvent(event);
      });
    });

    if (Platform.isAndroid) {
      await _requestAndroidPermissions();
    }
  }

  static Future<void> bindSession({
    required AuthSession session,
    required TurnaCallCoordinator coordinator,
    required VoidCallback onSessionExpired,
  }) async {
    _session = session;
    _coordinator = coordinator;
    _onSessionExpired = onSessionExpired;
    if (Platform.isAndroid) {
      await _requestAndroidPermissions();
    }
    await syncVoipToken(session);
    await _reconcileStaleCalls(session);
    await _consumePendingAction();
    await _recoverAcceptedNativeCall();
  }

  static void unbindSession(String userId) {
    if (_session?.userId != userId) return;
    _session = null;
    _coordinator = null;
    _onSessionExpired = null;
  }

  static Future<void> handleAppResumed() async {
    final session = _session;
    if (session != null) {
      await _reconcileStaleCalls(session);
    }
    await _consumePendingAction();
    await _recoverAcceptedNativeCall();
  }

  static Future<void> _reconcileStaleCalls(AuthSession session) async {
    try {
      final reconciledCallIds = await CallApi.reconcileCalls(session);
      for (final callId in reconciledCallIds) {
        await endCallUi(callId);
      }
    } catch (error) {
      turnaLog('call reconcile skipped', error);
    }
  }

  static Future<void> handleBackgroundRemoteMessage(
    Map<String, dynamic> data,
  ) async {
    await initialize();
    final type = (data['type'] ?? '').toString();
    if (type == 'incoming_call') {
      await _showIncomingCallkitIfNeeded(data);
      return;
    }
    if (type == 'call_ended') {
      final callId = _readCallId(data);
      if (callId != null) {
        await endCallUi(callId);
      }
    }
  }

  static Future<void> handleForegroundRemoteMessage(
    Map<String, dynamic> data,
  ) async {
    final type = (data['type'] ?? '').toString();
    if (type == 'call_ended') {
      final callId = _readCallId(data);
      if (callId != null) {
        await endCallUi(callId);
      }
    }
  }

  static Future<void> syncVoipToken(AuthSession session) async {
    if (!Platform.isIOS) return;
    try {
      final token = (await FlutterCallkitIncoming.getDevicePushTokenVoIP())
          ?.toString()
          .trim();
      if (token == null || token.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getString(_lastVoipPushTokenKey);
      if (previous == token) return;
      await PushApi.registerDevice(
        session,
        token: token,
        platform: 'ios',
        tokenKind: 'voip',
        deviceLabel: 'ios-voip',
      );
      await prefs.setString(_lastVoipPushTokenKey, token);
      turnaLog('voip token synced');
    } catch (error) {
      turnaLog('voip token sync skipped', error);
    }
  }

  static Future<void> setCallConnected(String callId) async {
    _activeCallId = callId;
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (error) {
      turnaLog('native call connected skipped', error);
    }
  }

  static Future<void> endCallUi(String callId) async {
    _shownIncomingCalls.remove(callId);
    if (_activeCallId == callId) {
      _activeCallId = null;
    }
    _suppressedEndEvents.add(callId);
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (error) {
      turnaLog('native call end skipped', error);
      _suppressedEndEvents.remove(callId);
    }
  }

  static Future<void> _requestAndroidPermissions() async {
    if (!Platform.isAndroid || _androidPermissionsRequested) return;
    _androidPermissionsRequested = true;
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Bildirim izni',
        'rationaleMessagePermission':
            'Gelen aramalari gosterebilmek icin bildirim izni gerekiyor.',
        'postNotificationMessageRequired':
            'Gelen aramalari gosterebilmek icin bildirim izni ver.',
      });
    } catch (error) {
      turnaLog('android notification permission skipped', error);
    }
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (error) {
      turnaLog('android full intent permission skipped', error);
    }
  }

  static Future<void> _handleCallkitEvent(CallEvent event) async {
    final body = _normalizeBody(event.body);
    final callId = _readCallId(body);
    switch (event.event) {
      case Event.actionDidUpdateDevicePushTokenVoip:
        final session = _session;
        if (session != null) {
          await syncVoipToken(session);
        }
        return;
      case Event.actionCallIncoming:
        if (callId != null) {
          _shownIncomingCalls.add(callId);
        }
        return;
      case Event.actionCallAccept:
        await _queueOrHandleAction('accept', body);
        return;
      case Event.actionCallDecline:
        await _queueOrHandleAction('decline', body);
        return;
      case Event.actionCallEnded:
        if (callId != null && _suppressedEndEvents.remove(callId)) {
          return;
        }
        await _queueOrHandleAction('end', body);
        return;
      case Event.actionCallTimeout:
        await _queueOrHandleAction('timeout', body);
        return;
      default:
        return;
    }
  }

  static Future<void> _queueOrHandleAction(
    String action,
    Map<String, dynamic> body,
  ) async {
    final handled = await _handleAction(action, body);
    if (handled) {
      await _clearPendingAction();
      return;
    }
    await _persistPendingAction(
      _TurnaPendingNativeAction(action: action, body: body),
    );
  }

  static Future<bool> _handleAction(
    String action,
    Map<String, dynamic> body,
  ) async {
    final session = _session;
    final coordinator = _coordinator;
    if (session == null || coordinator == null) return false;

    final callId = _readCallId(body);
    if (callId == null || callId.isEmpty) return false;
    final actionKey = '$action:$callId';
    if (_handledActionKeys.contains(actionKey)) {
      return true;
    }

    try {
      switch (action) {
        case 'accept':
          final accepted = await CallApi.acceptCall(session, callId: callId);
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          _shownIncomingCalls.remove(callId);
          await _openAcceptedCall(session, coordinator, accepted);
          return true;
        case 'decline':
          await CallApi.declineCall(session, callId: callId);
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          await endCallUi(callId);
          return true;
        case 'end':
          await CallApi.endCall(session, callId: callId);
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          await endCallUi(callId);
          return true;
        case 'timeout':
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          await endCallUi(callId);
          return true;
        default:
          return false;
      }
    } on TurnaUnauthorizedException {
      _onSessionExpired?.call();
      return true;
    } catch (error) {
      turnaLog('native call action failed', {
        'action': action,
        'callId': callId,
        'error': error.toString(),
      });
      return false;
    }
  }

  static Future<void> _openAcceptedCall(
    AuthSession session,
    TurnaCallCoordinator coordinator,
    TurnaAcceptedCallEvent accepted,
  ) async {
    if (_activeCallId == accepted.call.id) return;
    await Future<void>.delayed(Duration.zero);
    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    _activeCallId = accepted.call.id;
    final returnChat = buildDirectChatPreviewForCall(session, accepted.call);
    final callSession = kTurnaCallUiController.obtainSession(
      session: session,
      coordinator: coordinator,
      call: accepted.call,
      connect: accepted.connect,
      onSessionExpired: _onSessionExpired ?? () {},
      returnChatOnExit: returnChat,
    );
    await navigator.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'active-call'),
        builder: (_) => ActiveCallPage(callSession: callSession),
      ),
    );
  }

  static Future<void> _recoverAcceptedNativeCall() async {
    final session = _session;
    if (session == null) return;
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls is! List || activeCalls.isEmpty) return;
      for (final item in activeCalls) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final accepted = map['accepted'] == true || map['isAccepted'] == true;
        if (!accepted) continue;
        final callId = _readCallId(map);
        if (callId == null || callId.isEmpty) continue;
        await _handleAction('accept', map);
        break;
      }
    } catch (error) {
      turnaLog('active native call recovery skipped', error);
    }
  }

  static Future<void> _persistPendingAction(
    _TurnaPendingNativeAction action,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingActionKey, jsonEncode(action.toMap()));
  }

  static Future<void> _clearPendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingActionKey);
  }

  static Future<void> _consumePendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingActionKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final pending = _TurnaPendingNativeAction.fromMap(map);
      final handled = await _handleAction(pending.action, pending.body);
      if (handled) {
        await prefs.remove(_pendingActionKey);
      }
    } catch (error) {
      turnaLog('pending native call action parse failed', error);
      await prefs.remove(_pendingActionKey);
    }
  }

  static Map<String, dynamic> _normalizeBody(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  static String? _readCallId(Map<String, dynamic> map) {
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : const <String, dynamic>{};
    final id = map['id'] ?? map['callId'] ?? extra['callId'] ?? extra['id'];
    final value = id?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static String _readCallerName(Map<String, dynamic> map) {
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : const <String, dynamic>{};
    return (map['callerDisplayName'] ??
                map['nameCaller'] ??
                extra['callerDisplayName'] ??
                map['handle'] ??
                'Turna')
            .toString()
            .trim()
            .isEmpty
        ? 'Turna'
        : (map['callerDisplayName'] ??
                  map['nameCaller'] ??
                  extra['callerDisplayName'] ??
                  map['handle'] ??
                  'Turna')
              .toString();
  }

  static bool _readIsVideo(Map<String, dynamic> map) {
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : const <String, dynamic>{};
    final raw =
        map['isVideo'] ??
        map['callType'] ??
        extra['callType'] ??
        extra['isVideo'];
    if (raw is bool) return raw;
    final text = raw?.toString().toLowerCase();
    return text == 'video' || text == 'true' || text == '1';
  }

  static Future<void> _showIncomingCallkitIfNeeded(
    Map<String, dynamic> payload,
  ) async {
    final callId = _readCallId(payload);
    if (callId == null || callId.isEmpty) return;
    if (_shownIncomingCalls.contains(callId)) return;
    if (Platform.isIOS) {
      return;
    }

    _shownIncomingCalls.add(callId);
    final isVideo = _readIsVideo(payload);
    final callerName = _readCallerName(payload);
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Turna',
      handle: callerName,
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'Ac',
      textDecline: 'Reddet',
      extra: <String, dynamic>{
        'callId': callId,
        'callerId': (payload['callerId'] ?? '').toString(),
        'callerDisplayName': callerName,
        'callType': isVideo ? 'video' : 'audio',
      },
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Cevapsiz arama',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#101314',
        actionColor: '#2F80ED',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Turna Arama',
        missedCallNotificationChannelName: 'Turna Cevapsiz',
        isShowCallID: false,
        isShowFullLockedScreen: true,
        isImportant: true,
      ),
      ios: IOSParams(
        handleType: 'generic',
        supportsVideo: isVideo,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (error) {
      _shownIncomingCalls.remove(callId);
      turnaLog('native incoming call show failed', error);
    }
  }
}

class AvatarUploadTicket {
  AvatarUploadTicket({
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
  });

  final String objectKey;
  final String uploadUrl;
  final Map<String, String> headers;

  factory AvatarUploadTicket.fromMap(Map<String, dynamic> map) {
    final rawHeaders = map['headers'] as Map<String, dynamic>? ?? const {};
    return AvatarUploadTicket(
      objectKey: (map['objectKey'] ?? '').toString(),
      uploadUrl: (map['uploadUrl'] ?? '').toString(),
      headers: rawHeaders.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }
}

class ChatAttachmentUploadTicket {
  ChatAttachmentUploadTicket({
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
  });

  final String objectKey;
  final String uploadUrl;
  final Map<String, String> headers;

  factory ChatAttachmentUploadTicket.fromMap(Map<String, dynamic> map) {
    final rawHeaders = map['headers'] as Map<String, dynamic>? ?? const {};
    return ChatAttachmentUploadTicket(
      objectKey: (map['objectKey'] ?? '').toString(),
      uploadUrl: (map['uploadUrl'] ?? '').toString(),
      headers: rawHeaders.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }
}

class OutgoingAttachmentDraft {
  OutgoingAttachmentDraft({
    required this.objectKey,
    required this.kind,
    required this.contentType,
    required this.sizeBytes,
    this.fileName,
    this.width,
    this.height,
    this.durationSeconds,
  });

  final String objectKey;
  final ChatAttachmentKind kind;
  final String? fileName;
  final String contentType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationSeconds;

  Map<String, dynamic> toMap() {
    return {
      'objectKey': objectKey,
      'kind': kind.name,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'width': width,
      'height': height,
      'durationSeconds': durationSeconds,
    };
  }
}

class ProfileApi {
  static Future<TurnaUserProfile> fetchMe(AuthSession session) async {
    final res = await http.get(
      Uri.parse('$kBackendBaseUrl/api/profile/me'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(_extractApiError(res.body, res.statusCode));
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<TurnaUserProfile> fetchUser(
    AuthSession session,
    String userId,
  ) async {
    final res = await http.get(
      Uri.parse('$kBackendBaseUrl/api/profile/users/$userId'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(_extractApiError(res.body, res.statusCode));
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<TurnaUserProfile> updateMe(
    AuthSession session, {
    required String displayName,
    required String about,
    required String phone,
    required String email,
  }) async {
    final res = await http.put(
      Uri.parse('$kBackendBaseUrl/api/profile/me'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'displayName': displayName,
        'about': about.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
      }),
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(_extractApiError(res.body, res.statusCode));
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<AvatarUploadTicket> createAvatarUpload(
    AuthSession session, {
    required String contentType,
    required String fileName,
  }) async {
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/profile/avatar/upload-url'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'contentType': contentType, 'fileName': fileName}),
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(_extractApiError(res.body, res.statusCode));
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return AvatarUploadTicket.fromMap(data);
  }

  static Future<TurnaUserProfile> completeAvatarUpload(
    AuthSession session, {
    required String objectKey,
  }) async {
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/profile/avatar/complete'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'objectKey': objectKey}),
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(_extractApiError(res.body, res.statusCode));
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<TurnaUserProfile> deleteAvatar(AuthSession session) async {
    final res = await http.delete(
      Uri.parse('$kBackendBaseUrl/api/profile/avatar'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    if (res.statusCode >= 400) {
      throw TurnaApiException(_extractApiError(res.body, res.statusCode));
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static String _extractApiError(String body, int statusCode) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final error = map['error']?.toString();
      switch (error) {
        case 'phone_already_in_use':
          return 'Bu telefon başka bir hesapta kullanılıyor.';
        case 'email_already_in_use':
          return 'Bu email başka bir hesapta kullanılıyor.';
        case 'validation_error':
          return 'Girilen bilgiler geçersiz.';
        case 'user_not_found':
          return 'Kullanıcı bulunamadı.';
        case 'storage_not_configured':
          return 'Dosya depolama servisi hazır değil.';
        case 'invalid_avatar_key':
          return 'Avatar yüklemesi doğrulanamadı.';
        case 'invalid_attachment_key':
          return 'Medya yüklemesi doğrulanamadı.';
        case 'message_not_found':
          return 'Mesaj bulunamadi.';
        case 'message_delete_not_allowed':
          return 'Bu mesaj sadece gonderen tarafindan herkesten silinebilir.';
        case 'message_delete_window_expired':
          return 'Mesaj artik herkesten silinemez. 10 dakika siniri doldu.';
        case 'uploaded_file_not_found':
          return 'Yüklenen dosya bulunamadı.';
        case 'avatar_not_found':
          return 'Avatar bulunamadı.';
        case 'text_or_attachment_required':
          return 'Mesaj veya ek secmelisin.';
        case 'call_provider_not_configured':
          return 'Arama servisi henuz hazir degil.';
        case 'call_conflict':
          return 'Kullanicilardan biri baska bir aramada.';
        case 'invalid_call_target':
          return 'Bu kullanici aranamaz.';
        case 'call_not_found':
          return 'Arama kaydi bulunamadi.';
        case 'call_not_ringing':
          return 'Bu arama artik cevaplanamaz.';
        case 'call_not_active':
          return 'Arama zaten sonlanmis.';
        default:
          return error ?? 'İşlem başarısız ($statusCode)';
      }
    } catch (_) {
      return 'İşlem başarısız ($statusCode)';
    }
  }
}

class ChatApi {
  static Future<List<ChatPreview>> fetchChats(
    AuthSession session, {
    int refreshTick = 0,
  }) async {
    try {
      final headers = {'Authorization': 'Bearer ${session.token}'};
      turnaLog('api fetchChats', {'refreshTick': refreshTick});

      final chatsRes = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats'),
        headers: headers,
      );
      _throwIfApiError(chatsRes);

      final chatsMap = jsonDecode(chatsRes.body) as Map<String, dynamic>;
      final chatsData = (chatsMap['data'] as List<dynamic>? ?? []);
      return chatsData.map((item) {
        final map = item as Map<String, dynamic>;
        return ChatPreview(
          chatId: map['chatId'].toString(),
          name: map['title']?.toString() ?? 'Chat',
          message: sanitizeTurnaChatPreviewText(
            map['lastMessage']?.toString() ?? '',
          ),
          time: _formatTime(map['lastMessageAt']?.toString()),
          avatarUrl: _nullableString(map['avatarUrl']),
          unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Sunucuya baglanilamadi.');
    }
  }

  static Future<List<ChatUser>> fetchDirectory(AuthSession session) async {
    try {
      final headers = {'Authorization': 'Bearer ${session.token}'};
      turnaLog('api fetchDirectory');
      final directoryRes = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/directory/list'),
        headers: headers,
      );
      _throwIfApiError(directoryRes);

      final directoryMap =
          jsonDecode(directoryRes.body) as Map<String, dynamic>;
      final users = (directoryMap['data'] as List<dynamic>? ?? []);
      return users.map((item) {
        final map = item as Map<String, dynamic>;
        return ChatUser(
          id: map['id'].toString(),
          displayName: map['displayName']?.toString() ?? 'User',
          avatarUrl: _nullableString(map['avatarUrl']),
        );
      }).toList();
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Kisi listesine ulasilamadi.');
    }
  }

  static String buildDirectChatId(String currentUserId, String peerUserId) {
    final sorted = [currentUserId, peerUserId]..sort();
    return 'direct_${sorted[0]}_${sorted[1]}';
  }

  static String? extractPeerUserId(String chatId, String currentUserId) {
    if (!chatId.startsWith('direct_')) return null;
    final parts = chatId
        .replaceFirst('direct_', '')
        .split('_')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length != 2) return null;
    if (!parts.contains(currentUserId)) return null;
    return parts.firstWhere((part) => part != currentUserId);
  }

  static Future<ChatMessagesPage> fetchMessagesPage(
    String token,
    String chatId, {
    String? before,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse('$kBackendBaseUrl/api/chats/$chatId/messages')
          .replace(
            queryParameters: {
              'limit': '$limit',
              if (before != null && before.isNotEmpty) 'before': before,
            },
          );

      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (map['data'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final pageInfo = map['pageInfo'] as Map<String, dynamic>? ?? const {};

      return ChatMessagesPage(
        items: items,
        hasMore: pageInfo['hasMore'] == true,
        nextBefore: _nullableString(pageInfo['nextBefore']),
      );
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesajlar yuklenemedi.');
    }
  }

  static Future<ChatAttachmentUploadTicket> createAttachmentUpload(
    AuthSession session, {
    required String chatId,
    required ChatAttachmentKind kind,
    required String contentType,
    required String fileName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/attachments/upload-url'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chatId': chatId,
          'kind': kind.name,
          'contentType': contentType,
          'fileName': fileName,
        }),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatAttachmentUploadTicket.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Dosya yukleme hazirligi basarisiz oldu.');
    }
  }

  static Future<ChatMessage> sendMessage(
    AuthSession session, {
    required String chatId,
    String? text,
    List<OutgoingAttachmentDraft> attachments = const [],
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/chats/messages'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chatId': chatId,
          'text': text?.trim(),
          'attachments': attachments
              .map((attachment) => attachment.toMap())
              .toList(),
        }),
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatMessage.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesaj gonderilemedi.');
    }
  }

  static Future<ChatMessage> deleteMessageForEveryone(
    AuthSession session, {
    required String messageId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(
          '$kBackendBaseUrl/api/chats/messages/$messageId/delete-for-everyone',
        ),
        headers: {
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        },
      );
      _throwIfApiError(res);

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      return ChatMessage.fromMap(data);
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Mesaj herkesten silinemedi.');
    }
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static void _throwIfApiError(http.Response response) {
    if (response.statusCode < 400) return;

    turnaLog('chat api failed', {
      'statusCode': response.statusCode,
      'body': response.body,
    });
    final message = ProfileApi._extractApiError(
      response.body,
      response.statusCode,
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw TurnaUnauthorizedException(message);
    }
    throw TurnaApiException(message);
  }

  static String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

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

class TurnaCallCoordinator extends ChangeNotifier {
  TurnaIncomingCallEvent? _pendingIncoming;
  final Map<String, TurnaAcceptedCallEvent> _acceptedEvents = {};
  final Map<String, TurnaTerminalCallEvent> _terminalEvents = {};

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

  void clearCall(String callId) {
    if (_pendingIncoming?.call.id == callId) {
      _pendingIncoming = null;
    }
    _acceptedEvents.remove(callId);
    _terminalEvents.remove(callId);
  }
}

class CallsPage extends StatefulWidget {
  const CallsPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    widget.callCoordinator.addListener(_onCallUpdate);
  }

  @override
  void dispose() {
    widget.callCoordinator.removeListener(_onCallUpdate);
    super.dispose();
  }

  void _onCallUpdate() {
    if (!mounted) return;
    setState(() => _refreshTick++);
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _statusLabel(TurnaCallHistoryItem item) {
    switch (item.status) {
      case TurnaCallStatus.accepted:
        if (item.durationSeconds != null && item.durationSeconds! > 0) {
          final minutes = item.durationSeconds! ~/ 60;
          final seconds = item.durationSeconds! % 60;
          return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        }
        return 'Baglandi';
      case TurnaCallStatus.declined:
        return 'Reddedildi';
      case TurnaCallStatus.missed:
        return 'Cevapsiz';
      case TurnaCallStatus.cancelled:
        return 'Iptal edildi';
      case TurnaCallStatus.ended:
        return 'Sonlandi';
      case TurnaCallStatus.ringing:
        return 'Caliyor';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: FutureBuilder<List<TurnaCallHistoryItem>>(
        future: CallApi.fetchCalls(widget.session, refreshTick: _refreshTick),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            final isAuthError = error is TurnaUnauthorizedException;
            return _CenteredState(
              icon: isAuthError
                  ? Icons.lock_outline
                  : Icons.call_missed_outgoing,
              title: isAuthError
                  ? 'Oturumun suresi doldu'
                  : 'Aramalar yuklenemedi',
              message: error.toString(),
              primaryLabel: isAuthError ? 'Yeniden giris yap' : 'Tekrar dene',
              onPrimary: isAuthError
                  ? widget.onSessionExpired
                  : () => setState(() => _refreshTick++),
            );
          }

          final calls = snapshot.data ?? const [];
          if (calls.isEmpty) {
            return const _CenteredState(
              icon: Icons.call_outlined,
              title: 'Henuz arama yok',
              message: 'Yaptigin ve aldigin aramalar burada listelenecek.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => setState(() => _refreshTick++),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: calls.length,
              itemBuilder: (context, index) {
                final item = calls[index];
                final isMissed =
                    item.status == TurnaCallStatus.missed ||
                    item.status == TurnaCallStatus.declined;
                return ListTile(
                  leading: _ProfileAvatar(
                    label: item.peer.displayName,
                    avatarUrl: item.peer.avatarUrl,
                    authToken: widget.session.token,
                    radius: 22,
                  ),
                  title: Text(
                    item.peer.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Row(
                    children: [
                      Icon(
                        item.direction == 'incoming'
                            ? Icons.call_received
                            : Icons.call_made,
                        size: 16,
                        color: isMissed
                            ? Colors.red.shade400
                            : TurnaColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _statusLabel(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(item.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777C79),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Icon(
                        item.type == TurnaCallType.video
                            ? Icons.videocam_outlined
                            : Icons.call_outlined,
                        color: const Color(0xFF777C79),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({
    super.key,
    required this.session,
    required this.coordinator,
    required this.incoming,
    required this.onSessionExpired,
    this.returnChatOnExit,
  });

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaIncomingCallEvent incoming;
  final VoidCallback onSessionExpired;
  final ChatPreview? returnChatOnExit;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_handleCoordinator);
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinator);
    super.dispose();
  }

  void _handleCoordinator() {
    final terminal = widget.coordinator.consumeTerminal(
      widget.incoming.call.id,
    );
    if (terminal == null || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final accepted = await CallApi.acceptCall(
        widget.session,
        callId: widget.incoming.call.id,
      );
      widget.coordinator.clearCall(widget.incoming.call.id);
      if (!mounted) return;
      final callSession = kTurnaCallUiController.obtainSession(
        session: widget.session,
        coordinator: widget.coordinator,
        call: accepted.call,
        connect: accepted.connect,
        onSessionExpired: widget.onSessionExpired,
        returnChatOnExit: widget.returnChatOnExit,
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'active-call'),
          builder: (_) => ActiveCallPage(callSession: callSession),
        ),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CallApi.declineCall(
        widget.session,
        callId: widget.incoming.call.id,
      );
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onSessionExpired();
      }
    } catch (_) {}

    widget.coordinator.clearCall(widget.incoming.call.id);
    await TurnaNativeCallManager.endCallUi(widget.incoming.call.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.incoming.call;
    final isVideo = call.type == TurnaCallType.video;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1112),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Stack(
              children: [
                Center(
                  child: _CallIdentityPanel(
                    authToken: widget.session.token,
                    displayName: call.peer.displayName,
                    avatarUrl: call.peer.avatarUrl,
                    subtitle: isVideo ? 'Goruntulu arama' : 'Sesli arama',
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton(
                          heroTag: 'decline_${call.id}',
                          backgroundColor: Colors.red.shade400,
                          onPressed: _busy ? null : _decline,
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 72),
                        FloatingActionButton(
                          heroTag: 'accept_${call.id}',
                          backgroundColor: TurnaColors.primary,
                          onPressed: _busy ? null : _accept,
                          child: Icon(
                            isVideo ? Icons.videocam : Icons.call,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OutgoingCallPage extends StatefulWidget {
  const OutgoingCallPage({
    super.key,
    required this.session,
    required this.coordinator,
    required this.initialCall,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaCallSummary initialCall;
  final VoidCallback onSessionExpired;

  @override
  State<OutgoingCallPage> createState() => _OutgoingCallPageState();
}

class _OutgoingCallPageState extends State<OutgoingCallPage> {
  bool _ending = false;
  bool _navigatedToActive = false;

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_handleCoordinator);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCoordinator());
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinator);
    super.dispose();
  }

  void _handleCoordinator() {
    if (!mounted || _navigatedToActive) return;
    final accepted = widget.coordinator.consumeAccepted(widget.initialCall.id);
    if (accepted != null) {
      _navigatedToActive = true;
      widget.coordinator.clearCall(widget.initialCall.id);
      final callSession = kTurnaCallUiController.obtainSession(
        session: widget.session,
        coordinator: widget.coordinator,
        call: accepted.call,
        connect: accepted.connect,
        onSessionExpired: widget.onSessionExpired,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ActiveCallPage(callSession: callSession),
        ),
      );
      return;
    }

    final terminal = widget.coordinator.consumeTerminal(widget.initialCall.id);
    if (terminal == null) return;

    final message = switch (terminal.kind) {
      'declined' => 'Arama reddedildi.',
      'missed' => 'Cevap yok.',
      _ => 'Arama sonlandi.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  Future<void> _cancelCall() async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      await CallApi.endCall(widget.session, callId: widget.initialCall.id);
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onSessionExpired();
      }
    } catch (_) {}

    widget.coordinator.clearCall(widget.initialCall.id);
    await TurnaNativeCallManager.endCallUi(widget.initialCall.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.initialCall;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1112),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              Center(
                child: _CallIdentityPanel(
                  authToken: widget.session.token,
                  displayName: call.peer.displayName,
                  avatarUrl: call.peer.avatarUrl,
                  subtitle: call.type == TurnaCallType.video
                      ? 'Goruntulu arama caliyor...'
                      : 'Sesli arama caliyor...',
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: FloatingActionButton(
                    backgroundColor: Colors.red.shade400,
                    onPressed: _ending ? null : _cancelCall,
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallIdentityPanel extends StatelessWidget {
  const _CallIdentityPanel({
    required this.authToken,
    required this.displayName,
    required this.avatarUrl,
    required this.subtitle,
  });

  final String authToken;
  final String displayName;
  final String? avatarUrl;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfileAvatar(
            label: displayName,
            avatarUrl: avatarUrl,
            authToken: authToken,
            radius: 48,
          ),
          const SizedBox(height: 20),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB7BCB9), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

abstract class CallProviderAdapter {
  Future<void> connect();
  Future<void> disconnect();
}

class LiveKitCallAdapter extends ChangeNotifier implements CallProviderAdapter {
  LiveKitCallAdapter({required this.connectPayload, required this.videoEnabled})
    : room = lk.Room(
        roomOptions: lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioOutputOptions: lk.AudioOutputOptions(speakerOn: false),
        ),
      );

  final TurnaCallConnectPayload connectPayload;
  final bool videoEnabled;
  final lk.Room room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  bool connecting = false;
  bool connected = false;
  bool microphoneEnabled = true;
  bool cameraEnabled = false;
  bool speakerEnabled = false;
  lk.CameraPosition cameraPosition = lk.CameraPosition.front;
  String? error;

  Iterable<lk.RemoteParticipant> get remoteParticipants =>
      room.remoteParticipants.values;

  lk.VideoTrack? get primaryRemoteVideoTrack {
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track is lk.VideoTrack && publication.subscribed) {
          return track;
        }
      }
    }
    return null;
  }

  lk.VideoTrack? get localVideoTrack {
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return null;
    for (final publication in localParticipant.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.VideoTrack) {
        return track;
      }
    }
    return null;
  }

  lk.LocalVideoTrack? get localCameraTrack {
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return null;
    for (final publication in localParticipant.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.LocalVideoTrack) {
        return track;
      }
    }
    return null;
  }

  @override
  Future<void> connect() async {
    if (connecting || connected) return;

    connecting = true;
    error = null;
    notifyListeners();

    _listener = room.createListener()
      ..on<lk.RoomDisconnectedEvent>((_) {
        connected = false;
        connecting = false;
        notifyListeners();
      })
      ..on<lk.ParticipantConnectedEvent>((_) => notifyListeners())
      ..on<lk.ParticipantDisconnectedEvent>((_) => notifyListeners())
      ..on<lk.TrackSubscribedEvent>((_) => notifyListeners())
      ..on<lk.TrackUnsubscribedEvent>((_) => notifyListeners())
      ..on<lk.LocalTrackPublishedEvent>((_) => notifyListeners())
      ..on<lk.LocalTrackUnpublishedEvent>((_) => notifyListeners());

    try {
      await room.prepareConnection(connectPayload.url, connectPayload.token);
      await room.connect(connectPayload.url, connectPayload.token);
      final localParticipant = room.localParticipant;
      if (localParticipant == null) {
        throw StateError('local_participant_missing');
      }
      await localParticipant.setMicrophoneEnabled(true);
      microphoneEnabled = true;
      speakerEnabled = false;

      if (videoEnabled) {
        await localParticipant.setCameraEnabled(true);
        cameraEnabled = true;
      }

      await room.setSpeakerOn(false);

      connected = true;
      connecting = false;
      notifyListeners();
    } catch (err) {
      connecting = false;
      error = 'Cagri baglantisi kurulamadi.';
      turnaLog('livekit connect failed', err);
      notifyListeners();
    }
  }

  Future<void> toggleMicrophone() async {
    final next = !microphoneEnabled;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    await localParticipant.setMicrophoneEnabled(next);
    microphoneEnabled = next;
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final next = !cameraEnabled;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    await localParticipant.setCameraEnabled(next);
    cameraEnabled = next;
    notifyListeners();
  }

  Future<void> flipCamera() async {
    final track = localCameraTrack;
    if (track == null) return;
    cameraPosition = cameraPosition.switched();
    await track.setCameraPosition(cameraPosition);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    final next = !speakerEnabled;
    await room.setSpeakerOn(next);
    speakerEnabled = next;
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    try {
      await room.disconnect();
    } catch (_) {}
    connected = false;
    connecting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _listener?.dispose();
    room.disconnect();
    super.dispose();
  }
}

class TurnaManagedCallSession extends ChangeNotifier {
  TurnaManagedCallSession({
    required this.session,
    required this.coordinator,
    required this.call,
    required this.connect,
    required this.onSessionExpired,
    this.returnChatOnExit,
  }) : adapter = LiveKitCallAdapter(
         connectPayload: connect,
         videoEnabled: call.type == TurnaCallType.video,
       ) {
    adapter.addListener(_handleAdapterChanged);
    coordinator.addListener(_handleCoordinatorChanged);
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!adapter.connected || _ended) return;
      _durationSeconds++;
      notifyListeners();
    });
  }

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaCallSummary call;
  final TurnaCallConnectPayload connect;
  final VoidCallback onSessionExpired;
  final ChatPreview? returnChatOnExit;
  final LiveKitCallAdapter adapter;

  bool _started = false;
  bool _ended = false;
  bool _reportedConnected = false;
  bool presentingFullScreen = false;
  String? terminalMessage;
  int _durationSeconds = 0;
  Timer? _durationTicker;

  bool get ended => _ended;
  int get durationSeconds => _durationSeconds;

  String formatDuration() {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    await adapter.connect();
  }

  void setFullScreenVisible(bool value) {
    if (presentingFullScreen == value) return;
    presentingFullScreen = value;
    notifyListeners();
  }

  Future<void> endCall() async {
    if (_ended) return;
    try {
      await CallApi.endCall(session, callId: call.id);
    } on TurnaUnauthorizedException {
      onSessionExpired();
    } catch (_) {}

    coordinator.clearCall(call.id);
    await adapter.disconnect();
    await TurnaNativeCallManager.endCallUi(call.id);
    _ended = true;
    terminalMessage = null;
    notifyListeners();
    kTurnaCallUiController.clearEndedSession(this);
  }

  void _handleAdapterChanged() {
    if (adapter.connected && !_reportedConnected) {
      _reportedConnected = true;
      TurnaNativeCallManager.setCallConnected(call.id);
    }
    notifyListeners();
  }

  void _handleCoordinatorChanged() {
    final terminal = coordinator.consumeTerminal(call.id);
    if (terminal == null || _ended) return;
    coordinator.clearCall(call.id);
    terminalMessage = switch (terminal.kind) {
      'declined' => 'Arama reddedildi.',
      'missed' => 'Cevap yok.',
      _ => 'Arama sonlandi.',
    };
    _ended = true;
    unawaited(adapter.disconnect());
    unawaited(TurnaNativeCallManager.endCallUi(call.id));
    notifyListeners();
    kTurnaCallUiController.clearEndedSession(this);
  }

  @override
  void dispose() {
    adapter.removeListener(_handleAdapterChanged);
    coordinator.removeListener(_handleCoordinatorChanged);
    _durationTicker?.cancel();
    adapter.dispose();
    super.dispose();
  }
}

class TurnaCallUiController {
  TurnaManagedCallSession? _currentSession;
  OverlayEntry? _miniOverlayEntry;
  VoidCallback? _miniListener;

  TurnaManagedCallSession obtainSession({
    required AuthSession session,
    required TurnaCallCoordinator coordinator,
    required TurnaCallSummary call,
    required TurnaCallConnectPayload connect,
    required VoidCallback onSessionExpired,
    ChatPreview? returnChatOnExit,
  }) {
    if (_currentSession?.call.id == call.id) {
      return _currentSession!;
    }
    _disposeCurrentSession();
    _currentSession = TurnaManagedCallSession(
      session: session,
      coordinator: coordinator,
      call: call,
      connect: connect,
      onSessionExpired: onSessionExpired,
      returnChatOnExit: returnChatOnExit,
    );
    return _currentSession!;
  }

  void showMini(TurnaManagedCallSession session) {
    hideMini();
    _currentSession = session;
    final navigator = kTurnaNavigatorKey.currentState;
    final overlay = navigator?.overlay;
    if (overlay == null) return;

    _miniListener = () {
      if (session.ended) {
        clearEndedSession(session);
      } else {
        _miniOverlayEntry?.markNeedsBuild();
      }
    };
    session.addListener(_miniListener!);
    _miniOverlayEntry = OverlayEntry(
      builder: (_) => _MiniCallOverlay(session: session),
    );
    overlay.insert(_miniOverlayEntry!);
  }

  void hideMini() {
    final session = _currentSession;
    final listener = _miniListener;
    if (session != null && listener != null) {
      session.removeListener(listener);
    }
    _miniListener = null;
    _miniOverlayEntry?.remove();
    _miniOverlayEntry = null;
  }

  Future<void> expandMini(TurnaManagedCallSession session) async {
    if (session.presentingFullScreen) return;
    hideMini();
    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => ActiveCallPage(callSession: session)),
    );
  }

  void clearEndedSession(TurnaManagedCallSession session) {
    if (!identical(_currentSession, session)) return;
    hideMini();
    if (!session.presentingFullScreen) {
      _currentSession = null;
      session.dispose();
    }
  }

  void releaseFullScreenSession(TurnaManagedCallSession session) {
    if (!identical(_currentSession, session)) return;
    if (session.ended) {
      hideMini();
      _currentSession = null;
      session.dispose();
    }
  }

  void _disposeCurrentSession() {
    hideMini();
    _currentSession?.dispose();
    _currentSession = null;
  }
}

class _MiniCallOverlay extends StatelessWidget {
  const _MiniCallOverlay({required this.session});

  final TurnaManagedCallSession session;

  @override
  Widget build(BuildContext context) {
    final remoteVideo = session.adapter.primaryRemoteVideoTrack;
    return Positioned(
      right: 16,
      top: 92,
      width: 138,
      height: 196,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => kTurnaCallUiController.expandMini(session),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                remoteVideo != null && session.call.type == TurnaCallType.video
                    ? lk.VideoTrackRenderer(remoteVideo)
                    : Container(
                        color: const Color(0xFF111416),
                        child: Center(
                          child: _ProfileAvatar(
                            label: session.call.peer.displayName,
                            avatarUrl: session.call.peer.avatarUrl,
                            authToken: session.session.token,
                            radius: 26,
                          ),
                        ),
                      ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.44),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      session.call.peer.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ActiveCallPage extends StatefulWidget {
  const ActiveCallPage({super.key, required this.callSession});

  final TurnaManagedCallSession callSession;

  @override
  State<ActiveCallPage> createState() => _ActiveCallPageState();
}

class _ActiveCallPageState extends State<ActiveCallPage> {
  late final TurnaManagedCallSession _callSession;
  bool _ending = false;
  bool _handledSessionEnd = false;

  @override
  void initState() {
    super.initState();
    _callSession = widget.callSession;
    kTurnaCallUiController.hideMini();
    _callSession
      ..addListener(_refresh)
      ..setFullScreenVisible(true);
    unawaited(_callSession.ensureStarted());
  }

  @override
  void dispose() {
    _callSession
      ..removeListener(_refresh)
      ..setFullScreenVisible(false);
    kTurnaCallUiController.releaseFullScreenSession(_callSession);
    super.dispose();
  }

  void _refresh() {
    if (_callSession.ended && !_handledSessionEnd && mounted) {
      _handledSessionEnd = true;
      final message = _callSession.terminalMessage;
      if (message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      _leaveCallView();
      return;
    }
    if (mounted) setState(() {});
  }

  void _leaveCallView() {
    final returnChat = _callSession.returnChatOnExit;
    if (returnChat == null) {
      Navigator.of(context).pop();
      return;
    }

    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      buildChatRoomRoute(
        chat: returnChat,
        session: _callSession.session,
        callCoordinator: _callSession.coordinator,
        onSessionExpired: _callSession.onSessionExpired,
      ),
      (route) => route.isFirst,
    );
  }

  void _minimizeCall() {
    if (_callSession.call.type != TurnaCallType.video) {
      _leaveCallView();
      return;
    }
    kTurnaCallUiController.showMini(_callSession);
    Navigator.of(context).pop();
  }

  Future<void> _endCall() async {
    if (_ending) return;
    setState(() => _ending = true);
    await _callSession.endCall();
    if (mounted) {
      _leaveCallView();
    }
  }

  @override
  Widget build(BuildContext context) {
    final adapter = _callSession.adapter;
    final remoteVideo = adapter.primaryRemoteVideoTrack;
    final localVideo = adapter.localVideoTrack;
    final isVideo = _callSession.call.type == TurnaCallType.video;

    return PopScope(
      canPop: !isVideo,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isVideo) {
          _minimizeCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF101314),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: isVideo ? _minimizeCall : _leaveCallView,
          ),
          title: Text(_callSession.call.peer.displayName),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: remoteVideo != null && isVideo
                    ? lk.VideoTrackRenderer(remoteVideo)
                    : Container(
                        color: const Color(0xFF101314),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ProfileAvatar(
                                label: _callSession.call.peer.displayName,
                                avatarUrl: _callSession.call.peer.avatarUrl,
                                authToken: _callSession.session.token,
                                radius: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _callSession.call.peer.displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                adapter.connecting
                                    ? 'Baglaniyor...'
                                    : (adapter.connected
                                          ? _callSession.formatDuration()
                                          : (adapter.error ??
                                                'Arama hazirlaniyor')),
                                style: const TextStyle(
                                  color: Color(0xFFB7BCB9),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              if (localVideo != null && isVideo)
                Positioned(
                  right: 16,
                  top: 16,
                  width: 110,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: Colors.black,
                      child: lk.VideoTrackRenderer(localVideo),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (isVideo)
                      FloatingActionButton(
                        heroTag: 'flip_${_callSession.call.id}',
                        backgroundColor: Colors.white12,
                        onPressed: adapter.connecting
                            ? null
                            : () => adapter.flipCamera(),
                        child: const Icon(
                          Icons.cameraswitch_outlined,
                          color: Colors.white,
                        ),
                      ),
                    FloatingActionButton(
                      heroTag: 'end_${_callSession.call.id}',
                      backgroundColor: Colors.red.shade400,
                      onPressed: _ending ? null : _endCall,
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                    FloatingActionButton(
                      heroTag: 'mute_${_callSession.call.id}',
                      backgroundColor: Colors.white12,
                      onPressed: adapter.connecting
                          ? null
                          : () => adapter.toggleMicrophone(),
                      child: Icon(
                        adapter.microphoneEnabled ? Icons.mic : Icons.mic_off,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
      return items;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      throw TurnaApiException('Arama gecmisi yuklenemedi.');
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
      throw TurnaApiException('Arama baslatilamadi.');
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
      throw TurnaApiException('Arama sonlandirilamadi.');
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
      throw TurnaApiException('Arama durumu esitlenemedi.');
    }
  }
}
