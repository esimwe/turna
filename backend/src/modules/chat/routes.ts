import { Router } from "express";
import { z } from "zod";
import { logError } from "../../lib/logger.js";
import { prisma } from "../../lib/prisma.js";
import { sendChatMessagePush } from "../../lib/push.js";
import {
  createChatAttachmentUploadUrl,
  isChatAttachmentKeyOwnedByUser,
  isStorageConfigured
} from "../../lib/storage.js";
import { requireAuth, requireMessagingAccess } from "../../middleware/auth.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";
import { findLookupDisplayName } from "../profile/contact-lookup.js";
import { normalizeUsername } from "../profile/username.js";
import { normalizeE164Phone } from "../auth/phone.js";
import {
  emitChatMessage,
  emitChatStatus,
  emitInboxUpdate,
  getSocketsInUserRoom
} from "./chat.realtime.js";
import { chatService } from "./chat.service.js";

export const chatRouter = Router();
const prismaUserContact = (prisma as unknown as { userContact: any }).userContact;

const sendMessageAttachmentSchema = z.object({
  objectKey: z.string().trim().min(1).max(512),
  kind: z.enum(["image", "video", "file"]),
  fileName: z.string().trim().min(1).max(255).nullable().optional(),
  contentType: z.string().trim().min(1).max(100),
  sizeBytes: z.coerce.number().int().min(0).max(500 * 1024 * 1024).nullable().optional(),
  width: z.coerce.number().int().min(0).max(10000).nullable().optional(),
  height: z.coerce.number().int().min(0).max(10000).nullable().optional(),
  durationSeconds: z.coerce.number().int().min(0).max(24 * 60 * 60).nullable().optional()
});

const sendMessageSchema = z.object({
  chatId: z.string().min(1),
  text: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().max(4000).optional().nullable()
    ),
  attachments: z.array(sendMessageAttachmentSchema).max(30).optional().default([])
}).superRefine((value, ctx) => {
  if ((value.text?.length ?? 0) > 0 || value.attachments.length > 0) {
    return;
  }

  ctx.addIssue({
    code: z.ZodIssueCode.custom,
    message: "text_or_attachment_required",
    path: ["text"]
  });
});

const attachmentUploadInitSchema = z.object({
  chatId: z.string().trim().min(1).max(255),
  kind: z.enum(["image", "video", "file"]),
  contentType: z.string().trim().min(1).max(100),
  fileName: z.string().trim().min(1).max(255).optional()
}).superRefine((value, ctx) => {
  if (value.kind === "image" && !value.contentType.startsWith("image/")) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "image_content_type_required",
      path: ["contentType"]
    });
  }
  if (value.kind === "video" && !value.contentType.startsWith("video/")) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "video_content_type_required",
      path: ["contentType"]
    });
  }
});

const listMessagesQuerySchema = z.object({
  before: z.string().datetime().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(30)
});

const messageIdParamSchema = z.object({
  messageId: z.string().trim().min(1).max(255)
});

const submitMessageReportSchema = z.object({
  reasonCode: z.string().trim().min(2).max(50),
  details: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().max(1000).nullable().optional()
    )
});

const editMessageSchema = z.object({
  text: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().min(1).max(4000)
    )
});

const bulkDeleteChatsSchema = z.object({
  chatIds: z.array(z.string().trim().min(1).max(255)).min(1).max(200)
});

const chatIdParamSchema = z.object({
  chatId: z.string().trim().min(1).max(255)
});

const setChatMutedSchema = z.object({
  muted: z.boolean()
});

const setChatBlockedSchema = z.object({
  blocked: z.boolean()
});

const setChatArchivedSchema = z.object({
  archived: z.boolean()
});

const setChatFolderSchema = z.object({
  folderId: z.string().trim().min(1).max(255).nullable()
});

const createFolderSchema = z.object({
  name: z.string().trim().min(1).max(24)
});

const folderIdParamSchema = z.object({
  folderId: z.string().trim().min(1).max(255)
});

