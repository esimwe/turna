import { Router } from "express";
import { z } from "zod";
import { logError } from "../../lib/logger.js";
import { prisma } from "../../lib/prisma.js";
import { sendChatMessagePush } from "../../lib/push.js";
import {
  createObjectReadUrl,
  createChatAttachmentUploadUrl,
  getObjectHead,
  isAvatarKeyOwnedByUser,
  isChatAttachmentKeyOwnedByUser,
  isStorageConfigured
} from "../../lib/storage.js";
import { requireAuth, requireMessagingAccess } from "../../middleware/auth.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";
import { findLookupDisplayName } from "../profile/contact-lookup.js";
import { normalizeUsername } from "../profile/username.js";
import { normalizeLookupPhone } from "../auth/phone.js";
import {
  emitChatMessage,
  emitChatStatus,
  emitUserEvent,
  emitInboxUpdate,
  getActiveChatUserIds,
  getSocketsInUserRoom
} from "./chat.realtime.js";
import { chatService } from "./chat.service.js";

export const chatRouter = Router();
const prismaUserContact = (prisma as unknown as { userContact: any }).userContact;

const sendMessageAttachmentSchema = z.object({
  objectKey: z.string().trim().min(1).max(512),
  kind: z.enum(["image", "video", "file"]),
  transferMode: z.enum(["standard", "hd", "document"]).optional().default("standard"),
  fileName: z.string().trim().min(1).max(255).nullable().optional(),
  contentType: z.string().trim().min(1).max(100),
  sizeBytes: z.coerce.number().int().min(0).max(2 * 1024 * 1024 * 1024).nullable().optional(),
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

const chatSearchQuerySchema = listMessagesQuerySchema.extend({
  q: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().min(1).max(120)
    )
});

const chatCollectionQuerySchema = listMessagesQuerySchema.extend({
  type: z.enum(["media", "docs", "links"])
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

const messageReactionSchema = z.object({
  emoji: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().min(1).max(16)
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

const setChatFavoritedSchema = z.object({
  favorited: z.boolean()
});

const setChatLockedSchema = z.object({
  locked: z.boolean()
});

const setChatFolderSchema = z.object({
  folderId: z.string().trim().min(1).max(255).nullable()
});

const createFolderSchema = z.object({
  name: z.string().trim().min(1).max(24)
});

const createGroupSchema = z.object({
  title: z.string().trim().min(1).max(80),
  memberUserIds: z.array(z.string().trim().min(1).max(255)).min(1).max(2047)
});

const folderIdParamSchema = z.object({
  folderId: z.string().trim().min(1).max(255)
});

const groupMembersBodySchema = z.object({
  memberUserIds: z.array(z.string().trim().min(1).max(255)).min(1).max(2047)
});

const groupMembersQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(40),
  offset: z.coerce.number().int().min(0).default(0)
});

const updateGroupSchema = z
  .object({
    title: z
      .preprocess(
        (value) => (typeof value === "string" ? value.trim() : value),
        z.string().min(1).max(80).nullable().optional()
      ),
    description: z
      .preprocess(
        (value) => (typeof value === "string" ? value.trim() : value),
        z.string().max(240).nullable().optional()
      ),
    avatarObjectKey: z.string().trim().min(1).max(512).nullable().optional(),
    clearAvatar: z.boolean().optional().default(false)
  })
  .superRefine((value, ctx) => {
    if (
      value.title !== undefined ||
      value.description !== undefined ||
      value.avatarObjectKey !== undefined ||
      value.clearAvatar === true
    ) {
      return;
    }
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "group_update_required",
      path: ["title"]
    });
  });

const chatPolicyScopeSchema = z.enum([
  "OWNER_ONLY",
  "ADMIN_ONLY",
  "EDITOR_ONLY",
  "EVERYONE"
]);

const updateGroupSettingsSchema = z
  .object({
    isPublic: z.boolean().optional(),
    joinApprovalRequired: z.boolean().optional(),
    whoCanSend: chatPolicyScopeSchema.optional(),
    whoCanEditInfo: chatPolicyScopeSchema.optional(),
    whoCanInvite: chatPolicyScopeSchema.optional(),
    whoCanAddMembers: chatPolicyScopeSchema.optional(),
    whoCanStartCalls: chatPolicyScopeSchema.optional(),
    historyVisibleToNewMembers: z.boolean().optional()
  })
  .superRefine((value, ctx) => {
    if (
      value.isPublic !== undefined ||
      value.joinApprovalRequired !== undefined ||
      value.whoCanSend !== undefined ||
      value.whoCanEditInfo !== undefined ||
      value.whoCanInvite !== undefined ||
      value.whoCanAddMembers !== undefined ||
      value.whoCanStartCalls !== undefined ||
      value.historyVisibleToNewMembers !== undefined
    ) {
      return;
    }
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "group_settings_update_required",
      path: ["whoCanSend"]
    });
  });

