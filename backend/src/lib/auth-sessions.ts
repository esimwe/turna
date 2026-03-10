import type { Request } from "express";
import { prisma } from "./prisma.js";
import { emitSessionRevoked } from "../modules/chat/chat.realtime.js";

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

export function getRequestDeviceModel(req: Request): string | null {
  return firstHeaderValue(req.headers["x-turna-device-model"]);
}

export function getRequestOsVersion(req: Request): string | null {
  return firstHeaderValue(req.headers["x-turna-os-version"]);
}

export function getRequestAppVersion(req: Request): string | null {
  return firstHeaderValue(req.headers["x-turna-app-version"]);
}

export function getRequestLocaleTag(req: Request): string | null {
  return firstHeaderValue(req.headers["x-turna-locale"]);
}

export function getRequestRegionCode(req: Request): string | null {
  return firstHeaderValue(req.headers["x-turna-region"]);
}

export function getRequestConnectionType(req: Request): string | null {
  return firstHeaderValue(req.headers["x-turna-connection-type"]);
}

export function getRequestCountryIso(req: Request): string | null {
  const countryIso = firstHeaderValue(req.headers["x-turna-country-iso"]);
  return countryIso?.toUpperCase() ?? null;
}

export function getRequestIpCountryIso(req: Request): string | null {
  const headerValue =
    firstHeaderValue(req.headers["cf-ipcountry"]) ??
    firstHeaderValue(req.headers["x-vercel-ip-country"]) ??
    firstHeaderValue(req.headers["x-country-code"]);
  return headerValue?.toUpperCase() ?? null;
}

async function revokeSessionIds(sessionIds: string[], reason: string): Promise<number> {
  if (sessionIds.length === 0) return 0;

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

  await Promise.all(
    sessionIds.map((sessionId) =>
      emitSessionRevoked(sessionId, reason).catch(() => undefined)
    )
  );

  return result.count;
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
    const activeSessions = await prismaAuthSession.findMany({
      where: {
        userId,
        revokedAt: null
      },
      select: {
        id: true
      }
    });
    await revokeSessionIds(
      activeSessions.map((session: { id: string }) => session.id),
      options.revokeReason ?? "new_login"
    );
  }

  return prismaAuthSession.create({
    data: {
      userId,
      deviceId: getRequestDeviceId(req),
      platform: getRequestPlatform(req),
      deviceModel: getRequestDeviceModel(req),
      osVersion: getRequestOsVersion(req),
      appVersion: getRequestAppVersion(req),
      localeTag: getRequestLocaleTag(req),
      regionCode: getRequestRegionCode(req),
      connectionType: getRequestConnectionType(req),
      countryIso: getRequestCountryIso(req),
      ipCountryIso: getRequestIpCountryIso(req),
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req)
    }
  });
}

export async function revokeAuthSession(sessionId: string, reason: string): Promise<void> {
  await revokeSessionIds([sessionId], reason);
}

export async function revokeAllAuthSessionsForUser(userId: string, reason: string): Promise<number> {
  const activeSessions = await prismaAuthSession.findMany({
    where: {
      userId,
      revokedAt: null
    },
    select: {
      id: true
    }
  });
  return revokeSessionIds(
    activeSessions.map((session: { id: string }) => session.id),
    reason
  );
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

export async function touchActiveAuthSessionForRequest(
  sessionId: string,
  req: Request
): Promise<void> {
  const data: Record<string, unknown> = {
    lastSeenAt: new Date()
  };

  const deviceId = getRequestDeviceId(req);
  const platform = getRequestPlatform(req);
  const deviceModel = getRequestDeviceModel(req);
  const osVersion = getRequestOsVersion(req);
  const appVersion = getRequestAppVersion(req);
  const localeTag = getRequestLocaleTag(req);
  const regionCode = getRequestRegionCode(req);
  const connectionType = getRequestConnectionType(req);
  const countryIso = getRequestCountryIso(req);
  const ipCountryIso = getRequestIpCountryIso(req);
  const ipAddress = getRequestIp(req);
  const userAgent = getRequestUserAgent(req);

  if (deviceId) data.deviceId = deviceId;
  if (platform) data.platform = platform;
  if (deviceModel) data.deviceModel = deviceModel;
  if (osVersion) data.osVersion = osVersion;
  if (appVersion) data.appVersion = appVersion;
  if (localeTag) data.localeTag = localeTag;
  if (regionCode) data.regionCode = regionCode;
  if (connectionType) data.connectionType = connectionType;
  if (countryIso) data.countryIso = countryIso;
  if (ipCountryIso) data.ipCountryIso = ipCountryIso;
  if (ipAddress) data.ipAddress = ipAddress;
  if (userAgent) data.userAgent = userAgent;

  await prismaAuthSession.updateMany({
    where: {
      id: sessionId,
      revokedAt: null
    },
    data
  });
}
