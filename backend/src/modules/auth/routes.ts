import bcrypt from "bcryptjs";
import { Router } from "express";
import { z } from "zod";
import { signAccessToken } from "../../lib/jwt.js";
import { prisma } from "../../lib/prisma.js";
import { requireAuth } from "../../middleware/auth.js";

export const authRouter = Router();

const registerSchema = z.object({
  username: z.string().min(3).max(32).optional(),
  phone: z.string().min(5).max(20).optional(),
  displayName: z.string().min(2).max(80),
  password: z.string().min(4).max(128).optional()
});

const loginSchema = z.object({
  username: z.string().min(3).max(32).optional(),
  phone: z.string().min(5).max(20).optional(),
  password: z.string().min(4).max(128).optional()
});

function pickIdentity(input: { username?: string; phone?: string }): { username?: string; phone?: string } | null {
  if (input.username) return { username: input.username.toLowerCase() };
  if (input.phone) return { phone: input.phone };
  return null;
}

authRouter.post("/register", async (req, res) => {
  const parsed = registerSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const identity = pickIdentity(parsed.data);
  if (!identity) {
    res.status(400).json({ error: "username_or_phone_required" });
    return;
  }

  const existing = await prisma.user.findFirst({
    where: {
      OR: [
        identity.username ? { username: identity.username } : undefined,
        identity.phone ? { phone: identity.phone } : undefined
      ].filter(Boolean) as Array<{ username?: string; phone?: string }>
    },
    select: { id: true }
  });

  if (existing) {
    res.status(409).json({ error: "account_already_exists" });
    return;
  }

  const passwordHash = parsed.data.password ? await bcrypt.hash(parsed.data.password, 10) : null;

  const user = await prisma.user.create({
    data: {
      username: identity.username,
      phone: identity.phone,
      displayName: parsed.data.displayName,
      passwordHash
    }
  });

  const accessToken = signAccessToken(user.id);

  res.status(201).json({
    accessToken,
    user: {
      id: user.id,
      username: user.username,
      phone: user.phone,
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

  const identity = pickIdentity(parsed.data);
  if (!identity) {
    res.status(400).json({ error: "username_or_phone_required" });
    return;
  }

  const user = await prisma.user.findFirst({
    where: {
      OR: [
        identity.username ? { username: identity.username } : undefined,
        identity.phone ? { phone: identity.phone } : undefined
      ].filter(Boolean) as Array<{ username?: string; phone?: string }>
    }
  });

  if (!user) {
    res.status(404).json({ error: "account_not_found" });
    return;
  }

  if (user.passwordHash) {
    if (!parsed.data.password) {
      res.status(401).json({ error: "password_required" });
      return;
    }

    const ok = await bcrypt.compare(parsed.data.password, user.passwordHash);
    if (!ok) {
      res.status(401).json({ error: "invalid_password" });
      return;
    }
  }

  const accessToken = signAccessToken(user.id);
  res.json({
    accessToken,
    user: {
      id: user.id,
      username: user.username,
      phone: user.phone,
      displayName: user.displayName
    }
  });
});

authRouter.get("/me", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({
    where: { id: req.authUserId! },
    select: { id: true, username: true, displayName: true, phone: true, email: true, createdAt: true }
  });

  if (!user) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  res.json({ data: user });
});