const groupMemberParamSchema = z.object({
  chatId: z.string().trim().min(1).max(255),
  memberUserId: z.string().trim().min(1).max(255)
});

const updateGroupMemberRoleSchema = z.object({
  role: z.enum(["ADMIN", "EDITOR", "MEMBER"])
});

const transferGroupOwnerSchema = z.object({
  newOwnerUserId: z.string().trim().min(1).max(255)
});

const inviteLinkDurationSchema = z.enum(["7_DAYS", "30_DAYS", "UNLIMITED"]);

const createInviteLinkSchema = z.object({
  duration: inviteLinkDurationSchema.default("7_DAYS")
});

const inviteLinkParamSchema = z.object({
  chatId: z.string().trim().min(1).max(255),
  inviteLinkId: z.string().trim().min(1).max(255)
});

const joinByInviteSchema = z.object({
  token: z.string().trim().min(8).max(255)
});

const muteGroupMemberSchema = z.object({
  duration: z.enum(["1_HOUR", "24_HOURS", "PERMANENT"]),
  reason: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().max(240).nullable().optional()
    )
});

const banGroupMemberSchema = z.object({
  reason: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().max(240).nullable().optional()
    )
});

const joinRequestParamSchema = z.object({
  chatId: z.string().trim().min(1).max(255),
  requestId: z.string().trim().min(1).max(255)
});

function isAbsoluteUrl(value: string): boolean {
  return /^https?:\/\//i.test(value);
}

async function resolveGroupAvatarUrl(avatarUrl: string | null): Promise<string | null> {
  if (!avatarUrl) return null;
  if (isAbsoluteUrl(avatarUrl)) return avatarUrl;
  try {
    return await createObjectReadUrl(avatarUrl);
  } catch (error) {
    logError("group avatar read url create failed", error);
    return null;
  }
}

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

chatRouter.get("/:chatId/search", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedQuery = chatSearchQuerySchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({ error: "validation_error", details: parsedQuery.error.flatten() });
    return;
  }

  try {
    const page = await chatService.searchMessagePage(
      parsedParams.data.chatId,
      req.authUserId!,
      parsedQuery.data.q,
      {
        before: parsedQuery.data.before ?? null,
        limit: parsedQuery.data.limit
      }
    );
    res.json({
      data: page.items,
      pageInfo: {
        hasMore: page.hasMore,
        nextBefore: page.nextBefore
      }
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
        case "chat_search_query_required":
          res.status(400).json({ error: error.message });
          return;
      }
    }

    logError("chat search failed", error);
    res.status(500).json({ error: "failed_to_search_chat_messages" });
  }
});

chatRouter.get("/:chatId/media-items", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedQuery = chatCollectionQuerySchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({ error: "validation_error", details: parsedQuery.error.flatten() });
    return;
  }

  try {
    const page = await chatService.getCollectionMessagePage(
      parsedParams.data.chatId,
      req.authUserId!,
      parsedQuery.data.type,
      {
        before: parsedQuery.data.before ?? null,
        limit: parsedQuery.data.limit
      }
    );
    res.json({
      data: page.items,
      pageInfo: {
        hasMore: page.hasMore,
        nextBefore: page.nextBefore
      }
    });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: error.message });
      return;
    }

    logError("chat media items failed", error);
    res.status(500).json({ error: "failed_to_get_chat_media_items" });
  }
});

chatRouter.get("/", requireAuth, async (req, res) => {
  const userId = req.authUserId!;
  const [chats, folders] = await Promise.all([
    chatService.getChatSummaries(userId),
    chatService.listFolders(userId)
  ]);
  const data = await Promise.all(
    chats.map(async (chat) => ({
      chatId: chat.chatId,
      title: chat.title,
      chatType: chat.chatType,
      memberPreviewNames: chat.memberPreviewNames,
      lastMessage: chat.lastMessage,
      lastMessageAt: chat.lastMessageAt,
      unreadCount: chat.unreadCount,
      peerId: chat.peerId,
      memberCount: chat.memberCount,
      myRole: chat.myRole,
      isPublic: chat.isPublic,
      description: chat.groupDescription,
      isMuted: chat.isMuted,
      isBlockedByMe: chat.isBlockedByMe,
      isArchived: chat.isArchived,
      isFavorited: chat.isFavorited,
      isLocked: chat.isLocked,
      folderId: chat.folderId,
      folderName: chat.folderName,
      avatarUrl:
        chat.chatType === "group"
          ? await resolveGroupAvatarUrl(chat.groupAvatarUrl)
          : chat.peerId && chat.peerAvatarKey && chat.peerUpdatedAt
          ? buildAvatarUrl(req, chat.peerId, new Date(chat.peerUpdatedAt))
          : null
    }))
  );
  res.json({
    data,
    folders: folders.map((folder) => ({
      id: folder.id,
      name: folder.name,
      sortOrder: folder.sortOrder
    }))
  });
});

