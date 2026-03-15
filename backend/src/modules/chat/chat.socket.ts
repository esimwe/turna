import type { Server, Socket } from "socket.io";
import { z } from "zod";
import { findActiveAuthSession } from "../../lib/auth-sessions.js";
import { logError, logInfo } from "../../lib/logger.js";
import { verifyAccessToken } from "../../lib/jwt.js";
import { sendChatMessagePush } from "../../lib/push.js";
import {
  assertUserCanAccessAppById,
  assertUserCanSendMessagesById
} from "../../lib/user-access.js";
import {
  buildUserPresencePayload,
  chatRoom,
  emitChatMessage,
  emitPresenceUpdate,
  emitChatStatus,
  emitInboxUpdate,
  getActiveChatUserIds,
  registerUserSocket,
  sessionRoom,
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
  emitPresenceUpdate(
    audienceUserIds,
    await buildUserPresencePayload(userId, lastSeenAt)
  );
}

async function sendDirectPeerPresenceSnapshot(socket: Socket, chatId: string, userId: string): Promise<void> {
  const peerUserId = chatService.getDirectPeerId(chatId, userId);
  if (!peerUserId) return;

  const lastSeenAt = await chatService.getUserLastSeenAt(peerUserId);
  socket.emit(
    "user:presence",
    await buildUserPresencePayload(peerUserId, lastSeenAt)
  );
}

