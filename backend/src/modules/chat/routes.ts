import { Router } from "express";
import { z } from "zod";
import { logError } from "../../lib/logger.js";
import { requireAuth } from "../../middleware/auth.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";
import { chatService } from "./chat.service.js";

export const chatRouter = Router();

const sendMessageSchema = z.object({
  chatId: z.string().min(1),
  text: z.string().min(1).max(4000)
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

  const messages = await chatService.getMessages(chatId);
  res.json({ data: messages });
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

chatRouter.post("/messages", requireAuth, async (req, res) => {
  const parsed = sendMessageSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const userId = req.authUserId!;
  try {
    const message = await chatService.sendMessage({
      chatId: parsed.data.chatId,
      senderId: userId,
      text: parsed.data.text
    });
    res.status(201).json({ data: message });
  } catch (error) {
    if (error instanceof Error && error.message === "forbidden_chat_access") {
      res.status(403).json({ error: "forbidden_chat_access" });
      return;
    }

    logError("chat http send failed", error);
    res.status(500).json({ error: "failed_to_send_message" });
  }
});
