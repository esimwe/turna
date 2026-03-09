import type { Request } from "express";
import { Router } from "express";
import { z } from "zod";
import { logError } from "../../lib/logger.js";
import { prisma } from "../../lib/prisma.js";
import {
  assertObjectExists,
  createAvatarUploadUrl,
  deleteObject,
  getObjectBytes,
  isAvatarKeyOwnedByUser,
  isStorageConfigured
} from "../../lib/storage.js";
import { requireAuth } from "../../middleware/auth.js";
import { buildAvatarUrl } from "./avatar-url.js";

export const profileRouter = Router();
const prismaReportCase = (prisma as unknown as { reportCase: any }).reportCase;

const nullableTrimmedString = (maxLength: number) =>
  z.preprocess((value) => {
    if (typeof value !== "string") return value;
    const trimmed = value.trim();
    return trimmed.length === 0 ? null : trimmed;
  }, z.string().max(maxLength).nullable());

const nullableTrimmedPhone = z.preprocess((value) => {
  if (typeof value !== "string") return value;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}, z.string().min(5).max(20).nullable());

const nullableEmail = z.preprocess((value) => {
  if (typeof value !== "string") return value;
  const trimmed = value.trim().toLowerCase();
  return trimmed.length === 0 ? null : trimmed;
}, z.string().email().max(255).nullable());

const updateProfileSchema = z.object({
  displayName: z.string().trim().min(2).max(80),
  about: nullableTrimmedString(160),
  phone: nullableTrimmedPhone,
  email: nullableEmail
});

const avatarUploadInitSchema = z.object({
  contentType: z
    .string()
    .trim()
    .min(1)
    .max(100)
    .refine((value) => value.startsWith("image/"), {
      message: "image_content_type_required"
    }),
  fileName: z.string().trim().min(1).max(255).optional()
});

const avatarUploadCompleteSchema = z.object({
  objectKey: z.string().trim().min(1).max(512)
});

const submitUserReportSchema = z.object({
  reasonCode: z.string().trim().min(2).max(50),
  details: nullableTrimmedString(1000)
});

function toProfileDto(
  req: Request,
  user: {
    id: string;
    displayName: string;
    phone: string | null;
    email: string | null;
    about: string | null;
    avatarUrl: string | null;
    createdAt: Date;
    updatedAt: Date;
  }
) {
  return {
    id: user.id,
    displayName: user.displayName,
    phone: user.phone,
    email: user.email,
    about: user.about,
    avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null,
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString()
  };
}

function toPublicProfileDto(
  req: Request,
  user: {
    id: string;
    displayName: string;
    phone: string | null;
    about: string | null;
    avatarUrl: string | null;
    createdAt: Date;
    updatedAt: Date;
  }
) {
  return {
    id: user.id,
    displayName: user.displayName,
    phone: user.phone,
    about: user.about,
    avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null,
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString()
  };
}

profileRouter.get("/me", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({
    where: { id: req.authUserId! },
    select: {
      id: true,
      displayName: true,
      phone: true,
      email: true,
      about: true,
      avatarUrl: true,
      createdAt: true,
      updatedAt: true
    }
  });

  if (!user) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  res.json({ data: toProfileDto(req, user) });
});

profileRouter.get("/users/:userId", requireAuth, async (req, res) => {
  const rawUserId = req.params.userId;
  const userId = Array.isArray(rawUserId) ? rawUserId[0] : rawUserId;
  if (!userId) {
    res.status(400).json({ error: "user_id_required" });
    return;
  }

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
      displayName: true,
      phone: true,
      about: true,
      avatarUrl: true,
      createdAt: true,
      updatedAt: true
    }
  });

  if (!user) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  res.json({ data: toPublicProfileDto(req, user) });
});

profileRouter.post("/users/:userId/report", requireAuth, async (req, res) => {
  const rawUserId = req.params.userId;
  const userId = Array.isArray(rawUserId) ? rawUserId[0] : rawUserId;
  if (!userId) {
    res.status(400).json({ error: "user_id_required" });
    return;
  }

  const parsed = submitUserReportSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  if (userId === req.authUserId) {
    res.status(400).json({ error: "cannot_report_self" });
    return;
  }

  const reportedUser = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true }
  });
  if (!reportedUser) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  const existing = await prismaReportCase.findFirst({
    where: {
      reporterUserId: req.authUserId!,
      targetType: "USER",
      reportedUserId: userId,
      status: {
        in: ["OPEN", "UNDER_REVIEW"]
      }
    },
    select: { id: true }
  });

  if (existing) {
    res.status(409).json({ error: "report_already_exists" });
    return;
  }

  const report = await prismaReportCase.create({
    data: {
      reporterUserId: req.authUserId!,
      targetType: "USER",
      reportedUserId: userId,
      reasonCode: parsed.data.reasonCode.trim().toUpperCase(),
      details: parsed.data.details
    }
  });

  res.status(201).json({ data: { id: report.id, status: report.status } });
});

