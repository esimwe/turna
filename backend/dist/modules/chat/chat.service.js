import { AttachmentKind, ChatType, MessageStatus } from "@prisma/client";
import { logError } from "../../lib/logger.js";
import { prisma } from "../../lib/prisma.js";
import { createObjectReadUrl, deleteObject, getObjectHead } from "../../lib/storage.js";
const prismaUser = prisma.user;
const TURNA_DELETED_EVERYONE_MARKER = "[[turna-deleted-everyone]]";
const DELETE_FOR_EVERYONE_WINDOW_MS = 10 * 60 * 1000;
function toAttachmentKind(kind) {
    switch (kind) {
        case AttachmentKind.IMAGE:
            return "image";
        case AttachmentKind.VIDEO:
            return "video";
        default:
            return "file";
    }
}
function fromAttachmentKind(kind) {
    switch (kind) {
        case "image":
            return AttachmentKind.IMAGE;
        case "video":
            return AttachmentKind.VIDEO;
        default:
            return AttachmentKind.FILE;
    }
}
function summarizeMessage(row) {
    const text = row.text?.trim();
    if (text === TURNA_DELETED_EVERYONE_MARKER)
        return "Silindi.";
    if (text)
        return text;
    const attachments = row.attachments ?? [];
    if (attachments.length === 0)
        return "Sohbet baslat";
    if (attachments.length > 1)
        return `${attachments.length} ek gonderildi`;
    switch (attachments[0].kind) {
        case AttachmentKind.IMAGE:
            return "Fotograf";
        case AttachmentKind.VIDEO:
            return "Video";
        default:
            return "Dosya";
    }
}
async function toChatAttachment(row) {
    let url = null;
    try {
        url = await createObjectReadUrl(row.objectKey);
    }
    catch (error) {
        logError("attachment read url create failed", error);
    }
    return {
        id: row.id,
        objectKey: row.objectKey,
        kind: toAttachmentKind(row.kind),
        fileName: row.fileName,
        contentType: row.contentType,
        sizeBytes: row.sizeBytes,
        width: row.width,
        height: row.height,
        durationSeconds: row.durationSeconds,
        url
    };
}
async function toChatMessage(row) {
    const attachments = await Promise.all(row.attachments.map((attachment) => toChatAttachment(attachment)));
    return {
        id: row.id,
        chatId: row.chatId,
        senderId: row.senderId,
        text: row.text ?? "",
        createdAt: row.createdAt.toISOString(),
        status: row.status,
        attachments
    };
}
export class ChatService {
    extractDirectParticipants(chatId) {
        if (!chatId.startsWith("direct_"))
            return null;
        const key = chatId.replace("direct_", "").trim();
        const participants = key.split("_").filter(Boolean);
        if (participants.length !== 2)
            return null;
        const sorted = [...participants].sort();
        const normalized = `direct_${sorted[0]}_${sorted[1]}`;
        if (normalized !== chatId)
            return null;
        return [sorted[0], sorted[1]];
    }
    getDirectPeerId(chatId, userId) {
        const participants = this.extractDirectParticipants(chatId);
        if (!participants || !participants.includes(userId))
            return null;
        return participants.find((participantId) => participantId !== userId) ?? null;
    }
    getDirectParticipants(chatId) {
        const participants = this.extractDirectParticipants(chatId);
        return participants ? [...participants] : [];
    }
    async getChatParticipantIds(chatId) {
        const members = await prisma.chatMember.findMany({
            where: { chatId },
            select: { userId: true }
        });
        return members.map((member) => member.userId);
    }
    async resolvePeerId(chatId, userId) {
        const directPeer = this.getDirectPeerId(chatId, userId);
        if (directPeer)
            return directPeer;
        const participants = await this.getChatParticipantIds(chatId);
        const peer = participants.find((participantId) => participantId !== userId);
        return peer ?? null;
    }
    async ensureChatAccess(chatId, userId) {
        const member = await prisma.chatMember.findUnique({
            where: { chatId_userId: { chatId, userId } },
            select: { chatId: true }
        });
        if (member)
            return true;
        const participants = this.extractDirectParticipants(chatId);
        if (!participants || !participants.includes(userId))
            return false;
        const users = await prisma.user.findMany({
            where: { id: { in: participants } },
            select: { id: true }
        });
        if (users.length !== 2)
            return false;
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
    async sendMessage(payload) {
        const hasAccess = await this.ensureChatAccess(payload.chatId, payload.senderId);
        if (!hasAccess) {
            throw new Error("forbidden_chat_access");
        }
        const preparedAttachments = await this.prepareAttachments(payload.chatId, payload.senderId, payload.attachments ?? []);
        const message = await prisma.message.create({
            data: {
                chatId: payload.chatId,
                senderId: payload.senderId,
                text: payload.text?.trim() ? payload.text.trim() : null,
                status: MessageStatus.sent,
                attachments: preparedAttachments.length
                    ? {
                        create: preparedAttachments.map((attachment) => ({
                            objectKey: attachment.objectKey,
                            kind: attachment.kind,
                            fileName: attachment.fileName,
                            contentType: attachment.contentType,
                            sizeBytes: attachment.sizeBytes,
                            width: attachment.width,
                            height: attachment.height,
                            durationSeconds: attachment.durationSeconds
                        }))
                    }
                    : undefined
            },
            include: {
                attachments: {
                    orderBy: { createdAt: "asc" }
                }
            }
        });
        return toChatMessage(message);
    }
    async deleteMessageForEveryone(messageId, requesterId) {
        const existing = await prisma.message.findUnique({
            where: { id: messageId },
            include: {
                attachments: {
                    orderBy: { createdAt: "asc" }
                }
            }
        });
        if (!existing) {
            throw new Error("message_not_found");
        }
        const hasAccess = await this.ensureChatAccess(existing.chatId, requesterId);
        if (!hasAccess) {
            throw new Error("forbidden_chat_access");
        }
        if (existing.senderId !== requesterId) {
            throw new Error("message_delete_not_allowed");
        }
        if ((existing.text ?? "").trim() === TURNA_DELETED_EVERYONE_MARKER) {
            return toChatMessage(existing);
        }
        if (Date.now() - existing.createdAt.getTime() > DELETE_FOR_EVERYONE_WINDOW_MS) {
            throw new Error("message_delete_window_expired");
        }
        const updated = await prisma.$transaction(async (tx) => {
            await tx.messageAttachment.deleteMany({
                where: { messageId: existing.id }
            });
            return tx.message.update({
                where: { id: existing.id },
                data: {
                    text: TURNA_DELETED_EVERYONE_MARKER,
                    isViewOnce: false
                },
                include: {
                    attachments: {
                        orderBy: { createdAt: "asc" }
                    }
                }
            });
        });
        await Promise.all(existing.attachments.map((attachment) => deleteObject(attachment.objectKey).catch((error) => {
            logError("message attachment delete failed", error);
        })));
        return toChatMessage(updated);
    }
    async markMessagesDelivered(chatId, userId) {
        const targetRows = await prisma.message.findMany({
            where: {
                chatId,
                senderId: { not: userId },
                status: MessageStatus.sent
            },
            select: { id: true }
        });
        const messageIds = targetRows.map((row) => row.id);
        if (messageIds.length === 0)
            return [];
        await prisma.message.updateMany({
            where: { id: { in: messageIds } },
            data: { status: MessageStatus.delivered }
        });
        return messageIds;
    }
    async markMessagesRead(chatId, userId) {
        const targetRows = await prisma.message.findMany({
            where: {
                chatId,
                senderId: { not: userId },
                status: { in: [MessageStatus.sent, MessageStatus.delivered] }
            },
            select: { id: true }
        });
        const messageIds = targetRows.map((row) => row.id);
        if (messageIds.length === 0)
            return [];
        await prisma.message.updateMany({
            where: { id: { in: messageIds } },
            data: { status: MessageStatus.read, readAt: new Date() }
        });
        return messageIds;
    }
    async getMessages(chatId) {
        const page = await this.getMessagePage(chatId, { limit: 30 });
        return page.items;
    }
    async getMessagePage(chatId, options = {}) {
        const limit = Math.min(Math.max(options.limit ?? 30, 1), 100);
        const beforeDate = options.before && !Number.isNaN(Date.parse(options.before))
            ? new Date(options.before)
            : null;
        const rows = await prisma.message.findMany({
            where: {
                chatId,
                ...(beforeDate ? { createdAt: { lt: beforeDate } } : {})
            },
            include: {
                attachments: {
                    orderBy: { createdAt: "asc" }
                }
            },
            orderBy: { createdAt: "desc" },
            take: limit + 1
        });
        const hasMore = rows.length > limit;
        const pageRows = rows.slice(0, limit).reverse();
        return {
            items: await Promise.all(pageRows.map((row) => toChatMessage(row))),
            hasMore,
            nextBefore: hasMore && pageRows.length > 0 ? pageRows[0].createdAt.toISOString() : null
        };
    }
    async getChatSummaries(userId) {
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
                            take: 1,
                            include: {
                                attachments: {
                                    orderBy: { createdAt: "asc" },
                                    take: 3
                                }
                            }
                        }
                    }
                }
            },
            orderBy: { joinedAt: "desc" }
        });
        const items = await Promise.all(memberships.map(async (membership) => {
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
                lastMessage: last ? summarizeMessage(last) : "Sohbet baslat",
                lastMessageAt: last ? last.createdAt.toISOString() : null,
                unreadCount,
                peerId: peer?.id ?? null,
                peerAvatarKey: peer?.avatarUrl ?? null,
                peerUpdatedAt: peer?.updatedAt ? peer.updatedAt.toISOString() : null,
                joinedAt: membership.joinedAt
            };
        }));
        items.sort((a, b) => {
            const aTime = a.lastMessageAt ? new Date(a.lastMessageAt).getTime() : a.joinedAt.getTime();
            const bTime = b.lastMessageAt ? new Date(b.lastMessageAt).getTime() : b.joinedAt.getTime();
            return bTime - aTime;
        });
        return items.map(({ joinedAt: _joinedAt, ...summary }) => summary);
    }
    async getUserDirectory(userId) {
        const users = await prisma.user.findMany({
            where: { id: { not: userId } },
            select: { id: true, displayName: true, avatarUrl: true, updatedAt: true },
            orderBy: { createdAt: "desc" }
        });
        return users.map((user) => ({
            id: user.id,
            displayName: user.displayName,
            avatarKey: user.avatarUrl,
            updatedAt: user.updatedAt.toISOString()
        }));
    }
    async getUserChats(userId) {
        const memberships = await prisma.chatMember.findMany({
            where: { userId },
            select: { chatId: true }
        });
        return memberships.map((m) => m.chatId);
    }
    async getPresenceAudienceUserIds(userId) {
        const chatIds = await this.getUserChats(userId);
        if (chatIds.length === 0)
            return [];
        const relatedMembers = await prisma.chatMember.findMany({
            where: {
                chatId: { in: chatIds },
                userId: { not: userId }
            },
            select: { userId: true }
        });
        return Array.from(new Set(relatedMembers.map((member) => member.userId)));
    }
    async getUserLastSeenAt(userId) {
        const user = await prismaUser.findUnique({
            where: { id: userId },
            select: { lastSeenAt: true }
        });
        return user?.lastSeenAt ?? null;
    }
    async updateUserLastSeen(userId, seenAt = new Date()) {
        const user = await prismaUser.update({
            where: { id: userId },
            data: { lastSeenAt: seenAt },
            select: { lastSeenAt: true }
        });
        return user.lastSeenAt ?? seenAt;
    }
    async getUserDisplayName(userId) {
        const user = await prisma.user.findUnique({
            where: { id: userId },
            select: { displayName: true }
        });
        return user?.displayName ?? "Turna";
    }
    async prepareAttachments(chatId, senderId, attachments) {
        if (attachments.length === 0)
            return [];
        return Promise.all(attachments.map(async (attachment) => {
            if (!attachment.objectKey.startsWith(`chat-media/${chatId}/${senderId}/`)) {
                throw new Error("invalid_attachment_key");
            }
            const head = await getObjectHead(attachment.objectKey);
            return {
                objectKey: attachment.objectKey,
                kind: fromAttachmentKind(attachment.kind),
                fileName: attachment.fileName?.trim() || null,
                contentType: head.contentType ?? attachment.contentType,
                sizeBytes: head.contentLength != null
                    ? Number(head.contentLength)
                    : Math.max(0, Math.trunc(attachment.sizeBytes ?? 0)),
                width: attachment.width != null ? Math.max(0, Math.trunc(attachment.width)) : null,
                height: attachment.height != null ? Math.max(0, Math.trunc(attachment.height)) : null,
                durationSeconds: attachment.durationSeconds != null
                    ? Math.max(0, Math.trunc(attachment.durationSeconds))
                    : null
            };
        }));
    }
}
export const chatService = new ChatService();
