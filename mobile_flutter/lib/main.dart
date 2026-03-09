import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as rec;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';

part 'src/turna_chats.dart';
part 'src/turna_auth_flow.dart';
part 'src/turna_profile_shell.dart';
part 'src/turna_core.dart';

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
final ValueNotifier<AppLifecycleState> kTurnaLifecycleState = ValueNotifier(
  AppLifecycleState.resumed,
);
final TurnaActiveChatRegistry kTurnaActiveChatRegistry =
    TurnaActiveChatRegistry();
final TurnaCallUiController kTurnaCallUiController = TurnaCallUiController();

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
  static const Duration _minimumSplashDuration = Duration(milliseconds: 750);
  static const Duration _maximumBootstrapWait = Duration(seconds: 6);

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
              setState(() => _session = lateSession);
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
          ? TurnaPhoneAuthPage(
              onAuthenticated: (session) => setState(() => _session = session),
            )
          : _session!.needsOnboarding
          ? TurnaProfileOnboardingPage(
              session: _session!,
              onCompleted: (session) {
                setState(() => _session = session);
              },
            )
          : MainTabs(
              session: _session!,
              onSessionUpdated: (session) {
                setState(() => _session = session);
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
                setState(() => _session = null);
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
