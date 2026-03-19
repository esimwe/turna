import bcrypt from "bcryptjs";
import { Router } from "express";
import { z } from "zod";
import { signAccessToken } from "../../lib/jwt.js";
import { otpService } from "./otp.service.js";
import { prisma } from "../../lib/prisma.js";
import {
  buildAuthSessionContextFromRequest,
  createAuthSession,
  createAuthSessionForRequest,
  revokeAuthSession
} from "../../lib/auth-sessions.js";
import {
  approveWebLoginRequest,
  createWebLoginRequest,
  getWebLoginRequestStatus,
  validatePendingWebLoginRequest
} from "../../lib/web-login-requests.js";
import { assertUserCanAccessApp } from "../../lib/user-access.js";
import { requireAuth } from "../../middleware/auth.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";

export const authRouter = Router();
const prismaUser = (prisma as unknown as { user: any }).user;
const prismaAuthSession = (prisma as unknown as { authSession: any }).authSession;

const registerSchema = z.object({
  username: z.string().min(3).max(32),
  password: z.string().min(4).max(128)
});

const loginSchema = z.object({
  username: z.string().min(3).max(32),
  password: z.string().min(4).max(128)
});

const requestOtpSchema = z.object({
  countryIso: z.string().trim().min(2).max(2),
  dialCode: z.string().trim().min(1).max(10),
  nationalNumber: z.string().trim().min(4).max(20)
});

const verifyOtpSchema = z.object({
  phone: z.string().trim().min(8).max(20),
  code: z.string().trim().min(4).max(8)
});

const createWebLoginRequestSchema = z.object({
  deviceLabel: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().max(120).nullable().optional()
    )
});

const confirmWebLoginSchema = z.object({
  requestId: z.string().trim().min(1).max(255),
  secret: z.string().trim().min(1).max(255)
});

const webLoginRequestParamSchema = z.object({
  requestId: z.string().trim().min(1).max(255)
});

const webLoginStatusQuerySchema = z.object({
  secret: z.string().trim().min(1).max(255)
});

const sessionIdParamSchema = z.object({
  sessionId: z.string().trim().min(1).max(255)
});

function serializeLinkedDeviceSession(session: any) {
  const explicitLabel = session.deviceModel?.trim();
  const fallbackLabel = session.userAgent?.trim();
  return {
    id: session.id,
    deviceLabel:
      explicitLabel?.length
        ? explicitLabel
        : fallbackLabel?.length
          ? fallbackLabel
          : "Turna Web",
    platform: session.platform ?? "web",
    deviceModel: session.deviceModel ?? null,
    osVersion: session.osVersion ?? null,
    appVersion: session.appVersion ?? null,
    localeTag: session.localeTag ?? null,
    regionCode: session.regionCode ?? null,
    connectionType: session.connectionType ?? null,
    countryIso: session.countryIso ?? null,
    ipCountryIso: session.ipCountryIso ?? null,
    ipAddress: session.ipAddress ?? null,
    userAgent: session.userAgent ?? null,
    createdAt: session.createdAt.toISOString(),
    lastSeenAt: session.lastSeenAt.toISOString()
  };
}

function handleWebLoginError(res: any, error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  switch (error.message) {
    case "web_login_unavailable":
      res.status(503).json({ error: "web_login_unavailable" });
      return true;
    case "web_login_expired":
      res.status(410).json({ error: "web_login_expired" });
      return true;
    case "web_login_secret_invalid":
      res.status(403).json({ error: "web_login_secret_invalid" });
      return true;
    case "web_login_already_approved":
      res.status(409).json({ error: "web_login_already_approved" });
      return true;
    default:
      return false;
  }
}

