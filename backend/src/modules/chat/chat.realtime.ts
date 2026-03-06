import type { Server } from "socket.io";
import { logInfo } from "../../lib/logger.js";
import type { ChatMessage } from "./chat.types.js";

let chatIo: Server | null = null;

export function attachChatRealtime(io: Server): void {
  chatIo = io;
}

export function userRoom(userId: string): string {
  return `user:${userId}`;
}

export function emitInboxUpdate(userIds: string[]): void {
  if (!chatIo) return;
  const uniqueUserIds = Array.from(new Set(userIds));
  for (const userId of uniqueUserIds) {
    chatIo.to(userRoom(userId)).emit("chat:inbox:update");
  }
}

export function emitChatMessage(chatId: string, message: ChatMessage, participantIds: string[]): void {
  if (!chatIo) return;
  chatIo.to(chatId).emit("chat:message", message);
  for (const participantId of participantIds) {
    chatIo.to(userRoom(participantId)).emit("chat:message", message);
  }
}

export async function getSocketsInUserRoom(userId: string) {
  if (!chatIo) return [];
  return chatIo.in(userRoom(userId)).fetchSockets();
}

export function emitChatStatus(params: {
  chatId: string;
  status: "delivered" | "read";
  messageIds: string[];
  participantIds?: string[];
  userIds?: string[];
}): void {
  if (!chatIo) return;

  const payload = {
    chatId: params.chatId,
    status: params.status,
    messageIds: params.messageIds
  };

  chatIo.to(params.chatId).emit("chat:status", payload);

  const userIds = params.userIds ?? params.participantIds ?? [];
  for (const userId of userIds) {
    chatIo.to(userRoom(userId)).emit("chat:status", payload);
  }
}

export function logRealtimeUnavailable(context: string): void {
  if (!chatIo) {
    logInfo("chat realtime unavailable", { context });
  }
}
