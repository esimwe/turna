import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const String kBackendBaseUrl = 'http://178.104.8.155:4000';

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

class _TurnaAppState extends State<TurnaApp> {
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
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
          ? AuthPage(onAuthenticated: (session) => setState(() => _session = session))
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
        final body = jsonDecode(res.body);
        setState(() => _error = 'İşlem başarısız: ${body['error'] ?? res.statusCode}');
        return;
      }

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final token = map['accessToken']?.toString();
      final user = map['user'] as Map<String, dynamic>?;
      final userId = user?['id']?.toString();
      final displayName = user?['displayName']?.toString() ?? username;
      if (token == null || userId == null) {
        setState(() => _error = 'Sunucu yanıtı geçersiz.');
        return;
      }

      final session = AuthSession(token: token, userId: userId, displayName: displayName);
      await session.save();
      widget.onAuthenticated(session);
    } catch (_) {
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
          Text(_isRegisterMode ? 'Username/telefon ile kayıt ol.' : 'Username/telefon ile giriş yap.', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Telefon (opsiyonel)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Ad Soyad (kayıtta zorunlu)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Şifre (opsiyonel)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Text(_loading ? 'Bekleyin...' : (_isRegisterMode ? 'Kayıt Ol' : 'Giriş Yap')),
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
            child: Text(_isRegisterMode ? 'Hesabım var, giriş yap' : 'Hesabım yok, kayıt ol'),
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
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.update), label: 'Updates'),
          NavigationDestination(icon: Icon(Icons.call_outlined), label: 'Calls'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key, required this.session});

  final AuthSession session;

<<<<<<< HEAD
  static final chats = <ChatPreview>[
    ChatPreview(userId: 'jon', name: 'Mr Jon', message: 'Hi', time: '08:23', unread: 2),
    ChatPreview(userId: 'denver', name: 'Denver', message: 'Helo', time: '08:28', unread: 0),
    ChatPreview(userId: 'reck', name: 'Reck', message: 'Why', time: '07:23', unread: 0),
    ChatPreview(userId: 'heli', name: 'Heli', message: 'you', time: '08:23', unread: 1),
    ChatPreview(userId: 'junu', name: 'Junu', message: 'say no', time: '06:23', unread: 0),
  ];

=======
>>>>>>> 1a42523 (chore: connect local repo)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Turna', style: TextStyle(color: Color(0xFF1FAA59), fontWeight: FontWeight.w700)),
        actions: const [
          Icon(Icons.qr_code_scanner_outlined),
          SizedBox(width: 12),
          Icon(Icons.camera_alt_outlined),
          SizedBox(width: 12),
          Icon(Icons.more_vert),
          SizedBox(width: 8),
        ],
      ),
<<<<<<< HEAD
      body: ListView.builder(
        itemCount: chats.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Ask Meta AI Search',
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

          final chat = chats[index - 1];
          return ListTile(
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFDBEFE2),
              child: Text(chat.name.characters.first, style: const TextStyle(color: Color(0xFF1FAA59), fontWeight: FontWeight.w700)),
            ),
            title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(chat.time, style: const TextStyle(fontSize: 12, color: Color(0xFF777C79))),
                const SizedBox(height: 6),
                if (chat.unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: const BoxDecoration(color: Color(0xFF1FAA59), shape: BoxShape.circle),
                    child: Text('${chat.unread}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatRoomPage(chat: chat, session: session)),
=======
      body: FutureBuilder<List<ChatPreview>>(
        future: ChatApi.fetchChats(session),
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
                  child: Text('Henüz sohbet yok. Başlatmak için başka bir kullanıcıyla giriş yap.'),
                );
              }

              final chat = chats[index - 1];
              return ListTile(
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFDBEFE2),
                  child: Text(chat.name.characters.first, style: const TextStyle(color: Color(0xFF1FAA59), fontWeight: FontWeight.w700)),
                ),
                title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(chat.time, style: const TextStyle(fontSize: 12, color: Color(0xFF777C79))),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatRoomPage(chat: chat, session: session)),
                  );
                },