chatRouter.get("/:chatId/messages", requireAuth, async (req, res) => {
  const rawChatId = req.params.chatId;
  const chatId = Array.isArray(rawChatId) ? rawChatId[0] : rawChatId;
  if (!chatId) {
    res.status(400).json({ error: "chat_id_required" });
    return;
  }

  const userId = req.authUserId!;
  const hasAccess = await chatService.ensureChatAccess(chatId, userId);
  if (!hasAccess) {
    res.status(403).json({ error: "forbidden_chat_access" });
    return;
  }

  const parsedQuery = listMessagesQuerySchema.safeParse(req.query);
  if (!parsedQuery.success) {
    res.status(400).json({ error: "validation_error", details: parsedQuery.error.flatten() });
    return;
  }

  const page = await chatService.getMessagePage(chatId, {
    ...parsedQuery.data,
    userId
  });
  res.json({
    data: page.items,
    pageInfo: {
      hasMore: page.hasMore,
      nextBefore: page.nextBefore
    }
  });
});

chatRouter.get("/", requireAuth, async (req, res) => {
  const userId = req.authUserId!;
  const [chats, folders] = await Promise.all([
    chatService.getChatSummaries(userId),
    chatService.listFolders(userId)
  ]);
  res.json({
    data: chats.map((chat) => ({
      chatId: chat.chatId,
      title: chat.title,
      lastMessage: chat.lastMessage,
      lastMessageAt: chat.lastMessageAt,
      unreadCount: chat.unreadCount,
      peerId: chat.peerId,
      isMuted: chat.isMuted,
      isBlockedByMe: chat.isBlockedByMe,
      isArchived: chat.isArchived,
      folderId: chat.folderId,
      folderName: chat.folderName,
      avatarUrl:
        chat.peerId && chat.peerAvatarKey && chat.peerUpdatedAt
          ? buildAvatarUrl(req, chat.peerId, new Date(chat.peerUpdatedAt))
          : null
    })),
    folders: folders.map((folder) => ({
      id: folder.id,
      name: folder.name,
      sortOrder: folder.sortOrder
    }))
  });
});

chatRouter.get("/folders", requireAuth, async (req, res) => {
  const folders = await chatService.listFolders(req.authUserId!);
  res.json({ data: folders });
});

chatRouter.post("/folders", requireAuth, async (req, res) => {
  const parsed = createFolderSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const folder = await chatService.createFolder(req.authUserId!, parsed.data.name);
    emitInboxUpdate([req.authUserId!]);
    res.status(201).json({ data: folder });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "chat_folder_limit_reached":
          res.status(409).json({ error: error.message });
          return;
        case "chat_folder_exists":
          res.status(409).json({ error: error.message });
          return;
        case "chat_folder_name_required":
          res.status(400).json({ error: error.message });
          return;
      }
    }

    logError("chat folder create failed", error);
    res.status(500).json({ error: "failed_to_create_chat_folder" });
  }
});

chatRouter.delete("/folders/:folderId", requireAuth, async (req, res) => {
  const parsed = folderIdParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    await chatService.deleteFolder(req.authUserId!, parsed.data.folderId);
    emitInboxUpdate([req.authUserId!]);
    res.json({ data: { deleted: true } });
  } catch (error) {
    if (error instanceof Error && error.message === "chat_folder_not_found") {
      res.status(404).json({ error: error.message });
      return;
    }

    logError("chat folder delete failed", error);
    res.status(500).json({ error: "failed_to_delete_chat_folder" });
  }
});

chatRouter.post("/read-all", requireAuth, async (req, res) => {
  const userId = req.authUserId!;

  try {
    const results = await chatService.markAllChatsRead(userId);

    for (const result of results) {
      const participants = await chatService.getChatParticipantIds(result.chatId);
      const senderIds = participants.filter((participantId) => participantId !== userId);
      emitChatStatus({
        chatId: result.chatId,
        status: "read",
        messageIds: result.messageIds,
        userIds: senderIds
      });
    }

    emitInboxUpdate([userId]);
    res.json({
      data: {
        updatedChatCount: results.length,
        updatedMessageCount: results.reduce((sum, item) => sum + item.messageIds.length, 0)
      }
    });
  } catch (error) {
    logError("chat mark all read failed", error);
    res.status(500).json({ error: "failed_to_mark_all_read" });
  }
});

