import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';

const String kBackendBaseUrl = 'http://178.104.8.155:4000';
const bool kTurnaDebugLogs = true;
const String kChatRoomRouteName = 'chat-room';

final GlobalKey<NavigatorState> kTurnaNavigatorKey =
    GlobalKey<NavigatorState>();
final RouteObserver<PageRoute<dynamic>> kTurnaRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
final TurnaActiveChatRegistry kTurnaActiveChatRegistry =
    TurnaActiveChatRegistry();

void turnaLog(String message, [Object? data]) {
  if (!kTurnaDebugLogs) return;
  if (data != null) {
    debugPrint('[turna-mobile] $message | $data');
    return;
  }
  debugPrint('[turna-mobile] $message');
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
      scaffoldBackgroundColor: const Color(0xFFF4F5F3),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1FAA59),
        primary: const Color(0xFF1FAA59),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF202124),
        centerTitle: false,
      ),
      dividerColor: const Color(0xFFE8EAE8),
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
    if (state != AppLifecycleState.resumed) return;
    _presenceClient.refreshConnection();
    TurnaNativeCallManager.handleAppResumed();
    _inboxUpdateNotifier.value++;
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
      ChatsPage(
        session: widget.session,
        inboxUpdateNotifier: _inboxUpdateNotifier,
        callCoordinator: _callCoordinator,
        onSessionExpired: widget.onLogout,
      ),
      const PlaceholderPage(title: 'Updates'),
      CallsPage(
        session: widget.session,
        callCoordinator: _callCoordinator,
        onSessionExpired: widget.onLogout,
      ),
      SettingsPage(
        session: widget.session,
        onSessionUpdated: widget.onSessionUpdated,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chats',
          ),
          NavigationDestination(icon: Icon(Icons.update), label: 'Updates'),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
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
  });

  final AuthSession session;
  final VoidCallback onSessionExpired;
  final TurnaCallCoordinator callCoordinator;
  final ValueNotifier<int>? inboxUpdateNotifier;

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
            color: Color(0xFF1FAA59),
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
                        fillColor: const Color(0xFFEFF1EE),
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
                    style: const TextStyle(fontWeight: FontWeight.w600),
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
                            color: Color(0xFF1FAA59),
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
        backgroundColor: const Color(0xFF1FAA59),
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