authRouter.post("/web-login/request", async (req, res) => {
  const parsed = createWebLoginRequestSchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const requestContext = buildAuthSessionContextFromRequest(req);
    const request = await createWebLoginRequest(
      {
        ...requestContext,
        platform: "web",
        deviceModel:
          parsed.data.deviceLabel?.trim() ||
          requestContext.deviceModel ||
          requestContext.userAgent ||
          "Turna Web"
      },
      parsed.data.deviceLabel
    );

    res.status(201).json({
      data: {
        requestId: request.requestId,
        secret: request.secret,
        qrText: request.qrText,
        expiresInSeconds: request.expiresInSeconds,
        expiresAt: request.expiresAt
      }
    });
  } catch (error) {
    if (handleWebLoginError(res, error)) {
      return;
    }
    res.status(500).json({ error: "web_login_request_failed" });
  }
});

authRouter.get("/web-login/request/:requestId", async (req, res) => {
  const parsedParams = webLoginRequestParamSchema.safeParse(req.params);
  const parsedQuery = webLoginStatusQuerySchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({ error: "validation_error", details: parsedQuery.error.flatten() });
    return;
  }

  try {
    const status = await getWebLoginRequestStatus(
      parsedParams.data.requestId,
      parsedQuery.data.secret
    );
    res.status(status.status === "expired" ? 410 : 200).json({ data: status });
  } catch (error) {
    if (handleWebLoginError(res, error)) {
      return;
    }
    res.status(500).json({ error: "web_login_status_failed" });
  }
});

authRouter.post("/web-login/confirm", requireAuth, async (req, res) => {
  const parsed = confirmWebLoginSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const pending = await validatePendingWebLoginRequest(
      parsed.data.requestId,
      parsed.data.secret
    );
    const user = await prismaUser.findUnique({
      where: { id: req.authUserId! },
      select: {
        id: true,
        username: true,
        displayName: true,
        phone: true,
        avatarUrl: true,
        updatedAt: true
      }
    });
    if (!user) {
      res.status(404).json({ error: "user_not_found" });
      return;
    }

    const webDeviceLabel =
      pending.deviceLabel?.trim() ||
      pending.webContext.deviceModel?.trim() ||
      pending.webContext.userAgent?.trim() ||
      "Turna Web";
    const session = await createAuthSession(
      req.authUserId!,
      {
        ...pending.webContext,
        platform: "web",
        deviceModel: webDeviceLabel
      },
      {
        revokeExisting: false
      }
    );
    const accessToken = signAccessToken(user.id, session.id);
    await approveWebLoginRequest({
      requestId: parsed.data.requestId,
      secret: parsed.data.secret,
      approvedByUserId: req.authUserId!,
      accessToken,
      user: {
        id: user.id,
        displayName: user.displayName,
        username: user.username ?? null,
        phone: user.phone ?? null,
        avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null
      }
    });

    res.status(201).json({
      data: {
        linked: true,
        sessionId: session.id,
        deviceLabel: webDeviceLabel,
        expiresAt: pending.expiresAt
      }
    });
  } catch (error) {
    if (handleWebLoginError(res, error)) {
      return;
    }
    res.status(500).json({ error: "web_login_confirm_failed" });
  }
});

authRouter.get("/linked-devices", requireAuth, async (req, res) => {
  const sessions = await prismaAuthSession.findMany({
    where: {
      userId: req.authUserId!,
      revokedAt: null,
      platform: "web"
    },
    orderBy: [{ lastSeenAt: "desc" }, { createdAt: "desc" }],
    select: {
      id: true,
      platform: true,
      deviceModel: true,
      osVersion: true,
      appVersion: true,
      localeTag: true,
      regionCode: true,
      connectionType: true,
      countryIso: true,
      ipCountryIso: true,
      ipAddress: true,
      userAgent: true,
      createdAt: true,
      lastSeenAt: true
    }
  });

  res.json({
    data: sessions.map((session: any) => serializeLinkedDeviceSession(session))
  });
});

authRouter.delete("/linked-devices/:sessionId", requireAuth, async (req, res) => {
  const parsed = sessionIdParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const session = await prismaAuthSession.findFirst({
    where: {
      id: parsed.data.sessionId,
      userId: req.authUserId!,
      revokedAt: null,
      platform: "web"
    },
    select: { id: true }
  });
  if (!session) {
    res.status(404).json({ error: "linked_device_not_found" });
    return;
  }

  await revokeAuthSession(session.id, "linked_device_removed");
  res.json({ data: { removed: true } });
});