chatRouter.post("/groups", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsed = createGroupSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const group = await chatService.createGroup({
      creatorUserId: req.authUserId!,
      title: parsed.data.title,
      memberUserIds: parsed.data.memberUserIds
    });
    emitInboxUpdate([req.authUserId!, ...parsed.data.memberUserIds]);
    res.status(201).json({ data: group });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "group_title_required":
        case "group_min_members_required":
        case "group_member_not_found":
        case "group_member_limit_exceeded":
          res.status(400).json({ error: error.message });
          return;
      }
    }

    logError("group create failed", error);
    res.status(500).json({ error: "failed_to_create_group" });
  }
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
      const audience = await chatService.getTypingAudience(result.chatId, userId);
      const activeUserIds = await getActiveChatUserIds(result.chatId);
      emitChatStatus({
        chatId: result.chatId,
        chatType: audience.chatType,
        status: "read",
        messageIds: result.messageIds,
        userIds: audience.recipientUserIds.filter((participantId) =>
          activeUserIds.includes(participantId)
        )
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
      const audience = await chatService.getTypingAudience(parsed.data.chatId, userId);
      const activeUserIds = await getActiveChatUserIds(parsed.data.chatId);
      emitChatStatus({
        chatId: parsed.data.chatId,
        chatType: audience.chatType,
        status: "read",
        messageIds,
        userIds: audience.recipientUserIds.filter((participantId) =>
          activeUserIds.includes(participantId)
        )
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

chatRouter.post("/:chatId/favorite", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedBody = setChatFavoritedSchema.safeParse(req.body);
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
    const favorited = await chatService.setChatFavorited(
      parsedParams.data.chatId,
      req.authUserId!,
      parsedBody.data.favorited
    );
    emitInboxUpdate([req.authUserId!]);
    res.json({ data: { favorited } });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: error.message });
      return;
    }
    logError("chat favorite update failed", error);
    res.status(500).json({ error: "failed_to_update_chat_favorite" });
  }
});

chatRouter.post("/:chatId/lock", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedBody = setChatLockedSchema.safeParse(req.body);
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
    const locked = await chatService.setChatLocked(
      parsedParams.data.chatId,
      req.authUserId!,
      parsedBody.data.locked
    );
    emitInboxUpdate([req.authUserId!]);
    res.json({ data: { locked } });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: error.message });
      return;
    }
    logError("chat lock update failed", error);
    res.status(500).json({ error: "failed_to_update_chat_lock" });
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
      const phone = normalizeLookupPhone(query);
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
  } else if (/^[\d\s()+-]+$/.test(query)) {
    try {
      const phone = normalizeLookupPhone(query);
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

chatRouter.get("/:chatId/members", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedQuery = groupMembersQuerySchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({ error: "validation_error", details: parsedQuery.error.flatten() });
    return;
  }

  try {
    const page = await chatService.listGroupMembers(
      parsedParams.data.chatId,
      req.authUserId!,
      parsedQuery.data
    );
    res.json({
      data: page.items.map((member) => ({
        userId: member.userId,
        displayName: member.displayName,
        username: member.username,
        phone: member.phone,
        role: member.role,
        canSend: member.canSend,
        joinedAt: member.joinedAt,
        lastSeenAt: member.lastSeenAt,
        isMuted: member.isMuted,
        mutedUntil: member.mutedUntil,
        muteReason: member.muteReason,
        avatarUrl:
          member.avatarKey && member.updatedAt
            ? buildAvatarUrl(req, member.userId, new Date(member.updatedAt))
            : null
      })),
      pageInfo: {
        totalCount: page.totalCount,
        hasMore: page.hasMore,
        limit: parsedQuery.data.limit,
        offset: parsedQuery.data.offset
      }
    });
  } catch (error) {
    if (error instanceof Error) {
      if (error.message === "forbidden_chat_access") {
        res.status(403).json({ error: error.message });
        return;
      }
      if (error.message === "group_not_found") {
        res.status(404).json({ error: error.message });
        return;
      }
    }

    logError("group member list failed", error);
    res.status(500).json({ error: "failed_to_list_group_members" });
  }
});

chatRouter.post("/:chatId/members", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedBody = groupMembersBodySchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const result = await chatService.addGroupMembers({
      chatId: parsedParams.data.chatId,
      requesterUserId: req.authUserId!,
      memberUserIds: parsedBody.data.memberUserIds
    });
    emitInboxUpdate([req.authUserId!, ...result.participantIds]);
    if (result.systemMessage) {
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.participantIds
      );
    }
    res.status(201).json({
      data: result.members.map((member) => ({
        userId: member.userId,
        displayName: member.displayName,
        username: member.username,
        phone: member.phone,
        role: member.role,
        canSend: member.canSend,
        joinedAt: member.joinedAt,
        lastSeenAt: member.lastSeenAt
      }))
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
        case "group_member_add_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
        case "group_member_not_found":
        case "group_member_limit_exceeded":
          res.status(400).json({ error: error.message });
          return;
      }
    }

    logError("group add members failed", error);
    res.status(500).json({ error: "failed_to_add_group_members" });
  }
});

