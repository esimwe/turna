import type { Server, Socket } from "socket.io";
import { z } from "zod";
import { chatService } from "./chat.service.js";
import type { SendMessagePayload } from "./chat.types.js";
import { logInfo } from "../../lib/logger.js";

const joinChatSchema = z.object({
  chatId: z.string().min(1),
  userId: z.string().min(1)
});

const sendMessageSchema = z.object({
  chatId: z.string().min(1),
  senderId: z.string().min(1),
  text: z.string().min(1).max(4000)
});

const seenChatSchema = z.object({
  chatId: z.string().min(1),
  userId: z.string().min(1)
});

export function registerChatSocket(io: Server): void {
  io.on("connection", (socket: Socket) => {
    logInfo("socket connected", { socketId: socket.id, transport: socket.conn.transport.name });

    socket.on("chat:join", async (payload) => {
      const parsed = joinChatSchema.safeParse(payload);
      if (!parsed.success) {
        logInfo("chat:join validation failed", { socketId: socket.id, payload });
        socket.emit("error:validation", parsed.error.flatten());
        return;
      }

      try {
        socket.join(parsed.data.chatId);
        const history = await chatService.getMessages(parsed.data.chatId);
        logInfo("chat:join ok", { socketId: socket.id, chatId: parsed.data.chatId, historyCount: history.length });
        socket.emit("chat:history", history);

        const deliveredIds = await chatService.markMessagesDelivered(parsed.data.chatId, parsed.data.userId);
        if (deliveredIds.length > 0) {
          io.to(parsed.data.chatId).emit("chat:status", {
            chatId: parsed.data.chatId,
            status: "delivered",
            messageIds: deliveredIds
          });
        }
      } catch (error) {
        socket.emit("error:internal", { message: "failed_to_join_chat" });
        logInfo("chat:join failed", { socketId: socket.id, chatId: parsed.data.chatId, error });
      }
    });

    socket.on("chat:send", async (payload) => {
      const parsed = sendMessageSchema.safeParse(payload);
      if (!parsed.success) {
        logInfo("chat:send validation failed", { socketId: socket.id, payload });
        socket.emit("error:validation", parsed.error.flatten());
        return;
      }

      try {
        const message = await chatService.sendMessage(parsed.data as SendMessagePayload);
        logInfo("chat:send ok", {
          socketId: socket.id,
          chatId: parsed.data.chatId,
          senderId: parsed.data.senderId,
          messageId: message.id
        });
        io.to(parsed.data.chatId).emit("chat:message", message);
      } catch (error) {
        socket.emit("error:internal", { message: "failed_to_send_message" });
        logInfo("chat:send failed", { socketId: socket.id, chatId: parsed.data.chatId, error });
      }
    });

    socket.on("chat:seen", async (payload) => {
      const parsed = seenChatSchema.safeParse(payload);
      if (!parsed.success) {
        logInfo("chat:seen validation failed", { socketId: socket.id, payload });
        socket.emit("error:validation", parsed.error.flatten());
        return;
      }

      try {
        const readIds = await chatService.markMessagesRead(parsed.data.chatId, parsed.data.userId);
        if (readIds.length > 0) {
          io.to(parsed.data.chatId).emit("chat:status", {
            chatId: parsed.data.chatId,
            status: "read",
            messageIds: readIds
          });
        }
      } catch (error) {
        socket.emit("error:internal", { message: "failed_to_mark_seen" });
        logInfo("chat:seen failed", { socketId: socket.id, chatId: parsed.data.chatId, error });
      }
    });

    socket.on("disconnect", (reason) => {
      logInfo("socket disconnected", { socketId: socket.id, reason });
    });
  });
}
