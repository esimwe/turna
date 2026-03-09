import type { Server, Socket } from "socket.io";
import { z } from "zod";
import { logError, logInfo } from "../../lib/logger.js";
import { verifyAccessToken } from "../../lib/jwt.js";
import { sendChatMessagePush } from "../../lib/push.js";
import {
  buildUserPresencePayload,
  emitChatMessage,
  emitPresenceUpdate,
  emitChatStatus,
  emitInboxUpdate,
  getSocketsInUserRoom,
  registerUserSocket,
  unregisterUserSocket,
  userRoom
} from "./chat.realtime.js";
import { chatService } from "./chat.service.js";

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

const typingChatSchema = z.object({
  chatId: z.string().min(1),
  isTyping: z.boolean()
});

async function notifyPresenceAudience(userId: string): Promise<void> {
  const audienceUserIds = await chatService.getPresenceAudienceUserIds(userId);
  if (audienceUserIds.length === 0) return;

  const lastSeenAt = await chatService.getUserLastSeenAt(userId);
  emitPresenceUpdate(audienceUserIds, buildUserPresencePayload(userId, lastSeenAt));
}

async function sendDirectPeerPresenceSnapshot(socket: Socket, chatId: string, userId: string): Promise<void> {
  const peerUserId = chatService.getDirectPeerId(chatId, userId);
  if (!peerUserId) return;

  const lastSeenAt = await chatService.getUserLastSeenAt(peerUserId);
  socket.emit("user:presence", buildUserPresencePayload(peerUserId, lastSeenAt));
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
    const becameOnline = registerUserSocket(userId, socket.id);
    logInfo("socket connected", { socketId: socket.id, userId, transport: socket.conn.transport.name });

    if (becameOnline) {
      try {
        await notifyPresenceAudience(userId);
      } catch (error) {
        logError("presence announce on connect failed", error);
      }
    }

    // Kullanıcı online olduğunda, ona gönderilen tüm "sent" mesajları "delivered" yap
    try {
      const userChats = await chatService.getUserChats(userId);
      for (const chatId of userChats) {
        const deliveredIds = await chatService.markMessagesDelivered(chatId, userId);
        if (deliveredIds.length > 0) {
          const participants = await chatService.getChatParticipantIds(chatId);
          const senderId = participants.find(p => p !== userId);
          if (senderId) {
            emitChatStatus({
              chatId,
              status: "delivered",
              messageIds: deliveredIds,
              userIds: [senderId]
            });
          }
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
        const historyPage = await chatService.getMessagePage(parsed.data.chatId, {
          limit: 30,
          userId
        });
        logInfo("chat:join ok", {
          socketId: socket.id,
          chatId: parsed.data.chatId,
          historyCount: historyPage.items.length
        });
        socket.emit("chat:history", historyPage.items);
        await sendDirectPeerPresenceSnapshot(socket, parsed.data.chatId, userId);

        const deliveredIds = await chatService.markMessagesDelivered(parsed.data.chatId, userId);
        if (deliveredIds.length > 0) {
          const participants = await chatService.getChatParticipantIds(parsed.data.chatId);
          const senderIds = participants.filter((participantId) => participantId !== userId);
          emitChatStatus({
            chatId: parsed.data.chatId,
            status: "delivered",
            messageIds: deliveredIds,
            userIds: senderIds
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
        await chatService.ensureCanInteract(parsed.data.chatId, userId);

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
        const participants = await chatService.getChatParticipantIds(parsed.data.chatId);
        emitChatMessage(parsed.data.chatId, message, participants);
        const recipientIds = participants.filter(
          (participantId) => participantId !== userId
        );
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
              logError("chat push after socket send failed", error);
            });
        }

        const peerId = recipientIds[0] ?? null;
        if (peerId) {
          const peerSockets = await getSocketsInUserRoom(peerId);
          if (peerSockets.length > 0) {
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
        }

        emitInboxUpdate(participants.length > 0 ? participants : [userId]);
      } catch (error) {
        if (error instanceof Error && error.message === "chat_blocked") {
          socket.emit("error:forbidden", { message: "chat_blocked" });
          return;
        }
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
          const participants = await chatService.getChatParticipantIds(parsed.data.chatId);
          const senderId = participants.find((p) => p !== userId);
          emitChatStatus({
            chatId: parsed.data.chatId,
            status: "read",
            messageIds: readIds,
            userIds: senderId ? [senderId] : []
          });

          emitInboxUpdate(participants.length > 0 ? participants : [userId]);
        }
      } catch (error) {
        socket.emit("error:internal", { message: "failed_to_mark_seen" });
        logInfo("chat:seen failed", { socketId: socket.id, chatId: parsed.data.chatId, error });
      }
    });

    socket.on("chat:typing", async (payload) => {
      const parsed = typingChatSchema.safeParse(payload);
      if (!parsed.success) {
        logInfo("chat:typing validation failed", { socketId: socket.id, payload });
        socket.emit("error:validation", parsed.error.flatten());
        return;
      }

      try {
        const hasAccess = await chatService.ensureChatAccess(parsed.data.chatId, userId);
        if (!hasAccess) {
          socket.emit("error:forbidden", { message: "forbidden_chat_access" });
          return;
        }
        await chatService.ensureCanInteract(parsed.data.chatId, userId);

        socket.to(parsed.data.chatId).emit("chat:typing", {
          chatId: parsed.data.chatId,
          userId,
          isTyping: parsed.data.isTyping
        });
      } catch (error) {
        if (error instanceof Error && error.message === "chat_blocked") {
          socket.emit("error:forbidden", { message: "chat_blocked" });
          return;
        }
        socket.emit("error:internal", { message: "failed_to_publish_typing" });
        logInfo("chat:typing failed", { socketId: socket.id, chatId: parsed.data.chatId, error });
      }
    });

    socket.on("disconnect", async (reason) => {
      logInfo("socket disconnected", { socketId: socket.id, reason });
      const becameOffline = unregisterUserSocket(userId, socket.id);
      if (!becameOffline) return;

      try {
        const lastSeenAt = await chatService.updateUserLastSeen(userId);
        const audienceUserIds = await chatService.getPresenceAudienceUserIds(userId);
        if (audienceUserIds.length === 0) return;

        emitPresenceUpdate(audienceUserIds, buildUserPresencePayload(userId, lastSeenAt));
      } catch (error) {
        logError("presence announce on disconnect failed", error);
      }
    });
  });
}
