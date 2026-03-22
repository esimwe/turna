import { randomBytes } from "node:crypto";
import { logError } from "../../lib/logger.js";
import { prisma } from "../../lib/prisma.js";
import { createObjectReadUrl, deleteObject, getObjectHead } from "../../lib/storage.js";
import {
  areUsersBlocked,
  getBlockedUserIdsByUser,
  setUserBlocked
} from "../../lib/user-relationship.js";
import {
  allowedMessageExpirationSeconds,
  canRequesterAddUserToGroup,
  getUserPrivacyPreference
} from "../../lib/user-privacy.js";
import type {
  AppChatType,
  ChatBanSummary,
  ChatAttachment,
  ChatDetail,
  ChatInviteLinkSummary,
  ChatJoinRequestSummary,
  ChatMessage,
  ChatMessageEditHistoryEntry,
  ChatMessageMention,
  ChatMessageReaction,
  ChatMessagePage,
  ChatMemberSummary,
  ChatMuteSummary,
  ChatPinnedMessageSummary,
  ScheduledMessageSummary,
  ChatSummary,
  DirectoryUser,
  SendMessageAttachmentInput,
  SendMessagePayload
} from "./chat.types.js";
import {
  TURNA_DELETED_EVERYONE_MARKER,
  canExtendLiveLocationEditWindow,
  summarizeTurnaMessageText
} from "./message-text.js";
import { normalizeUsername } from "../profile/username.js";
const AttachmentKind = {
  IMAGE: "IMAGE",
  VIDEO: "VIDEO",
  FILE: "FILE"
} as const;
const AttachmentTransferMode = {
  STANDARD: "STANDARD",
  HD: "HD",
  DOCUMENT: "DOCUMENT"
} as const;
const ChatType = {
  DIRECT: "DIRECT",
  GROUP: "GROUP"
} as const;
const ChatMemberRole = {
  OWNER: "OWNER",
  ADMIN: "ADMIN",
  EDITOR: "EDITOR",
  MEMBER: "MEMBER"
} as const;
const ChatMemberAddPolicy = {
  OWNER_ONLY: "OWNER_ONLY",
  ADMIN_ONLY: "ADMIN_ONLY",
  EDITOR_ONLY: "EDITOR_ONLY",
  EVERYONE: "EVERYONE"
} as const;
const ChatPolicyScope = {
  OWNER_ONLY: "OWNER_ONLY",
  ADMIN_ONLY: "ADMIN_ONLY",
  EDITOR_ONLY: "EDITOR_ONLY",
  EVERYONE: "EVERYONE"
} as const;
const ADMIN_NOTICE_SYSTEM_TYPE = "admin_notice";
const ADMIN_NOTICE_SILENT_SYSTEM_TYPE = "admin_notice_silent";
const GROUP_MEMBERS_ADDED_SYSTEM_TYPE = "group_members_added";
const GROUP_MEMBER_LEFT_SYSTEM_TYPE = "group_member_left";
const GROUP_MEMBER_REMOVED_SYSTEM_TYPE = "group_member_removed";
const GROUP_INFO_UPDATED_SYSTEM_TYPE = "group_info_updated";
const GROUP_SETTINGS_UPDATED_SYSTEM_TYPE = "group_settings_updated";
const GROUP_ROLE_UPDATED_SYSTEM_TYPE = "group_role_updated";
const GROUP_OWNER_TRANSFERRED_SYSTEM_TYPE = "group_owner_transferred";
const GROUP_JOIN_REQUEST_CREATED_SYSTEM_TYPE = "group_join_request_created";
const GROUP_JOIN_REQUEST_APPROVED_SYSTEM_TYPE = "group_join_request_approved";
const GROUP_MEMBER_MUTED_SYSTEM_TYPE = "group_member_muted";
const GROUP_MEMBER_UNMUTED_SYSTEM_TYPE = "group_member_unmuted";
const GROUP_MEMBER_BANNED_SYSTEM_TYPE = "group_member_banned";
const GROUP_MEMBER_UNBANNED_SYSTEM_TYPE = "group_member_unbanned";
const DIRECT_MESSAGE_EXPIRATION_UPDATED_SYSTEM_TYPE =
  "direct_message_expiration_updated";
const SAVED_MESSAGES_TITLE = "Kendime Notlar";
const MessageStatus = {
  sent: "sent",
  delivered: "delivered",
  read: "read"
} as const;
type AttachmentKindValue = typeof AttachmentKind[keyof typeof AttachmentKind];
type AttachmentTransferModeValue =
  typeof AttachmentTransferMode[keyof typeof AttachmentTransferMode];
type MessageStatusValue = typeof MessageStatus[keyof typeof MessageStatus];
type ChatTypeValue = typeof ChatType[keyof typeof ChatType];
type ChatMemberRoleValue = typeof ChatMemberRole[keyof typeof ChatMemberRole];
type ChatMemberAddPolicyValue =
  typeof ChatMemberAddPolicy[keyof typeof ChatMemberAddPolicy];
type ChatPolicyScopeValue = typeof ChatPolicyScope[keyof typeof ChatPolicyScope];
type ChatCollectionFilter = "media" | "docs" | "links";

function buildGroupMemberPreviewNames(
  members: Array<{
    userId: string;
    user?: {
      displayName?: string | null;
    } | null;
  }>,
  currentUserId: string,
  limit = 3
): string[] {
  return members
    .filter((member) => member.userId !== currentUserId)
    .map((member) => member.user?.displayName?.trim() ?? "")
    .filter((name) => name.length > 0)
    .slice(0, limit);
}

const prismaUser = (prisma as unknown as { user: any }).user;
const prismaReportCase = (prisma as unknown as { reportCase: any }).reportCase;
const prismaChatInviteLink = (prisma as unknown as { chatInviteLink: any }).chatInviteLink;
const prismaChatJoinRequest = (prisma as unknown as { chatJoinRequest: any }).chatJoinRequest;
const prismaChatMute = (prisma as unknown as { chatMute: any }).chatMute;
const prismaChatBan = (prisma as unknown as { chatBan: any }).chatBan;
const prismaMessageReaction = (prisma as unknown as { messageReaction: any }).messageReaction;
const prismaChatPinnedMessage = (prisma as unknown as { chatPinnedMessage: any }).chatPinnedMessage;
const DELETE_FOR_EVERYONE_WINDOW_MS = 10 * 60 * 1000;
const EDIT_MESSAGE_WINDOW_MS = 10 * 60 * 1000;
const CHAT_FOLDER_LIMIT = 3;
const GROUP_MEMBER_LIMIT = 2048;
const GROUP_CREATED_SYSTEM_TYPE = "group_created";
const GROUP_FLOOD_WINDOW_MS = 10 * 1000;
const GROUP_FLOOD_LIMIT = 8;
const groupSendRateLimit = new Map<string, number[]>();

const messageInclude = {
  attachments: {
    orderBy: { createdAt: "asc" as const }
  },
  sender: {
    select: {
      id: true,
      displayName: true
    }
  },
  mentions: {
    select: {
      mentionedUser: {
        select: {
          id: true,
          username: true,
          displayName: true
        }
      }
    }
  },
  reactions: {
    select: {
      emoji: true,
      userId: true
    }
  },
  pins: {
    where: { unpinnedAt: null },
    select: {
      messageId: true
    }
  }
};

type MessageRow = {
  id: string;
  chatId: string;
  senderId: string;
  text: string | null;
  systemType: string | null;
  systemPayload: unknown;
  createdAt: Date;
  expiresAt: Date | null;
  status: MessageStatusValue;
  editedAt: Date | null;
  editHistory: unknown;
  sender: {
    id: string;
    displayName: string;
  };
  mentions: Array<{
    mentionedUser: {
      id: string;
      username: string | null;
      displayName: string | null;
    };
  }>;
  reactions: Array<{
    emoji: string;
    userId: string;
  }>;
  pins: Array<{
    messageId: string;
  }>;
  attachments: Array<{
    id: string;
    objectKey: string;
    kind: AttachmentKindValue;
    transferMode: AttachmentTransferModeValue;
    fileName: string | null;
    contentType: string;
    sizeBytes: number;
    width: number | null;
    height: number | null;
    durationSeconds: number | null;
  }>;
};

type ScheduledMessageRow = {
  id: string;
  chatId: string;
  senderId: string;
  text: string;
  silent: boolean;
  scheduledFor: Date;
  createdAt: Date;
  status: "PENDING" | "PROCESSING" | "SENT" | "CANCELED" | "FAILED";
  lastError: string | null;
};

function isAllowedMessageExpirationSeconds(
  value: number | null | undefined
): value is (typeof allowedMessageExpirationSeconds)[number] {
  return value != null && allowedMessageExpirationSeconds.includes(value as any);
}

function buildActiveMessageExpirationWhere(now: Date = new Date()) {
  return {
    OR: [{ expiresAt: null }, { expiresAt: { gt: now } }]
  };
}

function isMessageActiveAt(
  message: { expiresAt?: Date | null },
  now: Date = new Date()
): boolean {
  return !message.expiresAt || message.expiresAt.getTime() > now.getTime();
}

function formatMessageExpirationSummary(seconds: number | null): string {
  switch (seconds) {
    case 24 * 60 * 60:
      return "24 Saat";
    case 7 * 24 * 60 * 60:
      return "7 Gün";
    case 90 * 24 * 60 * 60:
      return "90 Gün";
    default:
      return "Kapalı";
  }
}

function extractMentionUsernames(text: string | null | undefined): string[] {
  if (!text) return [];
  const matches = text.matchAll(/(^|[\s(])@([a-z][a-z0-9._]{2,23})/gi);
  const usernames = new Set<string>();
  for (const match of matches) {
    const raw = match[2]?.trim();
    if (!raw) continue;
    usernames.add(normalizeUsername(raw));
  }
  return [...usernames];
}

async function resolveMentionedUsersForChat(
  tx: any,
  chatId: string,
  senderId: string,
  text: string | null | undefined
): Promise<Array<{ userId: string }>> {
  const usernames = extractMentionUsernames(text);
  if (usernames.length === 0) return [];

  const members = await tx.chatMember.findMany({
    where: {
      chatId,
      userId: { not: senderId },
      user: {
        username: { in: usernames }
      }
    },
    select: {
      userId: true
    }
  });

  return members;
}

function toAttachmentKind(kind: AttachmentKindValue): ChatAttachment["kind"] {
  switch (kind) {
    case AttachmentKind.IMAGE:
      return "image";
    case AttachmentKind.VIDEO:
      return "video";
    default:
      return "file";
  }
}

function fromAttachmentKind(kind: SendMessageAttachmentInput["kind"]): AttachmentKindValue {
  switch (kind) {
    case "image":
      return AttachmentKind.IMAGE;
    case "video":
      return AttachmentKind.VIDEO;
    default:
      return AttachmentKind.FILE;
  }
}

function toAttachmentTransferMode(
  transferMode: AttachmentTransferModeValue | null | undefined
): ChatAttachment["transferMode"] {
  switch (transferMode) {
    case AttachmentTransferMode.HD:
      return "hd";
    case AttachmentTransferMode.DOCUMENT:
      return "document";
    default:
      return "standard";
  }
}

function fromAttachmentTransferMode(
  transferMode: SendMessageAttachmentInput["transferMode"]
): AttachmentTransferModeValue {
  switch (transferMode) {
    case "hd":
      return AttachmentTransferMode.HD;
    case "document":
      return AttachmentTransferMode.DOCUMENT;
    default:
      return AttachmentTransferMode.STANDARD;
  }
}

function isAudioAttachmentMeta(attachment: {
  kind: AttachmentKindValue;
  contentType?: string | null;
  fileName?: string | null;
}): boolean {
  const contentType = attachment.contentType?.toLowerCase() ?? "";
  if (contentType.startsWith("audio/")) return true;

  const fileName = attachment.fileName?.toLowerCase() ?? "";
  return (
    fileName.endsWith(".m4a") ||
    fileName.endsWith(".aac") ||
    fileName.endsWith(".mp3") ||
    fileName.endsWith(".wav") ||
    fileName.endsWith(".ogg") ||
    fileName.endsWith(".opus")
  );
}

function summarizeMessage(row: {
  text: string | null;
  systemType?: string | null;
  systemPayload?: Record<string, unknown> | null;
  attachments?: Array<{
    kind: AttachmentKindValue;
    contentType?: string | null;
    fileName?: string | null;
  }>;
}): string {
  if (row.systemType === GROUP_CREATED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const creatorName =
      typeof payload?.createdByDisplayName === "string" ? payload.createdByDisplayName.trim() : "";
    return creatorName ? `Grup oluşturuldu - ${creatorName} tarafından` : "Grup oluşturuldu";
  }

  if (row.systemType === GROUP_MEMBERS_ADDED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const rawNames = Array.isArray(payload?.memberNames)
      ? payload?.memberNames.filter((item): item is string => typeof item === "string")
      : [];
    const names = rawNames.map((item) => item.trim()).filter((item) => item.length > 0);
    if (names.length === 0) return "Yeni üyeler eklendi";
    if (names.length === 1) return `${names[0]} gruba eklendi`;
    if (names.length === 2) return `${names[0]} ve ${names[1]} gruba eklendi`;
    return `${names[0]} ve ${names.length - 1} kişi daha gruba eklendi`;
  }

  if (row.systemType === GROUP_MEMBER_LEFT_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const leftByDisplayName =
      typeof payload?.leftByDisplayName === "string" ? payload.leftByDisplayName.trim() : "";
    return leftByDisplayName.length > 0
      ? `${leftByDisplayName} gruptan ayrıldı`
      : "Bir üye gruptan ayrıldı";
  }

  if (row.systemType === GROUP_MEMBER_REMOVED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const memberDisplayName =
      typeof payload?.memberDisplayName === "string" ? payload.memberDisplayName.trim() : "";
    return memberDisplayName.length > 0
      ? `${memberDisplayName} gruptan çıkarıldı`
      : "Bir üye gruptan çıkarıldı";
  }

  if (row.systemType === GROUP_INFO_UPDATED_SYSTEM_TYPE) {
    return "Grup bilgileri güncellendi";
  }

  if (row.systemType === GROUP_SETTINGS_UPDATED_SYSTEM_TYPE) {
    return "Grup ayarları güncellendi";
  }

  if (row.systemType === DIRECT_MESSAGE_EXPIRATION_UPDATED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const seconds =
      typeof payload?.messageExpirationSeconds === "number"
        ? payload.messageExpirationSeconds
        : null;
    return seconds == null
      ? "Süreli mesajlar kapatıldı"
      : `Süreli mesajlar ${formatMessageExpirationSummary(seconds)} olarak ayarlandı`;
  }

  if (row.systemType === GROUP_ROLE_UPDATED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const memberDisplayName =
      typeof payload?.memberDisplayName === "string" ? payload.memberDisplayName.trim() : "";
    const roleLabel = typeof payload?.roleLabel === "string" ? payload.roleLabel.trim() : "";
    if (memberDisplayName && roleLabel) {
      return `${memberDisplayName} ${roleLabel} yapıldı`;
    }
    return "Üye rolü güncellendi";
  }

  if (row.systemType === GROUP_OWNER_TRANSFERRED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const newOwnerDisplayName =
      typeof payload?.newOwnerDisplayName === "string" ? payload.newOwnerDisplayName.trim() : "";
    return newOwnerDisplayName.length > 0
      ? `Grubun sahipliği ${newOwnerDisplayName} kişisine devredildi`
      : "Grubun sahipliği devredildi";
  }

  if (row.systemType === GROUP_JOIN_REQUEST_CREATED_SYSTEM_TYPE) {
    return "Katılım isteği gönderildi";
  }

  if (row.systemType === GROUP_JOIN_REQUEST_APPROVED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const memberDisplayName =
      typeof payload?.memberDisplayName === "string" ? payload.memberDisplayName.trim() : "";
    return memberDisplayName.length > 0
      ? `${memberDisplayName} gruba kabul edildi`
      : "Katılım isteği onaylandı";
  }

  if (row.systemType === GROUP_MEMBER_MUTED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const memberDisplayName =
      typeof payload?.memberDisplayName === "string" ? payload.memberDisplayName.trim() : "";
    return memberDisplayName.length > 0
      ? `${memberDisplayName} sessize alındı`
      : "Bir üye sessize alındı";
  }

  if (row.systemType === GROUP_MEMBER_UNMUTED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const memberDisplayName =
      typeof payload?.memberDisplayName === "string" ? payload.memberDisplayName.trim() : "";
    return memberDisplayName.length > 0
      ? `${memberDisplayName} tekrar konuşabilir`
      : "Sessiz kullanıcı kaldırıldı";
  }

  if (row.systemType === GROUP_MEMBER_BANNED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const memberDisplayName =
      typeof payload?.memberDisplayName === "string" ? payload.memberDisplayName.trim() : "";
    return memberDisplayName.length > 0
      ? `${memberDisplayName} gruptan yasaklandı`
      : "Bir üye gruptan yasaklandı";
  }

  if (row.systemType === GROUP_MEMBER_UNBANNED_SYSTEM_TYPE) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const memberDisplayName =
      typeof payload?.memberDisplayName === "string" ? payload.memberDisplayName.trim() : "";
    return memberDisplayName.length > 0
      ? `${memberDisplayName} yasağı kaldırıldı`
      : "Yasak kaldırıldı";
  }

  if (
    row.systemType === ADMIN_NOTICE_SYSTEM_TYPE ||
    row.systemType === ADMIN_NOTICE_SILENT_SYSTEM_TYPE
  ) {
    const payload =
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null;
    const title = typeof payload?.title === "string" ? payload.title.trim() : "";
    const text = typeof payload?.text === "string" ? payload.text.trim() : "";
    return title || text || "Bilgi notu";
  }

  const text = summarizeTurnaMessageText(row.text);
  if (text) return text;

  const attachments = row.attachments ?? [];
  if (attachments.length === 0) return "Sohbet başlat";
  if (attachments.length > 1) return `${attachments.length} ek gönderildi`;

  switch (attachments[0].kind) {
    case AttachmentKind.IMAGE:
      return "Fotoğraf";
    case AttachmentKind.VIDEO:
      return "Video";
    default:
      return isAudioAttachmentMeta(attachments[0]) ? "Ses kaydı" : "Dosya";
  }
}

