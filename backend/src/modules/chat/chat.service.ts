import { ChatType, MessageStatus } from "@prisma/client";
import { prisma } from "../../lib/prisma.js";
import type { ChatMessage, ChatSummary, SendMessagePayload } from "./chat.types.js";

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
    const peerId = this.extractPeerId(chatId, senderId);
    if (peerId) {
      await this.ensureUser(peerId);
    }

    await prisma.chat.upsert({
      where: { id: chatId },
      create: {
        id: chatId,
        type: ChatType.DIRECT,
        members: {
          create: [
            { userId: senderId },
            ...(peerId ? [{ userId: peerId }] : [])
          ]
        }
      },
      update: {
        members: {
          connectOrCreate: [
            {
              where: { chatId_userId: { chatId, userId: senderId } },
              create: { userId: senderId }
            },
            ...(peerId
              ? [
                  {
                    where: { chatId_userId: { chatId, userId: peerId } },
                    create: { userId: peerId }
                  }
                ]
              : [])
          ]
        }
      }
    });
  }

  extractPeerId(chatId: string, senderId: string): string | null {
    if (!chatId.startsWith("direct_")) return null;
    const key = chatId.replace("direct_", "").trim();
    if (!key) return null;

    const participants = key.split("_").filter(Boolean);
    if (participants.length === 1) {
      return participants[0];
    }

    return participants.find((id) => id !== senderId) ?? null;
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

  async getChatSummaries(userId: string): Promise<ChatSummary[]> {
    const memberships = await prisma.chatMember.findMany({
      where: { userId },
      include: {
        chat: {
          include: {
            members: {
              include: { user: true }
            },
            messages: {
              orderBy: { createdAt: "desc" },
              take: 1
            }
          }
        }
      },
      orderBy: { joinedAt: "desc" }
    });

    return memberships.map((membership) => {
      const chat = membership.chat;
      const peer = chat.members.find((m) => m.userId !== userId)?.user;
      const last = chat.messages[0];
      return {
        chatId: chat.id,
        title: peer?.displayName ?? "New Chat",
        lastMessage: last?.text ?? "Sohbet başlat",
        lastMessageAt: last ? last.createdAt.toISOString() : null
      };
    });
  }

  async getUserDirectory(userId: string): Promise<Array<{ id: string; displayName: string }>> {
    const users = await prisma.user.findMany({
      where: { id: { not: userId } },
      select: { id: true, displayName: true },
      orderBy: { createdAt: "desc" }
    });
    return users;
  }
}

export const chatService = new ChatService();
