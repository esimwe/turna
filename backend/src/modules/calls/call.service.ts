import { prisma } from "../../lib/prisma.js";
import type { CallProvider } from "./call.provider.js";
import { livekitCallProvider } from "./livekit.provider.js";
import type {
  AppCallStatus,
  AppCallType,
  CallHistoryItem,
  CallJoinPayload,
  CallRecord,
  CallUser
} from "./call.types.js";

type CallRow = Awaited<ReturnType<CallService["getCallRowById"]>>;
type PrismaCallStatus = "RINGING" | "ACCEPTED" | "DECLINED" | "MISSED" | "ENDED" | "CANCELLED";
type PrismaCallType = "AUDIO" | "VIDEO";

const prismaCall = (prisma as unknown as { call: any }).call;
const prismaCallEvent = (prisma as unknown as { callEvent: any }).callEvent;

function toAppCallType(type: PrismaCallType): AppCallType {
  return type === "AUDIO" ? "audio" : "video";
}

function toPrismaCallType(type: AppCallType): PrismaCallType {
  return type === "audio" ? "AUDIO" : "VIDEO";
}

function toAppCallStatus(status: PrismaCallStatus): AppCallStatus {
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

function toCallUser(row: {
  id: string;
  displayName: string;
  avatarUrl: string | null;
  updatedAt: Date;
}): CallUser {
  return {
    id: row.id,
    displayName: row.displayName,
    avatarKey: row.avatarUrl,
    updatedAt: row.updatedAt.toISOString()
  };
}

function toCallRecord(row: NonNullable<CallRow>): CallRecord {
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

function calculateDurationSeconds(record: CallRecord): number | null {
  if (!record.acceptedAt) return null;
  const acceptedAt = Date.parse(record.acceptedAt);
  if (Number.isNaN(acceptedAt)) return null;

  const endedAt = record.endedAt ? Date.parse(record.endedAt) : Date.now();
  if (Number.isNaN(endedAt) || endedAt <= acceptedAt) return 0;
  return Math.round((endedAt - acceptedAt) / 1000);
}

export class CallService {
  constructor(private readonly provider: CallProvider) {}

  isConfigured(): boolean {
    return this.provider.isConfigured();
  }

  private async recordEvent(
    callId: string,
    type: string,
    actorUserId?: string,
    payload?: Record<string, unknown>
  ): Promise<void> {
    await prismaCallEvent.create({
      data: {
        callId,
        type,
        actorUserId,
        payload: payload ?? undefined
      }
    });
  }

  private async getCallRowById(callId: string) {
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

  async getCallByIdForUser(callId: string, userId: string): Promise<CallRecord> {
    const row = await this.getCallRowById(callId);
    if (!row) {
      throw new Error("call_not_found");
    }
    if (row.callerId !== userId && row.calleeId !== userId) {
      throw new Error("forbidden_call_access");
    }
    return toCallRecord(row);
  }

  async listCalls(userId: string, limit = 50): Promise<CallHistoryItem[]> {
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

    return rows.map((row: NonNullable<CallRow>) => {
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

  private async ensureUsersExist(userIds: string[]): Promise<void> {
    const users = await prisma.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true }
    });
    if (users.length !== userIds.length) {
      throw new Error("user_not_found");
    }
  }

  private async ensureNoActiveConflict(userIds: string[]): Promise<void> {
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

  async startCall(params: {
    callerId: string;
    calleeId: string;
    type: AppCallType;
  }): Promise<CallRecord> {
    if (!this.provider.isConfigured()) {
      throw new Error("call_provider_not_configured");
    }
    if (params.callerId === params.calleeId) {
      throw new Error("invalid_call_target");
    }

    await this.ensureUsersExist([params.callerId, params.calleeId]);
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
    } catch (error) {
      await prismaCall.delete({ where: { id: created.id } }).catch(() => undefined);
      throw error;
    }
  }

  async acceptCall(params: {
    callId: string;
    userId: string;
  }): Promise<{
    call: CallRecord;
    joinByUserId: Record<string, CallJoinPayload>;
  }> {
    if (!this.provider.isConfigured()) {
      throw new Error("call_provider_not_configured");
    }

    const row = await this.getCallRowById(params.callId);
    if (!row) throw new Error("call_not_found");
    if (row.calleeId !== params.userId) throw new Error("forbidden_call_access");
    if (row.status !== "RINGING") throw new Error("call_not_ringing");
    if (!row.roomName) throw new Error("call_room_missing");

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

  async declineCall(params: {
    callId: string;
    userId: string;
  }): Promise<CallRecord> {
    const row = await this.getCallRowById(params.callId);
    if (!row) throw new Error("call_not_found");
    if (row.calleeId !== params.userId) throw new Error("forbidden_call_access");
    if (row.status !== "RINGING") throw new Error("call_not_ringing");

    await prismaCall.update({
      where: { id: params.callId },
      data: {
        status: "DECLINED",
        endedAt: new Date()
      }
    });
    await this.recordEvent(params.callId, "declined", params.userId);
    await this.provider.closeSession({
      callId: params.callId,
      sessionId: row.providerSessionId,
      roomName: row.roomName
    });

    return this.getCallByIdForUser(params.callId, params.userId);
  }

  async endCall(params: {
    callId: string;
    userId: string;
  }): Promise<CallRecord> {
    const row = await this.getCallRowById(params.callId);
    if (!row) throw new Error("call_not_found");
    if (row.callerId !== params.userId && row.calleeId !== params.userId) {
      throw new Error("forbidden_call_access");
    }
    if (!["RINGING", "ACCEPTED"].includes(row.status)) {
      throw new Error("call_not_active");
    }

    const nextStatus =
      row.status === "ACCEPTED"
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
    await this.recordEvent(params.callId, toAppCallStatus(nextStatus), params.userId);
    await this.provider.closeSession({
      callId: params.callId,
      sessionId: row.providerSessionId,
      roomName: row.roomName
    });

    return this.getCallByIdForUser(params.callId, params.userId);
  }
}

export const callService = new CallService(livekitCallProvider);
