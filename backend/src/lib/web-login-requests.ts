import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { AuthSessionContext } from "./auth-sessions.js";
import { redis } from "./redis.js";

const WEB_LOGIN_REQUEST_TTL_SECONDS = 120;

export interface WebLoginRequestUserPayload {
  id: string;
  displayName: string;
  username: string | null;
  phone: string | null;
  avatarUrl: string | null;
}

interface StoredWebLoginRequest {
  requestId: string;
  secretHash: string;
  status: "pending" | "approved";
  createdAt: string;
  expiresAt: string;
  deviceLabel: string | null;
  webContext: AuthSessionContext;
  approvedAt: string | null;
  approvedByUserId: string | null;
  accessToken: string | null;
  user: WebLoginRequestUserPayload | null;
}

export interface CreatedWebLoginRequest {
  requestId: string;
  secret: string;
  expiresInSeconds: number;
  expiresAt: string;
  qrText: string;
}

export interface WebLoginRequestStatus {
  status: "pending" | "approved" | "expired";
  expiresAt: string | null;
  approvedAt: string | null;
  accessToken: string | null;
  user: WebLoginRequestUserPayload | null;
}

export interface ValidatedWebLoginRequest {
  requestId: string;
  deviceLabel: string | null;
  webContext: AuthSessionContext;
  expiresAt: string;
}

function ensureWebLoginStoreAvailable(): void {
  if (redis.status !== "ready") {
    throw new Error("web_login_unavailable");
  }
}

function webLoginKey(requestId: string): string {
  return `turna:web-login:${requestId}`;
}

function hashSecret(secret: string): string {
  return createHash("sha256").update(secret).digest("hex");
}

function normalizeText(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed?.length ? trimmed : null;
}

function normalizeContext(context: Partial<AuthSessionContext> | null | undefined): AuthSessionContext {
  return {
    deviceId: normalizeText(context?.deviceId),
    platform: normalizeText(context?.platform),
    deviceModel: normalizeText(context?.deviceModel),
    osVersion: normalizeText(context?.osVersion),
    appVersion: normalizeText(context?.appVersion),
    localeTag: normalizeText(context?.localeTag),
    regionCode: normalizeText(context?.regionCode),
    connectionType: normalizeText(context?.connectionType),
    countryIso: normalizeText(context?.countryIso),
    ipCountryIso: normalizeText(context?.ipCountryIso),
    ipAddress: normalizeText(context?.ipAddress),
    userAgent: normalizeText(context?.userAgent)
  };
}

async function loadStoredWebLoginRequest(requestId: string): Promise<StoredWebLoginRequest | null> {
  ensureWebLoginStoreAvailable();
  const raw = await redis.get(webLoginKey(requestId));
  if (!raw) return null;
  try {
    return JSON.parse(raw) as StoredWebLoginRequest;
  } catch {
    await redis.del(webLoginKey(requestId));
    return null;
  }
}

async function saveStoredWebLoginRequest(
  record: StoredWebLoginRequest,
  ttlSeconds: number
): Promise<void> {
  ensureWebLoginStoreAvailable();
  if (ttlSeconds <= 0) {
    await redis.del(webLoginKey(record.requestId));
    return;
  }
  await redis.set(webLoginKey(record.requestId), JSON.stringify(record), "EX", ttlSeconds);
}

function computeRemainingSeconds(expiresAtIso: string): number {
  return Math.max(
    0,
    Math.ceil((new Date(expiresAtIso).getTime() - Date.now()) / 1000)
  );
}