profileRouter.put("/me", requireAuth, async (req, res) => {
  const parsed = updateProfileSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const userId = req.authUserId!;

  if (parsed.data.phone) {
    const phoneOwner = await prisma.user.findFirst({
      where: {
        phone: parsed.data.phone,
        id: { not: userId }
      },
      select: { id: true }
    });
    if (phoneOwner) {
      res.status(409).json({ error: "phone_already_in_use" });
      return;
    }
  }

  if (parsed.data.email) {
    const emailOwner = await prisma.user.findFirst({
      where: {
        email: parsed.data.email,
        id: { not: userId }
      },
      select: { id: true }
    });
    if (emailOwner) {
      res.status(409).json({ error: "email_already_in_use" });
      return;
    }
  }

  const user = await prisma.user.update({
    where: { id: userId },
    data: {
      displayName: parsed.data.displayName,
      about: parsed.data.about,
      phone: parsed.data.phone,
      email: parsed.data.email
    },
    select: {
      id: true,
      displayName: true,
      phone: true,
      email: true,
      about: true,
      avatarUrl: true,
      createdAt: true,
      updatedAt: true
    }
  });

  res.json({ data: toProfileDto(req, user) });
});

profileRouter.get("/avatar/:userId", requireAuth, async (req, res) => {
  if (!isStorageConfigured()) {
    res.status(503).json({ error: "storage_not_configured" });
    return;
  }

  const rawUserId = req.params.userId;
  const userId = Array.isArray(rawUserId) ? rawUserId[0] : rawUserId;
  if (!userId) {
    res.status(400).json({ error: "user_id_required" });
    return;
  }

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { avatarUrl: true }
  });

  if (!user?.avatarUrl) {
    res.status(404).json({ error: "avatar_not_found" });
    return;
  }

  try {
    const object = await getObjectBytes(user.avatarUrl);
    res.setHeader("Cache-Control", "private, max-age=300");
    if (object.contentLength != null) {
      res.setHeader("Content-Length", String(object.contentLength));
    }
    res.contentType(object.contentType);
    res.send(Buffer.from(object.bytes));
  } catch (error) {
    logError("avatar fetch failed", error);
    res.status(404).json({ error: "avatar_not_found" });
  }
});

profileRouter.post("/avatar/upload-url", requireAuth, async (req, res) => {
  if (!isStorageConfigured()) {
    res.status(503).json({ error: "storage_not_configured" });
    return;
  }

  const parsed = avatarUploadInitSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const upload = await createAvatarUploadUrl({
    userId: req.authUserId!,
    contentType: parsed.data.contentType,
    fileName: parsed.data.fileName
  });

  res.json({
    data: {
      objectKey: upload.objectKey,
      uploadUrl: upload.uploadUrl,
      headers: upload.headers
    }
  });
});

profileRouter.post("/avatar/complete", requireAuth, async (req, res) => {
  if (!isStorageConfigured()) {
    res.status(503).json({ error: "storage_not_configured" });
    return;
  }

  const parsed = avatarUploadCompleteSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const userId = req.authUserId!;
  if (!isAvatarKeyOwnedByUser(userId, parsed.data.objectKey)) {
    res.status(403).json({ error: "invalid_avatar_key" });
    return;
  }

  try {
    await assertObjectExists(parsed.data.objectKey);
  } catch (error) {
    logError("avatar complete missing object", error);
    res.status(404).json({ error: "uploaded_file_not_found" });
    return;
  }

  const previousUser = await prisma.user.findUnique({
    where: { id: userId },
    select: { avatarUrl: true }
  });

  const user = await prisma.user.update({
    where: { id: userId },
    data: {
      avatarUrl: parsed.data.objectKey
    },
    select: {
      id: true,
      displayName: true,
      phone: true,
      email: true,
      about: true,
      avatarUrl: true,
      createdAt: true,
      updatedAt: true
    }
  });

  if (previousUser?.avatarUrl && previousUser.avatarUrl !== parsed.data.objectKey) {
    deleteObject(previousUser.avatarUrl).catch((error: unknown) => {
      logError("old avatar delete failed", error);
    });
  }

  res.json({ data: toProfileDto(req, user) });
});

profileRouter.delete("/avatar", requireAuth, async (req, res) => {
  const userId = req.authUserId!;
  const previousUser = await prisma.user.findUnique({
    where: { id: userId },
    select: { avatarUrl: true }
  });

  const user = await prisma.user.update({
    where: { id: userId },
    data: { avatarUrl: null },
    select: {
      id: true,
      displayName: true,
      phone: true,
      email: true,
      about: true,
      avatarUrl: true,
      createdAt: true,
      updatedAt: true
    }
  });

  if (previousUser?.avatarUrl && isStorageConfigured()) {
    deleteObject(previousUser.avatarUrl).catch((error: unknown) => {
      logError("avatar delete failed", error);
    });
  }

  res.json({ data: toProfileDto(req, user) });
});