export function registerChatSocket(io: Server): void {
  io.use(async (socket, next) => {
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
      await assertUserCanAccessAppById(claims.sub);
      if (claims.sessionId) {
        const session = await findActiveAuthSession(claims.sessionId);
        if (!session || session.userId !== claims.sub) {
          next(new Error("session_revoked"));
          return;
        }
      }
      socket.data.userId = claims.sub;
      socket.data.sessionId = claims.sessionId;
      next();
    } catch (error) {
      next(new Error(error instanceof Error ? error.message : "invalid_token"));
    }
  });

  io.on("connection", async (socket: Socket) => {
    const userId = socket.data.userId as string;
    const sessionId =
      typeof socket.data.sessionId === "string" ? (socket.data.sessionId as string) : null;
    socket.join(userRoom(userId));
    if (sessionId) {
      socket.join(sessionRoom(sessionId));
    }
    const becameOnline = await registerUserSocket(userId, sessionId);
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
          const senderIds = participants.filter((participantId) => participantId !== userId);
          if (senderIds.length > 0) {
            emitChatStatus({
              chatId,
              status: "delivered",
              messageIds: deliveredIds,
              userIds: senderIds
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
        await assertUserCanAccessAppById(userId);
        const hasAccess = await chatService.ensureChatAccess(parsed.data.chatId, userId);
        if (!hasAccess) {
          socket.emit("error:forbidden", { message: "forbidden_chat_access" });
          return;
        }

        socket.join(chatRoom(parsed.data.chatId));
        const historyPage = await chatService.getMessagePage(parsed.data.chatId, {
          limit: 30,
          userId
        });
        const audience = await chatService.getTypingAudience(parsed.data.chatId, userId);
        logInfo("chat:join ok", {
          socketId: socket.id,
          chatId: parsed.data.chatId,
          historyCount: historyPage.items.length
        });
        socket.emit(
          "chat:history",
          historyPage.items.map((message) => ({ ...message, chatType: audience.chatType }))
        );
        await sendDirectPeerPresenceSnapshot(socket, parsed.data.chatId, userId);

        const deliveredIds = await chatService.markMessagesDelivered(parsed.data.chatId, userId);
        if (deliveredIds.length > 0) {
          emitChatStatus({
            chatId: parsed.data.chatId,
            chatType: audience.chatType,
            status: "delivered",
            messageIds: deliveredIds,
            userIds: []
          });
        }
      } catch (error) {
        if (
          error instanceof Error &&
          (error.message === "account_suspended" || error.message === "account_banned")
        ) {
          socket.emit("error:forbidden", { message: error.message });
          return;
        }
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
        await assertUserCanSendMessagesById(userId);
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
        const audience = await chatService.getTypingAudience(parsed.data.chatId, userId);
        logInfo("chat:send ok", {
          socketId: socket.id,
          chatId: parsed.data.chatId,
          senderId: userId,
          messageId: message.id
        });
        const socketMessage = { ...message, chatType: audience.chatType };
        emitChatMessage(parsed.data.chatId, socketMessage, audience.participantIds);
        const recipientIds = audience.recipientUserIds;
        if (recipientIds.length > 0) {
          chatService
            .getUserDisplayName(userId)
            .then((senderDisplayName) =>
              sendChatMessagePush({
                message: socketMessage,
                senderDisplayName,
                recipientUserIds: recipientIds
              })
            )
            .catch((error: unknown) => {
              logError("chat push after socket send failed", error);
            });
        }

        let activeRecipientId: string | null = null;
        const activeUserIds = await getActiveChatUserIds(parsed.data.chatId);
        for (const recipientId of recipientIds) {
          if (activeUserIds.includes(recipientId)) {
            activeRecipientId = recipientId;
            break;
          }
        }
        if (activeRecipientId) {
          const deliveredIds = await chatService.markMessagesDelivered(
            parsed.data.chatId,
            activeRecipientId
          );
          if (deliveredIds.length > 0) {
            emitChatStatus({
              chatId: parsed.data.chatId,
              chatType: audience.chatType,
              status: "delivered",
              messageIds: deliveredIds,
              userIds: []
            });
          }
        }

        emitInboxUpdate(
          audience.participantIds.length > 0 ? audience.participantIds : [userId]
        );
      } catch (error) {
        if (error instanceof Error) {
          if (error.message === "chat_blocked") {
            socket.emit("error:forbidden", { message: "chat_blocked" });
            return;
          }
          if (
            error.message === "account_suspended" ||
            error.message === "account_banned" ||
            error.message === "message_sending_restricted"
          ) {
            socket.emit("error:forbidden", { message: error.message });
            return;
          }
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
        await assertUserCanAccessAppById(userId);
        const hasAccess = await chatService.ensureChatAccess(parsed.data.chatId, userId);
        if (!hasAccess) {
          socket.emit("error:forbidden", { message: "forbidden_chat_access" });
          return;
        }

        const readIds = await chatService.markMessagesRead(parsed.data.chatId, userId);
        if (readIds.length > 0) {
          const audience = await chatService.getTypingAudience(parsed.data.chatId, userId);
          emitChatStatus({
            chatId: parsed.data.chatId,
            chatType: audience.chatType,
            status: "read",
            messageIds: readIds,
            userIds: []
          });

          const participants = await chatService.getChatParticipantIds(parsed.data.chatId);
          emitInboxUpdate(participants.length > 0 ? participants : [userId]);
        }
      } catch (error) {
        if (
          error instanceof Error &&
          (error.message === "account_suspended" || error.message === "account_banned")
        ) {
          socket.emit("error:forbidden", { message: error.message });
          return;
        }
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
        await assertUserCanSendMessagesById(userId);
        const hasAccess = await chatService.ensureChatAccess(parsed.data.chatId, userId);
        if (!hasAccess) {
          socket.emit("error:forbidden", { message: "forbidden_chat_access" });
          return;
        }
        await chatService.ensureCanInteract(parsed.data.chatId, userId);
        const audience = await chatService.getTypingAudience(parsed.data.chatId, userId);
        socket.to(chatRoom(parsed.data.chatId)).emit("chat:typing", {
          chatId: parsed.data.chatId,
          chatType: audience.chatType,
          userId,
          isTyping: parsed.data.isTyping,
          displayName: await chatService.getUserDisplayName(userId)
        });
      } catch (error) {
        if (error instanceof Error) {
          if (error.message === "chat_blocked") {
            socket.emit("error:forbidden", { message: "chat_blocked" });
            return;
          }
          if (
            error.message === "account_suspended" ||
            error.message === "account_banned" ||
            error.message === "message_sending_restricted"
          ) {
            socket.emit("error:forbidden", { message: error.message });
            return;
          }
        }
        socket.emit("error:internal", { message: "failed_to_publish_typing" });
        logInfo("chat:typing failed", { socketId: socket.id, chatId: parsed.data.chatId, error });
      }
    });

    socket.on("disconnect", async (reason) => {
      logInfo("socket disconnected", { socketId: socket.id, reason });
      const becameOffline = await unregisterUserSocket(userId, sessionId);
      if (!becameOffline) return;

      try {
        const lastSeenAt = await chatService.updateUserLastSeen(userId);
        const audienceUserIds = await chatService.getPresenceAudienceUserIds(userId);
        if (audienceUserIds.length === 0) return;

        emitPresenceUpdate(
          audienceUserIds,
          await buildUserPresencePayload(userId, lastSeenAt)
        );
      } catch (error) {
        logError("presence announce on disconnect failed", error);
      }
    });
  });
}