export async function createWebLoginRequest(
  context: Partial<AuthSessionContext> | null | undefined,
  deviceLabel?: string | null
): Promise<CreatedWebLoginRequest> {
  ensureWebLoginStoreAvailable();

  const requestId = randomUUID();
  const secret = randomBytes(24).toString("base64url");
  const createdAt = new Date();
  const expiresAt = new Date(createdAt.getTime() + WEB_LOGIN_REQUEST_TTL_SECONDS * 1000);

  const record: StoredWebLoginRequest = {
    requestId,
    secretHash: hashSecret(secret),
    status: "pending",
    createdAt: createdAt.toISOString(),
    expiresAt: expiresAt.toISOString(),
    deviceLabel: normalizeText(deviceLabel),
    webContext: normalizeContext(context),
    approvedAt: null,
    approvedByUserId: null,
    accessToken: null,
    user: null
  };

  await saveStoredWebLoginRequest(record, WEB_LOGIN_REQUEST_TTL_SECONDS);

  const qrUrl = new URL("turna://web-login");
  qrUrl.searchParams.set("requestId", requestId);
  qrUrl.searchParams.set("secret", secret);

  return {
    requestId,
    secret,
    expiresInSeconds: WEB_LOGIN_REQUEST_TTL_SECONDS,
    expiresAt: record.expiresAt,
    qrText: qrUrl.toString()
  };
}

export async function getWebLoginRequestStatus(
  requestId: string,
  secret: string
): Promise<WebLoginRequestStatus> {
  const record = await loadStoredWebLoginRequest(requestId);
  if (!record) {
    return {
      status: "expired",
      expiresAt: null,
      approvedAt: null,
      accessToken: null,
      user: null
    };
  }

  if (record.secretHash !== hashSecret(secret)) {
    throw new Error("web_login_secret_invalid");
  }

  const ttlSeconds = computeRemainingSeconds(record.expiresAt);
  if (ttlSeconds <= 0) {
    await redis.del(webLoginKey(requestId));
    return {
      status: "expired",
      expiresAt: null,
      approvedAt: null,
      accessToken: null,
      user: null
    };
  }

  return {
    status: record.status,
    expiresAt: record.expiresAt,
    approvedAt: record.approvedAt,
    accessToken: record.accessToken,
    user: record.user
  };
}

export async function validatePendingWebLoginRequest(
  requestId: string,
  secret: string
): Promise<ValidatedWebLoginRequest> {
  const record = await loadStoredWebLoginRequest(requestId);
  if (!record) {
    throw new Error("web_login_expired");
  }

  if (record.secretHash !== hashSecret(secret)) {
    throw new Error("web_login_secret_invalid");
  }

  const ttlSeconds = computeRemainingSeconds(record.expiresAt);
  if (ttlSeconds <= 0) {
    await redis.del(webLoginKey(requestId));
    throw new Error("web_login_expired");
  }
  if (record.status != "pending") {
    throw new Error("web_login_already_approved");
  }

  return {
    requestId: record.requestId,
    deviceLabel: record.deviceLabel,
    webContext: record.webContext,
    expiresAt: record.expiresAt
  };
}

export async function approveWebLoginRequest(params: {
  requestId: string;
  secret: string;
  approvedByUserId: string;
  accessToken: string;
  user: WebLoginRequestUserPayload;
}): Promise<{ deviceLabel: string | null; webContext: AuthSessionContext }> {
  const record = await loadStoredWebLoginRequest(params.requestId);
  if (!record) {
    throw new Error("web_login_expired");
  }

  if (record.secretHash !== hashSecret(params.secret)) {
    throw new Error("web_login_secret_invalid");
  }

  const ttlSeconds = computeRemainingSeconds(record.expiresAt);
  if (ttlSeconds <= 0) {
    await redis.del(webLoginKey(params.requestId));
    throw new Error("web_login_expired");
  }

  const nextRecord: StoredWebLoginRequest = {
    ...record,
    status: "approved",
    approvedAt: new Date().toISOString(),
    approvedByUserId: params.approvedByUserId,
    accessToken: params.accessToken,
    user: params.user
  };
  await saveStoredWebLoginRequest(nextRecord, ttlSeconds);
  return {
    deviceLabel: nextRecord.deviceLabel,
    webContext: nextRecord.webContext
  };
}