function isSilentSystemType(systemType: string | null | undefined): boolean {
  return (systemType ?? "").trim() === ADMIN_NOTICE_SILENT_SYSTEM_TYPE;
}

async function toChatAttachment(
  row: MessageRow["attachments"][number]
): Promise<ChatAttachment> {
  let url: string | null = null;
  try {
    url = await createObjectReadUrl(row.objectKey);
  } catch (error) {
    logError("attachment read url create failed", error);
  }

  return {
    id: row.id,
    objectKey: row.objectKey,
    kind: toAttachmentKind(row.kind),
    transferMode: toAttachmentTransferMode(row.transferMode),
    fileName: row.fileName,
    contentType: row.contentType,
    sizeBytes: row.sizeBytes,
    width: row.width,
    height: row.height,
    durationSeconds: row.durationSeconds,
    url
  };
}

function latestDate(a: Date | null | undefined, b: Date | null | undefined): Date | null {
  if (a && b) {
    return a.getTime() >= b.getTime() ? a : b;
  }
  return a ?? b ?? null;
}

function toEditHistoryEntries(value: unknown): ChatMessageEditHistoryEntry[] {
  if (!Array.isArray(value)) return [];

  return value
    .map((item) => {
      if (!item || typeof item !== "object") return null;
      const map = item as Record<string, unknown>;
      const text = typeof map.text === "string" ? map.text : null;
      const editedAt = typeof map.editedAt === "string" ? map.editedAt : null;
      if (!text || !editedAt) return null;
      return { text, editedAt };
    })
    .filter((item): item is ChatMessageEditHistoryEntry => item != null);
}

async function toChatMessage(row: MessageRow): Promise<ChatMessage> {
  const attachments = await Promise.all(row.attachments.map((attachment) => toChatAttachment(attachment)));
  const mentions: ChatMessageMention[] = row.mentions.map((entry) => ({
    userId: entry.mentionedUser.id,
    username: entry.mentionedUser.username ?? null,
    displayName: entry.mentionedUser.displayName ?? null
  }));
  const reactionsByEmoji = new Map<string, Set<string>>();
  for (const reaction of row.reactions) {
    if (!reactionsByEmoji.has(reaction.emoji)) {
      reactionsByEmoji.set(reaction.emoji, new Set<string>());
    }
    reactionsByEmoji.get(reaction.emoji)!.add(reaction.userId);
  }
  const reactions: ChatMessageReaction[] = [...reactionsByEmoji.entries()]
    .map(([emoji, userIds]) => ({
      emoji,
      count: userIds.size,
      userIds: [...userIds]
    }))
    .sort((a, b) => a.emoji.localeCompare(b.emoji));
  return {
    id: row.id,
    chatId: row.chatId,
    senderId: row.senderId,
    senderDisplayName: row.sender?.displayName ?? null,
    text: row.text ?? "",
    systemType: row.systemType ?? null,
    systemPayload:
      row.systemPayload && typeof row.systemPayload === "object"
        ? (row.systemPayload as Record<string, unknown>)
        : null,
    createdAt: row.createdAt.toISOString(),
    expiresAt: row.expiresAt ? row.expiresAt.toISOString() : null,
    status: row.status,
    editedAt: row.editedAt ? row.editedAt.toISOString() : null,
    isEdited: row.editedAt != null,
    editHistory: toEditHistoryEntries(row.editHistory),
    mentions,
    reactions,
    isPinned: row.pins.length > 0,
    attachments
  };
}

function toScheduledMessageSummary(row: ScheduledMessageRow): ScheduledMessageSummary {
  return {
    id: row.id,
    chatId: row.chatId,
    senderId: row.senderId,
    text: row.text,
    silent: row.silent,
    scheduledFor: row.scheduledFor.toISOString(),
    createdAt: row.createdAt.toISOString(),
    status: row.status === "FAILED" ? "FAILED" : "PENDING",
    lastError: row.lastError?.trim() || null
  };
}

export class ChatService {
  async getMessageById(messageId: string): Promise<{
    id: string;
    chatId: string;
    senderId: string;
    text: string | null;
    createdAt: Date;
  } | null> {
    return prisma.message.findUnique({
      where: { id: messageId },
      select: {
        id: true,
        chatId: true,
        senderId: true,
        text: true,
        createdAt: true
      }
    });
  }

  private async getMembershipState(chatId: string, userId: string): Promise<{
    role: ChatMemberRoleValue;
    canSend: boolean;
    joinedAt: Date;
    hiddenAt: Date | null;
    clearedAt: Date | null;
    archivedAt: Date | null;
    muted: boolean;
    favorited: boolean;
    locked: boolean;
    folderId: string | null;
  } | null> {
    return prisma.chatMember.findUnique({
      where: { chatId_userId: { chatId, userId } },
      select: {
        role: true,
        canSend: true,
        joinedAt: true,
        hiddenAt: true,
        clearedAt: true,
        archivedAt: true,
        muted: true,
        favorited: true,
        locked: true,
        folderId: true
      }
    });
  }

  private async getChatMeta(chatId: string): Promise<{
    id: string;
    type: ChatTypeValue;
    title: string | null;
    avatarUrl: string | null;
    description: string | null;
    createdByUserId: string | null;
    isPublic: boolean;
    joinApprovalRequired: boolean;
    memberAddPolicy: ChatMemberAddPolicyValue;
    whoCanSend: ChatPolicyScopeValue;
    whoCanEditInfo: ChatPolicyScopeValue;
    whoCanInvite: ChatPolicyScopeValue;
    whoCanAddMembers: ChatPolicyScopeValue;
    whoCanStartCalls: ChatPolicyScopeValue;
    historyVisibleToNewMembers: boolean;
    messageExpirationSeconds: number | null;
    usesDefaultMessageExpiration: boolean;
    defaultMessageExpirationUserId: string | null;
  } | null> {
    return prisma.chat.findUnique({
      where: { id: chatId },
      select: {
        id: true,
        type: true,
        title: true,
        avatarUrl: true,
        description: true,
        createdByUserId: true,
        isPublic: true,
        joinApprovalRequired: true,
        memberAddPolicy: true,
        whoCanSend: true,
        whoCanEditInfo: true,
        whoCanInvite: true,
        whoCanAddMembers: true,
        whoCanStartCalls: true,
        historyVisibleToNewMembers: true,
        messageExpirationSeconds: true,
        usesDefaultMessageExpiration: true,
        defaultMessageExpirationUserId: true
      }
    });
  }

