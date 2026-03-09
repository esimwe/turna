import { logInfo } from "../../lib/logger.js";
let chatIo = null;
const socketIdsByUserId = new Map();
export function attachChatRealtime(io) {
    chatIo = io;
}
export function registerUserSocket(userId, socketId) {
    const socketIds = socketIdsByUserId.get(userId) ?? new Set();
    const wasOnline = socketIds.size > 0;
    socketIds.add(socketId);
    socketIdsByUserId.set(userId, socketIds);
    return !wasOnline;
}
export function unregisterUserSocket(userId, socketId) {
    const socketIds = socketIdsByUserId.get(userId);
    if (!socketIds)
        return false;
    const wasOnline = socketIds.size > 0;
    socketIds.delete(socketId);
    if (socketIds.size === 0) {
        socketIdsByUserId.delete(userId);
    }
    return wasOnline && !isUserOnline(userId);
}
export function isUserOnline(userId) {
    return (socketIdsByUserId.get(userId)?.size ?? 0) > 0;
}
export function buildUserPresencePayload(userId, lastSeenAt) {
    return {
        userId,
        online: isUserOnline(userId),
        lastSeenAt: lastSeenAt instanceof Date
            ? lastSeenAt.toISOString()
            : typeof lastSeenAt === "string"
                ? lastSeenAt
                : null
    };
}
export function userRoom(userId) {
    return `user:${userId}`;
}
export function emitUserEvent(userIds, eventName, payload) {
    if (!chatIo)
        return;
    const uniqueUserIds = Array.from(new Set(userIds));
    for (const userId of uniqueUserIds) {
        chatIo.to(userRoom(userId)).emit(eventName, payload);
    }
}
export function emitInboxUpdate(userIds) {
    emitUserEvent(userIds, "chat:inbox:update", undefined);
}
export function emitPresenceUpdate(userIds, payload) {
    emitUserEvent(userIds, "user:presence", payload);
}
export function emitChatMessage(chatId, message, participantIds) {
    if (!chatIo)
        return;
    chatIo.to(chatId).emit("chat:message", message);
    for (const participantId of participantIds) {
        chatIo.to(userRoom(participantId)).emit("chat:message", message);
    }
}
export async function getSocketsInUserRoom(userId) {
    if (!chatIo)
        return [];
    return chatIo.in(userRoom(userId)).fetchSockets();
}
export function emitChatStatus(params) {
    if (!chatIo)
        return;
    const payload = {
        chatId: params.chatId,
        status: params.status,
        messageIds: params.messageIds
    };
    chatIo.to(params.chatId).emit("chat:status", payload);
    const userIds = params.userIds ?? params.participantIds ?? [];
    emitUserEvent(userIds, "chat:status", payload);
}
export function logRealtimeUnavailable(context) {
    if (!chatIo) {
        logInfo("chat realtime unavailable", { context });
    }
}
