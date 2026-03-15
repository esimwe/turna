import { logError } from "../../lib/logger.js";
import { prisma } from "../../lib/prisma.js";
import { createObjectReadUrl, deleteObject, getObjectHead } from "../../lib/storage.js";
import {
  areUsersBlocked,
  getBlockedUserIdsByUser,
  setUserBlocked
} from "../../lib/user-relationship.js";
import type {
  AppChatType,
  ChatAttachment,
  ChatDetail,
  ChatMessage,
  ChatMessageEditHistoryEntry,
  ChatMessagePage,
  ChatMemberSummary,
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
const AttachmentKind = {
  IMAGE: "IMAGE",
  VIDEO: "VIDEO",
  FILE: "FILE"
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
const ADMIN_NOTICE_SYSTEM_TYPE = "admin_notice";
const ADMIN_NOTICE_SILENT_SYSTEM_TYPE = "admin_notice_silent";
const GROUP_MEMBERS_ADDED_SYSTEM_TYPE = "group_members_added";
const GROUP_MEMBER_LEFT_SYSTEM_TYPE = "group_member_left";
const GROUP_MEMBER_REMOVED_SYSTEM_TYPE = "group_member_removed";
const GROUP_INFO_UPDATED_SYSTEM_TYPE = "group_info_updated";
const MessageStatus = {
  sent: "sent",
  delivered: "delivered",
  read: "read"
} as const;
type AttachmentKindValue = typeof AttachmentKind[keyof typeof AttachmentKind];
type MessageStatusValue = typeof MessageStatus[keyof typeof MessageStatus];
type ChatTypeValue = typeof ChatType[keyof typeof ChatType];
type ChatMemberRoleValue = typeof ChatMemberRole[keyof typeof ChatMemberRole];
type ChatMemberAddPolicyValue =
  typeof ChatMemberAddPolicy[keyof typeof ChatMemberAddPolicy];

const prismaUser = (prisma as unknown as { user: any }).user;
const prismaReportCase = (prisma as unknown as { reportCase: any }).reportCase;
const DELETE_FOR_EVERYONE_WINDOW_MS = 10 * 60 * 1000;
const EDIT_MESSAGE_WINDOW_MS = 10 * 60 * 1000;
const CHAT_FOLDER_LIMIT = 3;
const GROUP_MEMBER_LIMIT = 2048;
const GROUP_CREATED_SYSTEM_TYPE = "group_created";

const messageInclude = {
  attachments: {
    orderBy: { createdAt: "asc" as const }
  },
  sender: {
    select: {
      id: true,
      displayName: true
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
  status: MessageStatusValue;
  editedAt: Date | null;
  editHistory: unknown;
  sender: {
    id: string;
    displayName: string;
  };
  attachments: Array<{
    id: string;
    objectKey: string;
    kind: AttachmentKindValue;
    fileName: string | null;
    contentType: string;
    sizeBytes: number;
    width: number | null;
    height: number | null;
    durationSeconds: number | null;
  }>;
};

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
    status: row.status,
    editedAt: row.editedAt ? row.editedAt.toISOString() : null,
    isEdited: row.editedAt != null,
    editHistory: toEditHistoryEntries(row.editHistory),
    attachments
  };
}

export class ChatService {
  private async getMembershipState(chatId: string, userId: string): Promise<{
    role: ChatMemberRoleValue;
    canSend: boolean;
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
        memberAddPolicy: true
      }
    });
  }

  private canAddGroupMembers(params: {
    policy: ChatMemberAddPolicyValue;
    role: ChatMemberRoleValue;
  }): boolean {
    if (params.role === ChatMemberRole.OWNER) return true;
    switch (params.policy) {
      case ChatMemberAddPolicy.EVERYONE:
        return true;
      case ChatMemberAddPolicy.EDITOR_ONLY:
        return params.role === ChatMemberRole.ADMIN || params.role === ChatMemberRole.EDITOR;
      case ChatMemberAddPolicy.ADMIN_ONLY:
        return params.role === ChatMemberRole.ADMIN;
      default:
        return false;
    }
  }

  private canManageGroupInfo(role: ChatMemberRoleValue): boolean {
    return (
      role === ChatMemberRole.OWNER ||
      role === ChatMemberRole.ADMIN ||
      role === ChatMemberRole.EDITOR
    );
  }

  private canRemoveGroupMember(params: {
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
    if (membership && !membership.canSend) {
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
      if (member.hiddenAt) {
        await prisma.chatMember.update({
          where: { chatId_userId: { chatId, userId } },
          data: { hiddenAt: null }
        });
      }
      return true;
    }

    const participants = this.extractDirectParticipants(chatId);
    if (!participants || !participants.includes(userId)) return false;

    const users = await prisma.user.findMany({
      where: { id: { in: participants } },
      select: { id: true }
    });
    if (users.length !== 2) return false;

    await prisma.chat.upsert({
      where: { id: chatId },
      create: {
        id: chatId,
        type: ChatType.DIRECT,
        members: {
          create: participants.map((participantId) => ({ userId: participantId }))
        }
      },
      update: {
        members: {
          connectOrCreate: participants.map((participantId) => ({
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

    const preparedAttachments = await this.prepareAttachments(
      payload.chatId,
      payload.senderId,
      payload.attachments ?? []
    );

    const message = await prisma.$transaction(async (tx: any) => {
      const created = await tx.message.create({
        data: {
          chatId: payload.chatId,
          senderId: payload.senderId,
          text: payload.text?.trim() ? payload.text.trim() : null,
          status: MessageStatus.sent,
          attachments: preparedAttachments.length
            ? {
                create: preparedAttachments.map((attachment) => ({
                  objectKey: attachment.objectKey,
                  kind: attachment.kind,
                  fileName: attachment.fileName,
                  contentType: attachment.contentType,
                  sizeBytes: attachment.sizeBytes,
                  width: attachment.width,
                  height: attachment.height,
                  durationSeconds: attachment.durationSeconds
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

    const updated = await prisma.message.update({
      where: { id: messageId },
      data: {
        text: trimmedText,
        editedAt: new Date(),
        editCount: (existing.editCount ?? 0) + 1,
        editHistory: history as unknown as any
      },
      include: messageInclude
    });

    return toChatMessage(updated as MessageRow);
  }

  async markMessagesDelivered(chatId: string, userId: string): Promise<string[]> {
    const membership = await this.getMembershipState(chatId, userId);
    const cutoff = latestDate(membership?.hiddenAt, membership?.clearedAt);
    const targetRows = await prisma.message.findMany({
      where: {
        chatId,
        senderId: { not: userId },
        status: MessageStatus.sent,
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

  async markMessagesRead(chatId: string, userId: string): Promise<string[]> {
    const membership = await this.getMembershipState(chatId, userId);
    const cutoff = latestDate(membership?.hiddenAt, membership?.clearedAt);
    const targetRows = await prisma.message.findMany({
      where: {
        chatId,
        senderId: { not: userId },
        status: { in: [MessageStatus.sent, MessageStatus.delivered] },
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
    const clearedAt = membership?.clearedAt ?? null;

    const rows = await prisma.message.findMany({
      where: {
        chatId,
        createdAt: {
          ...(beforeDate ? { lt: beforeDate } : {}),
          ...(clearedAt ? { gt: clearedAt } : {})
        }
      },
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

  async getChatSummaries(userId: string): Promise<ChatSummary[]> {
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
        const last = chat.messages.find((message: any) => !isSilentSystemType(message.systemType)) ?? null;
        const hiddenAt = membership.hiddenAt;
        const clearedAt = membership.clearedAt;
        if (hiddenAt && (!last || last.createdAt <= hiddenAt)) {
          return null;
        }
        const unreadCutoff = latestDate(hiddenAt, clearedAt);
        const visibleLast =
          chat.messages.find(
            (message: any) =>
              !isSilentSystemType(message.systemType) &&
              (!clearedAt || message.createdAt > clearedAt)
          ) ?? null;
        const unreadCount = await prisma.message.count({
          where: {
            chatId: chat.id,
            senderId: { not: userId },
            status: { not: MessageStatus.read },
            NOT: {
              systemType: ADMIN_NOTICE_SILENT_SYSTEM_TYPE
            },
            ...(unreadCutoff ? { createdAt: { gt: unreadCutoff } } : {})
          }
        });

        return {
          chatId: chat.id,
          title:
            chat.type === ChatType.GROUP
              ? chat.title?.trim() || "Yeni grup"
              : peer?.phone ?? peer?.displayName ?? "New Chat",
          chatType: (chat.type === ChatType.GROUP ? "group" : "direct") as AppChatType,
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
          peerId: chat.type === ChatType.DIRECT ? (peer?.id ?? null) : null,
          peerAvatarKey: chat.type === ChatType.DIRECT ? (peer?.avatarUrl ?? null) : null,
          peerUpdatedAt:
            chat.type === ChatType.DIRECT && peer?.updatedAt ? peer.updatedAt.toISOString() : null,
          groupAvatarUrl: chat.type === ChatType.GROUP ? (chat.avatarUrl ?? null) : null,
          groupDescription: chat.type === ChatType.GROUP ? (chat.description ?? null) : null,
          memberCount: chat.members.length,
          myRole: chat.type === ChatType.GROUP ? membership.role : null,
          isPublic: chat.type === ChatType.GROUP ? chat.isPublic === true : false,
          isMuted: membership.muted,
          isBlockedByMe: chat.type === ChatType.DIRECT && peer ? blockedPeerIds.has(peer.id) : false,
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
        members: {
          select: {
            userId: true,
            role: true,
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

    return {
      chatId: chat.id,
      chatType: chat.type === ChatType.GROUP ? "group" : "direct",
      title:
        chat.type === ChatType.GROUP
          ? chat.title?.trim() || "Yeni grup"
          : peer?.phone ?? peer?.displayName ?? "New Chat",
      description: chat.type === ChatType.GROUP ? (chat.description ?? null) : null,
      avatarUrl:
        chat.type === ChatType.GROUP
          ? (chat.avatarUrl ?? null)
          : peer?.avatarUrl ?? null,
      createdByUserId: chat.createdByUserId ?? null,
      memberCount: chat.members.length,
      myRole: chat.type === ChatType.GROUP ? (myMembership?.role ?? null) : null,
      isPublic: chat.type === ChatType.GROUP ? chat.isPublic === true : false,
      joinApprovalRequired:
        chat.type === ChatType.GROUP ? chat.joinApprovalRequired === true : false,
      memberAddPolicy:
        chat.type === ChatType.GROUP ? chat.memberAddPolicy : ChatMemberAddPolicy.ADMIN_ONLY
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
      !this.canAddGroupMembers({
        policy: chat.memberAddPolicy,
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
    if (!this.canManageGroupInfo(membership.role)) {
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
      !this.canRemoveGroupMember({
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
        lastSeenAt: member.user.lastSeenAt ? member.user.lastSeenAt.toISOString() : null
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

    await prisma.chatMember.updateMany({
      where: {
        userId,
        chatId: { in: ownedChatIds }
      },
      data: {
        hiddenAt: new Date()
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
