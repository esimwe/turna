import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma.js";
import { signAccessToken } from "../../lib/jwt.js";
import { requireAuth } from "../../middleware/auth.js";

export const authRouter = Router();

const requestOtpSchema = z.object({
  target: z.string().min(5)
});

const verifyOtpSchema = z.object({
  target: z.string().min(5),
  code: z.string().length(6),
  displayName: z.string().min(2).max(80)
});

function generateOtpCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function splitTarget(target: string): { phone?: string; email?: string } {
  if (target.includes("@")) {
    return { email: target.toLowerCase() };
  }

  return { phone: target };
}

authRouter.post("/request-otp", async (req, res) => {
  const parsed = requestOtpSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const code = generateOtpCode();
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

  await prisma.otpCode.create({
    data: {
      target: parsed.data.target,
      code,
      expiresAt
    }
  });

  res.json({ ok: true, expiresAt: expiresAt.toISOString(), debugCode: code });
});

authRouter.post("/verify-otp", async (req, res) => {
  const parsed = verifyOtpSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const otp = await prisma.otpCode.findFirst({
    where: {
      target: parsed.data.target,
      code: parsed.data.code,
      consumed: false,
      expiresAt: { gt: new Date() }
    },
    orderBy: { createdAt: "desc" }
  });

  if (!otp) {
    res.status(401).json({ error: "invalid_or_expired_code" });
    return;
  }

  await prisma.otpCode.update({ where: { id: otp.id }, data: { consumed: true } });

  const target = splitTarget(parsed.data.target);

  const user = await prisma.user.upsert({
    where: target.email ? { email: target.email } : { phone: target.phone! },
    create: {
      displayName: parsed.data.displayName,
      email: target.email,
      phone: target.phone
    },
    update: {
      displayName: parsed.data.displayName
    }
  });

  const accessToken = signAccessToken(user.id);

  res.json({
    accessToken,
    user: {
      id: user.id,
      displayName: user.displayName,
      phone: user.phone,
      email: user.email
    }
  });
});

authRouter.get("/me", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({
    where: { id: req.authUserId! },
    select: { id: true, displayName: true, phone: true, email: true, createdAt: true }
  });

  if (!user) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  res.json({ data: user });
});