chatRouter.put("/:chatId", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedBody = updateGroupSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  if (parsedBody.data.avatarObjectKey) {
    if (!isAvatarKeyOwnedByUser(req.authUserId!, parsedBody.data.avatarObjectKey)) {
      res.status(403).json({ error: "forbidden_avatar_key" });
      return;
    }
    try {
      const head = await getObjectHead(parsedBody.data.avatarObjectKey);
      if (!head.contentType?.startsWith("image/")) {
        res.status(400).json({ error: "image_content_type_required" });
        return;
      }
    } catch (error) {
      logError("group avatar head failed", error);
      res.status(400).json({ error: "avatar_upload_missing" });
      return;
    }
  }

  try {
    const result = await chatService.updateGroupDetail({
      chatId: parsedParams.data.chatId,
      requesterUserId: req.authUserId!,
      title: parsedBody.data.title,
      description: parsedBody.data.description,
      avatarObjectKey: parsedBody.data.avatarObjectKey,
      clearAvatar: parsedBody.data.clearAvatar
    });
    emitInboxUpdate(result.participantIds);
    if (result.systemMessage) {
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.participantIds
      );
    }
    res.json({
      data: {
        ...result.detail,
        avatarUrl: await resolveGroupAvatarUrl(result.detail.avatarUrl)
      }
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
        case "group_info_update_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }

    logError("group update failed", error);
    res.status(500).json({ error: "failed_to_update_group" });
  }
});

chatRouter.put(
  "/:chatId/settings",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = chatIdParamSchema.safeParse(req.params);
    const parsedBody = updateGroupSettingsSchema.safeParse(req.body);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
      return;
    }

    try {
      const result = await chatService.updateGroupSettings({
        chatId: parsedParams.data.chatId,
        requesterUserId: req.authUserId!,
        ...parsedBody.data
      });
      emitInboxUpdate(result.participantIds);
      if (result.systemMessage) {
        emitChatMessage(
          parsedParams.data.chatId,
          { ...result.systemMessage, chatType: "group" },
          result.participantIds
        );
      }
      res.json({
        data: {
          ...result.detail,
          avatarUrl: await resolveGroupAvatarUrl(result.detail.avatarUrl)
        }
      });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_settings_update_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
            res.status(404).json({ error: error.message });
            return;
        }
      }

      logError("group settings update failed", error);
      res.status(500).json({ error: "failed_to_update_group_settings" });
    }
  }
);

chatRouter.put(
  "/:chatId/members/:memberUserId/role",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = groupMemberParamSchema.safeParse(req.params);
    const parsedBody = updateGroupMemberRoleSchema.safeParse(req.body);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
      return;
    }

    try {
      const result = await chatService.updateGroupMemberRole({
        chatId: parsedParams.data.chatId,
        requesterUserId: req.authUserId!,
        targetUserId: parsedParams.data.memberUserId,
        nextRole: parsedBody.data.role
      });
      emitInboxUpdate(result.participantIds);
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.participantIds
      );
      res.json({ ok: true });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_role_update_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
            res.status(404).json({ error: error.message });
            return;
          case "group_member_not_found":
            res.status(400).json({ error: error.message });
            return;
        }
      }

      logError("group role update failed", error);
      res.status(500).json({ error: "failed_to_update_group_member_role" });
    }
  }
);

chatRouter.post(
  "/:chatId/owner-transfer",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = chatIdParamSchema.safeParse(req.params);
    const parsedBody = transferGroupOwnerSchema.safeParse(req.body);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
      return;
    }

    try {
      const result = await chatService.transferGroupOwnership({
        chatId: parsedParams.data.chatId,
        requesterUserId: req.authUserId!,
        newOwnerUserId: parsedBody.data.newOwnerUserId
      });
      emitInboxUpdate(result.participantIds);
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.participantIds
      );
      res.json({
        data: {
          ...result.detail,
          avatarUrl: await resolveGroupAvatarUrl(result.detail.avatarUrl)
        }
      });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_owner_transfer_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
            res.status(404).json({ error: error.message });
            return;
          case "group_member_not_found":
            res.status(400).json({ error: error.message });
            return;
        }
      }

      logError("group owner transfer failed", error);
      res.status(500).json({ error: "failed_to_transfer_group_owner" });
    }
  }
);

chatRouter.get("/:chatId/invite-links", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }

  try {
    const links = await chatService.listInviteLinks(parsedParams.data.chatId, req.authUserId!);
    res.json({
      data: links.map((item) => ({
        ...item,
        inviteUrl: `turna://join-group?token=${item.token}`
      }))
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
        case "group_invite_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }
    logError("group invite links list failed", error);
    res.status(500).json({ error: "failed_to_list_group_invite_links" });
  }
});

