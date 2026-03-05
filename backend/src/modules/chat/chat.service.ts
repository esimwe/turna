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
  private extractDirectParticipants(chatId: string): [string, string] | null {
    if (!chatId.startsWith("direct_")) return null;
    const key = chatId.replace("direct_", "").trim();
    const participants = key.split("_").filter(Boolean);
    if (participants.length !== 2) return null;

    const sorted = [...participants].sort();
    const normalized = `direct_${sorted[0]}_${sorted[1]}`;
    if (normalized !== chatId) return null;

    return [sorted[0], sorted[1]];
  }

  getDirectPeerId(chatId: string, userId: string): string | null {
    const participants = this.extractDirectParticipants(chatId);
    if (!participants || !participants.includes(userId)) return null;
    return participants.find((participantId) => participantId !== userId) ?? null;
  }

  getDirectParticipants(chatId: string): string[] {
    const participants = this.extractDirectParticipants(chatId);
    return participants ? [...participants] : [];
  }

  async getChatParticipantIds(chatId: string): Promise<string[]> {
    const members = await prisma.chatMember.findMany({
      where: { chatId },
      select: { userId: true }
    });
    return members.map((member) => member.userId);
  }

  async resolvePeerId(chatId: string, userId: string): Promise<string | null> {
    const directPeer = this.getDirectPeerId(chatId, userId);
    if (directPeer) return directPeer;

    const participants = await this.getChatParticipantIds(chatId);
    const peer = participants.find((participantId) => participantId !== userId);
    return peer ?? null;
  }

  async ensureChatAccess(chatId: string, userId: string): Promise<boolean> {
    const member = await prisma.chatMember.findUnique({
      where: { chatId_userId: { chatId, userId } },
      select: { chatId: true }
    });
    if (member) return true;

    const participants = this.extractDirectParticipants(chatId);
    if (!participants || !participants.includes(userId)) return false;

    const users = await prisma.user.findMany({
      where: { id: { in: participants } },
      select: { id: true }
    });
    if (users.length !== 2) return false;

    await prisma.chat.upsert({
      where: { id: chatId },
      create: {
        id: chatId,
        type: ChatType.DIRECT,
        members: {
          create: participants.map((participantId) => ({ userId: participantId }))
        }
      },
      update: {
        members: {
          connectOrCreate: participants.map((participantId) => ({
            where: { chatId_userId: { chatId, userId: participantId } },
            create: { userId: participantId }
          }))
        }
      }
    });

    return true;
  }

  async sendMessage(payload: SendMessagePayload): Promise<ChatMessage> {
    const hasAccess = await this.ensureChatAccess(payload.chatId, payload.senderId);
    if (!hasAccess) {
      throw new Error("forbidden_chat_access");
    }

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

  async markMessagesDelivered(chatId: string, userId: string): Promise<string[]> {
    const targetRows = await prisma.message.findMany({
      where: {
        chatId,
        senderId: { not: userId },
        status: MessageStatus.sent
      },
      select: { id: true }
    });
    const messageIds = targetRows.map((row) => row.id);
    if (messageIds.length === 0) return [];

    await prisma.message.updateMany({
      where: { id: { in: messageIds } },
      data: { status: MessageStatus.delivered }
    });

    return messageIds;
  }

  async markMessagesRead(chatId: string, userId: string): Promise<string[]> {
    const targetRows = await prisma.message.findMany({
      where: {
        chatId,
        senderId: { not: userId },
        status: { in: [MessageStatus.sent, MessageStatus.delivered] }
      },
      select: { id: true }
    });
    const messageIds = targetRows.map((row) => row.id);
    if (messageIds.length === 0) return [];

    await prisma.message.updateMany({
      where: { id: { in: messageIds } },
      data: { status: MessageStatus.read, readAt: new Date() }
    });

    return messageIds;
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

    const items = await Promise.all(
      memberships.map(async (membership) => {
        const chat = membership.chat;
        const peer = chat.members.find((m) => m.userId !== userId)?.user;
        const last = chat.messages[0];
        const unreadCount = await prisma.message.count({
          where: {
            chatId: chat.id,
            senderId: { not: userId },
            status: { not: MessageStatus.read }
          }
        });

        return {
          chatId: chat.id,
          title: peer?.displayName ?? "New Chat",
          lastMessage: last?.text ?? "Sohbet başlat",
          lastMessageAt: last ? last.createdAt.toISOString() : null,
          unreadCount,
          joinedAt: membership.joinedAt
        };
      })
    );

    items.sort((a, b) => {
      const aTime = a.lastMessageAt ? new Date(a.lastMessageAt).getTime() : a.joinedAt.getTime();
      const bTime = b.lastMessageAt ? new Date(b.lastMessageAt).getTime() : b.joinedAt.getTime();
      return bTime - aTime;
    });

    return items.map(({ joinedAt: _joinedAt, ...summary }) => summary);
  }

  async getUserDirectory(userId: string): Promise<Array<{ id: string; displayName: string }>> {
    const users = await prisma.user.findMany({
      where: { id: { not: userId } },
      select: { id: true, displayName: true },
      orderBy: { createdAt: "desc" }
    });
    return users;
  }

  async getUserChats(userId: string): Promise<string[]> {
    const memberships = await prisma.chatMember.findMany({
      where: { userId },
      select: { chatId: true }
    });
    return memberships.map((m) => m.chatId);
  }
}

export const chatService = new ChatService();
