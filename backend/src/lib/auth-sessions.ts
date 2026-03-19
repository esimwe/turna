import type { Request } from "express";
import { prisma } from "./prisma.js";
import { emitSessionRevoked } from "../modules/chat/chat.realtime.js";

const prismaAuthSession = (prisma as unknown as { authSession: any }).authSession;

export interface AuthSessionContext {
  deviceId: string | null;
  platform: string | null;
  deviceModel: string | null;
  osVersion: string | null;
  appVersion: string | null;
  localeTag: string | null;
  regionCode: string | null;
  connectionType: string | null;
  countryIso: string | null;
  ipCountryIso: string | null;
  ipAddress: string | null;
  userAgent: string | null;
}

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

function normalizeSessionValue(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed?.length ? trimmed : null;
}

export function buildAuthSessionContextFromRequest(req: Request): AuthSessionContext {
  return {
    deviceId: normalizeSessionValue(getRequestDeviceId(req)),
    platform: normalizeSessionValue(getRequestPlatform(req)),
    deviceModel: normalizeSessionValue(getRequestDeviceModel(req)),
    osVersion: normalizeSessionValue(getRequestOsVersion(req)),
    appVersion: normalizeSessionValue(getRequestAppVersion(req)),
    localeTag: normalizeSessionValue(getRequestLocaleTag(req)),
    regionCode: normalizeSessionValue(getRequestRegionCode(req)),
    connectionType: normalizeSessionValue(getRequestConnectionType(req)),
    countryIso: normalizeSessionValue(getRequestCountryIso(req)),
    ipCountryIso: normalizeSessionValue(getRequestIpCountryIso(req)),
    ipAddress: normalizeSessionValue(getRequestIp(req)),
    userAgent: normalizeSessionValue(getRequestUserAgent(req))
  };
}

function buildPersistableAuthSessionContext(
  context: Partial<AuthSessionContext> | null | undefined
): AuthSessionContext {
  return {
    deviceId: normalizeSessionValue(context?.deviceId ?? null),
    platform: normalizeSessionValue(context?.platform ?? null),
    deviceModel: normalizeSessionValue(context?.deviceModel ?? null),
    osVersion: normalizeSessionValue(context?.osVersion ?? null),
    appVersion: normalizeSessionValue(context?.appVersion ?? null),
    localeTag: normalizeSessionValue(context?.localeTag ?? null),
    regionCode: normalizeSessionValue(context?.regionCode ?? null),
    connectionType: normalizeSessionValue(context?.connectionType ?? null),
    countryIso: normalizeSessionValue(context?.countryIso ?? null),
    ipCountryIso: normalizeSessionValue(context?.ipCountryIso ?? null),
    ipAddress: normalizeSessionValue(context?.ipAddress ?? null),
    userAgent: normalizeSessionValue(context?.userAgent ?? null)
  };
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

export async function createAuthSession(
  userId: string,
  context: Partial<AuthSessionContext> | null | undefined,
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
      ...buildPersistableAuthSessionContext(context)
    }
  });
}

export async function createAuthSessionForRequest(
  userId: string,
  req: Request,
  options: {
    revokeExisting?: boolean;
    revokeReason?: string;
  } = {}
) {
  return createAuthSession(userId, buildAuthSessionContextFromRequest(req), options);
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
