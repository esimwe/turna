export type ChatMessageStatus = "sent" | "delivered" | "read";

export interface ChatMessage {
  id: string;
  chatId: string;
  senderId: string;
  text: string;
  createdAt: string;
  status: ChatMessageStatus;
}

export interface SendMessagePayload {
  chatId: string;
  senderId: string;
  text: string;
}

export interface ChatSummary {
  chatId: string;
  title: string;
  lastMessage: string;
  lastMessageAt: string | null;
  unreadCount: number;
  peerId: string | null;
  peerAvatarKey: string | null;
  peerUpdatedAt: string | null;
}

export interface DirectoryUser {
  id: string;
  displayName: string;
  avatarKey: string | null;
  updatedAt: string;
}