class _ChatRoomPageState extends State<ChatRoomPage>
    with WidgetsBindingObserver, RouteAware {
  late final TurnaSocketClient _client;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _mediaPicker = ImagePicker();
  bool _showScrollToBottom = false;
  bool _attachmentBusy = false;
  int _lastRenderedMessageCount = 0;
  PageRoute<dynamic>? _route;

  String? get _peerUserId =>
      ChatApi.extractPeerUserId(widget.chat.chatId, widget.session.userId);

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
      token: widget.session.token,
      onSessionExpired: widget.onSessionExpired,
    )..connect();
    _client.addListener(_refresh);
    _scrollController.addListener(_handleScroll);
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
  }

  @override
  void didPopNext() {
    kTurnaActiveChatRegistry.setCurrent(widget.chat);
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
    if (_client.messages.length != _lastRenderedMessageCount) {
      _lastRenderedMessageCount = _client.messages.length;
      if (shouldSnapToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    }
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

  bool _shouldShowDayChip(List<ChatMessage> displayMessages, int index) {
    if (index == displayMessages.length - 1) return true;
    final current = DateTime.tryParse(displayMessages[index].createdAt);
    final older = DateTime.tryParse(displayMessages[index + 1].createdAt);
    if (current == null || older == null) return false;
    return current.year != older.year ||
        current.month != older.month ||
        current.day != older.day;
  }

  String? _guessContentType(String fileName) {
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

  String _formatFileSize(int bytes) {
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
        text: _controller.text.trim().isEmpty ? null : _controller.text.trim(),
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

  Future<void> _pickImage(ImageSource source) async {
    final file = await _mediaPicker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1800,
    );
    if (file == null) return;

    final contentType = _guessContentType(file.name);
    if (contentType == null || !contentType.startsWith('image/')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Desteklenmeyen gorsel formati.')),
      );
      return;
    }

    await _sendPickedAttachment(
      kind: ChatAttachmentKind.image,
      fileName: file.name,
      contentType: contentType,
      readBytes: file.readAsBytes,
      sizeBytes: await file.length(),
    );
  }

  Future<void> _pickVideo(ImageSource source) async {
    final file = await _mediaPicker.pickVideo(source: source);
    if (file == null) return;

    final contentType = _guessContentType(file.name);
    if (contentType == null || !contentType.startsWith('video/')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Desteklenmeyen video formati.')),
      );
      return;
    }

    await _sendPickedAttachment(
      kind: ChatAttachmentKind.video,
      fileName: file.name,
      contentType: contentType,
      readBytes: file.readAsBytes,
      sizeBytes: await file.length(),
    );
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
      contentType: _guessContentType(fileName) ?? 'application/octet-stream',
      readBytes: () => File(filePath).readAsBytes(),
      sizeBytes: file.size,
    );
  }

  Future<void> _showAttachmentSheet() async {
    if (_attachmentBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeriden foto'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Kameradan foto'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Galeriden video'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickVideo(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Kameradan video'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickVideo(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_outlined),
                title: const Text('Dosya sec'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickFile();
                },
              ),
            ],
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
    _controller.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _client.refreshConnection();
  }

  @override
  Widget build(BuildContext context) {
    final displayMessages = _client.messages.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _peerUserId == null ? null : _openPeerProfile,
          child: Row(
            children: [
              _ProfileAvatar(
                label: widget.chat.name,
                avatarUrl: widget.chat.avatarUrl,
                authToken: widget.session.token,
                radius: 18,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.chat.name)),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sesli ara',
            onPressed: _peerUserId == null
                ? null
                : () => _startCall(TurnaCallType.audio),
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            tooltip: 'Goruntulu ara',
            onPressed: _peerUserId == null
                ? null
                : () => _startCall(TurnaCallType.video),
            icon: const Icon(Icons.videocam_outlined),
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
              color: const Color(0xFFEAF6EE),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Medya yukleniyor. Mesaj hazirlaniyor...',
                style: TextStyle(color: Color(0xFF1E6B3C)),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (_client.loadingInitial && displayMessages.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (displayMessages.isEmpty)
                  const _CenteredState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Henuz mesaj yok',
                    message: 'Ilk mesaji gondererek sohbeti baslat.',
                  )
                else
                  ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: displayMessages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == displayMessages.length) {
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

                      final msg = displayMessages[index];
                      final mine = msg.senderId == widget.session.userId;
                      final hasText = msg.text.trim().isNotEmpty;
                      final hasError =
                          msg.errorText != null &&
                          msg.errorText!.trim().isNotEmpty;
                      final metaFooter = _MessageMetaFooter(
                        timeLabel: _formatMessageTime(msg.createdAt),
                        mine: mine,
                        status: msg.status,
                      );
                      return Column(
                        children: [
                          if (_shouldShowDayChip(displayMessages, index))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8ECE8),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    _formatDayLabel(msg.createdAt),
                                    style: const TextStyle(
                                      color: Color(0xFF5C625F),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onTap:
                                  mine &&
                                      (msg.status == ChatMessageStatus.failed ||
                                          msg.status ==
                                              ChatMessageStatus.queued)
                                  ? () => _client.retryMessage(msg)
                                  : null,
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? const Color(0xFFDCF5E7)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: msg.status == ChatMessageStatus.failed
                                      ? Border.all(color: Colors.red.shade200)
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (hasError)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Text(
                                          msg.errorText!,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                msg.status ==
                                                    ChatMessageStatus.failed
                                                ? Colors.red.shade600
                                                : const Color(0xFF777C79),
                                          ),
                                        ),
                                      ),
                                    if (hasText &&
                                        msg.attachments.isEmpty &&
                                        !hasError)
                                      SizedBox(
                                        width: double.infinity,
                                        child: Stack(
                                          alignment: Alignment.bottomRight,
                                          children: [
                                            Padding(
                                              padding: EdgeInsets.only(
                                                right: mine ? 56 : 40,
                                              ),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(msg.text),
                                              ),
                                            ),
                                            metaFooter,
                                          ],
                                        ),
                                      )
                                    else if (hasText)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(msg.text),
                                      ),
                                    if (hasText && msg.attachments.isNotEmpty)
                                      const SizedBox(height: 10),
                                    if (msg.attachments.isNotEmpty) ...[
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: _ChatAttachmentList(
                                          attachments: msg.attachments,
                                          onTap: _openAttachment,
                                          formatFileSize: _formatFileSize,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    if (msg.attachments.isNotEmpty || hasError)
                                      metaFooter,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1FAA59),
                      onPressed: _jumpToBottom,
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _attachmentBusy ? null : _showAttachmentSheet,
                    icon: _attachmentBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: 'Mesaj',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    backgroundColor: const Color(0xFF1FAA59),
                    onPressed: _attachmentBusy
                        ? null
                        : () {
                            final text = _controller.text.trim();
                            if (text.isEmpty) return;
                            _client.send(text);
                            TurnaAnalytics.logEvent('message_sent', {
                              'chat_id': widget.chat.chatId,
                              'kind': 'text',
                            });
                            _controller.clear();
                            _jumpToBottom();
                          },
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
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
  });

  final String timeLabel;
  final bool mine;
  final ChatMessageStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeLabel,
          style: const TextStyle(fontSize: 11, color: Color(0xFF777C79)),
        ),
        if (mine) ...[const SizedBox(width: 6), _StatusTick(status: status)],
      ],
    );
  }
}

