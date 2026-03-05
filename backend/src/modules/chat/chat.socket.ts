import type { Server, Socket } from "socket.io";
import { z } from "zod";
import { chatService } from "./chat.service.js";
import { logInfo } from "../../lib/logger.js";
import { verifyAccessToken } from "../../lib/jwt.js";

const joinChatSchema = z.object({
  chatId: z.string().min(1)
});

const sendMessageSchema = z.object({
  chatId: z.string().min(1),
  text: z.string().min(1).max(4000)
});

const seenChatSchema = z.object({
  chatId: z.string().min(1)
});

function userRoom(userId: string): string {
  return `user:${userId}`;
}

function emitInboxUpdate(io: Server, userIds: string[]): void {
  const uniqueUserIds = Array.from(new Set(userIds));
  for (const userId of uniqueUserIds) {
    io.to(userRoom(userId)).emit("chat:inbox:update");
  }
}

export function registerChatSocket(io: Server): void {
  io.use((socket, next) => {
    const authToken = socket.handshake.auth?.token;
    const headerToken = socket.handshake.headers.authorization;
    let token: string | null = null;

    if (typeof authToken === "string" && authToken.trim().length > 0) {
      token = authToken.trim();
    } else if (typeof headerToken === "string" && headerToken.startsWith("Bearer ")) {
      token = headerToken.replace("Bearer ", "").trim();
    }

    if (!token) {
      next(new Error("unauthorized"));
      return;
    }

    try {
      const claims = verifyAccessToken(token);
      socket.data.userId = claims.sub;
      next();
    } catch {
      next(new Error("invalid_token"));
    }
  });

  io.on("connection", async (socket: Socket) => {
    const userId = socket.data.userId as string;
    socket.join(userRoom(userId));
    logInfo("socket connected", { socketId: socket.id, userId, transport: socket.conn.transport.name });

    // Kullanıcı online olduğunda, ona gönderilen tüm "sent" mesajları "delivered" yap
    try {
      const userChats = await chatService.getUserChats(userId);
      for (const chatId of userChats) {
        const deliveredIds = await chatService.markMessagesDelivered(chatId, userId);
        if (deliveredIds.length > 0) {
          io.to(chatId).emit("chat:status", {
            chatId,
            status: "delivered",
            messageIds: deliveredIds
          });
        }
      }
    } catch (error) {
      logInfo("auto-deliver on connect failed", { userId, error });
    }

    socket.on("chat:join", async (payload) => {
      const parsed = joinChatSchema.safeParse(payload);
      if (!parsed.success) {
        logInfo("chat:join validation failed", { socketId: socket.id, payload });
        socket.emit("error:validation", parsed.error.flatten());
        return;
      }

      try {
        const hasAccess = await chatService.ensureChatAccess(parsed.data.chatId, userId);
        if (!hasAccess) {
          socket.emit("error:forbidden", { message: "forbidden_chat_access" });
          return;
        }

        socket.join(parsed.data.chatId);
        const history = await chatService.getMessages(parsed.data.chatId);
        logInfo("chat:join ok", { socketId: socket.id, chatId: parsed.data.chatId, historyCount: history.length });
        socket.emit("chat:history", history);

        const deliveredIds = await chatService.markMessagesDelivered(parsed.data.chatId, userId);
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
        const hasAccess = await chatService.ensureChatAccess(parsed.data.chatId, userId);
        if (!hasAccess) {
          socket.emit("error:forbidden", { message: "forbidden_chat_access" });
          return;
        }

        const message = await chatService.sendMessage({
          chatId: parsed.data.chatId,
          senderId: userId,
          text: parsed.data.text
        });
        logInfo("chat:send ok", {
          socketId: socket.id,
          chatId: parsed.data.chatId,
          senderId: userId,
          messageId: message.id
        });
        io.to(parsed.data.chatId).emit("chat:message", message);

        const participants = await chatService.getChatParticipantIds(parsed.data.chatId);
        const peerId = participants.find((participantId) => participantId !== userId) ?? null;
        if (peerId) {
          // Sadece karşı kullanıcı online ise (user room'a bağlıysa) mesajı delivered yap
          const peerSockets = await io.in(userRoom(peerId)).fetchSockets();
          if (peerSockets.length > 0) {
            const deliveredIds = await chatService.markMessagesDelivered(parsed.data.chatId, peerId);
            if (deliveredIds.length > 0) {
              io.to(parsed.data.chatId).emit("chat:status", {
                chatId: parsed.data.chatId,
                status: "delivered",
                messageIds: deliveredIds
              });
            }
          }
        }

        emitInboxUpdate(io, participants.length > 0 ? participants : [userId]);
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
        const hasAccess = await chatService.ensureChatAccess(parsed.data.chatId, userId);
        if (!hasAccess) {
          socket.emit("error:forbidden", { message: "forbidden_chat_access" });
          return;
        }

        const readIds = await chatService.markMessagesRead(parsed.data.chatId, userId);
        if (readIds.length > 0) {
          io.to(parsed.data.chatId).emit("chat:status", {
            chatId: parsed.data.chatId,
            status: "read",
            messageIds: readIds
          });
          const participants = await chatService.getChatParticipantIds(parsed.data.chatId);
          emitInboxUpdate(io, participants.length > 0 ? participants : [userId]);
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