authRouter.post("/request-otp", async (req, res) => {
  const parsed = requestOtpSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const result = await otpService.requestLoginOtp({
      ...parsed.data,
      ...otpService.buildRequestContext(req)
    });

    res.json({
      data: {
        sent: true,
        phone: result.phone,
        expiresInSeconds: result.expiresInSeconds,
        retryAfterSeconds: result.retryAfterSeconds
      }
    });
  } catch (error) {
    const mapped = otpService.extractRequestOtpError(error);
    res.status(mapped.status).json({
      error: mapped.error,
      ...(mapped.retryAfterSeconds ? { retryAfterSeconds: mapped.retryAfterSeconds } : {})
    });
  }
});

authRouter.post("/verify-otp", async (req, res) => {
  const parsed = verifyOtpSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const result = await otpService.verifyLoginOtp(parsed.data, req);
    res.json(result);
  } catch (error) {
    const mapped = otpService.extractVerifyOtpError(error);
    res.status(mapped.status).json({ error: mapped.error });
  }
});

authRouter.post("/register", async (req, res) => {
  const parsed = registerSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const username = parsed.data.username.toLowerCase();

  const existing = await prismaUser.findFirst({
    where: { username },
    select: { id: true }
  });

  if (existing) {
    res.status(409).json({ error: "account_already_exists" });
    return;
  }

  const passwordHash = await bcrypt.hash(parsed.data.password, 10);

  const user = await prismaUser.create({
    data: {
      username,
      displayName: parsed.data.username,
      passwordHash
    }
  });

  const session = await createAuthSessionForRequest(user.id, req, {
    revokeExisting: false
  });
  const accessToken = signAccessToken(user.id, session.id);

  res.status(201).json({
    accessToken,
    user: {
      id: user.id,
      username: user.username,
      displayName: user.displayName
    }
  });
});

authRouter.post("/login", async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const username = parsed.data.username.toLowerCase();

  const user = await prismaUser.findFirst({
    where: { username },
    select: {
      id: true,
      username: true,
      displayName: true,
      passwordHash: true,
      avatarUrl: true,
      updatedAt: true,
      accountStatus: true,
      otpBlocked: true,
      sendRestricted: true,
      callRestricted: true
    }
  });

  if (!user) {
    res.status(404).json({ error: "account_not_found" });
    return;
  }

  try {
    assertUserCanAccessApp({
      id: user.id,
      accountStatus: user.accountStatus,
      otpBlocked: user.otpBlocked,
      sendRestricted: user.sendRestricted,
      callRestricted: user.callRestricted
    });
  } catch (error) {
    res.status(403).json({ error: error instanceof Error ? error.message : "account_suspended" });
    return;
  }

  if (!user.passwordHash) {
    res.status(401).json({ error: "password_not_set" });
    return;
  }

  const ok = await bcrypt.compare(parsed.data.password, user.passwordHash);
  if (!ok) {
    res.status(401).json({ error: "invalid_password" });
    return;
  }

  const session = await createAuthSessionForRequest(user.id, req);
  const accessToken = signAccessToken(user.id, session.id);
  res.json({
    accessToken,
    user: {
      id: user.id,
      username: user.username,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null
    }
  });
});

authRouter.get("/me", requireAuth, async (req, res) => {
  const user = await prismaUser.findUnique({
    where: { id: req.authUserId! },
    select: {
      id: true,
      username: true,
      displayName: true,
      phone: true,
      avatarUrl: true,
      updatedAt: true,
      email: true,
      createdAt: true,
      accountStatus: true,
      otpBlocked: true,
      sendRestricted: true,
      callRestricted: true
    }
  });

  if (!user) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  res.json({
    data: {
      ...user,
      avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null
    }
  });
});

authRouter.post("/logout", requireAuth, async (req, res) => {
  if (req.authSessionId) {
    await revokeAuthSession(req.authSessionId, "logout");
  }

  res.json({
    data: {
      loggedOut: true
    }
  });
});
