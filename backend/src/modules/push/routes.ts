import prismaPkg from "@prisma/client";
import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma.js";
import { requireAuth } from "../../middleware/auth.js";

export const pushRouter = Router();
const { PushPlatform } = prismaPkg;
const prismaDeviceToken = (prisma as unknown as { deviceToken: any }).deviceToken;

const registerDeviceSchema = z.object({
  token: z.string().trim().min(1).max(512),
  platform: z.enum(["ios", "android"]),
  tokenKind: z.enum(["standard", "voip"]).default("standard"),
  deviceLabel: z.string().trim().max(120).optional()
});

const unregisterDeviceSchema = z.object({
  token: z.string().trim().min(1).max(512)
});

pushRouter.post("/devices", requireAuth, async (req, res) => {
  const parsed = registerDeviceSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const device = await prismaDeviceToken.upsert({
    where: { token: parsed.data.token },
    create: {
      userId: req.authUserId!,
      token: parsed.data.token,
      platform: parsed.data.platform === "ios" ? PushPlatform.IOS : PushPlatform.ANDROID,
      tokenKind: parsed.data.tokenKind === "voip" ? "VOIP" : "STANDARD",
      deviceLabel: parsed.data.deviceLabel?.trim() || null,
      isActive: true
    },
    update: {
      userId: req.authUserId!,
      platform: parsed.data.platform === "ios" ? PushPlatform.IOS : PushPlatform.ANDROID,
      tokenKind: parsed.data.tokenKind === "voip" ? "VOIP" : "STANDARD",
      deviceLabel: parsed.data.deviceLabel?.trim() || null,
      isActive: true
    },
    select: {
      id: true,
      token: true,
      platform: true,
      tokenKind: true,
      deviceLabel: true,
      isActive: true
    }
  });

  res.json({
    data: {
      id: device.id,
      token: device.token,
      platform: device.platform.toLowerCase(),
      tokenKind: device.tokenKind.toLowerCase(),
      deviceLabel: device.deviceLabel,
      isActive: device.isActive
    }
  });
});

pushRouter.delete("/devices", requireAuth, async (req, res) => {
  const parsed = unregisterDeviceSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  await prismaDeviceToken.updateMany({
    where: {
      userId: req.authUserId!,
      token: parsed.data.token
    },
    data: {
      isActive: false
    }
  });

  res.status(204).send();
});