chatRouter.post("/:chatId/invite-links", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedBody = createInviteLinkSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const durationDays =
      parsedBody.data.duration === "7_DAYS"
        ? 7
        : parsedBody.data.duration === "30_DAYS"
        ? 30
        : null;
    const link = await chatService.createInviteLink({
      chatId: parsedParams.data.chatId,
      requesterUserId: req.authUserId!,
      durationDays
    });
    res.status(201).json({
      data: {
        ...link,
        inviteUrl: `turna://join-group?token=${link.token}`
      }
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
        case "group_invite_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }
    logError("group invite link create failed", error);
    res.status(500).json({ error: "failed_to_create_group_invite_link" });
  }
});

chatRouter.post(
  "/:chatId/invite-links/:inviteLinkId/revoke",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = inviteLinkParamSchema.safeParse(req.params);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }

    try {
      await chatService.revokeInviteLink({
        chatId: parsedParams.data.chatId,
        inviteLinkId: parsedParams.data.inviteLinkId,
        requesterUserId: req.authUserId!
      });
      res.json({ ok: true });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_invite_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
          case "group_invite_not_found":
            res.status(404).json({ error: error.message });
            return;
        }
      }
      logError("group invite link revoke failed", error);
      res.status(500).json({ error: "failed_to_revoke_group_invite_link" });
    }
  }
);

chatRouter.post("/:chatId/join", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }

  try {
    const result = await chatService.joinGroup({
      chatId: parsedParams.data.chatId,
      requesterUserId: req.authUserId!
    });
    if (result.systemMessage) {
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.participantIds
      );
    }
    emitInboxUpdate(result.participantIds);
    res.status(result.status === "requested" ? 202 : 200).json({
      data: {
        ...result.detail,
        avatarUrl: await resolveGroupAvatarUrl(result.detail.avatarUrl)
      },
      status: result.status
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "group_private":
        case "group_join_banned":
          res.status(403).json({ error: error.message });
          return;
        case "group_member_limit_exceeded":
          res.status(409).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }
    logError("group join failed", error);
    res.status(500).json({ error: "failed_to_join_group" });
  }
});

chatRouter.post("/join-by-invite", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedBody = joinByInviteSchema.safeParse(req.body);
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const result = await chatService.joinGroupByInvite({
      token: parsedBody.data.token,
      requesterUserId: req.authUserId!
    });
    if (result.systemMessage) {
      emitChatMessage(
        result.detail.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.participantIds
      );
    }
    emitInboxUpdate(result.participantIds);
    res.json({
      data: {
        ...result.detail,
        avatarUrl: await resolveGroupAvatarUrl(result.detail.avatarUrl)
      }
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "group_invite_expired":
        case "group_join_banned":
          res.status(403).json({ error: error.message });
          return;
        case "group_invite_not_found":
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }
    logError("group join by invite failed", error);
    res.status(500).json({ error: "failed_to_join_group_by_invite" });
  }
});

chatRouter.get("/:chatId/join-requests", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  try {
    const items = await chatService.listJoinRequests(parsedParams.data.chatId, req.authUserId!);
    res.json({
      data: items.map((item) => ({
        ...item,
        avatarUrl: item.avatarKey
          ? buildAvatarUrl(req, item.userId, new Date())
          : null
      }))
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
        case "group_join_request_review_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }
    logError("group join requests list failed", error);
    res.status(500).json({ error: "failed_to_list_group_join_requests" });
  }
});

chatRouter.post(
  "/:chatId/join-requests/:requestId/approve",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = joinRequestParamSchema.safeParse(req.params);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    try {
      const result = await chatService.reviewJoinRequest({
        chatId: parsedParams.data.chatId,
        requestId: parsedParams.data.requestId,
        requesterUserId: req.authUserId!,
        approve: true
      });
      emitInboxUpdate(result.participantIds);
      if (result.systemMessage) {
        emitChatMessage(
          parsedParams.data.chatId,
          { ...result.systemMessage, chatType: "group" },
          result.participantIds
        );
      }
      res.json({
        ok: true,
        data: result.detail
          ? {
              ...result.detail,
              avatarUrl: await resolveGroupAvatarUrl(result.detail.avatarUrl)
            }
          : null
      });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_join_request_review_not_allowed":
          case "group_join_banned":
            res.status(403).json({ error: error.message });
            return;
          case "group_member_limit_exceeded":
            res.status(409).json({ error: error.message });
            return;
          case "group_not_found":
          case "group_join_request_not_found":
            res.status(404).json({ error: error.message });
            return;
        }
      }
      logError("group join request approve failed", error);
      res.status(500).json({ error: "failed_to_approve_group_join_request" });
    }
  }
);

