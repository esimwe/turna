import '../features/chat/turna_chat_models.dart';

enum TurnaShellMode { turna, community }

List<ChatPreview> prioritizeTurnaFavoritedChats(Iterable<ChatPreview> chats) {
  final favorited = <ChatPreview>[];
  final regular = <ChatPreview>[];
  for (final chat in chats) {
    if (chat.isFavorited) {
      favorited.add(chat);
    } else {
      regular.add(chat);
    }
  }
  return [...favorited, ...regular];
}
