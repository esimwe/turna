import { logError, logInfo } from "../../lib/logger.js";
import { sendChatMessagePush } from "../../lib/push.js";
import { emitChatMessage, emitChatStatus } from "./chat.realtime.js";
import { chatService } from "./chat.service.js";

const FLUSH_INTERVAL_MS = 15 * 1000;
const STALE_PROCESSING_MS = 5 * 60 * 1000;
let scheduledDispatcherTimer: NodeJS.Timeout | null = null;
let flushInFlight = false;

async function flushDueScheduledMessages(): Promise<void> {
  if (flushInFlight) return;
  flushInFlight = true;

  try {
    await chatService.recoverStuckScheduledMessages(
      new Date(Date.now() - STALE_PROCESSING_MS)
    );

    const claimedRows = await chatService.claimDueScheduledMessages(20);
    if (claimedRows.length === 0) {
      return;
    }

    for (const scheduled of claimedRows) {
      try {
        const audience = await chatService.getTypingAudience(
          scheduled.chatId,
          scheduled.senderId
        );
        const message = await chatService.sendMessage({
          chatId: scheduled.chatId,
          senderId: scheduled.senderId,
          text: scheduled.text,
          systemPayload: {
            ...(scheduled.silent ? { silent: true } : {}),
            scheduledFor: scheduled.scheduledFor.toISOString(),
            scheduledMessageId: scheduled.id
          }
        });

        await chatService.markScheduledMessageSent(scheduled.id, message.id);

        const socketMessage = { ...message, chatType: audience.chatType };
        const participants = await chatService.getChatParticipantIds(
          scheduled.chatId
        );
        emitChatMessage(scheduled.chatId, socketMessage, participants);

        let recipientIds = participants.filter(
          (participantId) => participantId !== scheduled.senderId
        );
        let senderDisplayName = await chatService.getUserDisplayName(
          scheduled.senderId
        );
        let ignoreMute = false;

        const isSelfReminder =
          recipientIds.length === 0 &&
          participants.length === 1 &&
          participants[0] === scheduled.senderId;
        if (isSelfReminder) {
          recipientIds = [scheduled.senderId];
          senderDisplayName = "Hatırlatıcı";
          ignoreMute = true;
        }

        if (recipientIds.length > 0) {
          const deliveredRecipientIds = await sendChatMessagePush({
            message: socketMessage,
            senderDisplayName,
            recipientUserIds: recipientIds,
            silent: scheduled.silent,
            ignoreMute
          });
          for (const recipientId of deliveredRecipientIds) {
            if (recipientId === scheduled.senderId) continue;
            const deliveredIds = await chatService.markSpecificMessagesDelivered(
              scheduled.chatId,
              recipientId,
              [message.id]
            );
            if (deliveredIds.length === 0) continue;
            emitChatStatus({
              chatId: scheduled.chatId,
              chatType: audience.chatType,
              status: "delivered",
              messageIds: deliveredIds,
              userIds: [scheduled.senderId]
            });
          }
        }
      } catch (error) {
        logError("scheduled chat message dispatch failed", {
          scheduledMessageId: scheduled.id,
          error: error instanceof Error ? error.message : String(error)
        });
        await chatService.markScheduledMessageFailed(
          scheduled.id,
          error instanceof Error ? error.message : String(error)
        );
      }
    }
  } catch (error) {
    logError("scheduled chat dispatcher flush failed", error);
  } finally {
    flushInFlight = false;
  }
}

export function startScheduledMessageDispatcher(): void {
  if (scheduledDispatcherTimer != null) {
    return;
  }

  void flushDueScheduledMessages();
  scheduledDispatcherTimer = setInterval(() => {
    void flushDueScheduledMessages();
  }, FLUSH_INTERVAL_MS);

  logInfo("scheduled chat dispatcher started", {
    intervalMs: FLUSH_INTERVAL_MS
  });
}
