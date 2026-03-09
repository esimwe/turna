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

const messageIdParamSchema = z.object({
  messageId: z.string().trim().min(1).max(255)
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
  const chats = await chatService.getChatSummaries(userId);
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
      avatarUrl:
        chat.peerId && chat.peerAvatarKey && chat.peerUpdatedAt
          ? buildAvatarUrl(req, chat.peerId, new Date(chat.peerUpdatedAt))
          : null
    }))
  });
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
    if (error instanceof Error && error.message === "chat_blocked") {
      res.status(403).json({ error: "chat_blocked" });
      return;
    }

    logError("chat http send failed", error);
    res.status(500).json({ error: "failed_to_send_message" });
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
