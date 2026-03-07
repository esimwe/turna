import { Router } from "express";
import { z } from "zod";
import { logError } from "../../lib/logger.js";
import { sendChatMessagePush } from "../../lib/push.js";
import {
  createChatAttachmentUploadUrl,
  isChatAttachmentKeyOwnedByUser,
  isStorageConfigured
} from "../../lib/storage.js";
import { requireAuth } from "../../middleware/auth.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";
import {
  emitChatMessage,
  emitChatStatus,
  emitInboxUpdate,
  getSocketsInUserRoom
} from "./chat.realtime.js";
import { chatService } from "./chat.service.js";

export const chatRouter = Router();

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

  const page = await chatService.getMessagePage(chatId, parsedQuery.data);
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
  const chats = await chatService.getChatSummaries(userId);
  res.json({
    data: chats.map((chat) => ({
      chatId: chat.chatId,
      title: chat.title,
      lastMessage: chat.lastMessage,
      lastMessageAt: chat.lastMessageAt,
      unreadCount: chat.unreadCount,
      avatarUrl:
        chat.peerId && chat.peerAvatarKey && chat.peerUpdatedAt
          ? buildAvatarUrl(req, chat.peerId, new Date(chat.peerUpdatedAt))
          : null
    }))
  });
});

chatRouter.get("/directory/list", requireAuth, async (req, res) => {
  const userId = req.authUserId!;
  const users = await chatService.getUserDirectory(userId);
  res.json({
    data: users.map((user) => ({
      id: user.id,
      displayName: user.displayName,
      avatarUrl: user.avatarKey ? buildAvatarUrl(req, user.id, new Date(user.updatedAt)) : null
    }))
  });
});

chatRouter.post("/attachments/upload-url", requireAuth, async (req, res) => {
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

chatRouter.post("/messages", requireAuth, async (req, res) => {
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

    logError("chat http send failed", error);
    res.status(500).json({ error: "failed_to_send_message" });
  }
});
