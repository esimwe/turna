import type { Request } from "express";
import { env } from "../../config/env.js";

function trimTrailingSlash(value: string): string {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}

function shouldForceHttpsHost(host: string | null | undefined): boolean {
  const normalized = (host ?? "").trim().toLowerCase();
  if (!normalized) return false;
  return !(
    normalized.startsWith("localhost") ||
    normalized.startsWith("127.0.0.1") ||
    normalized.startsWith("[::1]") ||
    normalized.startsWith("10.") ||
    normalized.startsWith("192.168.") ||
    /^172\.(1[6-9]|2\d|3[0-1])\./.test(normalized)
  );
}

export function getRequestOrigin(req: Request): string {
  const configuredBaseUrl = env.PUBLIC_BASE_URL?.trim();
  if (configuredBaseUrl) {
    return trimTrailingSlash(configuredBaseUrl);
  }

  const forwardedProto = req.header("x-forwarded-proto");
  const forwardedHost = req.header("x-forwarded-host");
  const host = forwardedHost?.split(",")[0]?.trim() || req.get("host") || "";

  let proto = forwardedProto?.split(",")[0]?.trim() || req.protocol;
  if (
    (env.FORCE_HTTPS || env.NODE_ENV === "production") &&
    shouldForceHttpsHost(host)
  ) {
    proto = "https";
  }

  return `${proto}://${host}`;
}

export function buildAvatarUrlFromOrigin(origin: string, userId: string, updatedAt: Date): string {
  const version = encodeURIComponent(updatedAt.toISOString());
  return `${trimTrailingSlash(origin)}/api/profile/avatar/${userId}?v=${version}`;
}

export function buildAvatarUrl(req: Request, userId: string, updatedAt: Date): string {
  return buildAvatarUrlFromOrigin(getRequestOrigin(req), userId, updatedAt);
}
