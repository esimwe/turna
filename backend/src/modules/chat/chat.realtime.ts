import type { Server } from "socket.io";
import { logInfo } from "../../lib/logger.js";
import type { ChatMessage } from "./chat.types.js";

let chatIo: Server | null = null;
const socketIdsByUserId = new Map<string, Set<string>>();

export interface UserPresencePayload {
  userId: string;
  online: boolean;
  lastSeenAt: string | null;
}

export function attachChatRealtime(io: Server): void {
  chatIo = io;
}

export function registerUserSocket(userId: string, socketId: string): boolean {
  const socketIds = socketIdsByUserId.get(userId) ?? new Set<string>();
  const wasOnline = socketIds.size > 0;
  socketIds.add(socketId);
  socketIdsByUserId.set(userId, socketIds);
  return !wasOnline;
}

export function unregisterUserSocket(userId: string, socketId: string): boolean {
  const socketIds = socketIdsByUserId.get(userId);
  if (!socketIds) return false;

  const wasOnline = socketIds.size > 0;
  socketIds.delete(socketId);
  if (socketIds.size === 0) {
    socketIdsByUserId.delete(userId);
  }

  return wasOnline && !isUserOnline(userId);
}

export function isUserOnline(userId: string): boolean {
  return (socketIdsByUserId.get(userId)?.size ?? 0) > 0;
}

export function buildUserPresencePayload(
  userId: string,
  lastSeenAt: Date | string | null | undefined
): UserPresencePayload {
  return {
    userId,
    online: isUserOnline(userId),
    lastSeenAt:
      lastSeenAt instanceof Date
        ? lastSeenAt.toISOString()
        : typeof lastSeenAt === "string"
          ? lastSeenAt
          : null
  };
}

export function userRoom(userId: string): string {
  return `user:${userId}`;
}

export function emitUserEvent<T>(userIds: string[], eventName: string, payload: T): void {
  if (!chatIo) return;
  const uniqueUserIds = Array.from(new Set(userIds));
  for (const userId of uniqueUserIds) {
    chatIo.to(userRoom(userId)).emit(eventName, payload);
  }
}

export function emitInboxUpdate(userIds: string[]): void {
  emitUserEvent(userIds, "chat:inbox:update", undefined);
}

export function emitPresenceUpdate(userIds: string[], payload: UserPresencePayload): void {
  emitUserEvent(userIds, "user:presence", payload);
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
  emitUserEvent(userIds, "chat:status", payload);
}

export function logRealtimeUnavailable(context: string): void {
  if (!chatIo) {
    logInfo("chat realtime unavailable", { context });
  }
}