  private async getActiveMute(chatId: string, userId: string): Promise<{
    id: string;
    mutedUntil: Date | null;
    reason: string | null;
  } | null> {
    const now = new Date();
    return prismaChatMute.findFirst({
      where: {
        chatId,
        userId,
        revokedAt: null,
        OR: [{ mutedUntil: null }, { mutedUntil: { gt: now } }]
      },
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        mutedUntil: true,
        reason: true
      }
    });
  }

  private async getActiveBan(chatId: string, userId: string): Promise<{ id: string } | null> {
    return prismaChatBan.findFirst({
      where: {
        chatId,
        userId,
        revokedAt: null
      },
      orderBy: { createdAt: "desc" },
      select: { id: true }
    });
  }

  private canReviewJoinRequests(role: ChatMemberRoleValue): boolean {
    return this.isAdminOrAbove(role);
  }

  private canBanMembers(role: ChatMemberRoleValue): boolean {
    return this.isAdminOrAbove(role);
  }

  private assertGroupRateLimit(chatId: string, userId: string): void {
    const now = Date.now();
    const key = `${chatId}:${userId}`;
    const current = (groupSendRateLimit.get(key) ?? []).filter(
      (timestamp) => now - timestamp < GROUP_FLOOD_WINDOW_MS
    );
    if (current.length >= GROUP_FLOOD_LIMIT) {
      groupSendRateLimit.set(key, current);
      throw new Error("chat_rate_limited");
    }
    current.push(now);
    groupSendRateLimit.set(key, current);
  }

  private canAddMembers(params: {
    policy: ChatPolicyScopeValue;
    role: ChatMemberRoleValue;
  }): boolean {
    return this.policyAllows(params.policy, params.role);
  }

  private isOwner(role: ChatMemberRoleValue): boolean {
    return role === ChatMemberRole.OWNER;
  }

  private isAdminOrAbove(role: ChatMemberRoleValue): boolean {
    return role === ChatMemberRole.OWNER || role === ChatMemberRole.ADMIN;
  }

  private isEditorOrAbove(role: ChatMemberRoleValue): boolean {
    return (
      role === ChatMemberRole.OWNER ||
      role === ChatMemberRole.ADMIN ||
      role === ChatMemberRole.EDITOR
    );
  }

  private policyAllows(policy: ChatPolicyScopeValue, role: ChatMemberRoleValue): boolean {
    if (this.isOwner(role)) return true;
    switch (policy) {
      case ChatPolicyScope.EVERYONE:
        return true;
      case ChatPolicyScope.EDITOR_ONLY:
        return this.isEditorOrAbove(role);
      case ChatPolicyScope.ADMIN_ONLY:
        return this.isAdminOrAbove(role);
      default:
        return false;
    }
  }

  private canEditGroupInfo(params: {
    policy: ChatPolicyScopeValue;
    role: ChatMemberRoleValue;
  }): boolean {
    return this.policyAllows(params.policy, params.role);
  }

  private canInviteMembers(params: {
    policy: ChatPolicyScopeValue;
    role: ChatMemberRoleValue;
  }): boolean {
    return this.policyAllows(params.policy, params.role);
  }

  private canSendInGroup(params: {
    policy: ChatPolicyScopeValue;
    role: ChatMemberRoleValue;
    canSend: boolean;
  }): boolean {
    return params.canSend && this.policyAllows(params.policy, params.role);
  }

  private canRemoveMember(params: {
    requesterRole: ChatMemberRoleValue;
    targetRole: ChatMemberRoleValue;
  }): boolean {
    if (params.targetRole === ChatMemberRole.OWNER) {
      return false;
    }

    switch (params.requesterRole) {
      case ChatMemberRole.OWNER:
        return true;
      case ChatMemberRole.ADMIN:
        return (
          params.targetRole === ChatMemberRole.EDITOR ||
          params.targetRole === ChatMemberRole.MEMBER
        );
      case ChatMemberRole.EDITOR:
        return params.targetRole === ChatMemberRole.MEMBER;
      default:
        return false;
    }
  }

  private async createSystemMessage(input: {
    chatId: string;
    senderId: string;
    systemType: string;
    text?: string | null;
    systemPayload?: Record<string, unknown>;
    touchChat?: boolean;
  }): Promise<ChatMessage> {
    const created = await prisma.$transaction(async (tx: any) => {
      const message = await tx.message.create({
        data: {
          chatId: input.chatId,
          senderId: input.senderId,
          text: input.text?.trim() || undefined,
          systemType: input.systemType,
          systemPayload: input.systemPayload ?? undefined,
          status: MessageStatus.sent
        },
        include: messageInclude
      });

      if (input.touchChat !== false) {
        await tx.chat.update({
          where: { id: input.chatId },
          data: { updatedAt: new Date() }
        });
      }

      return message;
    });

    return toChatMessage(created);
  }

  private extractDirectParticipants(chatId: string): [string, string] | null {
    if (!chatId.startsWith("direct_")) return null;
    const key = chatId.replace("direct_", "").trim();
    const participants = key.split("_").filter(Boolean);
    if (participants.length !== 2) return null;

    const sorted = [...participants].sort();
    const normalized = `direct_${sorted[0]}_${sorted[1]}`;
    if (normalized !== chatId) return null;

    return [sorted[0], sorted[1]];
  }

  getDirectPeerId(chatId: string, userId: string): string | null {
    const participants = this.extractDirectParticipants(chatId);
    if (!participants || !participants.includes(userId)) return null;
    return participants.find((participantId) => participantId !== userId) ?? null;
  }

  private isSelfDirectChat(chatId: string, userId: string): boolean {
    const participants = this.extractDirectParticipants(chatId);
    if (!participants) return false;
    return participants[0] === userId && participants[1] === userId;
  }

  private buildDirectChatTitle(input: {
    viewerUserId: string;
    peer:
      | {
          id?: string | null;
          phone?: string | null;
          displayName?: string | null;
        }
      | null;
  }): string {
    const peer = input.peer;
    if (!peer || peer.id === input.viewerUserId) {
      return SAVED_MESSAGES_TITLE;
    }
    return peer.phone ?? peer.displayName ?? "New Chat";
  }

  private async ensureSavedMessagesChat(userId: string): Promise<void> {
    await this.ensureChatAccess(`direct_${userId}_${userId}`, userId);
  }

  getDirectParticipants(chatId: string): string[] {
    const participants = this.extractDirectParticipants(chatId);
    return participants ? [...participants] : [];
  }

  async getChatParticipantIds(chatId: string): Promise<string[]> {
    const members = await prisma.chatMember.findMany({
      where: { chatId },
      select: { userId: true }
    });
    return members.map((member: any) => member.userId);
  }

  async getTypingAudience(chatId: string, userId: string): Promise<{
    chatType: AppChatType;
    participantIds: string[];
    recipientUserIds: string[];
  }> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    const chat = await this.getChatMeta(chatId);
    if (!chat) {
      throw new Error("chat_not_found");
    }

    const participantIds = await this.getChatParticipantIds(chatId);
    return {
      chatType: chat.type === ChatType.GROUP ? "group" : "direct",
      participantIds,
      recipientUserIds: participantIds.filter((participantId) => participantId !== userId)
    };
  }

  async resolvePeerId(chatId: string, userId: string): Promise<string | null> {
    const directPeer = this.getDirectPeerId(chatId, userId);
    if (directPeer) return directPeer;
    const chat = await this.getChatMeta(chatId);
    if (!chat || chat.type === ChatType.GROUP) return null;

    const participants = await this.getChatParticipantIds(chatId);
    const peer = participants.find((participantId) => participantId !== userId);
    return peer ?? null;
  }

  async ensureCanInteract(chatId: string, userId: string): Promise<void> {
    const membership = await this.getMembershipState(chatId, userId);
    const chat = await this.getChatMeta(chatId);
    if (chat?.type === ChatType.GROUP && membership) {
      const activeMute = await this.getActiveMute(chatId, userId);
      if (activeMute) {
        throw new Error("chat_send_restricted");
      }
      if (
        !this.canSendInGroup({
          policy: chat.whoCanSend,
          role: membership.role,
          canSend: membership.canSend
        })
      ) {
        throw new Error("chat_send_restricted");
      }
    } else if (membership && !membership.canSend) {
      throw new Error("chat_send_restricted");
    }

    const peerId = this.getDirectPeerId(chatId, userId);
    if (!peerId) return;

    if (await areUsersBlocked(userId, peerId)) {
      throw new Error("chat_blocked");
    }
  }

  async ensureChatAccess(chatId: string, userId: string): Promise<boolean> {
    const member = await this.getMembershipState(chatId, userId);
    if (member) {
      if (await this.getActiveBan(chatId, userId)) {
        return false;
      }
      return true;
    }

    const participants = this.extractDirectParticipants(chatId);
    if (!participants || !participants.includes(userId)) return false;
    const uniqueParticipants = Array.from(new Set(participants));

    const users = await prisma.user.findMany({
      where: { id: { in: uniqueParticipants } },
      select: { id: true }
    });
    if (users.length !== uniqueParticipants.length) return false;
    const preference = await getUserPrivacyPreference(userId);
    const defaultMessageExpirationSeconds =
      preference.defaultMessageExpirationSeconds;

    await prisma.chat.upsert({
      where: { id: chatId },
      create: {
        id: chatId,
        type: ChatType.DIRECT,
        messageExpirationSeconds: defaultMessageExpirationSeconds,
        usesDefaultMessageExpiration: defaultMessageExpirationSeconds != null,
        defaultMessageExpirationUserId:
          defaultMessageExpirationSeconds != null ? userId : null,
        members: {
          create: uniqueParticipants.map((participantId) => ({
            userId: participantId
          }))
        }
      },
      update: {
        members: {
          connectOrCreate: uniqueParticipants.map((participantId) => ({
            where: { chatId_userId: { chatId, userId: participantId } },
            create: { userId: participantId }
          }))
        }
      }
    });

    return true;
  }

  async sendMessage(payload: SendMessagePayload): Promise<ChatMessage> {
    const hasAccess = await this.ensureChatAccess(payload.chatId, payload.senderId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }
    await this.ensureCanInteract(payload.chatId, payload.senderId);
    const chat = await this.getChatMeta(payload.chatId);
    if (chat?.type === ChatType.GROUP) {
      this.assertGroupRateLimit(payload.chatId, payload.senderId);
    }
    const isSelfDirectMessage =
      chat?.type === ChatType.DIRECT &&
      this.isSelfDirectChat(payload.chatId, payload.senderId);

    const preparedAttachments = await this.prepareAttachments(
      payload.chatId,
      payload.senderId,
      payload.attachments ?? []
    );

    const message = await prisma.$transaction(async (tx: any) => {
      const expiresAt =
        chat?.messageExpirationSeconds != null
          ? new Date(Date.now() + chat.messageExpirationSeconds * 1000)
          : null;
      const mentionedUsers =
        chat?.type === ChatType.GROUP
          ? await resolveMentionedUsersForChat(
              tx,
              payload.chatId,
              payload.senderId,
              payload.text ?? null
            )
          : [];
      const created = await tx.message.create({
        data: {
          chatId: payload.chatId,
          senderId: payload.senderId,
          text: payload.text?.trim() ? payload.text.trim() : null,
          systemPayload: payload.systemPayload ?? undefined,
          status: isSelfDirectMessage ? MessageStatus.read : MessageStatus.sent,
          expiresAt,
          attachments: preparedAttachments.length
            ? {
                create: preparedAttachments.map((attachment) => ({
                  objectKey: attachment.objectKey,
                  kind: attachment.kind,
                  transferMode: attachment.transferMode,
                  fileName: attachment.fileName,
                  contentType: attachment.contentType,
                  sizeBytes: attachment.sizeBytes,
                  width: attachment.width,
                  height: attachment.height,
                  durationSeconds: attachment.durationSeconds
                }))
              }
            : undefined,
          mentions: mentionedUsers.length
            ? {
                create: mentionedUsers.map((user) => ({
                  mentionedUserId: user.userId
                }))
              }
            : undefined
        },
        include: messageInclude
      });

      await tx.chat.update({
        where: { id: payload.chatId },
        data: { updatedAt: new Date() }
      });

      return created;
    });

    return toChatMessage(message);
  }

  async scheduleMessage(input: {
    chatId: string;
    senderId: string;
    text: string;
    scheduledFor: string;
    silent?: boolean;
  }): Promise<ScheduledMessageSummary> {
    const hasAccess = await this.ensureChatAccess(input.chatId, input.senderId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }
    await this.ensureCanInteract(input.chatId, input.senderId);

    const text = input.text.trim();
    if (!text) {
      throw new Error("scheduled_message_text_required");
    }

    const scheduledFor = new Date(input.scheduledFor);
    if (Number.isNaN(scheduledFor.getTime())) {
      throw new Error("scheduled_message_invalid_time");
    }

    const now = Date.now();
    if (scheduledFor.getTime() < now + 30 * 1000) {
      throw new Error("scheduled_message_must_be_future");
    }
    if (scheduledFor.getTime() > now + 365 * 24 * 60 * 60 * 1000) {
      throw new Error("scheduled_message_too_far");
    }

    const rows = await prisma.$queryRaw<ScheduledMessageRow[]>`
      INSERT INTO "ScheduledMessage" (
        "chatId",
        "senderId",
        "text",
        "silent",
        "scheduledFor",
        "status",
        "createdAt",
        "updatedAt"
      )
      VALUES (
        ${input.chatId},
        ${input.senderId},
        ${text},
        ${input.silent === true},
        ${scheduledFor},
        'PENDING'::"ScheduledMessageStatus",
        NOW(),
        NOW()
      )
      RETURNING
        "id",
        "chatId",
        "senderId",
        "text",
        "silent",
        "scheduledFor",
        "createdAt",
        "status",
        "lastError"
    `;
    const created = rows[0];
    if (!created) {
      throw new Error("failed_to_schedule_message");
    }
    return toScheduledMessageSummary(created);
  }

  async listScheduledMessages(
    chatId: string,
    requesterId: string
  ): Promise<ScheduledMessageSummary[]> {
    const hasAccess = await this.ensureChatAccess(chatId, requesterId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    const rows = await prisma.$queryRaw<ScheduledMessageRow[]>`
      SELECT
        "id",
        "chatId",
        "senderId",
        "text",
        "silent",
        "scheduledFor",
        "createdAt",
        "status",
        "lastError"
      FROM "ScheduledMessage"
      WHERE
        "chatId" = ${chatId}
        AND "senderId" = ${requesterId}
        AND "status" IN (
          'PENDING'::"ScheduledMessageStatus",
          'FAILED'::"ScheduledMessageStatus"
        )
      ORDER BY
        CASE WHEN "status" = 'FAILED'::"ScheduledMessageStatus" THEN 0 ELSE 1 END,
        "scheduledFor" ASC
    `;
    return rows.map((row) => toScheduledMessageSummary(row));
  }

  async cancelScheduledMessage(
    scheduledMessageId: string,
    requesterId: string
  ): Promise<void> {
    const rows = await prisma.$queryRaw<Array<{ id: string }>>`
      UPDATE "ScheduledMessage"
      SET
        "status" = 'CANCELED'::"ScheduledMessageStatus",
        "canceledAt" = NOW(),
        "updatedAt" = NOW()
      WHERE
        "id" = ${scheduledMessageId}
        AND "senderId" = ${requesterId}
        AND "status" IN (
          'PENDING'::"ScheduledMessageStatus",
          'FAILED'::"ScheduledMessageStatus"
        )
      RETURNING "id"
    `;
    if (rows.length === 0) {
      throw new Error("scheduled_message_not_found");
    }
  }

  async recoverStuckScheduledMessages(staleBefore: Date): Promise<void> {
    await prisma.$executeRaw`
      UPDATE "ScheduledMessage"
      SET
        "status" = 'PENDING'::"ScheduledMessageStatus",
        "updatedAt" = NOW()
      WHERE
        "status" = 'PROCESSING'::"ScheduledMessageStatus"
        AND "updatedAt" < ${staleBefore}
    `;
  }

  async claimDueScheduledMessages(limit = 20): Promise<ScheduledMessageRow[]> {
    const safeLimit = Math.max(1, Math.min(limit, 50));
    const now = new Date();
    return prisma.$queryRaw<ScheduledMessageRow[]>`
      UPDATE "ScheduledMessage"
      SET
        "status" = 'PROCESSING'::"ScheduledMessageStatus",
        "updatedAt" = NOW(),
        "lastError" = NULL
      WHERE "id" IN (
        SELECT "id"
        FROM "ScheduledMessage"
        WHERE
          "status" = 'PENDING'::"ScheduledMessageStatus"
          AND "scheduledFor" <= ${now}
        ORDER BY "scheduledFor" ASC
        LIMIT ${safeLimit}
        FOR UPDATE SKIP LOCKED
      )
      RETURNING
        "id",
        "chatId",
        "senderId",
        "text",
        "silent",
        "scheduledFor",
        "createdAt",
        "status",
        "lastError"
    `;
  }

  async markScheduledMessageSent(
    scheduledMessageId: string,
    deliveredMessageId: string
  ): Promise<void> {
    await prisma.$executeRaw`
      UPDATE "ScheduledMessage"
      SET
        "status" = 'SENT'::"ScheduledMessageStatus",
        "sentAt" = NOW(),
        "updatedAt" = NOW(),
        "deliveredMessageId" = ${deliveredMessageId},
        "lastError" = NULL
      WHERE "id" = ${scheduledMessageId}
    `;
  }

  async markScheduledMessageFailed(
    scheduledMessageId: string,
    errorMessage: string
  ): Promise<void> {
    const normalizedError = errorMessage.trim().slice(0, 500) || "Mesaj gönderilemedi.";
    await prisma.$executeRaw`
      UPDATE "ScheduledMessage"
      SET
        "status" = 'FAILED'::"ScheduledMessageStatus",
        "updatedAt" = NOW(),
        "lastError" = ${normalizedError}
      WHERE "id" = ${scheduledMessageId}
    `;
  }

  async deleteMessageForEveryone(messageId: string, requesterId: string): Promise<ChatMessage> {
    const existing = await prisma.message.findUnique({
      where: { id: messageId },
      include: messageInclude
    });

    if (!existing) {
      throw new Error("message_not_found");
    }

    const hasAccess = await this.ensureChatAccess(existing.chatId, requesterId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    if (existing.senderId !== requesterId) {
      throw new Error("message_delete_not_allowed");
    }

    if (existing.systemType) {
      throw new Error("message_delete_not_allowed");
    }

    if ((existing.text ?? "").trim() === TURNA_DELETED_EVERYONE_MARKER) {
      return toChatMessage(existing);
    }

    if (Date.now() - existing.createdAt.getTime() > DELETE_FOR_EVERYONE_WINDOW_MS) {
      throw new Error("message_delete_window_expired");
    }

    const updated = await prisma.$transaction(async (tx: any) => {
      await tx.messageAttachment.deleteMany({
        where: { messageId: existing.id }
      });

      return tx.message.update({
        where: { id: existing.id },
        data: {
          text: TURNA_DELETED_EVERYONE_MARKER,
          isViewOnce: false
        },
        include: messageInclude
      });
    });

    await Promise.all(
      existing.attachments.map((attachment: any) =>
        deleteObject(attachment.objectKey).catch((error: unknown) => {
          logError("message attachment delete failed", error);
        })
      )
    );

    return toChatMessage(updated);
  }

  async editMessage(
    messageId: string,
    requesterId: string,
    nextText: string
  ): Promise<ChatMessage> {
    const existing = await prisma.message.findUnique({
      where: { id: messageId },
      include: messageInclude
    });

    if (!existing) {
      throw new Error("message_not_found");
    }

    const hasAccess = await this.ensureChatAccess(existing.chatId, requesterId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    if (existing.senderId !== requesterId) {
      throw new Error("message_edit_not_allowed");
    }

    if (existing.systemType) {
      throw new Error("message_edit_not_allowed");
    }

    if ((existing.text ?? "").trim() === TURNA_DELETED_EVERYONE_MARKER) {
      throw new Error("message_edit_not_allowed");
    }

    if (!(existing.text ?? "").trim()) {
      throw new Error("message_edit_not_allowed");
    }

    const trimmedText = nextText.trim();
    if (!trimmedText) {
      throw new Error("message_edit_text_required");
    }

    if (trimmedText === (existing.text ?? "").trim()) {
      return toChatMessage(existing);
    }

    const withinDefaultWindow = Date.now() - existing.createdAt.getTime() <= EDIT_MESSAGE_WINDOW_MS;
    if (!withinDefaultWindow && !canExtendLiveLocationEditWindow(existing.text ?? "", trimmedText)) {
      throw new Error("message_edit_window_expired");
    }

    const history = toEditHistoryEntries(existing.editHistory);
    history.push({
      text: existing.text ?? "",
      editedAt: new Date().toISOString()
    });

    const updated = await prisma.$transaction(async (tx: any) => {
      const chat = await tx.chat.findUnique({
        where: { id: existing.chatId },
        select: { type: true }
      });
      const mentionedUsers =
        chat?.type === ChatType.GROUP
          ? await resolveMentionedUsersForChat(
              tx,
              existing.chatId,
              requesterId,
              trimmedText
            )
          : [];

      await tx.messageMention.deleteMany({
        where: { messageId }
      });

      return tx.message.update({
        where: { id: messageId },
        data: {
          text: trimmedText,
          editedAt: new Date(),
          editCount: (existing.editCount ?? 0) + 1,
          editHistory: history as unknown as any,
          mentions: mentionedUsers.length
            ? {
                create: mentionedUsers.map((user) => ({
                  mentionedUserId: user.userId
                }))
              }
            : undefined
        },
        include: messageInclude
      });
    });

    return toChatMessage(updated as MessageRow);
  }

  async addReaction(messageId: string, requesterId: string, emoji: string): Promise<ChatMessage> {
    const normalizedEmoji = emoji.trim();
    if (!normalizedEmoji) {
      throw new Error("reaction_emoji_required");
    }

    const existing = await prisma.message.findUnique({
      where: { id: messageId },
      include: messageInclude
    });
    if (!existing) {
      throw new Error("message_not_found");
    }

    const hasAccess = await this.ensureChatAccess(existing.chatId, requesterId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }
    if (existing.systemType) {
      throw new Error("message_reaction_not_allowed");
    }

    await prismaMessageReaction.upsert({
      where: {
        messageId_userId_emoji: {
          messageId,
          userId: requesterId,
          emoji: normalizedEmoji
        }
      },
      create: {
        messageId,
        userId: requesterId,
        emoji: normalizedEmoji
      },
      update: {}
    });

    const updated = await prisma.message.findUnique({
      where: { id: messageId },
      include: messageInclude
    });
    if (!updated) {
      throw new Error("message_not_found");
    }
    return toChatMessage(updated as MessageRow);
  }

  async removeReaction(messageId: string, requesterId: string, emoji: string): Promise<ChatMessage> {
    const normalizedEmoji = emoji.trim();
    if (!normalizedEmoji) {
      throw new Error("reaction_emoji_required");
    }

    const existing = await prisma.message.findUnique({
      where: { id: messageId },
      include: messageInclude
    });
    if (!existing) {
      throw new Error("message_not_found");
    }

    const hasAccess = await this.ensureChatAccess(existing.chatId, requesterId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    await prismaMessageReaction.deleteMany({
      where: {
        messageId,
        userId: requesterId,
        emoji: normalizedEmoji
      }
    });

    const updated = await prisma.message.findUnique({
      where: { id: messageId },
      include: messageInclude
    });
    if (!updated) {
      throw new Error("message_not_found");
    }
    return toChatMessage(updated as MessageRow);
  }

  async pinMessage(messageId: string, requesterId: string): Promise<ChatPinnedMessageSummary> {
    const message = await prisma.message.findUnique({
      where: { id: messageId },
      include: {
        sender: {
          select: {
            id: true,
            displayName: true
          }
        }
      }
    });
    if (!message) {
      throw new Error("message_not_found");
    }

    const chat = await this.getChatMeta(message.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }

    const membership = await this.getMembershipState(message.chatId, requesterId);
    if (
      !membership ||
      !this.canEditGroupInfo({
        policy: chat.whoCanEditInfo,
        role: membership.role
      })
    ) {
      throw new Error("group_pin_not_allowed");
    }

    await prismaChatPinnedMessage.updateMany({
      where: {
        chatId: message.chatId,
        unpinnedAt: null
      },
      data: {
        unpinnedAt: new Date()
      }
    });

    await prismaChatPinnedMessage.upsert({
      where: {
        chatId_messageId: {
          chatId: message.chatId,
          messageId
        }
      },
      create: {
        chatId: message.chatId,
        messageId,
        pinnedByUserId: requesterId
      },
      update: {
        pinnedByUserId: requesterId,
        createdAt: new Date(),
        unpinnedAt: null
      }
    });

    const latest = await this.listPinnedMessages(message.chatId, requesterId, { limit: 1 });
    if (latest.length === 0) {
      throw new Error("group_pin_failed");
    }
    return latest[0];
  }

  async unpinMessage(messageId: string, requesterId: string): Promise<void> {
    const message = await prisma.message.findUnique({
      where: { id: messageId },
      select: {
        id: true,
        chatId: true
      }
    });
    if (!message) {
      throw new Error("message_not_found");
    }

    const chat = await this.getChatMeta(message.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }

    const membership = await this.getMembershipState(message.chatId, requesterId);
    if (
      !membership ||
      !this.canEditGroupInfo({
        policy: chat.whoCanEditInfo,
        role: membership.role
      })
    ) {
      throw new Error("group_pin_not_allowed");
    }

    await prismaChatPinnedMessage.updateMany({
      where: {
        chatId: message.chatId,
        messageId,
        unpinnedAt: null
      },
      data: {
        unpinnedAt: new Date()
      }
    });
  }

  async listPinnedMessages(
    chatId: string,
    requesterId: string,
    options: { limit?: number } = {}
  ): Promise<ChatPinnedMessageSummary[]> {
    const hasAccess = await this.ensureChatAccess(chatId, requesterId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    const rows = await prismaChatPinnedMessage.findMany({
      where: {
        chatId,
        unpinnedAt: null
      },
      orderBy: { createdAt: "desc" },
      take: options.limit ?? 20,
      select: {
        chatId: true,
        messageId: true,
        createdAt: true,
        pinnedByUserId: true,
        pinnedByUser: {
          select: {
            displayName: true
          }
        },
        message: {
          select: {
            id: true,
            senderId: true,
            text: true,
            systemType: true,
            systemPayload: true,
            createdAt: true,
            sender: {
              select: {
                displayName: true
              }
            },
            attachments: {
              orderBy: { createdAt: "asc" }
            }
          }
        }
      }
    });

    return rows.map((row: any) => ({
      messageId: row.messageId,
      chatId: row.chatId,
      senderId: row.message.senderId,
      senderDisplayName: row.message.sender?.displayName ?? null,
      previewText: summarizeMessage({
        text: row.message.text ?? "",
        systemType: row.message.systemType ?? null,
        systemPayload:
          row.message.systemPayload && typeof row.message.systemPayload === "object"
            ? (row.message.systemPayload as Record<string, unknown>)
            : null,
        attachments: row.message.attachments ?? []
      }),
      pinnedAt: row.createdAt.toISOString(),
      pinnedByUserId: row.pinnedByUserId,
      pinnedByDisplayName: row.pinnedByUser?.displayName ?? null,
      messageCreatedAt: row.message.createdAt.toISOString()
    }));
  }

  async markMessagesDelivered(chatId: string, userId: string): Promise<string[]> {
    const membership = await this.getMembershipState(chatId, userId);
    const cutoff = latestDate(membership?.hiddenAt, membership?.clearedAt);
    const targetRows = await prisma.message.findMany({
      where: {
        chatId,
        senderId: { not: userId },
        status: MessageStatus.sent,
        ...buildActiveMessageExpirationWhere(),
        ...(cutoff ? { createdAt: { gt: cutoff } } : {})
      },
      select: { id: true }
    });
    const messageIds = targetRows.map((row: any) => row.id);
    if (messageIds.length === 0) return [];

    await prisma.message.updateMany({
      where: { id: { in: messageIds } },
      data: { status: MessageStatus.delivered }
    });

    return messageIds;
  }

  async markSpecificMessagesDelivered(
    chatId: string,
    userId: string,
    messageIds: string[]
  ): Promise<string[]> {
    const uniqueMessageIds = [...new Set(messageIds.map((item) => item.trim()).filter(Boolean))];
    if (uniqueMessageIds.length === 0) return [];

    const membership = await this.getMembershipState(chatId, userId);
    const cutoff = latestDate(membership?.hiddenAt, membership?.clearedAt);
    const targetRows = await prisma.message.findMany({
      where: {
        id: { in: uniqueMessageIds },
        chatId,
        senderId: { not: userId },
        status: MessageStatus.sent,
        ...buildActiveMessageExpirationWhere(),
        ...(cutoff ? { createdAt: { gt: cutoff } } : {})
      },
      select: { id: true }
    });
    const deliverableIds = targetRows.map((row: any) => row.id);
    if (deliverableIds.length === 0) return [];

    await prisma.message.updateMany({
      where: { id: { in: deliverableIds } },
      data: { status: MessageStatus.delivered }
    });

    return deliverableIds;
  }

  async markMessagesRead(chatId: string, userId: string): Promise<string[]> {
    const membership = await this.getMembershipState(chatId, userId);
    const cutoff = latestDate(membership?.hiddenAt, membership?.clearedAt);
    const targetRows = await prisma.message.findMany({
      where: {
        chatId,
        senderId: { not: userId },
        status: { in: [MessageStatus.sent, MessageStatus.delivered] },
        ...buildActiveMessageExpirationWhere(),
        ...(cutoff ? { createdAt: { gt: cutoff } } : {})
      },
      select: { id: true }
    });
    const messageIds = targetRows.map((row: any) => row.id);
    if (messageIds.length === 0) return [];

    await prisma.message.updateMany({
      where: { id: { in: messageIds } },
      data: { status: MessageStatus.read, readAt: new Date() }
    });

    return messageIds;
  }

  async markAllChatsRead(
    userId: string
  ): Promise<Array<{ chatId: string; messageIds: string[] }>> {
    const memberships = await prisma.chatMember.findMany({
      where: { userId },
      select: { chatId: true }
    });

    const results: Array<{ chatId: string; messageIds: string[] }> = [];
    for (const membership of memberships) {
      const messageIds = await this.markMessagesRead(membership.chatId, userId);
      if (messageIds.length > 0) {
        results.push({ chatId: membership.chatId, messageIds });
      }
    }

    return results;
  }

  async getMessages(chatId: string): Promise<ChatMessage[]> {
    const page = await this.getMessagePage(chatId, { limit: 30 });
    return page.items;
  }

  async getMessagePage(
    chatId: string,
    options: {
      before?: string | null;
      limit?: number;
      userId?: string | null;
      searchQuery?: string | null;
      collectionFilter?: ChatCollectionFilter | null;
    } = {}
  ): Promise<ChatMessagePage> {
    const limit = Math.min(Math.max(options.limit ?? 30, 1), 100);
    const beforeDate =
      options.before && !Number.isNaN(Date.parse(options.before))
        ? new Date(options.before)
        : null;
    const membership =
      options.userId != null
        ? await this.getMembershipState(chatId, options.userId)
        : null;
    const chat = await this.getChatMeta(chatId);
    const visibleFrom =
      chat?.type === ChatType.GROUP &&
      chat.historyVisibleToNewMembers === false &&
      membership?.joinedAt
        ? membership.joinedAt
        : null;
    const clearedAt = latestDate(membership?.clearedAt ?? null, visibleFrom);
    const trimmedSearchQuery = options.searchQuery?.trim() ?? "";

    const whereAnd: Record<string, unknown>[] = [
      {
        chatId,
        createdAt: {
          ...(beforeDate ? { lt: beforeDate } : {}),
          ...(clearedAt ? { gt: clearedAt } : {})
        }
      },
      buildActiveMessageExpirationWhere()
    ];

    if (trimmedSearchQuery.length > 0 || options.collectionFilter) {
      whereAnd.push({ systemType: null });
    }

    if (trimmedSearchQuery.length > 0) {
      whereAnd.push({
        OR: [
          { text: { contains: trimmedSearchQuery, mode: "insensitive" } },
          { sender: { displayName: { contains: trimmedSearchQuery, mode: "insensitive" } } },
          {
            attachments: {
              some: {
                fileName: { contains: trimmedSearchQuery, mode: "insensitive" }
              }
            }
          }
        ]
      });
    }

    if (options.collectionFilter === "media") {
      whereAnd.push({
        attachments: {
          some: {
            kind: {
              in: [AttachmentKind.IMAGE, AttachmentKind.VIDEO]
            }
          }
        }
      });
    } else if (options.collectionFilter === "docs") {
      whereAnd.push({
        attachments: {
          some: {
            kind: AttachmentKind.FILE
          }
        }
      });
    } else if (options.collectionFilter === "links") {
      whereAnd.push({
        OR: [
          { text: { contains: "http://" } },
          { text: { contains: "https://" } },
          { text: { contains: "www." } }
        ]
      });
    }

    const where: Record<string, unknown> =
      whereAnd.length == 1 ? whereAnd[0] : { AND: whereAnd };

    const rows = await prisma.message.findMany({
      where,
      include: messageInclude,
      orderBy: { createdAt: "desc" },
      take: limit + 1
    });

    const hasMore = rows.length > limit;
    const pageRows = rows.slice(0, limit).reverse();

    return {
      items: await Promise.all(pageRows.map((row: any) => toChatMessage(row))),
      hasMore,
      nextBefore: hasMore && pageRows.length > 0 ? pageRows[0].createdAt.toISOString() : null
    };
  }

  async searchMessagePage(
    chatId: string,
    userId: string,
    query: string,
    options: {
      before?: string | null;
      limit?: number;
    } = {}
  ): Promise<ChatMessagePage> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }
    if (!query.trim()) {
      throw new Error("chat_search_query_required");
    }

    return this.getMessagePage(chatId, {
      userId,
      before: options.before,
      limit: options.limit,
      searchQuery: query
    });
  }

  async getCollectionMessagePage(
    chatId: string,
    userId: string,
    collectionFilter: ChatCollectionFilter,
    options: {
      before?: string | null;
      limit?: number;
    } = {}
  ): Promise<ChatMessagePage> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    return this.getMessagePage(chatId, {
      userId,
      before: options.before,
      limit: options.limit,
      collectionFilter
    });
  }

  async getChatSummaries(userId: string): Promise<ChatSummary[]> {
    await this.ensureSavedMessagesChat(userId);

    const memberships = await prisma.chatMember.findMany({
      where: { userId },
      select: {
        chatId: true,
        role: true,
        joinedAt: true,
        hiddenAt: true,
        clearedAt: true,
        archivedAt: true,
        muted: true,
        favorited: true,
        locked: true,
        folderId: true,
        folder: {
          select: {
            id: true,
            name: true
          }
        },
        chat: {
          select: {
            id: true,
            type: true,
            title: true,
            avatarUrl: true,
            description: true,
            isPublic: true,
            historyVisibleToNewMembers: true,
            members: {
              include: { user: true }
            },
            messages: {
              orderBy: { createdAt: "desc" },
              take: 12,
              include: messageInclude
            }
          }
        }
      },
      orderBy: { joinedAt: "desc" }
    });

    const peerIds = memberships
      .filter((membership: any) => membership.chat.type === ChatType.DIRECT)
      .map((membership: any) => membership.chat.members.find((m: any) => m.userId !== userId)?.user.id)
      .filter((peerId: any): peerId is string => Boolean(peerId));
    const blockedPeerIds = await getBlockedUserIdsByUser(
      userId,
      Array.from(new Set(peerIds))
    );

    const items = await Promise.all(
      memberships.map(async (membership: any) => {
        const chat = membership.chat;
        const peer = chat.members.find((m: any) => m.userId !== userId)?.user;
        const selfUser =
          chat.type === ChatType.DIRECT
            ? (chat.members.find((m: any) => m.userId === userId)?.user ?? null)
            : null;
        const directDisplayUser = peer ?? selfUser;
        const isSelfDirect =
          chat.type === ChatType.DIRECT &&
          (!peer || directDisplayUser?.id === userId);
        const last = chat.messages.find((message: any) => !isSilentSystemType(message.systemType)) ?? null;
        const hiddenAt = membership.hiddenAt;
        const clearedAt = membership.clearedAt;
        const visibleFrom =
          chat.type === ChatType.GROUP &&
          chat.historyVisibleToNewMembers === false &&
          membership.joinedAt
            ? membership.joinedAt
            : null;
        const visibilityCutoff = latestDate(clearedAt, visibleFrom);
        if (hiddenAt && (!last || last.createdAt <= hiddenAt)) {
          return null;
        }
        const unreadCutoff = latestDate(hiddenAt, visibilityCutoff);
        const now = new Date();
        const visibleLast =
          chat.messages.find(
            (message: any) =>
              !isSilentSystemType(message.systemType) &&
              isMessageActiveAt(message, now) &&
              (!visibilityCutoff || message.createdAt > visibilityCutoff)
          ) ?? null;
        const unreadCount = await prisma.message.count({
          where: {
            AND: [
              {
                chatId: chat.id,
                senderId: { not: userId },
                status: { not: MessageStatus.read },
                NOT: {
                  systemType: ADMIN_NOTICE_SILENT_SYSTEM_TYPE
                },
                ...(unreadCutoff ? { createdAt: { gt: unreadCutoff } } : {})
              },
              buildActiveMessageExpirationWhere(now)
            ]
          }
        });

        return {
          chatId: chat.id,
          title:
            chat.type === ChatType.GROUP
              ? chat.title?.trim() || "Yeni grup"
              : this.buildDirectChatTitle({
                  viewerUserId: userId,
                  peer: directDisplayUser
                }),
          chatType: (chat.type === ChatType.GROUP ? "group" : "direct") as AppChatType,
          memberPreviewNames:
            chat.type === ChatType.GROUP
              ? buildGroupMemberPreviewNames(chat.members, userId)
              : [],
          lastMessage: (() => {
            if (!visibleLast) return "Sohbet başlat";
            const summary = summarizeMessage(visibleLast);
            if (chat.type !== ChatType.GROUP || visibleLast.systemType) {
              return summary;
            }
            const senderName =
              visibleLast.senderId === userId
                ? "Siz"
                : visibleLast.sender?.displayName?.trim() || "Bilinmeyen";
            return `${senderName}: ${summary}`;
          })(),
          lastMessageAt: visibleLast ? visibleLast.createdAt.toISOString() : null,
          unreadCount,
          peerId:
            chat.type === ChatType.DIRECT && !isSelfDirect ? (peer?.id ?? null) : null,
          peerAvatarKey:
            chat.type === ChatType.DIRECT
              ? (directDisplayUser?.avatarUrl ?? null)
              : null,
          peerUpdatedAt:
            chat.type === ChatType.DIRECT && directDisplayUser?.updatedAt
              ? directDisplayUser.updatedAt.toISOString()
              : null,
          groupAvatarUrl: chat.type === ChatType.GROUP ? (chat.avatarUrl ?? null) : null,
          groupDescription: chat.type === ChatType.GROUP ? (chat.description ?? null) : null,
          memberCount: chat.members.length,
          myRole: chat.type === ChatType.GROUP ? membership.role : null,
          isPublic: chat.type === ChatType.GROUP ? chat.isPublic === true : false,
          isMuted: membership.muted,
          isBlockedByMe:
            chat.type === ChatType.DIRECT && peer && !isSelfDirect
              ? blockedPeerIds.has(peer.id)
              : false,
          isArchived: membership.archivedAt != null,
          isFavorited: membership.favorited === true,
          isLocked: membership.locked === true,
          folderId: membership.folderId,
          folderName: membership.folder?.name ?? null,
          joinedAt: membership.joinedAt
        };
      })
    );

    const visibleItems = items.filter(
      (item): item is NonNullable<typeof item> => item != null
    );

    visibleItems.sort((a, b) => {
      if (a.isFavorited != b.isFavorited) {
        return a.isFavorited ? -1 : 1;
      }
      const aTime = a.lastMessageAt ? new Date(a.lastMessageAt).getTime() : a.joinedAt.getTime();
      const bTime = b.lastMessageAt ? new Date(b.lastMessageAt).getTime() : b.joinedAt.getTime();
      return bTime - aTime;
    });

    return visibleItems.map(({ joinedAt: _joinedAt, ...summary }) => summary);
  }

  async createGroup(input: {
    creatorUserId: string;
    title: string;
    memberUserIds: string[];
  }): Promise<ChatDetail> {
    const title = input.title.trim();
    if (!title) {
      throw new Error("group_title_required");
    }

    const normalizedMemberIds = Array.from(
      new Set(
        input.memberUserIds
          .map((item) => item.trim())
          .filter((item) => item.length > 0 && item !== input.creatorUserId)
      )
    );

    if (normalizedMemberIds.length < 1) {
      throw new Error("group_min_members_required");
    }
    if (normalizedMemberIds.length + 1 > GROUP_MEMBER_LIMIT) {
      throw new Error("group_member_limit_exceeded");
    }

    const participantIds = [input.creatorUserId, ...normalizedMemberIds];
    const users = await prisma.user.findMany({
      where: {
        id: { in: participantIds }
      },
      select: { id: true }
    });
    if (users.length !== participantIds.length) {
      throw new Error("group_member_not_found");
    }

    const created = await prisma.$transaction(async (tx: any) => {
      const chat = await tx.chat.create({
        data: {
          type: ChatType.GROUP,
          title,
          createdByUserId: input.creatorUserId,
          whoCanSend: ChatPolicyScope.EVERYONE,
          whoCanEditInfo: ChatPolicyScope.EDITOR_ONLY,
          whoCanInvite: ChatPolicyScope.ADMIN_ONLY,
          whoCanAddMembers: ChatPolicyScope.ADMIN_ONLY,
          whoCanStartCalls: ChatPolicyScope.EDITOR_ONLY,
          memberAddPolicy: ChatMemberAddPolicy.ADMIN_ONLY,
          historyVisibleToNewMembers: true,
          members: {
            create: participantIds.map((participantId, index) => ({
              userId: participantId,
              role: index === 0 ? ChatMemberRole.OWNER : ChatMemberRole.MEMBER,
              canSend: true,
              addedByUserId: input.creatorUserId,
              joinedVia: index === 0 ? "created" : "added"
            }))
          }
        },
        select: {
          id: true
        }
      });

      const creator = await tx.user.findUnique({
        where: { id: input.creatorUserId },
        select: { displayName: true }
      });

      await tx.message.create({
        data: {
          chatId: chat.id,
          senderId: input.creatorUserId,
          systemType: GROUP_CREATED_SYSTEM_TYPE,
          systemPayload: {
            createdByUserId: input.creatorUserId,
            createdByDisplayName: creator?.displayName ?? "Turna"
          },
          status: MessageStatus.sent
        }
      });

      return chat;
    });

    const detail = await this.getChatDetail(created.id, input.creatorUserId);
    if (!detail) {
      throw new Error("group_not_found");
    }
    return detail;
  }

  async getChatDetail(chatId: string, userId: string): Promise<ChatDetail | null> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    const chat = await prisma.chat.findUnique({
      where: { id: chatId },
      select: {
        id: true,
        type: true,
        title: true,
        description: true,
        avatarUrl: true,
        createdByUserId: true,
        isPublic: true,
        joinApprovalRequired: true,
        memberAddPolicy: true,
        whoCanSend: true,
        whoCanEditInfo: true,
        whoCanInvite: true,
        whoCanAddMembers: true,
        whoCanStartCalls: true,
        historyVisibleToNewMembers: true,
        messageExpirationSeconds: true,
        usesDefaultMessageExpiration: true,
        members: {
          select: {
            userId: true,
            role: true,
            canSend: true,
            user: {
              select: {
                id: true,
                displayName: true,
                phone: true,
                avatarUrl: true,
                updatedAt: true
              }
            }
          }
        }
      }
    });
    if (!chat) return null;

    const myMembership = chat.members.find((member: any) => member.userId === userId) ?? null;
    const peer = chat.type === ChatType.DIRECT
      ? chat.members.find((member: any) => member.userId !== userId)?.user ?? null
      : null;
    const selfUser =
      chat.type === ChatType.DIRECT
        ? chat.members.find((member: any) => member.userId === userId)?.user ?? null
        : null;
    const directDisplayUser = peer ?? selfUser;
    const activeMute =
      chat.type === ChatType.GROUP ? await this.getActiveMute(chatId, userId) : null;

    return {
      chatId: chat.id,
      chatType: chat.type === ChatType.GROUP ? "group" : "direct",
      title:
        chat.type === ChatType.GROUP
          ? chat.title?.trim() || "Yeni grup"
          : this.buildDirectChatTitle({
              viewerUserId: userId,
              peer: directDisplayUser
            }),
      memberPreviewNames:
        chat.type === ChatType.GROUP ? buildGroupMemberPreviewNames(chat.members, userId) : [],
      description: chat.type === ChatType.GROUP ? (chat.description ?? null) : null,
      avatarUrl:
        chat.type === ChatType.GROUP
          ? (chat.avatarUrl ?? null)
          : directDisplayUser?.avatarUrl ?? null,
      createdByUserId: chat.createdByUserId ?? null,
      memberCount: chat.members.length,
      myRole: chat.type === ChatType.GROUP ? (myMembership?.role ?? null) : null,
      isPublic: chat.type === ChatType.GROUP ? chat.isPublic === true : false,
      joinApprovalRequired:
        chat.type === ChatType.GROUP ? chat.joinApprovalRequired === true : false,
      memberAddPolicy:
        chat.type === ChatType.GROUP
          ? (chat.whoCanAddMembers ?? chat.memberAddPolicy)
          : ChatMemberAddPolicy.ADMIN_ONLY,
      whoCanSend:
        chat.type === ChatType.GROUP ? chat.whoCanSend : ChatPolicyScope.EVERYONE,
      whoCanEditInfo:
        chat.type === ChatType.GROUP ? chat.whoCanEditInfo : ChatPolicyScope.EDITOR_ONLY,
      whoCanInvite:
        chat.type === ChatType.GROUP ? chat.whoCanInvite : ChatPolicyScope.ADMIN_ONLY,
      whoCanAddMembers:
        chat.type === ChatType.GROUP
          ? (chat.whoCanAddMembers ?? chat.memberAddPolicy)
          : ChatPolicyScope.ADMIN_ONLY,
      whoCanStartCalls:
        chat.type === ChatType.GROUP
          ? (chat.whoCanStartCalls ?? ChatPolicyScope.EDITOR_ONLY)
          : ChatPolicyScope.OWNER_ONLY,
      historyVisibleToNewMembers:
        chat.type === ChatType.GROUP ? chat.historyVisibleToNewMembers !== false : true,
      messageExpirationSeconds:
        chat.type === ChatType.DIRECT &&
        isAllowedMessageExpirationSeconds(chat.messageExpirationSeconds)
          ? chat.messageExpirationSeconds
          : null,
      usesDefaultMessageExpiration:
        chat.type === ChatType.DIRECT &&
        chat.messageExpirationSeconds != null &&
        chat.usesDefaultMessageExpiration === true,
      myCanSend: myMembership?.canSend === true,
      myIsMuted: activeMute != null,
      myMutedUntil: activeMute?.mutedUntil ? activeMute.mutedUntil.toISOString() : null,
      myMuteReason: activeMute?.reason ?? null
    };
  }

  async getGroupDetail(chatId: string, userId: string): Promise<ChatDetail | null> {
    const detail = await this.getChatDetail(chatId, userId);
    if (!detail || detail.chatType !== "group") {
      return null;
    }
    return detail;
  }

  async addGroupMembers(input: {
    chatId: string;
    requesterUserId: string;
    memberUserIds: string[];
  }): Promise<{
    members: ChatMemberSummary[];
    participantIds: string[];
    systemMessage: ChatMessage | null;
  }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }

    const requesterMembership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (!requesterMembership) {
      throw new Error("forbidden_chat_access");
    }

    if (
      !this.canAddMembers({
        policy: chat.whoCanAddMembers ?? chat.memberAddPolicy,
        role: requesterMembership.role
      })
    ) {
      throw new Error("group_member_add_not_allowed");
    }

    const memberUserIds = Array.from(
      new Set(
        input.memberUserIds
          .map((item) => item.trim())
          .filter((item) => item.length > 0 && item !== input.requesterUserId)
      )
    );
    if (memberUserIds.length === 0) {
      return {
        members: [],
        participantIds: await this.getChatParticipantIds(input.chatId),
        systemMessage: null
      };
    }

    const existingRows = await prisma.chatMember.findMany({
      where: {
        chatId: input.chatId,
        userId: { in: memberUserIds }
      },
      select: { userId: true }
    });
    const existingIds = new Set(existingRows.map((row: any) => row.userId));
    const missingMemberIds = memberUserIds.filter((userId) => !existingIds.has(userId));
    if (missingMemberIds.length === 0) {
      return {
        members: [],
        participantIds: await this.getChatParticipantIds(input.chatId),
        systemMessage: null
      };
    }

    const bannedRows = await prismaChatBan.findMany({
      where: {
        chatId: input.chatId,
        userId: { in: missingMemberIds },
        revokedAt: null
      },
      select: { userId: true }
    });
    if (bannedRows.length > 0) {
      throw new Error("group_join_banned");
    }

    const currentMemberCount = await prisma.chatMember.count({
      where: { chatId: input.chatId }
    });
    if (currentMemberCount + missingMemberIds.length > GROUP_MEMBER_LIMIT) {
      throw new Error("group_member_limit_exceeded");
    }

    const users = await prisma.user.findMany({
      where: { id: { in: missingMemberIds } },
      select: { id: true, displayName: true }
    });
    if (users.length !== missingMemberIds.length) {
      throw new Error("group_member_not_found");
    }

    for (const memberUserId of missingMemberIds) {
      const allowed = await canRequesterAddUserToGroup(
        input.requesterUserId,
        memberUserId
      );
      if (!allowed) {
        throw new Error("group_member_privacy_restricted");
      }
    }

    await prisma.chatMember.createMany({
      data: missingMemberIds.map((memberUserId) => ({
        chatId: input.chatId,
        userId: memberUserId,
        role: ChatMemberRole.MEMBER,
        canSend: true,
        addedByUserId: input.requesterUserId,
        joinedVia: "added"
      }))
    });

    const addedNameMap = new Map(
      users.map((user: any) => [user.id, (user.displayName ?? "").trim() || "Yeni üye"])
    );
    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_MEMBERS_ADDED_SYSTEM_TYPE,
      systemPayload: {
        memberNames: missingMemberIds.map((userId) => addedNameMap.get(userId) ?? "Yeni üye")
      }
    });

    const members = await this.listGroupMembers(input.chatId, input.requesterUserId, {
      limit: 200,
      offset: 0
    });
    return {
      members: members.items.filter((member) => missingMemberIds.includes(member.userId)),
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async leaveGroup(input: {
    chatId: string;
    requesterUserId: string;
  }): Promise<{
    participantIds: string[];
    systemMessage: ChatMessage;
  }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }

    const membership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }

    if (membership.role === ChatMemberRole.OWNER) {
      throw new Error("group_owner_leave_not_allowed");
    }

    const requester = await prismaUser.findUnique({
      where: { id: input.requesterUserId },
      select: { displayName: true }
    });

    await prisma.chatMember.delete({
      where: {
        chatId_userId: {
          chatId: input.chatId,
          userId: input.requesterUserId
        }
      }
    });

    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_MEMBER_LEFT_SYSTEM_TYPE,
      systemPayload: {
        leftByDisplayName: requester?.displayName?.trim() || "Bir üye"
      }
    });

    return {
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async updateGroupDetail(input: {
    chatId: string;
    requesterUserId: string;
    title?: string | null;
    description?: string | null;
    avatarObjectKey?: string | null;
    clearAvatar?: boolean;
  }): Promise<{
    detail: ChatDetail;
    participantIds: string[];
    systemMessage: ChatMessage | null;
  }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }

    const membership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (
      !this.canEditGroupInfo({
        policy: chat.whoCanEditInfo,
        role: membership.role
      })
    ) {
      throw new Error("group_info_update_not_allowed");
    }

    const nextTitle = typeof input.title === "string" ? input.title.trim() : undefined;
    const nextDescription =
      input.description === undefined ? undefined : (input.description ?? "").trim() || null;
    const nextAvatarObjectKey =
      typeof input.avatarObjectKey === "string" ? input.avatarObjectKey.trim() : undefined;
    const clearAvatar = input.clearAvatar === true;

    const titleChanged =
      nextTitle !== undefined && nextTitle !== (chat.title?.trim() ?? "");
    const descriptionChanged =
      nextDescription !== undefined && nextDescription !== (chat.description ?? null);
    const avatarChanged =
      (clearAvatar && chat.avatarUrl != null) ||
      (nextAvatarObjectKey !== undefined && nextAvatarObjectKey !== (chat.avatarUrl ?? null));

    if (!titleChanged && !descriptionChanged && !avatarChanged) {
      const detail = await this.getGroupDetail(input.chatId, input.requesterUserId);
      if (!detail) {
        throw new Error("group_not_found");
      }
      return {
        detail,
        participantIds: await this.getChatParticipantIds(input.chatId),
        systemMessage: null
      };
    }

    await prisma.chat.update({
      where: { id: input.chatId },
      data: {
        ...(titleChanged ? { title: nextTitle } : {}),
        ...(descriptionChanged ? { description: nextDescription } : {}),
        ...(avatarChanged
          ? { avatarUrl: clearAvatar ? null : nextAvatarObjectKey ?? null }
          : {})
      }
    });

    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_INFO_UPDATED_SYSTEM_TYPE,
      systemPayload: {
        titleChanged,
        descriptionChanged,
        avatarChanged
      }
    });

    const detail = await this.getGroupDetail(input.chatId, input.requesterUserId);
    if (!detail) {
      throw new Error("group_not_found");
    }

    return {
      detail,
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async updateGroupSettings(input: {
    chatId: string;
    requesterUserId: string;
    isPublic?: boolean;
    joinApprovalRequired?: boolean;
    whoCanSend?: ChatPolicyScopeValue;
    whoCanEditInfo?: ChatPolicyScopeValue;
    whoCanInvite?: ChatPolicyScopeValue;
    whoCanAddMembers?: ChatPolicyScopeValue;
    whoCanStartCalls?: ChatPolicyScopeValue;
    historyVisibleToNewMembers?: boolean;
  }): Promise<{
    detail: ChatDetail;
    participantIds: string[];
    systemMessage: ChatMessage | null;
  }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }

    const membership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (!this.isAdminOrAbove(membership.role)) {
      throw new Error("group_settings_update_not_allowed");
    }

    const nextIsPublic = input.isPublic ?? chat.isPublic;
    const nextJoinApprovalRequired = input.joinApprovalRequired ?? chat.joinApprovalRequired;
    const nextWhoCanSend = input.whoCanSend ?? chat.whoCanSend;
    const nextWhoCanEditInfo = input.whoCanEditInfo ?? chat.whoCanEditInfo;
    const nextWhoCanInvite = input.whoCanInvite ?? chat.whoCanInvite;
    const nextWhoCanAddMembers = input.whoCanAddMembers ?? chat.whoCanAddMembers;
    const nextWhoCanStartCalls = input.whoCanStartCalls ?? chat.whoCanStartCalls;
    const nextHistoryVisibleToNewMembers =
      input.historyVisibleToNewMembers ?? chat.historyVisibleToNewMembers;

    const changed =
      nextIsPublic !== chat.isPublic ||
      nextJoinApprovalRequired !== chat.joinApprovalRequired ||
      nextWhoCanSend !== chat.whoCanSend ||
      nextWhoCanEditInfo !== chat.whoCanEditInfo ||
      nextWhoCanInvite !== chat.whoCanInvite ||
      nextWhoCanAddMembers !== chat.whoCanAddMembers ||
      nextWhoCanStartCalls !== chat.whoCanStartCalls ||
      nextHistoryVisibleToNewMembers !== chat.historyVisibleToNewMembers;

    if (!changed) {
      const detail = await this.getGroupDetail(input.chatId, input.requesterUserId);
      if (!detail) {
        throw new Error("group_not_found");
      }
      return {
        detail,
        participantIds: await this.getChatParticipantIds(input.chatId),
        systemMessage: null
      };
    }

    await prisma.chat.update({
      where: { id: input.chatId },
      data: {
        isPublic: nextIsPublic,
        joinApprovalRequired: nextJoinApprovalRequired,
        whoCanSend: nextWhoCanSend,
        whoCanEditInfo: nextWhoCanEditInfo,
        whoCanInvite: nextWhoCanInvite,
        whoCanAddMembers: nextWhoCanAddMembers,
        whoCanStartCalls: nextWhoCanStartCalls,
        memberAddPolicy: nextWhoCanAddMembers as unknown as ChatMemberAddPolicyValue,
        historyVisibleToNewMembers: nextHistoryVisibleToNewMembers
      }
    });

    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_SETTINGS_UPDATED_SYSTEM_TYPE,
      systemPayload: {
        isPublic: nextIsPublic,
        joinApprovalRequired: nextJoinApprovalRequired,
        whoCanSend: nextWhoCanSend,
        whoCanEditInfo: nextWhoCanEditInfo,
        whoCanInvite: nextWhoCanInvite,
        whoCanAddMembers: nextWhoCanAddMembers,
        whoCanStartCalls: nextWhoCanStartCalls,
        historyVisibleToNewMembers: nextHistoryVisibleToNewMembers
      }
    });

    const detail = await this.getGroupDetail(input.chatId, input.requesterUserId);
    if (!detail) {
      throw new Error("group_not_found");
    }

    return {
      detail,
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async updateDirectMessageExpiration(input: {
    chatId: string;
    requesterUserId: string;
    messageExpirationSeconds: number | null;
  }): Promise<{
    detail: ChatDetail;
    participantIds: string[];
    systemMessage: ChatMessage | null;
  }> {
    const hasAccess = await this.ensureChatAccess(
      input.chatId,
      input.requesterUserId
    );
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.DIRECT) {
      throw new Error("direct_chat_not_found");
    }

    const nextMessageExpirationSeconds = isAllowedMessageExpirationSeconds(
      input.messageExpirationSeconds
    )
      ? input.messageExpirationSeconds
      : null;
    const changed =
      nextMessageExpirationSeconds !== chat.messageExpirationSeconds ||
      chat.usesDefaultMessageExpiration === true;

    if (!changed) {
      const detail = await this.getChatDetail(input.chatId, input.requesterUserId);
      if (!detail) {
        throw new Error("direct_chat_not_found");
      }
      return {
        detail,
        participantIds: await this.getChatParticipantIds(input.chatId),
        systemMessage: null
      };
    }

    await prisma.chat.update({
      where: { id: input.chatId },
      data: {
        messageExpirationSeconds: nextMessageExpirationSeconds,
        usesDefaultMessageExpiration: false,
        defaultMessageExpirationUserId: null
      }
    });

    const requester = await prisma.user.findUnique({
      where: { id: input.requesterUserId },
      select: { displayName: true }
    });

    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: DIRECT_MESSAGE_EXPIRATION_UPDATED_SYSTEM_TYPE,
      systemPayload: {
        updatedByUserId: input.requesterUserId,
        updatedByDisplayName: requester?.displayName ?? "Turna",
        messageExpirationSeconds: nextMessageExpirationSeconds
      }
    });

    const detail = await this.getChatDetail(input.chatId, input.requesterUserId);
    if (!detail) {
      throw new Error("direct_chat_not_found");
    }

    return {
      detail,
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async updateGroupMemberRole(input: {
    chatId: string;
    requesterUserId: string;
    targetUserId: string;
    nextRole: Exclude<ChatMemberRoleValue, "OWNER">;
  }): Promise<{
    participantIds: string[];
    systemMessage: ChatMessage;
  }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }
    if (input.requesterUserId === input.targetUserId) {
      throw new Error("group_role_update_not_allowed");
    }

    const [requesterMembership, targetMembership, targetUser] = await Promise.all([
      this.getMembershipState(input.chatId, input.requesterUserId),
      this.getMembershipState(input.chatId, input.targetUserId),
      prismaUser.findUnique({
        where: { id: input.targetUserId },
        select: { displayName: true }
      })
    ]);
    if (!requesterMembership) {
      throw new Error("forbidden_chat_access");
    }
    if (!targetMembership) {
      throw new Error("group_member_not_found");
    }
    if (targetMembership.role === ChatMemberRole.OWNER) {
      throw new Error("group_role_update_not_allowed");
    }

    if (this.isOwner(requesterMembership.role)) {
      // owner can update any non-owner to admin/editor/member
    } else if (requesterMembership.role === ChatMemberRole.ADMIN) {
      const targetRole = targetMembership.role;
      const allowedTarget =
        targetRole === ChatMemberRole.EDITOR || targetRole === ChatMemberRole.MEMBER;
      const allowedNext =
        input.nextRole === ChatMemberRole.EDITOR || input.nextRole === ChatMemberRole.MEMBER;
      if (!allowedTarget || !allowedNext) {
        throw new Error("group_role_update_not_allowed");
      }
    } else {
      throw new Error("group_role_update_not_allowed");
    }

    if (targetMembership.role === input.nextRole) {
      return {
        participantIds: await this.getChatParticipantIds(input.chatId),
        systemMessage: await this.createSystemMessage({
          chatId: input.chatId,
          senderId: input.requesterUserId,
          systemType: GROUP_ROLE_UPDATED_SYSTEM_TYPE,
          systemPayload: {
            memberDisplayName: targetUser?.displayName?.trim() || "Üye",
            roleLabel:
              input.nextRole === ChatMemberRole.ADMIN
                ? "admin"
                : input.nextRole === ChatMemberRole.EDITOR
                ? "editör"
                : "üye"
          },
          touchChat: false
        })
      };
    }

    await prisma.chatMember.update({
      where: {
        chatId_userId: {
          chatId: input.chatId,
          userId: input.targetUserId
        }
      },
      data: { role: input.nextRole }
    });

    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_ROLE_UPDATED_SYSTEM_TYPE,
      systemPayload: {
        memberDisplayName: targetUser?.displayName?.trim() || "Üye",
        roleLabel:
          input.nextRole === ChatMemberRole.ADMIN
            ? "admin"
            : input.nextRole === ChatMemberRole.EDITOR
            ? "editör"
            : "üye"
      }
    });

    return {
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async transferGroupOwnership(input: {
    chatId: string;
    requesterUserId: string;
    newOwnerUserId: string;
  }): Promise<{
    detail: ChatDetail;
    participantIds: string[];
    systemMessage: ChatMessage;
  }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }
    if (input.requesterUserId === input.newOwnerUserId) {
      throw new Error("group_owner_transfer_not_allowed");
    }

    const [requesterMembership, targetMembership, newOwnerUser] = await Promise.all([
      this.getMembershipState(input.chatId, input.requesterUserId),
      this.getMembershipState(input.chatId, input.newOwnerUserId),
      prismaUser.findUnique({
        where: { id: input.newOwnerUserId },
        select: { displayName: true }
      })
    ]);
    if (!requesterMembership) {
      throw new Error("forbidden_chat_access");
    }
    if (!this.isOwner(requesterMembership.role)) {
      throw new Error("group_owner_transfer_not_allowed");
    }
    if (!targetMembership) {
      throw new Error("group_member_not_found");
    }

    await prisma.$transaction([
      prisma.chatMember.update({
        where: {
          chatId_userId: {
            chatId: input.chatId,
            userId: input.requesterUserId
          }
        },
        data: { role: ChatMemberRole.ADMIN }
      }),
      prisma.chatMember.update({
        where: {
          chatId_userId: {
            chatId: input.chatId,
            userId: input.newOwnerUserId
          }
        },
        data: { role: ChatMemberRole.OWNER }
      }),
      prisma.chat.update({
        where: { id: input.chatId },
        data: { createdByUserId: input.newOwnerUserId }
      })
    ]);

    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_OWNER_TRANSFERRED_SYSTEM_TYPE,
      systemPayload: {
        newOwnerUserId: input.newOwnerUserId,
        newOwnerDisplayName: newOwnerUser?.displayName?.trim() || "Yeni sahip"
      }
    });

    const detail = await this.getGroupDetail(input.chatId, input.requesterUserId);
    if (!detail) {
      throw new Error("group_not_found");
    }

    return {
      detail,
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async removeGroupMember(input: {
    chatId: string;
    requesterUserId: string;
    memberUserId: string;
  }): Promise<{
    remainingParticipantIds: string[];
    notifyUserIds: string[];
    systemMessage: ChatMessage;
  }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }

    if (input.requesterUserId === input.memberUserId) {
      throw new Error("group_member_self_remove_not_allowed");
    }

    const [requesterMembership, targetMembership] = await Promise.all([
      this.getMembershipState(input.chatId, input.requesterUserId),
      this.getMembershipState(input.chatId, input.memberUserId)
    ]);
    if (!requesterMembership) {
      throw new Error("forbidden_chat_access");
    }
    if (!targetMembership) {
      throw new Error("group_member_not_found");
    }
    if (
      !this.canRemoveMember({
        requesterRole: requesterMembership.role,
        targetRole: targetMembership.role
      })
    ) {
      throw new Error("group_member_remove_not_allowed");
    }

    const [participantIdsBefore, targetUser] = await Promise.all([
      this.getChatParticipantIds(input.chatId),
      prismaUser.findUnique({
        where: { id: input.memberUserId },
        select: { displayName: true }
      })
    ]);

    await prisma.chatMember.delete({
      where: {
        chatId_userId: {
          chatId: input.chatId,
          userId: input.memberUserId
        }
      }
    });

    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_MEMBER_REMOVED_SYSTEM_TYPE,
      systemPayload: {
        memberDisplayName: targetUser?.displayName?.trim() || "Bir üye"
      }
    });

    return {
      remainingParticipantIds: participantIdsBefore.filter(
        (participantId) => participantId !== input.memberUserId
      ),
      notifyUserIds: participantIdsBefore,
      systemMessage
    };
  }

  async closeGroup(input: {
    chatId: string;
    requesterUserId: string;
  }): Promise<{ participantIds: string[] }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }

    const membership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (membership.role !== ChatMemberRole.OWNER) {
      throw new Error("group_close_not_allowed");
    }

    const participantIds = await this.getChatParticipantIds(input.chatId);
    await prisma.chat.delete({
      where: { id: input.chatId }
    });
    return { participantIds };
  }

  async listInviteLinks(
    chatId: string,
    requesterUserId: string
  ): Promise<ChatInviteLinkSummary[]> {
    const chat = await this.getChatMeta(chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }
    const membership = await this.getMembershipState(chatId, requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (
      !this.canInviteMembers({
        policy: chat.whoCanInvite,
        role: membership.role
      })
    ) {
      throw new Error("group_invite_not_allowed");
    }

    const rows = await prismaChatInviteLink.findMany({
      where: { chatId },
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        token: true,
        expiresAt: true,
        revokedAt: true,
        createdAt: true
      }
    });
    return rows.map((row: any) => ({
      id: row.id,
      token: row.token,
      expiresAt: row.expiresAt ? row.expiresAt.toISOString() : null,
      revokedAt: row.revokedAt ? row.revokedAt.toISOString() : null,
      createdAt: row.createdAt.toISOString()
    }));
  }

  async createInviteLink(input: {
    chatId: string;
    requesterUserId: string;
    durationDays: 7 | 30 | null;
  }): Promise<ChatInviteLinkSummary> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }
    const membership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (
      !this.canInviteMembers({
        policy: chat.whoCanInvite,
        role: membership.role
      })
    ) {
      throw new Error("group_invite_not_allowed");
    }

    const created = await prismaChatInviteLink.create({
      data: {
        chatId: input.chatId,
        createdByUserId: input.requesterUserId,
        token: randomBytes(18).toString("base64url"),
        expiresAt:
          input.durationDays == null
            ? null
            : new Date(Date.now() + input.durationDays * 24 * 60 * 60 * 1000)
      },
      select: {
        id: true,
        token: true,
        expiresAt: true,
        revokedAt: true,
        createdAt: true
      }
    });
    return {
      id: created.id,
      token: created.token,
      expiresAt: created.expiresAt ? created.expiresAt.toISOString() : null,
      revokedAt: created.revokedAt ? created.revokedAt.toISOString() : null,
      createdAt: created.createdAt.toISOString()
    };
  }

  async revokeInviteLink(input: {
    chatId: string;
    inviteLinkId: string;
    requesterUserId: string;
  }): Promise<void> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }
    const membership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (
      !this.canInviteMembers({
        policy: chat.whoCanInvite,
        role: membership.role
      })
    ) {
      throw new Error("group_invite_not_allowed");
    }

    const existing = await prismaChatInviteLink.findFirst({
      where: {
        id: input.inviteLinkId,
        chatId: input.chatId
      },
      select: { id: true }
    });
    if (!existing) {
      throw new Error("group_invite_not_found");
    }

    await prismaChatInviteLink.update({
      where: { id: input.inviteLinkId },
      data: { revokedAt: new Date() }
    });
  }

  async joinGroupByInvite(input: {
    token: string;
    requesterUserId: string;
  }): Promise<{ detail: ChatDetail; participantIds: string[]; systemMessage: ChatMessage | null }> {
    const invite = await prismaChatInviteLink.findUnique({
      where: { token: input.token.trim() },
      select: {
        id: true,
        chatId: true,
        revokedAt: true,
        expiresAt: true
      }
    });
    if (!invite) {
      throw new Error("group_invite_not_found");
    }
    if (invite.revokedAt) {
      throw new Error("group_invite_not_found");
    }
    if (invite.expiresAt && invite.expiresAt.getTime() <= Date.now()) {
      throw new Error("group_invite_expired");
    }
    return this.joinGroup({
      chatId: invite.chatId,
      requesterUserId: input.requesterUserId,
      bypassApproval: true
    });
  }

  async joinGroup(input: {
    chatId: string;
    requesterUserId: string;
    bypassApproval?: boolean;
  }): Promise<{
    detail: ChatDetail;
    participantIds: string[];
    status: "joined" | "requested";
    systemMessage: ChatMessage | null;
  }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }
    if (await this.getActiveBan(input.chatId, input.requesterUserId)) {
      throw new Error("group_join_banned");
    }

    const existingMembership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (existingMembership) {
      const detail = await this.getGroupDetail(input.chatId, input.requesterUserId);
      if (!detail) {
        throw new Error("group_not_found");
      }
      return {
        detail,
        participantIds: await this.getChatParticipantIds(input.chatId),
        status: "joined",
        systemMessage: null
      };
    }

    if (!chat.isPublic && input.bypassApproval !== true) {
      throw new Error("group_private");
    }

    if (chat.joinApprovalRequired === true && input.bypassApproval !== true) {
      const existingRequest = await prismaChatJoinRequest.findFirst({
        where: {
          chatId: input.chatId,
          userId: input.requesterUserId,
          status: "PENDING"
        },
        select: { id: true }
      });
      if (!existingRequest) {
        await prismaChatJoinRequest.create({
          data: {
            chatId: input.chatId,
            userId: input.requesterUserId,
            status: "PENDING"
          }
        });
      }
      const detail = await this.getGroupDetail(input.chatId, input.requesterUserId).catch(() => null);
      return {
        detail:
          detail ??
          ({
            chatId: input.chatId,
            chatType: "group",
            title: chat.title?.trim() || "Yeni grup",
            memberPreviewNames: [],
            description: chat.description ?? null,
            avatarUrl: chat.avatarUrl ?? null,
            createdByUserId: chat.createdByUserId ?? null,
            memberCount: await prisma.chatMember.count({ where: { chatId: input.chatId } }),
            myRole: null,
            isPublic: chat.isPublic === true,
            joinApprovalRequired: chat.joinApprovalRequired === true,
            memberAddPolicy: chat.whoCanAddMembers ?? chat.memberAddPolicy,
            whoCanSend: chat.whoCanSend,
            whoCanEditInfo: chat.whoCanEditInfo,
            whoCanInvite: chat.whoCanInvite,
            whoCanAddMembers: chat.whoCanAddMembers ?? chat.memberAddPolicy,
            whoCanStartCalls: chat.whoCanStartCalls ?? ChatPolicyScope.EDITOR_ONLY,
            historyVisibleToNewMembers: chat.historyVisibleToNewMembers !== false,
            messageExpirationSeconds: null,
            usesDefaultMessageExpiration: false,
            myCanSend: false,
            myIsMuted: false,
            myMutedUntil: null,
            myMuteReason: null
          } satisfies ChatDetail),
        participantIds: await this.getChatParticipantIds(input.chatId),
        status: "requested",
        systemMessage: null
      };
    }

    const currentMemberCount = await prisma.chatMember.count({ where: { chatId: input.chatId } });
    if (currentMemberCount + 1 > GROUP_MEMBER_LIMIT) {
      throw new Error("group_member_limit_exceeded");
    }

    await prisma.chatMember.create({
      data: {
        chatId: input.chatId,
        userId: input.requesterUserId,
        role: ChatMemberRole.MEMBER,
        canSend: true,
        addedByUserId: input.requesterUserId,
        joinedVia: input.bypassApproval ? "invite" : "public"
      }
    });

    await prismaChatJoinRequest.updateMany({
      where: {
        chatId: input.chatId,
        userId: input.requesterUserId,
        status: "PENDING"
      },
      data: {
        status: "APPROVED",
        reviewedAt: new Date(),
        reviewedByUserId: input.requesterUserId
      }
    });

    const joinedUser = await prismaUser.findUnique({
      where: { id: input.requesterUserId },
      select: { displayName: true }
    });
    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_MEMBERS_ADDED_SYSTEM_TYPE,
      systemPayload: {
        memberNames: [joinedUser?.displayName?.trim() || "Yeni üye"]
      }
    });
    const detail = await this.getGroupDetail(input.chatId, input.requesterUserId);
    if (!detail) {
      throw new Error("group_not_found");
    }
    return {
      detail,
      participantIds: await this.getChatParticipantIds(input.chatId),
      status: "joined",
      systemMessage
    };
  }

  async listJoinRequests(
    chatId: string,
    requesterUserId: string
  ): Promise<ChatJoinRequestSummary[]> {
    const chat = await this.getChatMeta(chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }
    const membership = await this.getMembershipState(chatId, requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (!this.canReviewJoinRequests(membership.role)) {
      throw new Error("group_join_request_review_not_allowed");
    }
    const rows = await prismaChatJoinRequest.findMany({
      where: { chatId, status: "PENDING" },
      orderBy: { createdAt: "asc" },
      select: {
        id: true,
        createdAt: true,
        status: true,
        user: {
          select: {
            id: true,
            displayName: true,
            username: true,
            phone: true,
            avatarUrl: true
          }
        }
      }
    });
    return rows.map((row: any) => ({
      id: row.id,
      userId: row.user.id,
      displayName: row.user.displayName,
      username: row.user.username,
      phone: row.user.phone,
      avatarKey: row.user.avatarUrl,
      createdAt: row.createdAt.toISOString(),
      status: row.status
    }));
  }

  async reviewJoinRequest(input: {
    chatId: string;
    requestId: string;
    requesterUserId: string;
    approve: boolean;
  }): Promise<{
    participantIds: string[];
    detail: ChatDetail | null;
    systemMessage: ChatMessage | null;
  }> {
    const chat = await this.getChatMeta(input.chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }
    const membership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (!this.canReviewJoinRequests(membership.role)) {
      throw new Error("group_join_request_review_not_allowed");
    }

    const request = await prismaChatJoinRequest.findFirst({
      where: {
        id: input.requestId,
        chatId: input.chatId,
        status: "PENDING"
      },
      select: {
        id: true,
        userId: true,
        user: {
          select: {
            displayName: true
          }
        }
      }
    });
    if (!request) {
      throw new Error("group_join_request_not_found");
    }

    if (input.approve) {
      if (await this.getActiveBan(input.chatId, request.userId)) {
        throw new Error("group_join_banned");
      }
      const count = await prisma.chatMember.count({ where: { chatId: input.chatId } });
      if (count + 1 > GROUP_MEMBER_LIMIT) {
        throw new Error("group_member_limit_exceeded");
      }
      await prisma.$transaction([
        prismaChatJoinRequest.update({
          where: { id: request.id },
          data: {
            status: "APPROVED",
            reviewedAt: new Date(),
            reviewedByUserId: input.requesterUserId
          }
        }),
        prisma.chatMember.create({
          data: {
            chatId: input.chatId,
            userId: request.userId,
            role: ChatMemberRole.MEMBER,
            canSend: true,
            addedByUserId: input.requesterUserId,
            joinedVia: "request"
          }
        })
      ]);
      const systemMessage = await this.createSystemMessage({
        chatId: input.chatId,
        senderId: input.requesterUserId,
        systemType: GROUP_JOIN_REQUEST_APPROVED_SYSTEM_TYPE,
        systemPayload: {
          memberDisplayName: request.user.displayName?.trim() || "Yeni üye"
        }
      });
      return {
        participantIds: await this.getChatParticipantIds(input.chatId),
        detail: await this.getGroupDetail(input.chatId, request.userId),
        systemMessage
      };
    }

    await prismaChatJoinRequest.update({
      where: { id: request.id },
      data: {
        status: "REJECTED",
        reviewedAt: new Date(),
        reviewedByUserId: input.requesterUserId
      }
    });
    return {
      participantIds: await this.getChatParticipantIds(input.chatId),
      detail: null,
      systemMessage: null
    };
  }

  async muteGroupMember(input: {
    chatId: string;
    requesterUserId: string;
    memberUserId: string;
    duration: "1_HOUR" | "24_HOURS" | "PERMANENT";
    reason?: string | null;
  }): Promise<{
    participantIds: string[];
    systemMessage: ChatMessage;
  }> {
    if (input.requesterUserId === input.memberUserId) {
      throw new Error("group_member_mute_not_allowed");
    }
    const [requesterMembership, targetMembership, targetUser] = await Promise.all([
      this.getMembershipState(input.chatId, input.requesterUserId),
      this.getMembershipState(input.chatId, input.memberUserId),
      prismaUser.findUnique({
        where: { id: input.memberUserId },
        select: { displayName: true }
      })
    ]);
    if (!requesterMembership) {
      throw new Error("forbidden_chat_access");
    }
    if (!targetMembership) {
      throw new Error("group_member_not_found");
    }
    if (
      !this.canRemoveMember({
        requesterRole: requesterMembership.role,
        targetRole: targetMembership.role
      })
    ) {
      throw new Error("group_member_mute_not_allowed");
    }

    const now = new Date();
    const mutedUntil =
      input.duration === "1_HOUR"
        ? new Date(now.getTime() + 60 * 60 * 1000)
        : input.duration === "24_HOURS"
        ? new Date(now.getTime() + 24 * 60 * 60 * 1000)
        : null;
    await prismaChatMute.updateMany({
      where: {
        chatId: input.chatId,
        userId: input.memberUserId,
        revokedAt: null
      },
      data: { revokedAt: now }
    });
    await prismaChatMute.create({
      data: {
        chatId: input.chatId,
        userId: input.memberUserId,
        mutedByUserId: input.requesterUserId,
        reason: input.reason?.trim() || null,
        mutedUntil
      }
    });
    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_MEMBER_MUTED_SYSTEM_TYPE,
      systemPayload: {
        memberDisplayName: targetUser?.displayName?.trim() || "Bir üye",
        mutedUntil: mutedUntil ? mutedUntil.toISOString() : null
      }
    });
    return {
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async unmuteGroupMember(input: {
    chatId: string;
    requesterUserId: string;
    memberUserId: string;
  }): Promise<{
    participantIds: string[];
    systemMessage: ChatMessage;
  }> {
    const [requesterMembership, targetMembership, targetUser] = await Promise.all([
      this.getMembershipState(input.chatId, input.requesterUserId),
      this.getMembershipState(input.chatId, input.memberUserId),
      prismaUser.findUnique({
        where: { id: input.memberUserId },
        select: { displayName: true }
      })
    ]);
    if (!requesterMembership) {
      throw new Error("forbidden_chat_access");
    }
    if (!targetMembership) {
      throw new Error("group_member_not_found");
    }
    if (
      !this.canRemoveMember({
        requesterRole: requesterMembership.role,
        targetRole: targetMembership.role
      })
    ) {
      throw new Error("group_member_mute_not_allowed");
    }
    await prismaChatMute.updateMany({
      where: {
        chatId: input.chatId,
        userId: input.memberUserId,
        revokedAt: null
      },
      data: { revokedAt: new Date() }
    });
    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_MEMBER_UNMUTED_SYSTEM_TYPE,
      systemPayload: {
        memberDisplayName: targetUser?.displayName?.trim() || "Bir üye"
      }
    });
    return {
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async listGroupMutes(
    chatId: string,
    requesterUserId: string
  ): Promise<ChatMuteSummary[]> {
    const membership = await this.getMembershipState(chatId, requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (!this.isEditorOrAbove(membership.role)) {
      throw new Error("group_member_mute_not_allowed");
    }
    const rows = await prismaChatMute.findMany({
      where: {
        chatId,
        revokedAt: null,
        OR: [{ mutedUntil: null }, { mutedUntil: { gt: new Date() } }]
      },
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        reason: true,
        mutedUntil: true,
        createdAt: true,
        user: {
          select: {
            id: true,
            displayName: true,
            username: true,
            avatarUrl: true
          }
        }
      }
    });
    return rows.map((row: any) => ({
      id: row.id,
      userId: row.user.id,
      displayName: row.user.displayName,
      username: row.user.username,
      avatarKey: row.user.avatarUrl,
      reason: row.reason ?? null,
      mutedUntil: row.mutedUntil ? row.mutedUntil.toISOString() : null,
      createdAt: row.createdAt.toISOString()
    }));
  }

  async banGroupMember(input: {
    chatId: string;
    requesterUserId: string;
    memberUserId: string;
    reason?: string | null;
  }): Promise<{
    remainingParticipantIds: string[];
    notifyUserIds: string[];
    systemMessage: ChatMessage;
  }> {
    if (input.requesterUserId === input.memberUserId) {
      throw new Error("group_member_ban_not_allowed");
    }
    const [requesterMembership, targetMembership, targetUser] = await Promise.all([
      this.getMembershipState(input.chatId, input.requesterUserId),
      this.getMembershipState(input.chatId, input.memberUserId),
      prismaUser.findUnique({
        where: { id: input.memberUserId },
        select: { displayName: true }
      })
    ]);
    if (!requesterMembership) {
      throw new Error("forbidden_chat_access");
    }
    if (!targetMembership) {
      throw new Error("group_member_not_found");
    }
    if (
      !this.canBanMembers(requesterMembership.role) ||
      !this.canRemoveMember({
        requesterRole: requesterMembership.role,
        targetRole: targetMembership.role
      })
    ) {
      throw new Error("group_member_ban_not_allowed");
    }

    const participantIdsBefore = await this.getChatParticipantIds(input.chatId);
    await prisma.$transaction([
      prisma.chatMember.delete({
        where: {
          chatId_userId: {
            chatId: input.chatId,
            userId: input.memberUserId
          }
        }
      }),
      prismaChatMute.updateMany({
        where: {
          chatId: input.chatId,
          userId: input.memberUserId,
          revokedAt: null
        },
        data: { revokedAt: new Date() }
      }),
      prismaChatJoinRequest.updateMany({
        where: {
          chatId: input.chatId,
          userId: input.memberUserId,
          status: "PENDING"
        },
        data: {
          status: "REJECTED",
          reviewedAt: new Date(),
          reviewedByUserId: input.requesterUserId
        }
      }),
      prismaChatBan.create({
        data: {
          chatId: input.chatId,
          userId: input.memberUserId,
          bannedByUserId: input.requesterUserId,
          reason: input.reason?.trim() || null
        }
      })
    ]);
    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_MEMBER_BANNED_SYSTEM_TYPE,
      systemPayload: {
        memberDisplayName: targetUser?.displayName?.trim() || "Bir üye"
      }
    });
    return {
      remainingParticipantIds: participantIdsBefore.filter(
        (participantId) => participantId !== input.memberUserId
      ),
      notifyUserIds: participantIdsBefore,
      systemMessage
    };
  }

  async unbanGroupMember(input: {
    chatId: string;
    requesterUserId: string;
    bannedUserId: string;
  }): Promise<{
    participantIds: string[];
    systemMessage: ChatMessage;
  }> {
    const membership = await this.getMembershipState(input.chatId, input.requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (!this.canBanMembers(membership.role)) {
      throw new Error("group_member_ban_not_allowed");
    }
    const existing = await prismaChatBan.findFirst({
      where: {
        chatId: input.chatId,
        userId: input.bannedUserId,
        revokedAt: null
      },
      select: { id: true }
    });
    if (!existing) {
      throw new Error("group_ban_not_found");
    }
    await prismaChatBan.update({
      where: { id: existing.id },
      data: { revokedAt: new Date() }
    });
    const targetUser = await prismaUser.findUnique({
      where: { id: input.bannedUserId },
      select: { displayName: true }
    });
    const systemMessage = await this.createSystemMessage({
      chatId: input.chatId,
      senderId: input.requesterUserId,
      systemType: GROUP_MEMBER_UNBANNED_SYSTEM_TYPE,
      systemPayload: {
        memberDisplayName: targetUser?.displayName?.trim() || "Bir üye"
      }
    });
    return {
      participantIds: await this.getChatParticipantIds(input.chatId),
      systemMessage
    };
  }

  async listGroupBans(
    chatId: string,
    requesterUserId: string
  ): Promise<ChatBanSummary[]> {
    const membership = await this.getMembershipState(chatId, requesterUserId);
    if (!membership) {
      throw new Error("forbidden_chat_access");
    }
    if (!this.canBanMembers(membership.role)) {
      throw new Error("group_member_ban_not_allowed");
    }
    const rows = await prismaChatBan.findMany({
      where: {
        chatId,
        revokedAt: null
      },
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        reason: true,
        createdAt: true,
        user: {
          select: {
            id: true,
            displayName: true,
            username: true,
            avatarUrl: true
          }
        }
      }
    });
    return rows.map((row: any) => ({
      id: row.id,
      userId: row.user.id,
      displayName: row.user.displayName,
      username: row.user.username,
      avatarKey: row.user.avatarUrl,
      reason: row.reason ?? null,
      createdAt: row.createdAt.toISOString()
    }));
  }

  async listGroupMembers(
    chatId: string,
    requesterUserId: string,
    options: { limit?: number; offset?: number } = {}
  ): Promise<{ items: ChatMemberSummary[]; totalCount: number; hasMore: boolean }> {
    const chat = await this.getChatMeta(chatId);
    if (!chat || chat.type !== ChatType.GROUP) {
      throw new Error("group_not_found");
    }

    const hasAccess = await this.ensureChatAccess(chatId, requesterUserId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    const limit = Math.min(Math.max(options.limit ?? 40, 1), 100);
    const offset = Math.max(options.offset ?? 0, 0);

    const [totalCount, members] = await Promise.all([
      prisma.chatMember.count({ where: { chatId } }),
      prisma.chatMember.findMany({
        where: { chatId },
        orderBy: [{ role: "asc" }, { joinedAt: "asc" }],
        skip: offset,
        take: limit,
        select: {
          userId: true,
          role: true,
          canSend: true,
          joinedAt: true,
          user: {
            select: {
              displayName: true,
              username: true,
              phone: true,
              avatarUrl: true,
              updatedAt: true,
              lastSeenAt: true
            }
          }
        }
      })
    ]);
    const muteRows = await prismaChatMute.findMany({
      where: {
        chatId,
        userId: { in: members.map((member: any) => member.userId) },
        revokedAt: null,
        OR: [{ mutedUntil: null }, { mutedUntil: { gt: new Date() } }]
      },
      orderBy: { createdAt: "desc" },
      select: {
        userId: true,
        mutedUntil: true,
        reason: true
      }
    });
    const muteMap = new Map<string, { mutedUntil: Date | null; reason: string | null }>();
    for (const row of muteRows as Array<any>) {
      if (!muteMap.has(row.userId)) {
        muteMap.set(row.userId, {
          mutedUntil: row.mutedUntil ?? null,
          reason: row.reason ?? null
        });
      }
    }

    return {
      items: members.map((member: any) => ({
        userId: member.userId,
        displayName: member.user.displayName,
        username: member.user.username,
        phone: member.user.phone,
        avatarKey: member.user.avatarUrl,
        updatedAt: member.user.updatedAt.toISOString(),
        role: member.role,
        canSend: member.canSend === true,
        joinedAt: member.joinedAt.toISOString(),
        lastSeenAt: member.user.lastSeenAt ? member.user.lastSeenAt.toISOString() : null,
        isMuted: muteMap.has(member.userId),
        mutedUntil: muteMap.get(member.userId)?.mutedUntil?.toISOString() ?? null,
        muteReason: muteMap.get(member.userId)?.reason ?? null
      })),
      totalCount,
      hasMore: offset + members.length < totalCount
    };
  }

  async getUserDirectory(userId: string): Promise<DirectoryUser[]> {
    const users = await prisma.user.findMany({
      where: { id: { not: userId } },
      select: {
        id: true,
        displayName: true,
        username: true,
        phone: true,
        about: true,
        avatarUrl: true,
        updatedAt: true
      },
      orderBy: { createdAt: "desc" }
    });
    return users.map((user: any) => ({
      id: user.id,
      displayName: user.displayName,
      username: user.username,
      phone: user.phone,
      about: user.about,
      avatarKey: user.avatarUrl,
      updatedAt: user.updatedAt.toISOString()
    }));
  }

  async getUserChats(userId: string): Promise<string[]> {
    const memberships = await prisma.chatMember.findMany({
      where: { userId },
      select: { chatId: true }
    });
    return memberships.map((m: any) => m.chatId);
  }

  async hideChatsForUser(userId: string, chatIds: string[]): Promise<string[]> {
    const membershipRows = await prisma.chatMember.findMany({
      where: {
        userId,
        chatId: { in: chatIds }
      },
      select: { chatId: true }
    });

    const ownedChatIds = membershipRows.map((row: any) => row.chatId);
    if (ownedChatIds.length === 0) return [];

    const now = new Date();
    await prisma.chatMember.updateMany({
      where: {
        userId,
        chatId: { in: ownedChatIds }
      },
      data: {
        hiddenAt: now,
        clearedAt: now
      }
    });

    return ownedChatIds;
  }

  async listFolders(userId: string): Promise<Array<{ id: string; name: string; sortOrder: number }>> {
    return prisma.chatFolder.findMany({
      where: { userId },
      select: {
        id: true,
        name: true,
        sortOrder: true
      },
      orderBy: [{ sortOrder: "asc" }, { createdAt: "asc" }]
    });
  }

  async createFolder(userId: string, rawName: string): Promise<{ id: string; name: string; sortOrder: number }> {
    const name = rawName.trim();
    if (!name) {
      throw new Error("chat_folder_name_required");
    }

    const existingFolders = await this.listFolders(userId);
    if (existingFolders.length >= CHAT_FOLDER_LIMIT) {
      throw new Error("chat_folder_limit_reached");
    }

    const normalizedName = name.toLowerCase();
    if (existingFolders.some((item) => item.name.trim().toLowerCase() === normalizedName)) {
      throw new Error("chat_folder_exists");
    }

    return prisma.chatFolder.create({
      data: {
        userId,
        name,
        sortOrder: existingFolders.length
      },
      select: {
        id: true,
        name: true,
        sortOrder: true
      }
    });
  }

  async deleteFolder(userId: string, folderId: string): Promise<void> {
    const folder = await prisma.chatFolder.findFirst({
      where: {
        id: folderId,
        userId
      },
      select: { id: true }
    });

    if (!folder) {
      throw new Error("chat_folder_not_found");
    }

    await prisma.$transaction(async (tx: any) => {
      await tx.chatMember.updateMany({
        where: {
          userId,
          folderId
        },
        data: {
          folderId: null
        }
      });

      await tx.chatFolder.delete({
        where: { id: folderId }
      });
    });
  }

  async clearChatForUser(chatId: string, userId: string): Promise<void> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    await prisma.chatMember.update({
      where: {
        chatId_userId: { chatId, userId }
      },
      data: {
        clearedAt: new Date(),
        hiddenAt: null
      }
    });
  }

  async setChatArchived(chatId: string, userId: string, archived: boolean): Promise<boolean> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    await prisma.chatMember.update({
      where: {
        chatId_userId: { chatId, userId }
      },
      data: {
        archivedAt: archived ? new Date() : null
      }
    });

    return archived;
  }

  async setChatFolder(
    chatId: string,
    userId: string,
    folderId: string | null
  ): Promise<{ folderId: string | null; folderName: string | null }> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    let folderName: string | null = null;
    if (folderId != null) {
      const folder = await prisma.chatFolder.findFirst({
        where: {
          id: folderId,
          userId
        },
        select: {
          id: true,
          name: true
        }
      });
      if (!folder) {
        throw new Error("chat_folder_not_found");
      }
      folderName = folder.name;
    }

    await prisma.chatMember.update({
      where: {
        chatId_userId: { chatId, userId }
      },
      data: {
        folderId
      }
    });

    return { folderId, folderName };
  }

  async setChatMuted(chatId: string, userId: string, muted: boolean): Promise<boolean> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    await prisma.chatMember.update({
      where: {
        chatId_userId: { chatId, userId }
      },
      data: { muted }
    });
    return muted;
  }

  async setChatFavorited(chatId: string, userId: string, favorited: boolean): Promise<boolean> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    await prisma.chatMember.update({
      where: {
        chatId_userId: { chatId, userId }
      },
      data: { favorited }
    });
    return favorited;
  }

  async setChatLocked(chatId: string, userId: string, locked: boolean): Promise<boolean> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    await prisma.chatMember.update({
      where: {
        chatId_userId: { chatId, userId }
      },
      data: { locked }
    });
    return locked;
  }

  async setDirectChatBlocked(chatId: string, userId: string, blocked: boolean): Promise<boolean> {
    const hasAccess = await this.ensureChatAccess(chatId, userId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

    const peerId = this.getDirectPeerId(chatId, userId);
    if (!peerId) {
      throw new Error("invalid_block_target");
    }

    return setUserBlocked(userId, peerId, blocked);
  }

  async getPresenceAudienceUserIds(userId: string): Promise<string[]> {
    const chatIds = await this.getUserChats(userId);
    if (chatIds.length === 0) return [];

    const relatedMembers = await prisma.chatMember.findMany({
      where: {
        chatId: { in: chatIds },
        userId: { not: userId }
      },
      select: { userId: true }
    });

    return Array.from(new Set(relatedMembers.map((member: any) => member.userId)));
  }

  async getUserLastSeenAt(userId: string): Promise<Date | null> {
    const user = await prismaUser.findUnique({
      where: { id: userId },
      select: { lastSeenAt: true }
    });
    return user?.lastSeenAt ?? null;
  }

  async updateUserLastSeen(userId: string, seenAt = new Date()): Promise<Date> {
    const user = await prismaUser.update({
      where: { id: userId },
      data: { lastSeenAt: seenAt },
      select: { lastSeenAt: true }
    });
    return user.lastSeenAt ?? seenAt;
  }

  async getUserDisplayName(userId: string): Promise<string> {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { displayName: true }
    });
    return user?.displayName ?? "Turna";
  }

  async findOpenMessageReport(input: {
    reporterUserId: string;
    messageId: string;
  }): Promise<{ id: string } | null> {
    return prismaReportCase.findFirst({
      where: {
        reporterUserId: input.reporterUserId,
        targetType: "MESSAGE",
        messageId: input.messageId,
        status: {
          in: ["OPEN", "UNDER_REVIEW"]
        }
      },
      select: { id: true }
    });
  }

  async createMessageReport(input: {
    reporterUserId: string;
    messageId: string;
    chatId: string;
    reportedUserId: string;
    reasonCode: string;
    details: string | null;
  }) {
    return prismaReportCase.create({
      data: {
        reporterUserId: input.reporterUserId,
        targetType: "MESSAGE",
        messageId: input.messageId,
        chatId: input.chatId,
        reportedUserId: input.reportedUserId,
        reasonCode: input.reasonCode,
        details: input.details
      },
      select: {
        id: true,
        status: true
      }
    });
  }

  private async prepareAttachments(
    chatId: string,
    senderId: string,
    attachments: SendMessageAttachmentInput[]
  ) {
    if (attachments.length === 0) return [];

    return Promise.all(
      attachments.map(async (attachment) => {
        if (!attachment.objectKey.startsWith(`chat-media/${chatId}/${senderId}/`)) {
          throw new Error("invalid_attachment_key");
        }

        const head = await getObjectHead(attachment.objectKey);
        return {
          objectKey: attachment.objectKey,
          kind: fromAttachmentKind(attachment.kind),
          transferMode: fromAttachmentTransferMode(attachment.transferMode),
          fileName: attachment.fileName?.trim() || null,
          contentType: head.contentType ?? attachment.contentType,
          sizeBytes:
            head.contentLength != null
              ? Number(head.contentLength)
              : Math.max(0, Math.trunc(attachment.sizeBytes ?? 0)),
          width:
            attachment.width != null ? Math.max(0, Math.trunc(attachment.width)) : null,
          height:
            attachment.height != null ? Math.max(0, Math.trunc(attachment.height)) : null,
          durationSeconds:
            attachment.durationSeconds != null
              ? Math.max(0, Math.trunc(attachment.durationSeconds))
              : null
        };
      })
    );
  }

  async createAdminNotice(input: {
    chatId: string;
    title?: string | null;
    text: string;
    icon: string;
    silent?: boolean;
    createdByAdminId: string;
    createdByAdminRole?: string | null;
    createdByAdminDisplayName?: string | null;
  }): Promise<{
    message: ChatMessage;
    participantIds: string[];
  }> {
    const chat = await prisma.chat.findUnique({
      where: { id: input.chatId },
      select: {
        id: true,
        members: {
          orderBy: { joinedAt: "asc" },
          select: { userId: true }
        }
      }
    });

    if (!chat) {
      throw new Error("chat_not_found");
    }

    const senderId = chat.members[0]?.userId ?? null;
    if (!senderId) {
      throw new Error("chat_has_no_members");
    }

    const trimmedText = input.text.trim();
    if (!trimmedText) {
      throw new Error("admin_notice_text_required");
    }

    const message = await this.createSystemMessage({
      chatId: input.chatId,
      senderId,
      text: trimmedText,
      systemType: input.silent ? ADMIN_NOTICE_SILENT_SYSTEM_TYPE : ADMIN_NOTICE_SYSTEM_TYPE,
      systemPayload: {
        title: input.title?.trim() || null,
        text: trimmedText,
        icon: input.icon.trim() || "info",
        createdByAdminId: input.createdByAdminId,
        createdByAdminRole: input.createdByAdminRole ?? null,
        createdByAdminDisplayName: input.createdByAdminDisplayName?.trim() || null
      },
      touchChat: input.silent !== true
    });

    return {
      message,
      participantIds: chat.members.map((member: any) => member.userId)
    };
  }
}

export const chatService = new ChatService();
