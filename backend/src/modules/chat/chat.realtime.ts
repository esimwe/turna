import type { Server } from "socket.io";
import { redis } from "../../lib/redis.js";
import { logInfo } from "../../lib/logger.js";
import type { ChatMessage } from "./chat.types.js";

let chatIo: Server | null = null;
const PRESENCE_TTL_SECONDS = 60 * 60 * 12;

export interface UserPresencePayload {
  userId: string;
  online: boolean;
  lastSeenAt: string | null;
}

export function attachChatRealtime(io: Server): void {
  chatIo = io;
}

function presenceKey(userId: string): string {
  return `turna:presence:user:${userId}:sockets`;
}

function canUseRedisPresence(): boolean {
  return redis.status === "ready";
}

async function getPresenceCount(userId: string): Promise<number | null> {
  if (!canUseRedisPresence()) return null;
  try {
    return await redis.scard(presenceKey(userId));
  } catch {
    return null;
  }
}

async function syncPresenceCount(userId: string): Promise<number> {
  if (!chatIo) return 0;
  const sockets = await chatIo.in(userRoom(userId)).allSockets();
  if (!canUseRedisPresence()) {
    return sockets.size;
  }

  const key = presenceKey(userId);
  const multi = redis.multi().del(key);
  if (sockets.size > 0) {
    multi.sadd(key, [...sockets]).expire(key, PRESENCE_TTL_SECONDS);
  }
  await multi.exec();
  return sockets.size;
}

export function sessionRoom(sessionId: string): string {
  return `session:${sessionId}`;
}

export function chatRoom(chatId: string): string {
  return `chat:${chatId}`;
}

export async function registerUserSocket(
  userId: string,
  sessionId?: string | null
): Promise<boolean> {
  void sessionId;
  if (!chatIo) return true;
  const previousCount = await getPresenceCount(userId);
  const nextCount = await syncPresenceCount(userId);
  return (previousCount ?? 0) == 0 && nextCount > 0;
}

export async function unregisterUserSocket(
  userId: string,
  sessionId?: string | null
): Promise<boolean> {
  void sessionId;
  if (!chatIo) return false;
  const previousCount = await getPresenceCount(userId);
  const nextCount = await syncPresenceCount(userId);
  return (previousCount ?? 1) > 0 && nextCount == 0;
}

export async function isUserOnline(userId: string): Promise<boolean> {
  const cachedCount = await getPresenceCount(userId);
  if (cachedCount != null) {
    return cachedCount > 0;
  }
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
  chatIo.to(chatRoom(chatId)).emit("chat:message", message);
  void getActiveChatUserIds(chatId)
    .then((activeUserIds) => {
      for (const participantId of participantIds) {
        if (activeUserIds.includes(participantId)) continue;
        chatIo?.to(userRoom(participantId)).emit("chat:message", message);
      }
    })
    .catch(() => {
      for (const participantId of participantIds) {
        chatIo?.to(userRoom(participantId)).emit("chat:message", message);
      }
    });
}

export async function getSocketsInUserRoom(userId: string) {
  if (!chatIo) return [];
  return chatIo.in(userRoom(userId)).fetchSockets();
}

export async function getActiveChatUserIds(chatId: string): Promise<string[]> {
  if (!chatIo) return [];
  const sockets = await chatIo.in(chatRoom(chatId)).fetchSockets();
  const userIds = new Set<string>();
  for (const socket of sockets) {
    const userId = typeof socket.data.userId === "string" ? socket.data.userId : null;
    if (userId) {
      userIds.add(userId);
    }
  }
  return [...userIds];
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
  chatType?: "direct" | "group";
  status: "delivered" | "read";
  messageIds: string[];
  participantIds?: string[];
  userIds?: string[];
}): void {
  if (!chatIo) return;

  const payload = {
    chatId: params.chatId,
    chatType: params.chatType ?? null,
    status: params.status,
    messageIds: params.messageIds
  };

  chatIo.to(chatRoom(params.chatId)).emit("chat:status", payload);

  const userIds = params.userIds ?? params.participantIds ?? [];
  emitUserEvent(userIds, "chat:status", payload);
}

export function logRealtimeUnavailable(context: string): void {
  if (!chatIo) {
    logInfo("chat realtime unavailable", { context });
  }
}
