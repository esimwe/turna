import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const String kBackendBaseUrl = 'http://178.104.8.155:4000';
const bool kTurnaDebugLogs = true;

void turnaLog(String message, [Object? data]) {
  if (!kTurnaDebugLogs) return;
  if (data != null) {
    debugPrint('[turna-mobile] $message | $data');
    return;
  }
  debugPrint('[turna-mobile] $message');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: theme,
      home: _session == null
          ? AuthPage(
              onAuthenticated: (session) => setState(() => _session = session),
            )
          : MainTabs(
              session: _session!,
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
      if (token == null || userId == null) {
        setState(() => _error = 'Sunucu yanıtı geçersiz.');
        return;
      }

      final session = AuthSession(
        token: token,
        userId: userId,
        displayName: displayName,
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
  const MainTabs({super.key, required this.session, required this.onLogout});

  final AuthSession session;
  final VoidCallback onLogout;

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _index = 0;
  late final PresenceSocketClient _presenceClient;

  @override
  void initState() {
    super.initState();
    _presenceClient = PresenceSocketClient(token: widget.session.token)..connect();
  }

  @override
  void dispose() {
    _presenceClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ChatsPage(session: widget.session),
      const PlaceholderPage(title: 'Updates'),
      const PlaceholderPage(title: 'Calls'),
      SettingsPage(session: widget.session, onLogout: widget.onLogout),
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
  const ChatsPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  int _refreshTick = 0;
  io.Socket? _inboxSocket;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _connectInboxUpdates();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _refreshTick++);
    });
  }

  void _connectInboxUpdates() {
    _inboxSocket = io.io(
      kBackendBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': widget.session.token})
          .disableAutoConnect()
          .build(),
    );

    _inboxSocket!.on('chat:inbox:update', (_) {
      if (!mounted) return;
      setState(() => _refreshTick++);
    });
    _inboxSocket!.onConnect((_) => turnaLog('inbox connected', {'id': _inboxSocket?.id}));
    _inboxSocket!.onConnectError((data) => turnaLog('inbox connect_error', data));
    _inboxSocket!.connect();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inboxSocket?.dispose();
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

          final chats = snapshot.data ?? [];
          return ListView.builder(
            itemCount: chats.isEmpty ? 2 : chats.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Sohbetlerde ara',
                      prefixIcon: const Icon(Icons.search),
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

              if (chats.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Henüz sohbet yok. Başlatmak için başka bir kullanıcıyla giriş yap.',
                  ),
                );
              }

              final chat = chats[index - 1];
              return ListTile(
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFDBEFE2),
                  child: Text(
                    chat.name.characters.first,
                    style: const TextStyle(
                      color: Color(0xFF1FAA59),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                        ),
                        child: Text(
                          chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
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
                    MaterialPageRoute(
                      builder: (_) =>
                          ChatRoomPage(chat: chat, session: widget.session),
                    ),
                  );
                },
              );
            },
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
              builder: (_) => NewChatPage(session: widget.session),
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
  const ChatRoomPage({super.key, required this.chat, required this.session});

  final ChatPreview chat;
  final AuthSession session;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  late final TurnaSocketClient _client;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    turnaLog('chat room init', {
      'chatId': widget.chat.chatId,
      'senderId': widget.session.userId,
    });
    _client = TurnaSocketClient(
      chatId: widget.chat.chatId,
      senderId: widget.session.userId,
      token: widget.session.token,
    )..connect();
    _client.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    turnaLog('chat room dispose', {'chatId': widget.chat.chatId});
    _client.removeListener(_refresh);
    _client.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chat.name)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: _client.messages.length,
              itemBuilder: (context, index) {
                final msg =
                    _client.messages[_client.messages.length - 1 - index];
                final mine = msg.senderId == widget.session.userId;
                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: mine ? const Color(0xFFDCF5E7) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text(msg.text)),
                        if (mine) ...[
                          const SizedBox(width: 6),
                          _StatusTick(status: msg.status),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
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
                    onPressed: () {
                      final text = _controller.text.trim();
                      if (text.isEmpty) return;
                      _client.send(text);
                      _controller.clear();
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

class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status});

  final ChatMessageStatus status;

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.done;
    Color color = const Color(0xFF7D8380);

    if (status == ChatMessageStatus.delivered) {
      icon = Icons.done_all;
    } else if (status == ChatMessageStatus.read) {
      icon = Icons.done_all;
      color = const Color(0xFF1FA3E0);
    }

    return Icon(icon, size: 16, color: color);
  }
}

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatUser> _users = const [];
  bool _loading = true;

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
    final users = await ChatApi.fetchDirectory(widget.session);
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
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
                hintText: 'Username veya isim ara',
                prefixIcon: const Icon(Icons.search),
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
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFFDBEFE2),
                          child: Text(
                            user.displayName.characters.first.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF1FAA59),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
                          );
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatRoomPage(
                                chat: chat,
                                session: widget.session,
                              ),
                            ),
                          );
                          if (!mounted) return;
                          Navigator.pop(context, true);
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
    required this.onLogout,
  });

  final AuthSession session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(
              radius: 25,
              backgroundColor: Color(0xFFDBEFE2),
              child: Icon(Icons.person, color: Color(0xFF1FAA59)),
            ),
            title: Text(
              session.displayName.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(session.userId),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
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
            const PlaceholderPage(title: 'Avatar'),
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

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Center(
            child: CircleAvatar(
              radius: 58,
              backgroundColor: Color(0xFFDBEFE2),
              child: Icon(Icons.person, size: 52, color: Color(0xFF1FAA59)),
            ),
          ),
          SizedBox(height: 18),
          _ProfileRow(
            label: 'Name',
            value: 'Jon Desuja',
            icon: Icons.person_outline,
          ),
          _ProfileRow(label: 'About', value: 'Busy', icon: Icons.info_outline),
          _ProfileRow(
            label: 'Phone',
            value: '+90 555 123 1230',
            icon: Icons.call_outlined,
          ),
          _ProfileRow(label: 'Links', value: 'Add links', icon: Icons.link),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF606664)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Color(0xFF606664))),
              ],
            ),
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