>>>>>>> 1a42523 (chore: connect local repo)
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1FAA59),
        foregroundColor: Colors.white,
        onPressed: () {},
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
    _client = TurnaSocketClient(
<<<<<<< HEAD
      chatId: 'direct_${widget.chat.userId}',
=======
      chatId: widget.chat.chatId,
>>>>>>> 1a42523 (chore: connect local repo)
      senderId: widget.session.userId,
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
                final msg = _client.messages[_client.messages.length - 1 - index];
                final mine = msg.senderId == widget.session.userId;
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: mine ? const Color(0xFFDCF5E7) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(msg.text),
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

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session, required this.onLogout});

  final AuthSession session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(radius: 25, backgroundColor: Color(0xFFDBEFE2), child: Icon(Icons.person, color: Color(0xFF1FAA59))),
            title: Text(session.displayName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(session.userId),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
          ),
          const Divider(height: 1),
          _settingsItem(context, Icons.vpn_key_outlined, 'Account', const AccountPage()),
          _settingsItem(context, Icons.lock_outline, 'Privacy', const PlaceholderPage(title: 'Privacy')),
          _settingsItem(context, Icons.face_outlined, 'Avatar', const PlaceholderPage(title: 'Avatar')),
          _settingsItem(context, Icons.list_alt_outlined, 'Lists', const PlaceholderPage(title: 'Lists')),
          _settingsItem(context, Icons.chat_bubble_outline, 'Chats', const PlaceholderPage(title: 'Chats')),
          _settingsItem(context, Icons.notifications_none, 'Notifications', const PlaceholderPage(title: 'Notifications')),
          _settingsItem(context, Icons.data_saver_off_outlined, 'Storage and data', const PlaceholderPage(title: 'Storage and data')),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }

  Widget _settingsItem(BuildContext context, IconData icon, String label, Widget page) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF606664)),
      title: Text(label),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
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
          _ProfileRow(label: 'Name', value: 'Jon Desuja', icon: Icons.person_outline),
          _ProfileRow(label: 'About', value: 'Busy', icon: Icons.info_outline),
          _ProfileRow(label: 'Phone', value: '+90 555 123 1230', icon: Icons.call_outlined),
          _ProfileRow(label: 'Links', value: 'Add links', icon: Icons.link),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value, required this.icon});

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
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Color(0xFF606664))),
              ],
            ),
          )
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
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityNotificationsPage())),
          ),
          const ListTile(leading: Icon(Icons.key_outlined), title: Text('Passkeys')),
          const ListTile(leading: Icon(Icons.email_outlined), title: Text('Email address')),
          const ListTile(leading: Icon(Icons.lock_outline), title: Text('Two-step verification')),
          const ListTile(leading: Icon(Icons.numbers_outlined), title: Text('Change number')),
          const ListTile(leading: Icon(Icons.description_outlined), title: Text('Request account info')),
          const ListTile(leading: Icon(Icons.person_add_alt_outlined), title: Text('Add account')),
          const ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete account')),
        ],
      ),
    );
  }
}

class SecurityNotificationsPage extends StatefulWidget {
  const SecurityNotificationsPage({super.key});

  @override
  State<SecurityNotificationsPage> createState() => _SecurityNotificationsPageState();
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
          const Text('Your chats and calls are private', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('End-to-end encryption keeps your personal messages and calls private between you and your contacts.'),
          const SizedBox(height: 16),
          const ListTile(leading: Icon(Icons.message_outlined), title: Text('Text and voice messages')),
          const ListTile(leading: Icon(Icons.call_outlined), title: Text('Audio and video calls')),
          const ListTile(leading: Icon(Icons.photo_outlined), title: Text('photos, videos and documents')),
          const ListTile(leading: Icon(Icons.location_on_outlined), title: Text('Location sharing')),
          const ListTile(leading: Icon(Icons.circle_outlined), title: Text('Status updates')),
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
<<<<<<< HEAD
  ChatPreview({required this.userId, required this.name, required this.message, required this.time, required this.unread});

  final String userId;
  final String name;
  final String message;
  final String time;
  final int unread;
=======
  ChatPreview({required this.chatId, required this.name, required this.message, required this.time});

  final String chatId;
  final String name;
  final String message;
  final String time;
>>>>>>> 1a42523 (chore: connect local repo)
}

class ChatMessage {
  ChatMessage({required this.senderId, required this.text});

  final String senderId;
  final String text;

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      senderId: (map['senderId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
    );
  }
}

class TurnaSocketClient extends ChangeNotifier {
  TurnaSocketClient({required this.chatId, required this.senderId});

  final String chatId;
  final String senderId;

  final List<ChatMessage> messages = [];
  io.Socket? _socket;

  void connect() {
    _socket = io.io(
      kBackendBaseUrl,
      io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );

    _socket!.onConnect((_) {
      _socket!.emit('chat:join', {'chatId': chatId});
    });

    _socket!.on('chat:history', (data) {
      if (data is List) {
        messages
          ..clear()
          ..addAll(data.whereType<Map>().map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e))));
        notifyListeners();
      }
    });

    _socket!.on('chat:message', (data) {
      if (data is Map) {
        messages.add(ChatMessage.fromMap(Map<String, dynamic>.from(data)));
        notifyListeners();
      }
    });

    _socket!.connect();
  }

  void send(String text) {
    _socket?.emit('chat:send', {
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
    });
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }
}

class AuthSession {
  AuthSession({required this.token, required this.userId, required this.displayName});

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
<<<<<<< HEAD
=======

class ChatApi {
  static Future<List<ChatPreview>> fetchChats(AuthSession session) async {
    final headers = {'Authorization': 'Bearer ${session.token}'};

    final chatsRes = await http.get(Uri.parse('$kBackendBaseUrl/api/chats'), headers: headers);
    if (chatsRes.statusCode >= 400) return [];

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
        );
      }).toList();
    }

    final directoryRes = await http.get(Uri.parse('$kBackendBaseUrl/api/chats/directory/list'), headers: headers);
    if (directoryRes.statusCode >= 400) return [];

    final directoryMap = jsonDecode(directoryRes.body) as Map<String, dynamic>;
    final users = (directoryMap['data'] as List<dynamic>? ?? []);
    return users.map((item) {
      final map = item as Map<String, dynamic>;
      final peerId = map['id'].toString();
      return ChatPreview(
        chatId: 'direct_$peerId',
        name: map['displayName']?.toString() ?? 'User',
        message: 'Sohbet başlat',
        time: '',
      );
    }).toList();
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
>>>>>>> 1a42523 (chore: connect local repo)
