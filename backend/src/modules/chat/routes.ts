import { Router } from "express";
import { z } from "zod";
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

chatRouter.post("/messages", async (req, res) => {
  const parsed = sendMessageSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const message = await chatService.sendMessage(parsed.data);
  res.status(201).json({ data: message });
});
