import type { Server } from "socket.io";
import { logInfo } from "../../lib/logger.js";
import type { ChatMessage } from "./chat.types.js";

let chatIo: Server | null = null;

export interface UserPresencePayload {
  userId: string;
  online: boolean;
  lastSeenAt: string | null;
}

export function attachChatRealtime(io: Server): void {
  chatIo = io;
}

export function sessionRoom(sessionId: string): string {
  return `session:${sessionId}`;
}

export async function registerUserSocket(
  userId: string,
  sessionId?: string | null
): Promise<boolean> {
  if (!chatIo) return true;
  const sockets = await chatIo.in(userRoom(userId)).allSockets();
  void sessionId;
  return sockets.size === 1;
}

export async function unregisterUserSocket(
  userId: string,
  sessionId?: string | null
): Promise<boolean> {
  if (!chatIo) return false;
  const sockets = await chatIo.in(userRoom(userId)).allSockets();
  void sessionId;
  return sockets.size === 0;
}

export async function isUserOnline(userId: string): Promise<boolean> {
  if (!chatIo) return false;
  const sockets = await chatIo.in(userRoom(userId)).allSockets();
  return sockets.size > 0;
}

export async function buildUserPresencePayload(
  userId: string,
  lastSeenAt: Date | string | null | undefined
): Promise<UserPresencePayload> {
  return {
    userId,
    online: await isUserOnline(userId),
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

export async function emitSessionRevoked(sessionId: string, reason: string): Promise<void> {
  if (!chatIo) return;

  const room = sessionRoom(sessionId);
  chatIo.to(room).emit("auth:session_revoked", { reason });

  const sockets = await chatIo.in(room).fetchSockets();
  for (const socket of sockets) {
    setTimeout(() => {
      socket.disconnect(true);
    }, 25);
  }
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
