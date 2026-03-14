import type { Server } from "socket.io";
import { userRoom } from "../chat/chat.realtime.js";

let communityIo: Server | null = null;

export function attachCommunityRealtime(io: Server): void {
  communityIo = io;
}

export function communityChannelRoom(channelId: string): string {
  return `community:channel:${channelId}`;
}

export function communityThreadRoom(messageId: string): string {
  return `community:thread:${messageId}`;
}

export function emitCommunityChannelMessage(payload: {
  communityId: string;
  channelId: string;
  message: Record<string, unknown>;
}): void {
  if (!communityIo) return;
  communityIo
    .to(communityChannelRoom(payload.channelId))
    .emit("community:channel:message", payload);
}

export function emitCommunityThreadMessage(payload: {
  communityId: string;
  channelId: string;
  rootMessageId: string;
  message: Record<string, unknown>;
}): void {
  if (!communityIo) return;
  communityIo
    .to(communityThreadRoom(payload.rootMessageId))
    .emit("community:thread:message", payload);
}

export function emitCommunityThreadUpdate(payload: {
  communityId: string;
  channelId: string;
  rootMessageId: string;
  replyCount: number;
}): void {
  if (!communityIo) return;
  communityIo
    .to(communityChannelRoom(payload.channelId))
    .emit("community:thread:update", payload);
}

export function emitCommunityNotification(userIds: string[], payload: Record<string, unknown>): void {
  if (!communityIo) return;
  for (const userId of new Set(userIds)) {
    communityIo.to(userRoom(userId)).emit("community:notification", payload);
  }
}