chatRouter.post("/delete", requireAuth, async (req, res) => {
  const parsed = bulkDeleteChatsSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const userId = req.authUserId!;

  try {
    const uniqueChatIds = Array.from(new Set(parsed.data.chatIds));
    const hiddenChatIds = await chatService.hideChatsForUser(userId, uniqueChatIds);
    emitInboxUpdate([userId]);
    res.json({
      data: {
        chatIds: hiddenChatIds
      }
    });
  } catch (error) {
    logError("chat bulk delete failed", error);
    res.status(500).json({ error: "failed_to_delete_chats" });
  }
});

chatRouter.post("/:chatId/read", requireAuth, async (req, res) => {
  const parsed = chatIdParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const userId = req.authUserId!;
  const hasAccess = await chatService.ensureChatAccess(parsed.data.chatId, userId);
  if (!hasAccess) {
    res.status(403).json({ error: "forbidden_chat_access" });
    return;
  }

  try {
    const messageIds = await chatService.markMessagesRead(parsed.data.chatId, userId);
    if (messageIds.length > 0) {
      const participants = await chatService.getChatParticipantIds(parsed.data.chatId);
      const senderIds = participants.filter((participantId) => participantId !== userId);
      emitChatStatus({
        chatId: parsed.data.chatId,
        status: "read",
        messageIds,
        userIds: senderIds
      });
      emitInboxUpdate(participants.length > 0 ? participants : [userId]);
    }

    res.json({ data: { updatedMessageCount: messageIds.length } });
  } catch (error) {
    logError("chat mark read failed", error);
    res.status(500).json({ error: "failed_to_mark_chat_read" });
  }
});

chatRouter.post("/:chatId/mute", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedBody = setChatMutedSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedParams.error.flatten()
    });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedBody.error.flatten()
    });
    return;
  }

  try {
    const muted = await chatService.setChatMuted(
      parsedParams.data.chatId,
      req.authUserId!,
      parsedBody.data.muted
    );
    res.json({ data: { muted } });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: error.message });
      return;
    }
    logError("chat mute update failed", error);
    res.status(500).json({ error: "failed_to_update_chat_mute" });
  }
});

chatRouter.post("/:chatId/clear", requireAuth, async (req, res) => {
  const parsed = chatIdParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    await chatService.clearChatForUser(parsed.data.chatId, req.authUserId!);
    emitInboxUpdate([req.authUserId!]);
    res.json({ data: { cleared: true } });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: error.message });
      return;
    }
    logError("chat clear failed", error);
    res.status(500).json({ error: "failed_to_clear_chat" });
  }
});

chatRouter.post("/:chatId/archive", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedBody = setChatArchivedSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedParams.error.flatten()
    });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedBody.error.flatten()
    });
    return;
  }

  try {
    const archived = await chatService.setChatArchived(
      parsedParams.data.chatId,
      req.authUserId!,
      parsedBody.data.archived
    );
    emitInboxUpdate([req.authUserId!]);
    res.json({ data: { archived } });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: error.message });
      return;
    }
    logError("chat archive update failed", error);
    res.status(500).json({ error: "failed_to_update_chat_archive" });
  }
});