class ChatPreview {
  ChatPreview({
    required this.chatId,
    required this.name,
    required this.message,
    required this.time,
    this.unreadCount = 0,
  });

  final String chatId;
  final String name;
  final String message;
  final String time;
  final int unreadCount;
}

class ChatUser {
  ChatUser({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String text;
  final ChatMessageStatus status;
  final String createdAt;

  ChatMessage copyWith({ChatMessageStatus? status}) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      text: text,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: (map['id'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      status: ChatMessageStatusX.fromWire((map['status'] ?? '').toString()),
      createdAt: (map['createdAt'] ?? '').toString(),
    );
  }
}

enum ChatMessageStatus { sent, delivered, read }

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
}

class TurnaSocketClient extends ChangeNotifier {
  TurnaSocketClient({
    required this.chatId,
    required this.senderId,
    required this.token,
  });

  final String chatId;
  final String senderId;
  final String token;

  final List<ChatMessage> messages = [];
  io.Socket? _socket;
  bool _historyLoadedFromSocket = false;

  void connect() {
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
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      turnaLog('socket connected', {'id': _socket?.id, 'chatId': chatId});
      _socket!.emit('chat:join', {'chatId': chatId});
    });

    _socket!.onConnectError((data) {
      turnaLog('socket connect_error', data);
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
              (e) => ChatMessage.fromMap(Map<String, dynamic>.from(e)),
            ),
          );
        _markSeen();
        notifyListeners();
      }
    });

    _socket!.on('chat:message', (data) {
      if (data is Map) {
        turnaLog('socket chat:message', data);
        final message = ChatMessage.fromMap(Map<String, dynamic>.from(data));
        messages.add(message);
        if (message.senderId != senderId) {
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
      for (var i = 0; i < messages.length; i++) {
        final current = messages[i];
        if (!messageIds.contains(current.id)) continue;
        if (current.status == status) continue;
        messages[i] = current.copyWith(status: status);
        changed = true;
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
      turnaLog('socket disconnected', {'reason': reason, 'chatId': chatId});
    });

    _loadHistoryFromHttp();
    _socket!.connect();
  }

  Future<void> _loadHistoryFromHttp() async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/chats/$chatId/messages'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode >= 400) return;
      if (_historyLoadedFromSocket) return;

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final rawData = (map['data'] as List<dynamic>? ?? []);
      messages
        ..clear()
        ..addAll(
          rawData
              .whereType<Map>()
              .map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e))),
        );
      _markSeen();
      notifyListeners();
    } catch (_) {}
  }

  void _markSeen() {
    _socket?.emit('chat:seen', {'chatId': chatId});
  }

  void send(String text) {
    turnaLog('socket chat:send', {
      'chatId': chatId,
      'senderId': senderId,
      'textLen': text.length,
    });
    _socket?.emit('chat:send', {
      'chatId': chatId,
      'text': text,
    });
  }

  @override
  void dispose() {
    turnaLog('socket dispose', {'chatId': chatId, 'senderId': senderId});
    _socket?.dispose();
    super.dispose();
  }
}

