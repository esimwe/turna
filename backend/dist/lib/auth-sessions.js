import { prisma } from "./prisma.js";
import { emitSessionRevoked } from "../modules/chat/chat.realtime.js";
const prismaAuthSession = prisma.authSession;
function firstHeaderValue(value) {
    if (Array.isArray(value)) {
        return value[0]?.trim() || null;
    }
    if (typeof value === "string") {
        const trimmed = value.split(",")[0]?.trim();
        return trimmed?.length ? trimmed : null;
    }
    return null;
}
export function getRequestIp(req) {
    return firstHeaderValue(req.headers["x-forwarded-for"]) ?? req.socket.remoteAddress ?? null;
}
export function getRequestUserAgent(req) {
    return firstHeaderValue(req.headers["user-agent"]);
}
export function getRequestDeviceId(req) {
    return firstHeaderValue(req.headers["x-turna-device-id"]);
}
export function getRequestPlatform(req) {
    return firstHeaderValue(req.headers["x-turna-platform"]);
}
async function revokeSessionIds(sessionIds, reason) {
    if (sessionIds.length === 0)
        return 0;
    const result = await prismaAuthSession.updateMany({
        where: {
            id: { in: sessionIds },
            revokedAt: null
        },
        data: {
            revokedAt: new Date(),
            revokeReason: reason
        }
    });
    await Promise.all(sessionIds.map((sessionId) => emitSessionRevoked(sessionId, reason).catch(() => undefined)));
    return result.count;
}
export async function createAuthSessionForRequest(userId, req, options = {}) {
    if (options.revokeExisting ?? true) {
        const activeSessions = await prismaAuthSession.findMany({
            where: {
                userId,
                revokedAt: null
            },
            select: {
                id: true
            }
        });
        await revokeSessionIds(activeSessions.map((session) => session.id), options.revokeReason ?? "new_login");
    }
    return prismaAuthSession.create({
        data: {
            userId,
            deviceId: getRequestDeviceId(req),
            platform: getRequestPlatform(req),
            ipAddress: getRequestIp(req),
            userAgent: getRequestUserAgent(req)
        }
    });
}
export async function revokeAuthSession(sessionId, reason) {
    await revokeSessionIds([sessionId], reason);
}
export async function revokeAllAuthSessionsForUser(userId, reason) {
    const activeSessions = await prismaAuthSession.findMany({
        where: {
            userId,
            revokedAt: null
        },
        select: {
            id: true
        }
    });
    return revokeSessionIds(activeSessions.map((session) => session.id), reason);
}
export async function findActiveAuthSession(sessionId) {
    return prismaAuthSession.findFirst({
        where: {
            id: sessionId,
            revokedAt: null
        },
        select: {
            id: true,
            userId: true
        }
    });
}