class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status});

  final ChatMessageStatus status;

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.done;
    Color color = const Color(0xFF7D8380);

    if (status == ChatMessageStatus.sending) {
      icon = Icons.schedule;
    } else if (status == ChatMessageStatus.queued) {
      icon = Icons.cloud_off_outlined;
    } else if (status == ChatMessageStatus.failed) {
      icon = Icons.error_outline;
      color = Colors.red.shade400;
    } else if (status == ChatMessageStatus.delivered) {
      icon = Icons.done_all;
    } else if (status == ChatMessageStatus.read) {
      icon = Icons.done_all;
      color = const Color(0xFF1FA3E0);
    }

    return Icon(icon, size: 16, color: color);
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
                  color: const Color(0xFFE8ECE8),
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
                color: const Color(0xFFF3F5F3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.play_circle_outline
                          : Icons.insert_drive_file_outlined,
                      color: const Color(0xFF1FAA59),
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
                            color: Color(0xFF777C79),
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
                fillColor: const Color(0xFFEFF1EE),
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

class SettingsPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: _SessionAvatar(session: session),
            title: Text(
              session.displayName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(session.userId),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfilePage(
                  session: session,
                  onProfileUpdated: onSessionUpdated,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          _settingsItem(
            context,
            Icons.vpn_key_outlined,
            'Account',
            const AccountPage(),
          ),
          _settingsItem(
            context,
            Icons.lock_outline,
            'Privacy',
            const PlaceholderPage(title: 'Privacy'),
          ),
          _settingsItem(
            context,
            Icons.face_outlined,
            'Avatar',
            ProfilePage(session: session, onProfileUpdated: onSessionUpdated),
          ),
          _settingsItem(
            context,
            Icons.list_alt_outlined,
            'Lists',
            const PlaceholderPage(title: 'Lists'),
          ),
          _settingsItem(
            context,
            Icons.chat_bubble_outline,
            'Chats',
            const PlaceholderPage(title: 'Chats'),
          ),
          _settingsItem(
            context,
            Icons.notifications_none,
            'Notifications',
            const PlaceholderPage(title: 'Notifications'),
          ),
          _settingsItem(
            context,
            Icons.data_saver_off_outlined,
            'Storage and data',
            const PlaceholderPage(title: 'Storage and data'),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }

  Widget _settingsItem(
    BuildContext context,
    IconData icon,
    String label,
    Widget page,
  ) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF606664)),
      title: Text(label),
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
    );
  }
}

class _SessionAvatar extends StatelessWidget {
  const _SessionAvatar({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    return _ProfileAvatar(
      label: session.displayName,
      avatarUrl: session.avatarUrl,
      authToken: session.token,
      radius: 25,
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
        backgroundColor: const Color(0xFFDBEFE2),
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
      backgroundColor: const Color(0xFFDBEFE2),
      child: Text(
        initial,
        style: TextStyle(
          color: const Color(0xFF1FAA59),
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
  });

  final AuthSession session;
  final String userId;
  final String fallbackName;
  final String? fallbackAvatarUrl;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  TurnaUserProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
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

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final name = profile?.displayName ?? widget.fallbackName;
    final avatarUrl = profile?.avatarUrl ?? widget.fallbackAvatarUrl;

    if (_loading && profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kullanici Profili')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kullanici Profili')),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Kullanici Profili')),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                radius: 58,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 18),
          if (about != null && about.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Hakkinda'),
                subtitle: Text(about),
              ),
            ),
          if (phone != null && phone.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('Telefon'),
                subtitle: Text(phone),
              ),
            ),
          if ((about == null || about.isEmpty) &&
              (phone == null || phone.isEmpty))
            const Card(
              child: ListTile(
                leading: Icon(Icons.person_outline),
                title: Text('Bu kullanici henuz profil detayi eklememis.'),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loadProfile,
            child: const Text('Sunucudan yenile'),
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
          const Icon(Icons.lock, size: 54, color: Color(0xFF1FAA59)),
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
    required this.token,
    this.onSessionExpired,
  });

