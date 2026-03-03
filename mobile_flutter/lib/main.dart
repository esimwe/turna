import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const String kBackendBaseUrl = 'https://turna-production.up.railway.app';

void main() {
  runApp(const TurnaApp());
}

class TurnaApp extends StatelessWidget {
  const TurnaApp({super.key});

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
      home: const MainTabs(),
    );
  }
}

class MainTabs extends StatefulWidget {
  const MainTabs({super.key});

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ChatsPage(),
      const PlaceholderPage(title: 'Updates'),
      const PlaceholderPage(title: 'Calls'),
      const SettingsPage(),
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
  const ChatsPage({super.key});

  static final chats = <ChatPreview>[
    ChatPreview(userId: 'jon', name: 'Mr Jon', message: 'Hi', time: '08:23', unread: 2),
    ChatPreview(userId: 'denver', name: 'Denver', message: 'Helo', time: '08:28', unread: 0),
    ChatPreview(userId: 'reck', name: 'Reck', message: 'Why', time: '07:23', unread: 0),
    ChatPreview(userId: 'heli', name: 'Heli', message: 'you', time: '08:23', unread: 1),
    ChatPreview(userId: 'junu', name: 'Junu', message: 'say no', time: '06:23', unread: 0),
  ];

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
                MaterialPageRoute(builder: (_) => ChatRoomPage(chat: chat)),
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
  const ChatRoomPage({super.key, required this.chat});

  final ChatPreview chat;

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
      chatId: 'direct_me_${widget.chat.userId}',
      senderId: 'me',
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
                final mine = msg.senderId == 'me';
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
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(radius: 25, backgroundColor: Color(0xFFDBEFE2), child: Icon(Icons.person, color: Color(0xFF1FAA59))),
            title: const Text('JON DESUJA', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Busy'),
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
  ChatPreview({required this.userId, required this.name, required this.message, required this.time, required this.unread});

  final String userId;
  final String name;
  final String message;
  final String time;
  final int unread;
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
