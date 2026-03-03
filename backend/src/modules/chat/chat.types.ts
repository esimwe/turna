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