  final String chatId;
  final String senderId;
  final String token;
  final VoidCallback? onSessionExpired;

  static const int _pageSize = 30;
  final List<ChatMessage> messages = [];
  final Map<String, Timer> _messageTimeouts = {};
  final Map<String, ChatMessageStatus> _pendingStatusByMessageId = {};
  io.Socket? _socket;
  bool _historyLoadedFromSocket = false;
  bool _restoredPendingMessages = false;
  bool _isFlushingQueue = false;
  int _localMessageSeq = 0;
  bool isConnected = false;
  bool loadingInitial = true;
  bool loadingMore = false;
  bool hasMore = true;
  String? nextBefore;
  String? error;

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

    _socket!.onDisconnect((reason) {
      isConnected = false;
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
    for (final timer in _messageTimeouts.values) {
      timer.cancel();
    }
    _messageTimeouts.clear();
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
    await _consumePendingAction();
    await _recoverAcceptedNativeCall();
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
    await navigator.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'active-call'),
        builder: (_) => ActiveCallPage(
          session: session,
          coordinator: coordinator,
          call: accepted.call,
          connect: accepted.connect,
          onSessionExpired: _onSessionExpired ?? () {},
          returnChatOnExit: returnChat,
        ),
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
        actionColor: '#1FAA59',
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
          message: map['lastMessage']?.toString() ?? '',
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
                            : const Color(0xFF1FAA59),
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
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'active-call'),
          builder: (_) => ActiveCallPage(
            session: widget.session,
            coordinator: widget.coordinator,
            call: accepted.call,
            connect: accepted.connect,
            onSessionExpired: widget.onSessionExpired,
            returnChatOnExit: widget.returnChatOnExit,
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
            child: Column(
              children: [
                const Spacer(),
                _ProfileAvatar(
                  label: call.peer.displayName,
                  avatarUrl: call.peer.avatarUrl,
                  authToken: widget.session.token,
                  radius: 48,
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Column(
                    children: [
                      Text(
                        call.peer.displayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isVideo ? 'Goruntulu arama' : 'Sesli arama',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB7BCB9),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FloatingActionButton(
                      heroTag: 'decline_${call.id}',
                      backgroundColor: Colors.red.shade400,
                      onPressed: _busy ? null : _decline,
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                    FloatingActionButton(
                      heroTag: 'accept_${call.id}',
                      backgroundColor: const Color(0xFF1FAA59),
                      onPressed: _busy ? null : _accept,
                      child: Icon(
                        isVideo ? Icons.videocam : Icons.call,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ActiveCallPage(
            session: widget.session,
            coordinator: widget.coordinator,
            call: accepted.call,
            connect: accepted.connect,
            onSessionExpired: widget.onSessionExpired,
          ),
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
          child: Column(
            children: [
              const Spacer(),
              _ProfileAvatar(
                label: call.peer.displayName,
                avatarUrl: call.peer.avatarUrl,
                authToken: widget.session.token,
                radius: 48,
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Column(
                  children: [
                    Text(
                      call.peer.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      call.type == TurnaCallType.video
                          ? 'Goruntulu arama caliyor...'
                          : 'Sesli arama caliyor...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB7BCB9),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FloatingActionButton(
                backgroundColor: Colors.red.shade400,
                onPressed: _ending ? null : _cancelCall,
                child: const Icon(Icons.call_end, color: Colors.white),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
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

class ActiveCallPage extends StatefulWidget {
  const ActiveCallPage({
    super.key,
    required this.session,
    required this.coordinator,
    required this.call,
    required this.connect,
    required this.onSessionExpired,
    this.returnChatOnExit,
  });

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaCallSummary call;
  final TurnaCallConnectPayload connect;
  final VoidCallback onSessionExpired;
  final ChatPreview? returnChatOnExit;

  @override
  State<ActiveCallPage> createState() => _ActiveCallPageState();
}

class _ActiveCallPageState extends State<ActiveCallPage> {
  late final LiveKitCallAdapter _adapter;
  bool _ending = false;
  bool _reportedConnected = false;
  Timer? _durationTicker;
  int _durationSeconds = 0;

  @override
  void initState() {
    super.initState();
    _adapter =
        LiveKitCallAdapter(
            connectPayload: widget.connect,
            videoEnabled: widget.call.type == TurnaCallType.video,
          )
          ..addListener(_refresh)
          ..connect();
    widget.coordinator.addListener(_handleCoordinator);
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_adapter.connected) return;
      setState(() => _durationSeconds++);
    });
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinator);
    _durationTicker?.cancel();
    _adapter.removeListener(_refresh);
    _adapter.dispose();
    super.dispose();
  }

  void _refresh() {
    if (_adapter.connected && !_reportedConnected) {
      _reportedConnected = true;
      TurnaNativeCallManager.setCallConnected(widget.call.id);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _handleCoordinator() {
    final terminal = widget.coordinator.consumeTerminal(widget.call.id);
    if (terminal == null || !mounted) return;
    TurnaNativeCallManager.endCallUi(widget.call.id);
    _leaveCallView();
  }

  void _leaveCallView() {
    final returnChat = widget.returnChatOnExit;
    if (returnChat == null) {
      Navigator.of(context).pop();
      return;
    }

    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      buildChatRoomRoute(
        chat: returnChat,
        session: widget.session,
        callCoordinator: widget.coordinator,
        onSessionExpired: widget.onSessionExpired,
      ),
      (route) => route.isFirst,
    );
  }

  Future<void> _endCall() async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      await CallApi.endCall(widget.session, callId: widget.call.id);
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onSessionExpired();
      }
    } catch (_) {}

    widget.coordinator.clearCall(widget.call.id);
    await _adapter.disconnect();
    await TurnaNativeCallManager.endCallUi(widget.call.id);
    if (mounted) {
      _leaveCallView();
    }
  }

  String _formatDuration() {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final remoteVideo = _adapter.primaryRemoteVideoTrack;
    final localVideo = _adapter.localVideoTrack;
    final isVideo = widget.call.type == TurnaCallType.video;

    return Scaffold(
      backgroundColor: const Color(0xFF101314),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.call.peer.displayName),
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
                              label: widget.call.peer.displayName,
                              avatarUrl: widget.call.peer.avatarUrl,
                              authToken: widget.session.token,
                              radius: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.call.peer.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _adapter.connecting
                                  ? 'Baglaniyor...'
                                  : (_adapter.connected
                                        ? _formatDuration()
                                        : (_adapter.error ??
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
                  FloatingActionButton(
                    heroTag: 'mute_${widget.call.id}',
                    backgroundColor: Colors.white12,
                    onPressed: _adapter.connecting
                        ? null
                        : () => _adapter.toggleMicrophone(),
                    child: Icon(
                      _adapter.microphoneEnabled ? Icons.mic : Icons.mic_off,
                      color: Colors.white,
                    ),
                  ),
                  FloatingActionButton(
                    heroTag: 'speaker_${widget.call.id}',
                    backgroundColor: _adapter.speakerEnabled
                        ? const Color(0xFF1FAA59)
                        : Colors.white12,
                    onPressed: _adapter.connecting
                        ? null
                        : () => _adapter.toggleSpeaker(),
                    child: Icon(
                      _adapter.speakerEnabled ? Icons.volume_up : Icons.hearing,
                      color: Colors.white,
                    ),
                  ),
                  if (isVideo)
                    FloatingActionButton(
                      heroTag: 'camera_${widget.call.id}',
                      backgroundColor: Colors.white12,
                      onPressed: _adapter.connecting
                          ? null
                          : () => _adapter.toggleCamera(),
                      child: Icon(
                        _adapter.cameraEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        color: Colors.white,
                      ),
                    ),
                  FloatingActionButton(
                    heroTag: 'end_${widget.call.id}',
                    backgroundColor: Colors.red.shade400,
                    onPressed: _ending ? null : _endCall,
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
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
}