chatRouter.post(
  "/:chatId/join-requests/:requestId/reject",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = joinRequestParamSchema.safeParse(req.params);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    try {
      await chatService.reviewJoinRequest({
        chatId: parsedParams.data.chatId,
        requestId: parsedParams.data.requestId,
        requesterUserId: req.authUserId!,
        approve: false
      });
      res.json({ ok: true });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_join_request_review_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
          case "group_join_request_not_found":
            res.status(404).json({ error: error.message });
            return;
        }
      }
      logError("group join request reject failed", error);
      res.status(500).json({ error: "failed_to_reject_group_join_request" });
    }
  }
);

chatRouter.get("/:chatId/mutes", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  try {
    const items = await chatService.listGroupMutes(parsedParams.data.chatId, req.authUserId!);
    res.json({
      data: items.map((item) => ({
        ...item,
        avatarUrl: item.avatarKey
          ? buildAvatarUrl(req, item.userId, new Date())
          : null
      }))
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
        case "group_member_mute_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }
    logError("group mute list failed", error);
    res.status(500).json({ error: "failed_to_list_group_mutes" });
  }
});

chatRouter.post(
  "/:chatId/members/:memberUserId/mute",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = groupMemberParamSchema.safeParse(req.params);
    const parsedBody = muteGroupMemberSchema.safeParse(req.body);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
      return;
    }
    try {
      const result = await chatService.muteGroupMember({
        chatId: parsedParams.data.chatId,
        requesterUserId: req.authUserId!,
        memberUserId: parsedParams.data.memberUserId,
        duration: parsedBody.data.duration,
        reason: parsedBody.data.reason ?? null
      });
      emitInboxUpdate(result.participantIds);
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.participantIds
      );
      res.json({ ok: true });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_member_mute_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
            res.status(404).json({ error: error.message });
            return;
          case "group_member_not_found":
            res.status(400).json({ error: error.message });
            return;
        }
      }
      logError("group member mute failed", error);
      res.status(500).json({ error: "failed_to_mute_group_member" });
    }
  }
);

chatRouter.post(
  "/:chatId/members/:memberUserId/unmute",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = groupMemberParamSchema.safeParse(req.params);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    try {
      const result = await chatService.unmuteGroupMember({
        chatId: parsedParams.data.chatId,
        requesterUserId: req.authUserId!,
        memberUserId: parsedParams.data.memberUserId
      });
      emitInboxUpdate(result.participantIds);
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.participantIds
      );
      res.json({ ok: true });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_member_mute_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
            res.status(404).json({ error: error.message });
            return;
          case "group_member_not_found":
            res.status(400).json({ error: error.message });
            return;
        }
      }
      logError("group member unmute failed", error);
      res.status(500).json({ error: "failed_to_unmute_group_member" });
    }
  }
);

chatRouter.get("/:chatId/bans", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  try {
    const items = await chatService.listGroupBans(parsedParams.data.chatId, req.authUserId!);
    res.json({
      data: items.map((item) => ({
        ...item,
        avatarUrl: item.avatarKey
          ? buildAvatarUrl(req, item.userId, new Date())
          : null
      }))
    });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
        case "group_member_ban_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }
    logError("group ban list failed", error);
    res.status(500).json({ error: "failed_to_list_group_bans" });
  }
});

chatRouter.post(
  "/:chatId/members/:memberUserId/ban",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = groupMemberParamSchema.safeParse(req.params);
    const parsedBody = banGroupMemberSchema.safeParse(req.body);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
      return;
    }
    try {
      const result = await chatService.banGroupMember({
        chatId: parsedParams.data.chatId,
        requesterUserId: req.authUserId!,
        memberUserId: parsedParams.data.memberUserId,
        reason: parsedBody.data.reason ?? null
      });
      emitInboxUpdate(result.notifyUserIds);
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.remainingParticipantIds
      );
      res.json({ ok: true });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_member_ban_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
            res.status(404).json({ error: error.message });
            return;
          case "group_member_not_found":
            res.status(400).json({ error: error.message });
            return;
        }
      }
      logError("group member ban failed", error);
      res.status(500).json({ error: "failed_to_ban_group_member" });
    }
  }
);

chatRouter.post(
  "/:chatId/bans/:memberUserId/unban",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = groupMemberParamSchema.safeParse(req.params);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    try {
      const result = await chatService.unbanGroupMember({
        chatId: parsedParams.data.chatId,
        requesterUserId: req.authUserId!,
        bannedUserId: parsedParams.data.memberUserId
      });
      emitInboxUpdate(result.participantIds);
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.participantIds
      );
      res.json({ ok: true });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
          case "group_member_ban_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
          case "group_ban_not_found":
            res.status(404).json({ error: error.message });
            return;
        }
      }
      logError("group member unban failed", error);
      res.status(500).json({ error: "failed_to_unban_group_member" });
    }
  }
);

