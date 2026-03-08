import bcrypt from "bcryptjs";
import { Router } from "express";
import { z } from "zod";
import { signAccessToken } from "../../lib/jwt.js";
import { prisma } from "../../lib/prisma.js";
import { requireAuth } from "../../middleware/auth.js";

export const authRouter = Router();

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

  const existing = await prisma.user.findFirst({
    where: { username },
    select: { id: true }
  });

  if (existing) {
    res.status(409).json({ error: "account_already_exists" });
    return;
  }

  const passwordHash = await bcrypt.hash(parsed.data.password, 10);

  const user = await prisma.user.create({
    data: {
      username,
      displayName: parsed.data.username,
      passwordHash
    }
  });

  const accessToken = signAccessToken(user.id);

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

  const user = await prisma.user.findFirst({
    where: { username }
  });

  if (!user) {
    res.status(404).json({ error: "account_not_found" });
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

  const accessToken = signAccessToken(user.id);
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