class PresenceSocketClient {
  PresenceSocketClient({required this.token});

  final String token;
  io.Socket? _socket;

  void connect() {
    _socket = io.io(
      kBackendBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) => turnaLog('presence connected', {'id': _socket?.id}));
    _socket!.onDisconnect((reason) => turnaLog('presence disconnected', {'reason': reason}));
    _socket!.onConnectError((data) => turnaLog('presence connect_error', data));
    _socket!.connect();
  }

  void dispose() {
    _socket?.dispose();
  }
}

class AuthSession {
  AuthSession({
    required this.token,
    required this.userId,
    required this.displayName,
  });

  final String token;
  final String userId;
  final String displayName;

  static const _tokenKey = 'turna_auth_token';
  static const _userIdKey = 'turna_auth_user_id';
  static const _displayNameKey = 'turna_auth_display_name';

  static Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userId = prefs.getString(_userIdKey);
    final displayName = prefs.getString(_displayNameKey);
    if (token == null || userId == null || displayName == null) {
      return null;
    }

    return AuthSession(token: token, userId: userId, displayName: displayName);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_displayNameKey, displayName);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_displayNameKey);
  }
}

class ChatApi {
  static Future<List<ChatPreview>> fetchChats(
    AuthSession session, {
    int refreshTick = 0,
  }) async {
    final headers = {'Authorization': 'Bearer ${session.token}'};
    turnaLog('api fetchChats', {'refreshTick': refreshTick});

    final chatsRes = await http.get(
      Uri.parse('$kBackendBaseUrl/api/chats'),
      headers: headers,
    );
    if (chatsRes.statusCode >= 400) {
      turnaLog('api fetchChats failed', {'statusCode': chatsRes.statusCode});
      return [];
    }

    final chatsMap = jsonDecode(chatsRes.body) as Map<String, dynamic>;
    final chatsData = (chatsMap['data'] as List<dynamic>? ?? []);
    if (chatsData.isNotEmpty) {
      return chatsData.map((item) {
        final map = item as Map<String, dynamic>;
        return ChatPreview(
          chatId: map['chatId'].toString(),
          name: map['title']?.toString() ?? 'Chat',
          message: map['lastMessage']?.toString() ?? '',
          time: _formatTime(map['lastMessageAt']?.toString()),
          unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    }

    final users = await fetchDirectory(session);
    return users.map((user) {
      return ChatPreview(
        chatId: buildDirectChatId(session.userId, user.id),
        name: user.displayName,
        message: 'Sohbet başlat',
        time: '',
        unreadCount: 0,
      );
    }).toList();
  }

  static Future<List<ChatUser>> fetchDirectory(AuthSession session) async {
    final headers = {'Authorization': 'Bearer ${session.token}'};
    turnaLog('api fetchDirectory');
    final directoryRes = await http.get(
      Uri.parse('$kBackendBaseUrl/api/chats/directory/list'),
      headers: headers,
    );
    if (directoryRes.statusCode >= 400) {
      turnaLog('api fetchDirectory failed', {
        'statusCode': directoryRes.statusCode,
      });
      return [];
    }

    final directoryMap = jsonDecode(directoryRes.body) as Map<String, dynamic>;
    final users = (directoryMap['data'] as List<dynamic>? ?? []);
    return users.map((item) {
      final map = item as Map<String, dynamic>;
      return ChatUser(
        id: map['id'].toString(),
        displayName: map['displayName']?.toString() ?? 'User',
      );
    }).toList();
  }

  static String buildDirectChatId(String currentUserId, String peerUserId) {
    final sorted = [currentUserId, peerUserId]..sort();
    return 'direct_${sorted[0]}_${sorted[1]}';
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
