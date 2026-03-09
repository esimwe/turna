import { prisma } from "../../lib/prisma.js";
import { areUsersBlocked } from "../../lib/user-relationship.js";
import { livekitCallProvider } from "./livekit.provider.js";
import { CALL_RECONNECT_GRACE_MS, CALL_RING_TIMEOUT_MS, cancelCallReconnectGrace } from "./call.timeout.js";
const prismaCall = prisma.call;
const prismaCallEvent = prisma.callEvent;
const ACTIVE_CALL_STALE_GRACE_MS = CALL_RECONNECT_GRACE_MS;
function toAppCallType(type) {
    return type === "AUDIO" ? "audio" : "video";
}
function toPrismaCallType(type) {
    return type === "audio" ? "AUDIO" : "VIDEO";
}
function toAppCallStatus(status) {
    switch (status) {
        case "ACCEPTED":
            return "accepted";
        case "DECLINED":
            return "declined";
        case "MISSED":
            return "missed";
        case "ENDED":
            return "ended";
        case "CANCELLED":
            return "cancelled";
        default:
            return "ringing";
    }
}
function toCallUser(row) {
    return {
        id: row.id,
        displayName: row.displayName,
        avatarKey: row.avatarUrl,
        updatedAt: row.updatedAt.toISOString()
    };
}
function toCallRecord(row) {
    return {
        id: row.id,
        callerId: row.callerId,
        calleeId: row.calleeId,
        type: toAppCallType(row.type),
        status: toAppCallStatus(row.status),
        provider: "livekit",
        providerSessionId: row.providerSessionId,
        roomName: row.roomName,
        acceptedAt: row.acceptedAt?.toISOString() ?? null,
        endedAt: row.endedAt?.toISOString() ?? null,
        createdAt: row.createdAt.toISOString(),
        updatedAt: row.updatedAt.toISOString(),
        caller: toCallUser(row.caller),
        callee: toCallUser(row.callee)
    };
}
function calculateDurationSeconds(record) {
    if (!record.acceptedAt)
        return null;
    const acceptedAt = Date.parse(record.acceptedAt);
    if (Number.isNaN(acceptedAt))
        return null;
    const endedAt = record.endedAt ? Date.parse(record.endedAt) : Date.now();
    if (Number.isNaN(endedAt) || endedAt <= acceptedAt)
        return 0;
    return Math.round((endedAt - acceptedAt) / 1000);
}
export class CallService {
    provider;
    constructor(provider) {
        this.provider = provider;
    }
    isConfigured() {
        return this.provider.isConfigured();
    }
    async recordEvent(callId, type, actorUserId, payload) {
        await prismaCallEvent.create({
            data: {
                callId,
                type,
                actorUserId,
                payload: payload ?? undefined
            }
        });
    }
    async getCallRowById(callId) {
        return prismaCall.findUnique({
            where: { id: callId },
            include: {
                caller: {
                    select: {
                        id: true,
                        displayName: true,
                        avatarUrl: true,
                        updatedAt: true
                    }
                },
                callee: {
                    select: {
                        id: true,
                        displayName: true,
                        avatarUrl: true,
                        updatedAt: true
                    }
                }
            }
        });
    }
    async getCallRowByRoomName(roomName) {
        return prismaCall.findFirst({
            where: { roomName },
            include: {
                caller: {
                    select: {
                        id: true,
                        displayName: true,
                        avatarUrl: true,
                        updatedAt: true
                    }
                },
                callee: {
                    select: {
                        id: true,
                        displayName: true,
                        avatarUrl: true,
                        updatedAt: true
                    }
                }
            },
            orderBy: { createdAt: "desc" }
        });
    }
    async getCallByIdForUser(callId, userId) {
        const row = await this.getCallRowById(callId);
        if (!row) {
            throw new Error("call_not_found");
        }
        if (row.callerId !== userId && row.calleeId !== userId) {
            throw new Error("forbidden_call_access");
        }
        return toCallRecord(row);
    }
    async findCallByRoomName(roomName) {
        if (!roomName)
            return null;
        const row = await this.getCallRowByRoomName(roomName);
        return row ? toCallRecord(row) : null;
    }
    async findActiveCallByRoomName(roomName) {
        if (!roomName)
            return null;
        const row = await this.getCallRowByRoomName(roomName);
        if (!row || !["RINGING", "ACCEPTED"].includes(row.status)) {
            return null;
        }
        return toCallRecord(row);
    }
    async listCalls(userId, limit = 50) {
        const rows = await prismaCall.findMany({
            where: {
                OR: [{ callerId: userId }, { calleeId: userId }]
            },
            include: {
                caller: {
                    select: {
                        id: true,
                        displayName: true,
                        avatarUrl: true,
                        updatedAt: true
                    }
                },
                callee: {
                    select: {
                        id: true,
                        displayName: true,
                        avatarUrl: true,
                        updatedAt: true
                    }
                }
            },
            orderBy: { createdAt: "desc" },
            take: Math.min(Math.max(limit, 1), 100)
        });
        return rows.map((row) => {
            const record = toCallRecord(row);
            const outgoing = row.callerId === userId;
            return {
                id: record.id,
                type: record.type,
                status: record.status,
                direction: outgoing ? "outgoing" : "incoming",
                createdAt: record.createdAt,
                acceptedAt: record.acceptedAt,
                endedAt: record.endedAt,
                durationSeconds: calculateDurationSeconds(record),
                peer: outgoing ? record.callee : record.caller
            };
        });
    }
    async ensureUsersExist(userIds) {
        const users = await prisma.user.findMany({
            where: { id: { in: userIds } },
            select: { id: true }
        });
        if (users.length !== userIds.length) {
            throw new Error("user_not_found");
        }
    }
    async ensureNoActiveConflict(userIds) {
        await this.reconcileActiveCallsForUsers(userIds);
        const conflict = await prismaCall.findFirst({
            where: {
                status: { in: ["RINGING", "ACCEPTED"] },
                OR: [{ callerId: { in: userIds } }, { calleeId: { in: userIds } }]
            },
            select: { id: true }
        });
        if (conflict) {
            throw new Error("call_conflict");
        }
    }
    async finalizeReconciledCall(row, nextStatus, actorUserId, payload) {
        const updated = await prismaCall.updateMany({
            where: {
                id: row.id,
                status: row.status
            },
            data: {
                status: nextStatus,
                endedAt: new Date()
            }
        });
        if (updated.count === 0) {
            return null;
        }
        cancelCallReconnectGrace(row.id);
        await this.recordEvent(row.id, toAppCallStatus(nextStatus), actorUserId, payload);
        await this.provider.closeSession({
            callId: row.id,
            sessionId: row.providerSessionId,
            roomName: row.roomName
        });
        return this.getCallByIdForUser(row.id, row.callerId);
    }
    async endAcceptedCallByRoomName(params) {
        if (!params.roomName)
            return null;
        const row = await this.getCallRowByRoomName(params.roomName);
        if (!row || row.status !== "ACCEPTED") {
            return null;
        }
        let participantCount = null;
        if (typeof params.minParticipantCount === "number") {
            participantCount = await this.provider.getParticipantCount({
                callId: row.id,
                sessionId: row.providerSessionId,
                roomName: row.roomName
            });
            if (participantCount !== null && participantCount >= params.minParticipantCount) {
                return null;
            }
        }
        return this.finalizeReconciledCall(row, "ENDED", params.actorUserId, {
            reason: params.reason,
            ...(participantCount !== null ? { participantCount } : {})
        });
    }
    async reconcileActiveCallsForUsers(userIds) {
        const uniqueUserIds = [...new Set(userIds.filter(Boolean))];
        if (uniqueUserIds.length === 0)
            return [];
        const rows = await prismaCall.findMany({
            where: {
                status: { in: ["RINGING", "ACCEPTED"] },
                OR: [{ callerId: { in: uniqueUserIds } }, { calleeId: { in: uniqueUserIds } }]
            },
            include: {
                caller: {
                    select: {
                        id: true,
                        displayName: true,
                        avatarUrl: true,
                        updatedAt: true
                    }
                },
                callee: {
                    select: {
                        id: true,
                        displayName: true,
                        avatarUrl: true,
                        updatedAt: true
                    }
                }
            }
        });
        const now = Date.now();
        const reconciled = [];
        for (const row of rows) {
            if (row.status === "RINGING" &&
                now - row.createdAt.getTime() >= CALL_RING_TIMEOUT_MS + ACTIVE_CALL_STALE_GRACE_MS) {
                const updated = await this.finalizeReconciledCall(row, "MISSED", row.calleeId, {
                    reason: "stale_ringing_conflict"
                });
                if (updated)
                    reconciled.push(updated);
                continue;
            }
            if (row.status !== "ACCEPTED") {
                continue;
            }
            const participantCount = await this.provider.getParticipantCount({
                callId: row.id,
                sessionId: row.providerSessionId,
                roomName: row.roomName
            });
            if (participantCount === 0) {
                const updated = await this.finalizeReconciledCall(row, "ENDED", undefined, {
                    reason: "empty_room_conflict"
                });
                if (updated)
                    reconciled.push(updated);
            }
        }
        return reconciled;
    }
    async startCall(params) {
        if (!this.provider.isConfigured()) {
            throw new Error("call_provider_not_configured");
        }
        if (params.callerId === params.calleeId) {
            throw new Error("invalid_call_target");
        }
        await this.ensureUsersExist([params.callerId, params.calleeId]);
        if (await areUsersBlocked(params.callerId, params.calleeId)) {
            throw new Error("call_blocked");
        }
        await this.ensureNoActiveConflict([params.callerId, params.calleeId]);
        const created = await prismaCall.create({
            data: {
                callerId: params.callerId,
                calleeId: params.calleeId,
                type: toPrismaCallType(params.type),
                status: "RINGING",
                provider: "LIVEKIT"
            }
        });
        try {
            const session = await this.provider.createSession({
                callId: created.id,
                type: params.type,
                callerId: params.callerId,
                calleeId: params.calleeId
            });
            await prismaCall.update({
                where: { id: created.id },
                data: {
                    roomName: session.roomName,
                    providerSessionId: session.sessionId
                }
            });
            await this.recordEvent(created.id, "started", params.callerId, {
                type: params.type
            });
            return this.getCallByIdForUser(created.id, params.callerId);
        }
        catch (error) {
            await prismaCall.delete({ where: { id: created.id } }).catch(() => undefined);
            throw error;
        }
    }
    async acceptCall(params) {
        if (!this.provider.isConfigured()) {
            throw new Error("call_provider_not_configured");
        }
        const row = await this.getCallRowById(params.callId);
        if (!row)
            throw new Error("call_not_found");
        if (row.calleeId !== params.userId)
            throw new Error("forbidden_call_access");
        if (!row.roomName)
            throw new Error("call_room_missing");
        if (row.status === "ACCEPTED") {
            const callerToken = await this.provider.createParticipantToken({
                callId: row.id,
                roomName: row.roomName,
                type: toAppCallType(row.type),
                userId: row.caller.id,
                participantName: row.caller.displayName
            });
            const calleeToken = await this.provider.createParticipantToken({
                callId: row.id,
                roomName: row.roomName,
                type: toAppCallType(row.type),
                userId: row.callee.id,
                participantName: row.callee.displayName
            });
            return {
                call: await this.getCallByIdForUser(params.callId, params.userId),
                joinByUserId: {
                    [row.callerId]: callerToken,
                    [row.calleeId]: calleeToken
                }
            };
        }
        if (row.status !== "RINGING")
            throw new Error("call_not_ringing");
        const updated = await prismaCall.update({
            where: { id: params.callId },
            data: {
                status: "ACCEPTED",
                acceptedAt: new Date()
            }
        });
        await this.recordEvent(params.callId, "accepted", params.userId);
        const callerToken = await this.provider.createParticipantToken({
            callId: updated.id,
            roomName: row.roomName,
            type: toAppCallType(updated.type),
            userId: row.caller.id,
            participantName: row.caller.displayName
        });
        const calleeToken = await this.provider.createParticipantToken({
            callId: updated.id,
            roomName: row.roomName,
            type: toAppCallType(updated.type),
            userId: row.callee.id,
            participantName: row.callee.displayName
        });
        return {
            call: await this.getCallByIdForUser(params.callId, params.userId),
            joinByUserId: {
                [row.callerId]: callerToken,
                [row.calleeId]: calleeToken
            }
        };
    }
    async declineCall(params) {
        const row = await this.getCallRowById(params.callId);
        if (!row)
            throw new Error("call_not_found");
        if (row.calleeId !== params.userId)
            throw new Error("forbidden_call_access");
        if (row.status !== "RINGING")
            throw new Error("call_not_ringing");
        await prismaCall.update({
            where: { id: params.callId },
            data: {
                status: "DECLINED",
                endedAt: new Date()
            }
        });
        cancelCallReconnectGrace(params.callId);
        await this.recordEvent(params.callId, "declined", params.userId);
        await this.provider.closeSession({
            callId: params.callId,
            sessionId: row.providerSessionId,
            roomName: row.roomName
        });
        return this.getCallByIdForUser(params.callId, params.userId);
    }
    async endCall(params) {
        const row = await this.getCallRowById(params.callId);
        if (!row)
            throw new Error("call_not_found");
        if (row.callerId !== params.userId && row.calleeId !== params.userId) {
            throw new Error("forbidden_call_access");
        }
        if (!["RINGING", "ACCEPTED"].includes(row.status)) {
            throw new Error("call_not_active");
        }
        const nextStatus = row.status === "ACCEPTED"
            ? "ENDED"
            : row.callerId === params.userId
                ? "CANCELLED"
                : "DECLINED";
        await prismaCall.update({
            where: { id: params.callId },
            data: {
                status: nextStatus,
                endedAt: new Date()
            }
        });
        cancelCallReconnectGrace(params.callId);
        await this.recordEvent(params.callId, toAppCallStatus(nextStatus), params.userId);
        await this.provider.closeSession({
            callId: params.callId,
            sessionId: row.providerSessionId,
            roomName: row.roomName
        });
        return this.getCallByIdForUser(params.callId, params.userId);
    }
    async timeoutCall(callId) {
        const row = await this.getCallRowById(callId);
        if (!row)
            throw new Error("call_not_found");
        if (row.status !== "RINGING")
            throw new Error("call_not_ringing");
        await prismaCall.update({
            where: { id: callId },
            data: {
                status: "MISSED",
                endedAt: new Date()
            }
        });
        cancelCallReconnectGrace(callId);
        await this.recordEvent(callId, "missed", row.calleeId);
        await this.provider.closeSession({
            callId,
            sessionId: row.providerSessionId,
            roomName: row.roomName
        });
        return this.getCallByIdForUser(callId, row.calleeId);
    }
}
export const callService = new CallService(livekitCallProvider);
