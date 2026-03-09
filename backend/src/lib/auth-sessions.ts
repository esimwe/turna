import type { Request } from "express";
import { prisma } from "./prisma.js";

const prismaAuthSession = (prisma as unknown as { authSession: any }).authSession;

function firstHeaderValue(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) {
    return value[0]?.trim() || null;
  }
  if (typeof value === "string") {
    const trimmed = value.split(",")[0]?.trim();
    return trimmed?.length ? trimmed : null;
  }
  return null;
}

export function getRequestIp(req: Request): string | null {
  return firstHeaderValue(req.headers["x-forwarded-for"]) ?? req.socket.remoteAddress ?? null;
}

export function getRequestUserAgent(req: Request): string | null {
  return firstHeaderValue(req.headers["user-agent"]);
}

export function getRequestDeviceId(req: Request): string | null {
  return firstHeaderValue(req.headers["x-turna-device-id"]);
}

export function getRequestPlatform(req: Request): string | null {
  return firstHeaderValue(req.headers["x-turna-platform"]);
}

export async function createAuthSessionForRequest(
  userId: string,
  req: Request,
  options: {
    revokeExisting?: boolean;
    revokeReason?: string;
  } = {}
) {
  if (options.revokeExisting ?? true) {
    await prismaAuthSession.updateMany({
      where: {
        userId,
        revokedAt: null
      },
      data: {
        revokedAt: new Date(),
        revokeReason: options.revokeReason ?? "new_login"
      }
    });
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

export async function revokeAuthSession(sessionId: string, reason: string): Promise<void> {
  await prismaAuthSession.updateMany({
    where: {
      id: sessionId,
      revokedAt: null
    },
    data: {
      revokedAt: new Date(),
      revokeReason: reason
    }
  });
}

export async function revokeAllAuthSessionsForUser(userId: string, reason: string): Promise<number> {
  const result = await prismaAuthSession.updateMany({
    where: {
      userId,
      revokedAt: null
    },
    data: {
      revokedAt: new Date(),
      revokeReason: reason
    }
  });
  return result.count;
}

export async function findActiveAuthSession(sessionId: string) {
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
