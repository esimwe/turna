import 'package:flutter/foundation.dart';

import '../features/chat/turna_chat_models.dart';

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
