import bcrypt from "bcryptjs";
import { Router } from "express";
import { z } from "zod";
import { signAccessToken } from "../../lib/jwt.js";
import { prisma } from "../../lib/prisma.js";
import { createAuthSessionForRequest, revokeAuthSession } from "../../lib/auth-sessions.js";
import { assertUserCanAccessApp } from "../../lib/user-access.js";
import { requireAuth } from "../../middleware/auth.js";

export const authRouter = Router();
const prismaUser = (prisma as unknown as { user: any }).user;

const registerSchema = z.object({
  username: z.string().min(3).max(32),
  password: z.string().min(4).max(128)
});

const loginSchema = z.object({
  username: z.string().min(3).max(32),
  password: z.string().min(4).max(128)
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
    where: { username }
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
      displayName: user.displayName
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

  res.json({ data: user });
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