chatRouter.delete(
  "/:chatId/members/:memberUserId",
  requireAuth,
  requireMessagingAccess,
  async (req, res) => {
    const parsedParams = groupMemberParamSchema.safeParse(req.params);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }

    try {
      const result = await chatService.removeGroupMember({
        chatId: parsedParams.data.chatId,
        requesterUserId: req.authUserId!,
        memberUserId: parsedParams.data.memberUserId
      });
      emitInboxUpdate(result.notifyUserIds);
      emitChatMessage(
        parsedParams.data.chatId,
        { ...result.systemMessage, chatType: "group" },
        result.remainingParticipantIds
      );
      res.json({ ok: true });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "forbidden_chat_access":
            res.status(403).json({ error: error.message });
            return;
          case "group_member_remove_not_allowed":
          case "group_member_self_remove_not_allowed":
            res.status(403).json({ error: error.message });
            return;
          case "group_not_found":
            res.status(404).json({ error: error.message });
            return;
          case "group_member_not_found":
            res.status(400).json({ error: error.message });
            return;
        }
      }

      logError("group remove member failed", error);
      res.status(500).json({ error: "failed_to_remove_group_member" });
    }
  }
);

chatRouter.post("/:chatId/leave", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }

  try {
    const result = await chatService.leaveGroup({
      chatId: parsedParams.data.chatId,
      requesterUserId: req.authUserId!
    });
    emitInboxUpdate([req.authUserId!, ...result.participantIds]);
    emitChatMessage(
      parsedParams.data.chatId,
      { ...result.systemMessage, chatType: "group" },
      result.participantIds
    );
    res.json({ ok: true });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
        case "group_owner_leave_not_allowed":
          res.status(409).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }

    logError("group leave failed", error);
    res.status(500).json({ error: "failed_to_leave_group" });
  }
});

chatRouter.delete("/:chatId", requireAuth, requireMessagingAccess, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }

  try {
    const result = await chatService.closeGroup({
      chatId: parsedParams.data.chatId,
      requesterUserId: req.authUserId!
    });
    emitInboxUpdate(result.participantIds);
    res.json({ ok: true });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "forbidden_chat_access":
        case "group_close_not_allowed":
          res.status(403).json({ error: error.message });
          return;
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
      }
    }

    logError("group close failed", error);
    res.status(500).json({ error: "failed_to_close_group" });
  }
});

chatRouter.get("/:chatId", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }

  try {
    const detail = await chatService.getChatDetail(parsedParams.data.chatId, req.authUserId!);
    if (!detail) {
      res.status(404).json({ error: "chat_not_found" });
      return;
    }
    res.json({
      data: {
        ...detail,
        avatarUrl:
          detail.chatType === "group"
            ? await resolveGroupAvatarUrl(detail.avatarUrl)
            : detail.avatarUrl
      }
    });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: error.message });
      return;
    }

    logError("chat detail failed", error);
    res.status(500).json({ error: "failed_to_get_chat_detail" });
  }
});

