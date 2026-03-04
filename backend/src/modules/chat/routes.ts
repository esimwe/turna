import { Router } from "express";
import { z } from "zod";
<<<<<<< HEAD
=======
import { requireAuth } from "../../middleware/auth.js";
>>>>>>> 1a42523 (chore: connect local repo)
import { chatService } from "./chat.service.js";

export const chatRouter = Router();

const sendMessageSchema = z.object({
  chatId: z.string().min(1),
  senderId: z.string().min(1),
  text: z.string().min(1).max(4000)
});

chatRouter.get("/:chatId/messages", async (req, res) => {
  const chatId = req.params.chatId;
  const messages = await chatService.getMessages(chatId);
  res.json({ data: messages });
});

<<<<<<< HEAD
=======
chatRouter.get("/", requireAuth, async (req, res) => {
  const userId = req.authUserId!;
  const chats = await chatService.getChatSummaries(userId);
  res.json({ data: chats });
});

chatRouter.get("/directory/list", requireAuth, async (req, res) => {
  const userId = req.authUserId!;
  const users = await chatService.getUserDirectory(userId);
  res.json({ data: users });
});

>>>>>>> 1a42523 (chore: connect local repo)
chatRouter.post("/messages", async (req, res) => {
  const parsed = sendMessageSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const message = await chatService.sendMessage(parsed.data);
  res.status(201).json({ data: message });
});