chatRouter.post("/:chatId/folder", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedBody = setChatFolderSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedParams.error.flatten()
    });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedBody.error.flatten()
    });
    return;
  }

  try {
    const folder = await chatService.setChatFolder(
      parsedParams.data.chatId,
      req.authUserId!,
      parsedBody.data.folderId
    );
    emitInboxUpdate([req.authUserId!]);
    res.json({ data: folder });
  } catch (error) {
    if (error instanceof Error) {
      if (error.message === "forbidden_chat_access") {
        res.status(403).json({ error: error.message });
        return;
      }
      if (error.message === "chat_folder_not_found") {
        res.status(404).json({ error: error.message });
        return;
      }
    }
    logError("chat folder update failed", error);
    res.status(500).json({ error: "failed_to_update_chat_folder" });
  }
});

chatRouter.post("/:chatId/block", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedBody = setChatBlockedSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedParams.error.flatten()
    });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedBody.error.flatten()
    });
    return;
  }

  try {
    const blocked = await chatService.setDirectChatBlocked(
      parsedParams.data.chatId,
      req.authUserId!,
      parsedBody.data.blocked
    );
    res.json({ data: { blocked } });
  } catch (error) {
    if (error instanceof Error) {
      if (error.message === "forbidden_chat_access") {
        res.status(403).json({ error: error.message });
        return;
      }
      if (error.message === "invalid_block_target") {
        res.status(400).json({ error: error.message });
        return;
      }
    }
    logError("chat block update failed", error);
    res.status(500).json({ error: "failed_to_update_chat_block" });
  }
});

chatRouter.get("/directory/list", requireAuth, async (req, res) => {
  const userId = req.authUserId!;
  const users = await chatService.getUserDirectory(userId);
  res.json({
    data: users.map((user) => ({
      id: user.id,
      displayName: user.displayName,
      username: user.username,
      phone: user.phone,
      about: user.about,
      avatarUrl: user.avatarKey ? buildAvatarUrl(req, user.id, new Date(user.updatedAt)) : null
    }))
  });
});

chatRouter.get("/directory/contacts", requireAuth, async (req, res) => {
  const ownerId = req.authUserId!;
  const syncedContacts = await prismaUserContact.findMany({
    where: { ownerId },
    select: {
      lookupKey: true,
      displayName: true
    }
  });

  if (syncedContacts.length === 0) {
    res.json({ data: [] });
    return;
  }

  const labelsByKey = new Map<string, string>();
  for (const row of syncedContacts) {
    if (!labelsByKey.has(row.lookupKey)) {
      labelsByKey.set(row.lookupKey, row.displayName);
    }
  }

  const users = await prisma.user.findMany({
    where: {
      id: { not: ownerId },
      accountStatus: "ACTIVE",
      phone: { not: null }
    },
    select: {
      id: true,
      displayName: true,
      username: true,
      phone: true,
      about: true,
      avatarUrl: true,
      updatedAt: true
    }
  });

  const matchedUsers = users
    .map((user: any) => {
      const contactName = findLookupDisplayName(user.phone, labelsByKey);
      if (!contactName) return null;
      return {
        id: user.id,
        displayName: user.displayName,
        contactName,
        username: user.username,
        phone: user.phone,
        about: user.about,
        avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null
      };
    })
    .filter((item: any): item is NonNullable<typeof item> => item != null)
    .sort((left: any, right: any) => {
      const labelCompare = left.contactName.localeCompare(right.contactName, "tr");
      if (labelCompare !== 0) return labelCompare;
      return left.displayName.localeCompare(right.displayName, "tr");
    });

  res.json({ data: matchedUsers });
});

