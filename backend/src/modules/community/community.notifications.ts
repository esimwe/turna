import { prisma } from "../../lib/prisma.js";

const prismaCommunityNotification = (
  prisma as unknown as { communityNotification: any }
).communityNotification;

export type CommunityNotificationTypeValue =
  | "REPLY"
  | "MENTION"
  | "ANNOUNCEMENT"
  | "DM_REQUEST";

export interface CreateCommunityNotificationInput {
  userId: string;
  type: CommunityNotificationTypeValue;
  communityId?: string | null;
  channelId?: string | null;
  messageId?: string | null;
  topicId?: string | null;
  title: string;
  body?: string | null;
  metadata?: Record<string, unknown> | null;
}

export interface CommunityNotificationRow {
  id: string;
  type: CommunityNotificationTypeValue;
  communityId: string | null;
  channelId: string | null;
  messageId: string | null;
  topicId: string | null;
  title: string;
  body: string | null;
  readAt: Date | null;
  createdAt: Date;
}

export function extractMentionedUsernames(text: string): string[] {
  const usernames = new Set<string>();
  const matches = text.matchAll(/(^|[\s(])@([a-zA-Z0-9_]{3,32})\b/g);
  for (const match of matches) {
    const username = match[2]?.trim().toLowerCase();
    if (username) {
      usernames.add(username);
    }
  }
  return [...usernames];
}

export async function createCommunityNotifications(
  inputs: CreateCommunityNotificationInput[]
): Promise<void> {
  if (inputs.length === 0) return;

  const deduped = new Map<string, CreateCommunityNotificationInput>();
  for (const input of inputs) {
    const key = [
      input.userId,
      input.type,
      input.communityId ?? "",
      input.channelId ?? "",
      input.messageId ?? "",
      input.topicId ?? "",
      input.title
    ].join(":");
    deduped.set(key, input);
  }

  await prismaCommunityNotification.createMany({
    data: [...deduped.values()].map((item) => ({
      userId: item.userId,
      type: item.type,
      communityId: item.communityId ?? null,
      channelId: item.channelId ?? null,
      messageId: item.messageId ?? null,
      topicId: item.topicId ?? null,
      title: item.title,
      body: item.body ?? null,
      metadata: item.metadata ?? null
    }))
  });
}

export async function listCommunityNotifications(params: {
  userId: string;
  limit: number;
}): Promise<CommunityNotificationRow[]> {
  return prismaCommunityNotification.findMany({
    where: {
      userId: params.userId
    },
    take: params.limit,
    orderBy: [{ createdAt: "desc" }],
    select: {
      id: true,
      type: true,
      communityId: true,
      channelId: true,
      messageId: true,
      topicId: true,
      title: true,
      body: true,
      readAt: true,
      createdAt: true
    }
  });
}