chatRouter.get("/:chatId/pins", requireAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }

  try {
    const data = await chatService.listPinnedMessages(parsedParams.data.chatId, req.authUserId!);
    res.json({ data });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: error.message });
      return;
    }
    logError("chat pin list failed", error);
    res.status(500).json({ error: "failed_to_get_pinned_messages" });
  }
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
    if (error instanceof Error && error.message === "chat_send_restricted") {
      res.status(403).json({ error: "chat_send_restricted" });
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

    const audience = await chatService.getTypingAudience(parsed.data.chatId, userId);
    const message = await chatService.sendMessage({
      chatId: parsed.data.chatId,
      senderId: userId,
      text: parsed.data.text,
      attachments
    });
    const socketMessage = { ...message, chatType: audience.chatType };

    const participants = await chatService.getChatParticipantIds(parsed.data.chatId);
    emitChatMessage(parsed.data.chatId, socketMessage, participants);
    const recipientIds = participants.filter((participantId) => participantId !== userId);
    if (recipientIds.length > 0) {
      chatService
        .getUserDisplayName(userId)
        .then(async (senderDisplayName) => {
          const deliveredRecipientIds = await sendChatMessagePush({
            message: socketMessage,
            senderDisplayName,
            recipientUserIds: recipientIds
          });
          for (const recipientId of deliveredRecipientIds) {
            const deliveredIds = await chatService.markSpecificMessagesDelivered(
              parsed.data.chatId,
              recipientId,
              [message.id]
            );
            if (deliveredIds.length === 0) continue;
            emitChatStatus({
              chatId: parsed.data.chatId,
              chatType: audience.chatType,
              status: "delivered",
              messageIds: deliveredIds,
              userIds: [userId]
            });
          }
        })
        .catch((error: unknown) => {
          logError("chat push after http send failed", error);
        });
    }

    let activeRecipientId: string | null = null;
    for (const peerId of recipientIds) {
      const peerSockets = await getSocketsInUserRoom(peerId);
      if (peerSockets.length === 0) continue;
      activeRecipientId = peerId;
      break;
    }
    if (activeRecipientId) {
      const deliveredIds = await chatService.markMessagesDelivered(
        parsed.data.chatId,
        activeRecipientId
      );
      if (deliveredIds.length > 0) {
        const activeUserIds = await getActiveChatUserIds(parsed.data.chatId);
        emitChatStatus({
          chatId: parsed.data.chatId,
          chatType: audience.chatType,
          status: "delivered",
          messageIds: deliveredIds,
          userIds: activeUserIds.includes(userId) ? [userId] : []
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
    if (error instanceof Error && error.message === "chat_send_restricted") {
      res.status(403).json({ error: "chat_send_restricted" });
      return;
    }
    if (error instanceof Error && error.message === "chat_rate_limited") {
      res.status(429).json({ error: "chat_rate_limited" });
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
    const audience = await chatService.getTypingAudience(message.chatId, userId);
    const participants = await chatService.getChatParticipantIds(message.chatId);
    emitChatMessage(message.chatId, { ...message, chatType: audience.chatType }, participants);
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

chatRouter.post("/messages/:messageId/reactions", requireAuth, async (req, res) => {
  const parsedParams = messageIdParamSchema.safeParse(req.params);
  const parsedBody = messageReactionSchema.safeParse(req.body);
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
    const message = await chatService.addReaction(
      parsedParams.data.messageId,
      userId,
      parsedBody.data.emoji
    );
    const audience = await chatService.getTypingAudience(message.chatId, userId);
    const participants = await chatService.getChatParticipantIds(message.chatId);
    emitChatMessage(message.chatId, { ...message, chatType: audience.chatType }, participants);
    res.json({ data: message });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "message_not_found":
          res.status(404).json({ error: error.message });
          return;
        case "reaction_emoji_required":
          res.status(400).json({ error: error.message });
          return;
        case "message_reaction_not_allowed":
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
      }
    }

    logError("chat reaction add failed", error);
    res.status(500).json({ error: "failed_to_add_reaction" });
  }
});

chatRouter.delete("/messages/:messageId/reactions", requireAuth, async (req, res) => {
  const parsedParams = messageIdParamSchema.safeParse(req.params);
  const parsedBody = messageReactionSchema.safeParse(req.body);
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
    const message = await chatService.removeReaction(
      parsedParams.data.messageId,
      userId,
      parsedBody.data.emoji
    );
    const audience = await chatService.getTypingAudience(message.chatId, userId);
    const participants = await chatService.getChatParticipantIds(message.chatId);
    emitChatMessage(message.chatId, { ...message, chatType: audience.chatType }, participants);
    res.json({ data: message });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "message_not_found":
          res.status(404).json({ error: error.message });
          return;
        case "reaction_emoji_required":
          res.status(400).json({ error: error.message });
          return;
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
      }
    }

    logError("chat reaction remove failed", error);
    res.status(500).json({ error: "failed_to_remove_reaction" });
  }
});

chatRouter.post("/messages/:messageId/pin", requireAuth, async (req, res) => {
  const parsedParams = messageIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }

  const userId = req.authUserId!;
  try {
    const pinned = await chatService.pinMessage(parsedParams.data.messageId, userId);
    const participants = await chatService.getChatParticipantIds(pinned.chatId);
    const payload = {
      chatId: pinned.chatId,
      pinnedMessages: await chatService.listPinnedMessages(pinned.chatId, userId)
    };
    emitUserEvent(participants, "chat:pin:update", payload);
    res.json({ data: pinned });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "message_not_found":
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
        case "group_pin_not_allowed":
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
      }
    }

    logError("chat pin failed", error);
    res.status(500).json({ error: "failed_to_pin_message" });
  }
});

chatRouter.delete("/messages/:messageId/pin", requireAuth, async (req, res) => {
  const parsedParams = messageIdParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }

  const userId = req.authUserId!;
  try {
    const message = await chatService.getMessageById(parsedParams.data.messageId);
    if (!message) {
      res.status(404).json({ error: "message_not_found" });
      return;
    }
    await chatService.unpinMessage(parsedParams.data.messageId, userId);
    const participants = await chatService.getChatParticipantIds(message.chatId);
    const payload = {
      chatId: message.chatId,
      pinnedMessages: await chatService.listPinnedMessages(message.chatId, userId)
    };
    emitUserEvent(participants, "chat:pin:update", payload);
    res.json({ data: { ok: true } });
  } catch (error) {
    if (error instanceof Error) {
      switch (error.message) {
        case "message_not_found":
        case "group_not_found":
          res.status(404).json({ error: error.message });
          return;
        case "group_pin_not_allowed":
        case "forbidden_chat_access":
          res.status(403).json({ error: error.message });
          return;
      }
    }

    logError("chat unpin failed", error);
    res.status(500).json({ error: "failed_to_unpin_message" });
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
    const audience = await chatService.getTypingAudience(message.chatId, userId);
    const participants = await chatService.getChatParticipantIds(message.chatId);
    emitChatMessage(message.chatId, { ...message, chatType: audience.chatType }, participants);
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