chatRouter.get("/directory/lookup", requireAuth, async (req, res) => {
  type LookupUser = {
    id: string;
    displayName: string;
    username: string | null;
    phone: string | null;
    about: string | null;
    avatarUrl: string | null;
    updatedAt: Date;
  };

  const rawQuery =
    (Array.isArray(req.query.q) ? req.query.q[0] : req.query.q) ??
    (Array.isArray(req.query.phone) ? req.query.phone[0] : req.query.phone);
  if (typeof rawQuery !== "string" || rawQuery.trim().length === 0) {
    res.status(400).json({ error: "lookup_query_required" });
    return;
  }

  const query = rawQuery.trim();
  let user: LookupUser | null = null;

  if (query.startsWith("+")) {
    try {
      const phone = normalizeE164Phone(query);
      user = await prisma.user.findFirst({
        where: {
          phone,
          id: { not: req.authUserId! },
          accountStatus: "ACTIVE"
        },
        select: {
          id: true,
          displayName: true,
          username: true,
          phone: true,
          about: true,
          avatarUrl: true,
          updatedAt: true
        }
      });
    } catch (_error) {
      res.status(400).json({ error: "invalid_phone" });
      return;
    }
  } else {
    const username = normalizeUsername(query);
    user = await prisma.user.findFirst({
      where: {
        username,
        id: { not: req.authUserId! },
        accountStatus: "ACTIVE"
      },
      select: {
        id: true,
        displayName: true,
        username: true,
        phone: true,
        about: true,
        avatarUrl: true,
        updatedAt: true
      }
    });
  }

  if (!user) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  res.json({
    data: {
      id: user.id,
      displayName: user.displayName,
      username: user.username,
      phone: user.phone,
      about: user.about,
      avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null
    }
  });
});

chatRouter.post("/attachments/upload-url", requireAuth, requireMessagingAccess, async (req, res) => {
  if (!isStorageConfigured()) {
    res.status(503).json({ error: "storage_not_configured" });
    return;
  }

  const parsed = attachmentUploadInitSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const userId = req.authUserId!;
  const hasAccess = await chatService.ensureChatAccess(parsed.data.chatId, userId);
  if (!hasAccess) {
    res.status(403).json({ error: "forbidden_chat_access" });
    return;
  }
  try {
    await chatService.ensureCanInteract(parsed.data.chatId, userId);
  } catch (error) {
    if (error instanceof Error && error.message === "chat_blocked") {
      res.status(403).json({ error: "chat_blocked" });
      return;
    }
    logError("chat attachment access check failed", error);
    res.status(500).json({ error: "failed_to_prepare_attachment_upload" });
    return;
  }

  const upload = await createChatAttachmentUploadUrl({
    chatId: parsed.data.chatId,
    userId,
    kind: parsed.data.kind,
    contentType: parsed.data.contentType,
    fileName: parsed.data.fileName
  });

  res.json({
    data: {
      objectKey: upload.objectKey,
      uploadUrl: upload.uploadUrl,
      headers: upload.headers
    }
  });
});

chatRouter.post("/messages", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsed = sendMessageSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const userId = req.authUserId!;
  try {
    const attachments = parsed.data.attachments.map((attachment) => ({
      objectKey: attachment.objectKey,
      kind: attachment.kind,
      fileName: attachment.fileName ?? null,
      contentType: attachment.contentType,
      sizeBytes: attachment.sizeBytes ?? null,
      width: attachment.width ?? null,
      height: attachment.height ?? null,
      durationSeconds: attachment.durationSeconds ?? null
    }));

    for (const attachment of attachments) {
      if (!isChatAttachmentKeyOwnedByUser({
        chatId: parsed.data.chatId,
        userId,
        objectKey: attachment.objectKey
      })) {
        res.status(403).json({ error: "invalid_attachment_key" });
        return;
      }
    }

    const message = await chatService.sendMessage({
      chatId: parsed.data.chatId,
      senderId: userId,
      text: parsed.data.text,
      attachments
    });

    const participants = await chatService.getChatParticipantIds(parsed.data.chatId);
    emitChatMessage(parsed.data.chatId, message, participants);
    const recipientIds = participants.filter((participantId) => participantId !== userId);
    if (recipientIds.length > 0) {
      chatService
        .getUserDisplayName(userId)
        .then((senderDisplayName) =>
          sendChatMessagePush({
            message,
            senderDisplayName,
            recipientUserIds: recipientIds
          })
        )
        .catch((error: unknown) => {
          logError("chat push after http send failed", error);
        });
    }

    for (const peerId of recipientIds) {
      const peerSockets = await getSocketsInUserRoom(peerId);
      if (peerSockets.length === 0) continue;
      const deliveredIds = await chatService.markMessagesDelivered(parsed.data.chatId, peerId);
      if (deliveredIds.length > 0) {
        emitChatStatus({
          chatId: parsed.data.chatId,
          status: "delivered",
          messageIds: deliveredIds,
          userIds: [userId]
        });
      }
    }

    emitInboxUpdate(participants.length > 0 ? participants : [userId]);
    res.status(201).json({ data: message });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: "forbidden_chat_access" });
      return;
    }
    if (error instanceof Error && error.message === "invalid_attachment_key") {
      res.status(403).json({ error: "invalid_attachment_key" });
      return;
    }
    if (error instanceof Error && error.message === "chat_blocked") {
      res.status(403).json({ error: "chat_blocked" });
      return;
    }

    logError("chat http send failed", error);
    res.status(500).json({ error: "failed_to_send_message" });
  }
});

