import { ChatType, MessageStatus } from "@prisma/client";
import { prisma } from "../../lib/prisma.js";
<<<<<<< HEAD
import type { ChatMessage, SendMessagePayload } from "./chat.types.js";
=======
import type { ChatMessage, ChatSummary, SendMessagePayload } from "./chat.types.js";
>>>>>>> 1a42523 (chore: connect local repo)

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
<<<<<<< HEAD
=======
    const peerId = this.extractPeerId(chatId);
    if (peerId) {
      await this.ensureUser(peerId);
    }
>>>>>>> 1a42523 (chore: connect local repo)

    await prisma.chat.upsert({
      where: { id: chatId },
      create: {
        id: chatId,
        type: ChatType.DIRECT,
        members: {
<<<<<<< HEAD
          create: [{ userId: senderId }]
=======
          create: [
            { userId: senderId },
            ...(peerId ? [{ userId: peerId }] : [])
          ]
>>>>>>> 1a42523 (chore: connect local repo)
        }
      },
      update: {
        members: {
<<<<<<< HEAD
          connectOrCreate: {
            where: { chatId_userId: { chatId, userId: senderId } },
            create: { userId: senderId }
          }
=======
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
>>>>>>> 1a42523 (chore: connect local repo)
        }
      }
    });
  }

<<<<<<< HEAD
=======
  extractPeerId(chatId: string): string | null {
    if (!chatId.startsWith("direct_")) return null;
    const peerId = chatId.replace("direct_", "").trim();
    return peerId.length > 0 ? peerId : null;
  }

>>>>>>> 1a42523 (chore: connect local repo)
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
<<<<<<< HEAD
=======

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
>>>>>>> 1a42523 (chore: connect local repo)
}

export const chatService = new ChatService();
