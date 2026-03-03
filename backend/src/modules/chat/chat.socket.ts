import type { Server, Socket } from "socket.io";
import { z } from "zod";
import { chatService } from "./chat.service.js";
import type { SendMessagePayload } from "./chat.types.js";
import { logInfo } from "../../lib/logger.js";

const joinChatSchema = z.object({
  chatId: z.string().min(1)
});

const sendMessageSchema = z.object({
  chatId: z.string().min(1),
  senderId: z.string().min(1),
  text: z.string().min(1).max(4000)
});

export function registerChatSocket(io: Server): void {
  io.on("connection", (socket: Socket) => {
    logInfo("socket connected", { socketId: socket.id });

    socket.on("chat:join", async (payload) => {
      const parsed = joinChatSchema.safeParse(payload);
      if (!parsed.success) {
        socket.emit("error:validation", parsed.error.flatten());
        return;
      }

      try {
        socket.join(parsed.data.chatId);
        const history = await chatService.getMessages(parsed.data.chatId);
        socket.emit("chat:history", history);
      } catch (error) {
        socket.emit("error:internal", { message: "failed_to_join_chat" });
        logInfo("chat:join failed", { error });
      }
    });

    socket.on("chat:send", async (payload) => {
      const parsed = sendMessageSchema.safeParse(payload);
      if (!parsed.success) {
        socket.emit("error:validation", parsed.error.flatten());
        return;
      }

      try {
        const message = await chatService.sendMessage(parsed.data as SendMessagePayload);
        io.to(parsed.data.chatId).emit("chat:message", message);
      } catch (error) {
        socket.emit("error:internal", { message: "failed_to_send_message" });
        logInfo("chat:send failed", { error });
      }
    });

    socket.on("disconnect", () => {
      logInfo("socket disconnected", { socketId: socket.id });
    });
  });
}