chatRouter.post("/messages/:messageId/report", requireAuth, async (req, res) => {
  const parsedParams = messageIdParamSchema.safeParse(req.params);
  const parsedBody = submitMessageReportSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  const message = await chatService.getMessageById(parsedParams.data.messageId);
  if (!message) {
    res.status(404).json({ error: "message_not_found" });
    return;
  }

  const hasAccess = await chatService.ensureChatAccess(message.chatId, req.authUserId!);
  if (!hasAccess) {
    res.status(403).json({ error: "forbidden_chat_access" });
    return;
  }

  if (message.senderId === req.authUserId) {
    res.status(400).json({ error: "cannot_report_own_message" });
    return;
  }

  const existing = await chatService.findOpenMessageReport({
    reporterUserId: req.authUserId!,
    messageId: message.id
  });
  if (existing) {
    res.status(409).json({ error: "report_already_exists" });
    return;
  }

  const report = await chatService.createMessageReport({
    reporterUserId: req.authUserId!,
    messageId: message.id,
    chatId: message.chatId,
    reportedUserId: message.senderId,
    reasonCode: parsedBody.data.reasonCode.trim().toUpperCase(),
    details: parsedBody.data.details ?? null
  });

  res.status(201).json({ data: { id: report.id, status: report.status } });
});

chatRouter.put("/messages/:messageId", requireAuth, async (req, res) => {
  const parsedParams = messageIdParamSchema.safeParse(req.params);
  const parsedBody = editMessageSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  const userId = req.authUserId!;
  try {
    const message = await chatService.editMessage(
      parsedParams.data.messageId,
      userId,
      parsedBody.data.text
    );
    const participants = await chatService.getChatParticipantIds(message.chatId);
    emitChatMessage(message.chatId, message, participants);
    emitInboxUpdate(participants.length > 0 ? participants : [userId]);
    res.json({ data: message });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "message_not_found":
          res.status(404).json({ error: error.message });
          return;
        case "message_edit_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "message_edit_window_expired":
          res.status(409).json({ error: error.message });
          return;
        case "message_edit_text_required":
          res.status(400).json({ error: error.message });
          return;
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
      }
    }

    logError("chat edit failed", error);
    res.status(500).json({ error: "failed_to_edit_message" });
  }
});

chatRouter.post("/messages/:messageId/delete-for-everyone", requireAuth, async (req, res) => {
  const parsed = messageIdParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const userId = req.authUserId!;
  try {
    const message = await chatService.deleteMessageForEveryone(parsed.data.messageId, userId);
    const participants = await chatService.getChatParticipantIds(message.chatId);
    emitChatMessage(message.chatId, message, participants);
    emitInboxUpdate(participants.length > 0 ? participants : [userId]);
    res.json({ data: message });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "message_not_found":
          res.status(404).json({ error: error.message });
          return;
        case "message_delete_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "message_delete_window_expired":
          res.status(409).json({ error: error.message });
          return;
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
      }
    }

    logError("chat delete for everyone failed", error);
    res.status(500).json({ error: "failed_to_delete_message" });
  }
});
