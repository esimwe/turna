import { ChatType, MessageStatus } from "@prisma/client";
import { prisma } from "../../lib/prisma.js";
import type { ChatMessage, SendMessagePayload } from "./chat.types.js";

function toChatMessage(row: {
  id: string;
  chatId: string;
  senderId: string;
  text: string;
  createdAt: Date;
  status: MessageStatus;
}): ChatMessage {
  return {
    id: row.id,
    chatId: row.chatId,
    senderId: row.senderId,
    text: row.text,
    createdAt: row.createdAt.toISOString(),
    status: row.status
  };
}

export class ChatService {
  async ensureUser(userId: string): Promise<void> {
    const existing = await prisma.user.findUnique({ where: { id: userId }, select: { id: true } });
    if (existing) return;

    await prisma.user.create({
      data: {
        id: userId,
        displayName: userId
      }
    });
  }

  async ensureDirectChat(chatId: string, senderId: string): Promise<void> {
    await this.ensureUser(senderId);

    await prisma.chat.upsert({
      where: { id: chatId },
      create: {
        id: chatId,
        type: ChatType.DIRECT,
        members: {
          create: [{ userId: senderId }]
        }
      },
      update: {
        members: {
          connectOrCreate: {
            where: { chatId_userId: { chatId, userId: senderId } },
            create: { userId: senderId }
          }
        }
      }
    });
  }

  async sendMessage(payload: SendMessagePayload): Promise<ChatMessage> {
    await this.ensureDirectChat(payload.chatId, payload.senderId);

    const message = await prisma.message.create({
      data: {
        chatId: payload.chatId,
        senderId: payload.senderId,
        text: payload.text,
        status: MessageStatus.sent
      }
    });

    return toChatMessage(message);
  }

  async getMessages(chatId: string): Promise<ChatMessage[]> {
    const rows = await prisma.message.findMany({
      where: { chatId },
      orderBy: { createdAt: "asc" }
    });

    return rows.map(toChatMessage);
  }
}

export const chatService = new ChatService();
