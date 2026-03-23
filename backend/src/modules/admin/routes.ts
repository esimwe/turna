import bcrypt from "bcryptjs";
import express, { Router } from "express";
import { z } from "zod";
import {
  ADMIN_ROLES,
  REPORT_STATUSES,
  REPORT_TARGET_TYPES,
  SMS_PROVIDERS,
  USER_ACCOUNT_STATUSES,
  type AdminRoleValue,
  type ReportStatusValue
} from "../../lib/admin-types.js";
import { env } from "../../config/env.js";
import { revokeAllAuthSessionsForUser } from "../../lib/auth-sessions.js";
import { signAdminAccessToken } from "../../lib/jwt.js";
import { logError } from "../../lib/logger.js";
import { prisma } from "../../lib/prisma.js";
import { redis } from "../../lib/redis.js";
import { createObjectReadUrl } from "../../lib/storage.js";
import { writeAdminAuditLog } from "../../lib/admin-audit.js";
import { requireAdminAuth, requireAdminRole } from "../../middleware/admin-auth.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";
import { buildPhoneLookupKeys } from "../profile/contact-lookup.js";
import { emitChatMessage, emitInboxUpdate } from "../chat/chat.realtime.js";
import {
  isExpressionPackValidationError,
  listAdminExpressionPacks,
  upsertAdminExpressionPack,
  updateAdminExpressionPackStatus,
  writeAdminExpressionPackArchive
} from "../chat/expression-packs.js";
import { chatService } from "../chat/chat.service.js";

export const adminRouter = Router();
const prismaUser = (prisma as unknown as { user: any }).user;
const prismaAdminUser = (prisma as unknown as { adminUser: any }).adminUser;
const prismaAuthSession = (prisma as unknown as { authSession: any }).authSession;
const prismaFeatureFlag = (prisma as unknown as { featureFlag: any }).featureFlag;
const prismaCountryPolicy = (prisma as unknown as { countryPolicy: any }).countryPolicy;
const prismaReportCase = (prisma as unknown as { reportCase: any }).reportCase;
const prismaAdminAuditLog = (prisma as unknown as { adminAuditLog: any }).adminAuditLog;
const prismaChatMember = (prisma as unknown as { chatMember: any }).chatMember;
const prismaMessage = (prisma as unknown as { message: any }).message;
const prismaMessageAttachment = (prisma as unknown as { messageAttachment: any }).messageAttachment;
const prismaUserContact = (prisma as unknown as { userContact: any }).userContact;

const adminLoginSchema = z.object({
  username: z.string().trim().min(3).max(64),
  password: z.string().min(8).max(255)
});

const listUsersQuerySchema = z.object({
  q: z.string().trim().min(1).max(120).optional(),
  status: z.enum(USER_ACCOUNT_STATUSES).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50)
});

const userIdParamSchema = z.object({
  userId: z.string().trim().min(1).max(255)
});

const reportIdParamSchema = z.object({
  reportId: z.string().trim().min(1).max(255)
});

const updateModerationSchema = z
  .object({
    accountStatus: z.enum(USER_ACCOUNT_STATUSES).optional(),
    accountStatusReason: z.string().trim().min(4).max(500).nullable().optional(),
    otpBlocked: z.boolean().optional(),
    sendRestricted: z.boolean().optional(),
    callRestricted: z.boolean().optional(),
    reason: z.string().trim().min(4).max(500)
  })
  .superRefine((value, ctx) => {
    if (
      value.accountStatus === undefined &&
      value.accountStatusReason === undefined &&
      value.otpBlocked === undefined &&
      value.sendRestricted === undefined &&
      value.callRestricted === undefined
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "at_least_one_field_required",
        path: ["reason"]
      });
    }
  });

const revokeSessionsSchema = z.object({
  reason: z.string().trim().min(4).max(500)
});

const listReportsQuerySchema = z.object({
  status: z.enum(REPORT_STATUSES).optional(),
  targetType: z.enum(REPORT_TARGET_TYPES).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50)
});

const updateReportSchema = z.object({
  status: z.enum(REPORT_STATUSES),
  resolutionNote: z.string().trim().min(4).max(1000).nullable().optional(),
  reason: z.string().trim().min(4).max(500)
});

const updateFeatureFlagSchema = z.object({
  enabled: z.boolean(),
  description: z.string().trim().min(1).max(240).nullable().optional(),
  metadata: z.record(z.string(), z.unknown()).nullable().optional(),
  reason: z.string().trim().min(4).max(500)
});

const featureFlagKeyParamSchema = z.object({
  key: z.string().trim().min(1).max(120)
});

const expressionPackParamSchema = z.object({
  packId: z.string().trim().min(1).max(120),
  version: z.string().trim().min(1).max(60)
});

const expressionPackItemSchema = z.object({
  id: z.string().trim().min(1).max(120),
  emoji: z.string().trim().min(1).max(32),
  label: z.string().trim().min(1).max(80),
  assetType: z.enum(["static_png", "static_webp", "animated_lottie", "video_webm"]),
  relativeAssetPath: z.string().trim().min(1).max(512),
  palette: z.array(z.string().trim().min(4).max(16)).max(2).optional().default([])
});

const upsertExpressionPackSchema = z.object({
  id: z.string().trim().min(1).max(120),
  title: z.string().trim().min(1).max(80),
  subtitle: z.string().trim().max(160).nullable().optional(),
  version: z.string().trim().min(1).max(60),
  isActive: z.boolean().optional().default(true),
  items: z.array(expressionPackItemSchema).min(1).max(200),
  reason: z.string().trim().min(4).max(500).optional()
});

const updateExpressionPackStatusSchema = z.object({
  isActive: z.boolean(),
  reason: z.string().trim().min(4).max(500).optional()
});

const countryPolicyParamSchema = z.object({
  countryIso: z
    .string()
    .trim()
    .min(2)
    .max(2)
    .transform((value) => value.toUpperCase())
});

const updateCountryPolicySchema = z
  .object({
    countryName: z.string().trim().min(2).max(120).optional(),
    dialCode: z.string().trim().min(2).max(10).nullable().optional(),
    isServiceEnabled: z.boolean().optional(),
    isSignupEnabled: z.boolean().optional(),
    isLoginEnabled: z.boolean().optional(),
    isOtpEnabled: z.boolean().optional(),
    isPhoneChangeEnabled: z.boolean().optional(),
    isMessagingEnabled: z.boolean().optional(),
    isCallingEnabled: z.boolean().optional(),
    isMediaUploadEnabled: z.boolean().optional(),
    smsProvider: z.enum(SMS_PROVIDERS).optional(),
    otpCooldownSeconds: z.coerce.number().int().min(15).max(300).nullable().optional(),
    otpTtlSeconds: z.coerce.number().int().min(30).max(900).nullable().optional(),
    otpPhoneLimit10m: z.coerce.number().int().min(1).max(50).nullable().optional(),
    otpPhoneLimit24h: z.coerce.number().int().min(1).max(200).nullable().optional(),
    otpIpLimit10m: z.coerce.number().int().min(1).max(100).nullable().optional(),
    otpIpLimit24h: z.coerce.number().int().min(1).max(500).nullable().optional(),
    notes: z.string().trim().min(4).max(1000).nullable().optional(),
    reason: z.string().trim().min(4).max(500)
  })
  .superRefine((value, ctx) => {
    const hasUpdatableField = Object.entries(value).some(([key, fieldValue]) => key !== "reason" && fieldValue !== undefined);
    if (!hasUpdatableField) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "at_least_one_field_required",
        path: ["reason"]
      });
    }
  });

const listAuditLogsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(100)
});

const listGenericQuerySchema = z.object({
  q: z.string().trim().min(1).max(120).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(100)
});

const listSessionsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(50)
});

const listChatsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(100)
});

const listMessagesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(100)
});

const chatIdParamSchema = z.object({
  chatId: z.string().trim().min(1).max(255)
});

const ADMIN_NOTICE_ICONS = [
  "lock",
  "info",
  "megaphone",
  "shield",
  "warning",
  "sparkles"
] as const;

const sendChatNoticeSchema = z.object({
  title: z.string().trim().min(1).max(80).nullable().optional(),
  text: z.string().trim().min(1).max(1000),
  icon: z.enum(ADMIN_NOTICE_ICONS).default("info"),
  silent: z.boolean().default(true),
  reason: z.string().trim().min(4).max(500).nullable().optional()
});

function summarizeMessage(row: {
  text?: string | null;
  attachments?: Array<{ kind?: string | null }>;
}): string {
  const text = row.text?.trim();
  if (text) return text;
  const firstKind = row.attachments?.[0]?.kind?.toUpperCase?.();
  if (!firstKind) return "Sohbet başlat";
  if ((row.attachments?.length ?? 0) > 1) return `${row.attachments?.length ?? 0} ek gönderildi`;
  if (firstKind === "IMAGE") return "Fotoğraf";
  if (firstKind === "VIDEO") return "Video";
  return "Dosya";
}

async function resolveAttachmentAdminPayload(attachment: {
  id: string;
  objectKey: string;
  kind: string;
  fileName: string | null;
  contentType: string;
  sizeBytes: number;
  width: number | null;
  height: number | null;
  durationSeconds: number | null;
  createdAt?: Date;
}) {
  let url: string | null = null;
  try {
    url = await createObjectReadUrl(attachment.objectKey);
  } catch (_) {
    url = null;
  }

  return {
    id: attachment.id,
    objectKey: attachment.objectKey,
    kind: attachment.kind.toLowerCase(),
    fileName: attachment.fileName,
    contentType: attachment.contentType,
    sizeBytes: attachment.sizeBytes,
    width: attachment.width,
    height: attachment.height,
    durationSeconds: attachment.durationSeconds,
    createdAt: attachment.createdAt?.toISOString?.() ?? null,
    url
  };
}

async function ensureBootstrapAdmin(): Promise<void> {
  if (!env.ADMIN_BOOTSTRAP_USERNAME || !env.ADMIN_BOOTSTRAP_PASSWORD) {
    return;
  }

  const adminCount = await prismaAdminUser.count();
  if (adminCount > 0) {
    return;
  }

  await prismaAdminUser.create({
    data: {
      username: env.ADMIN_BOOTSTRAP_USERNAME.trim().toLowerCase(),
      passwordHash: await bcrypt.hash(env.ADMIN_BOOTSTRAP_PASSWORD, 10),
      displayName: env.ADMIN_BOOTSTRAP_DISPLAY_NAME?.trim() || "Turna Admin",
      role: "SUPER_ADMIN"
    }
  });
}

function canMutateUser(role: AdminRoleValue): boolean {
  return ["SUPER_ADMIN", "OPS_ADMIN", "MODERATOR"].includes(role);
}

function canResolveReports(role: AdminRoleValue): boolean {
  return ["SUPER_ADMIN", "OPS_ADMIN", "MODERATOR", "SUPPORT_ADMIN"].includes(role);
}

function normalizeUsername(value: string): string {
  return value.trim().toLowerCase();
}

function resolveReportFinalState(status: ReportStatusValue): { resolvedAt: Date | null; resolvedByAdminId: string | null } {
  if (["ACTIONED", "REJECTED", "RESOLVED"].includes(status)) {
    return { resolvedAt: new Date(), resolvedByAdminId: null };
  }
  return { resolvedAt: null, resolvedByAdminId: null };
}

function toAdminUserSummary(
  req: Parameters<typeof buildAvatarUrl>[0],
  user: {
    id: string;
    displayName: string;
    username?: string | null;
    phone?: string | null;
    avatarUrl?: string | null;
    updatedAt?: Date | null;
  }
) {
  return {
    id: user.id,
    displayName: user.displayName,
    username: user.username ?? null,
    phone: user.phone ?? null,
    avatarUrl:
      user.avatarUrl && user.updatedAt ? buildAvatarUrl(req, user.id, user.updatedAt) : null
  };
}

adminRouter.post("/auth/login", async (req, res) => {
  const parsed = adminLoginSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  await ensureBootstrapAdmin();

  const admin = await prismaAdminUser.findUnique({
    where: { username: normalizeUsername(parsed.data.username) }
  });

  if (!admin || !admin.isActive) {
    res.status(401).json({ error: "invalid_admin_credentials" });
    return;
  }

  const ok = await bcrypt.compare(parsed.data.password, admin.passwordHash);
  if (!ok) {
    res.status(401).json({ error: "invalid_admin_credentials" });
    return;
  }

  await prismaAdminUser.update({
    where: { id: admin.id },
    data: { lastLoginAt: new Date() }
  });

  res.json({
    accessToken: signAdminAccessToken(admin.id, admin.role),
    admin: {
      id: admin.id,
      username: admin.username,
      displayName: admin.displayName,
      role: admin.role
    }
  });
});

adminRouter.get("/auth/me", requireAdminAuth, async (req, res) => {
  const admin = await prismaAdminUser.findUnique({
    where: { id: req.adminUserId! },
    select: {
      id: true,
      username: true,
      displayName: true,
      role: true,
      isActive: true,
      lastLoginAt: true,
      createdAt: true
    }
  });

  if (!admin) {
    res.status(404).json({ error: "admin_not_found" });
    return;
  }

  res.json({ data: admin });
});

adminRouter.get("/dashboard/summary", requireAdminAuth, async (_req, res) => {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const [
    totalUsers,
    suspendedUsers,
    bannedUsers,
    activeSessions,
    totalChats,
    messagesLast24h,
    callsLast24h,
    openReports,
    activeDeviceTokens,
    enabledFeatureFlags,
    countryPolicyCount
  ] = await prisma.$transaction([
    prismaUser.count(),
    prismaUser.count({ where: { accountStatus: "SUSPENDED" } }),
    prismaUser.count({ where: { accountStatus: "BANNED" } }),
    prismaAuthSession.count({ where: { revokedAt: null } }),
    prisma.chat.count(),
    prisma.message.count({ where: { createdAt: { gte: since } } }),
    prisma.call.count({ where: { createdAt: { gte: since } } }),
    prismaReportCase.count({ where: { status: { in: ["OPEN", "UNDER_REVIEW"] } } }),
    prisma.deviceToken.count({ where: { isActive: true } }),
    prismaFeatureFlag.count({ where: { enabled: true } }),
    prismaCountryPolicy.count()
  ]);

  res.json({
    data: {
      totalUsers,
      suspendedUsers,
      bannedUsers,
      activeUsers: totalUsers - suspendedUsers - bannedUsers,
      activeSessions,
      totalChats,
      messagesLast24h,
      callsLast24h,
      openReports,
      activeDeviceTokens,
      enabledFeatureFlags,
      countryPolicyCount
    }
  });
});

adminRouter.get("/feature-flags", requireAdminAuth, async (_req, res) => {
  const flags = await prismaFeatureFlag.findMany({
    orderBy: { key: "asc" }
  });

  res.json({ data: flags });
});

adminRouter.put(
  "/feature-flags/:key",
  requireAdminAuth,
  requireAdminRole("SUPER_ADMIN", "OPS_ADMIN"),
  async (req, res) => {
    const parsedParams = featureFlagKeyParamSchema.safeParse(req.params);
    const parsedBody = updateFeatureFlagSchema.safeParse(req.body);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
      return;
    }

    const flag = await prismaFeatureFlag.upsert({
      where: { key: parsedParams.data.key },
      update: {
        enabled: parsedBody.data.enabled,
        description:
          parsedBody.data.description !== undefined ? parsedBody.data.description : undefined,
        metadata: parsedBody.data.metadata !== undefined ? parsedBody.data.metadata : undefined,
        updatedByAdminId: req.adminUserId!
      },
      create: {
        key: parsedParams.data.key,
        enabled: parsedBody.data.enabled,
        description: parsedBody.data.description ?? null,
        metadata: parsedBody.data.metadata ?? null,
        updatedByAdminId: req.adminUserId!
      }
    });

    await writeAdminAuditLog({
      actorAdminId: req.adminUserId!,
      action: "feature_flag_upserted",
      targetType: "feature_flag",
      targetId: flag.key,
      reason: parsedBody.data.reason,
      metadata: {
        enabled: flag.enabled,
        description: flag.description
      }
    });

    res.json({ data: flag });
  }
);

adminRouter.get("/expression-packs", requireAdminAuth, async (_req, res) => {
  try {
    const data = await listAdminExpressionPacks();
    res.json({ data });
  } catch (error) {
    logError("admin expression packs fetch failed", error);
    res.status(500).json({ error: "failed_to_fetch_expression_packs" });
  }
});

adminRouter.post(
  "/expression-packs",
  requireAdminAuth,
  requireAdminRole("SUPER_ADMIN", "OPS_ADMIN"),
  async (req, res) => {
    const parsed = upsertExpressionPackSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
      return;
    }

    try {
      const pack = await upsertAdminExpressionPack({
        id: parsed.data.id,
        title: parsed.data.title,
        subtitle: parsed.data.subtitle,
        version: parsed.data.version,
        isActive: parsed.data.isActive,
        items: parsed.data.items
      });
      await writeAdminAuditLog({
        actorAdminId: req.adminUserId!,
        action: "expression_pack_upserted",
        targetType: "expression_pack",
        targetId: `${pack.id}@${pack.version}`,
        reason: parsed.data.reason ?? "Expression pack metadata guncellendi.",
        metadata: {
          isActive: pack.isActive,
          itemCount: pack.itemCount
        }
      });
      res.json({ data: pack });
    } catch (error) {
      if (isExpressionPackValidationError(error)) {
        res.status(400).json({ error: error.message });
        return;
      }
      logError("admin expression pack upsert failed", error);
      res.status(500).json({ error: "failed_to_upsert_expression_pack" });
    }
  }
);

adminRouter.put(
  "/expression-packs/:packId/:version/status",
  requireAdminAuth,
  requireAdminRole("SUPER_ADMIN", "OPS_ADMIN"),
  async (req, res) => {
    const parsedParams = expressionPackParamSchema.safeParse(req.params);
    const parsedBody = updateExpressionPackStatusSchema.safeParse(req.body);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
      return;
    }

    try {
      const pack = await updateAdminExpressionPackStatus({
        id: parsedParams.data.packId,
        version: parsedParams.data.version,
        isActive: parsedBody.data.isActive
      });
      await writeAdminAuditLog({
        actorAdminId: req.adminUserId!,
        action: "expression_pack_status_updated",
        targetType: "expression_pack",
        targetId: `${pack.id}@${pack.version}`,
        reason:
          parsedBody.data.reason ??
          (pack.isActive
            ? "Expression pack aktif edildi."
            : "Expression pack pasife alindi."),
        metadata: {
          isActive: pack.isActive
        }
      });
      res.json({ data: pack });
    } catch (error) {
      if (error instanceof Error && error.message === "expression_pack_not_found") {
        res.status(404).json({ error: error.message });
        return;
      }
      logError("admin expression pack status update failed", error);
      res.status(500).json({ error: "failed_to_update_expression_pack_status" });
    }
  }
);

adminRouter.put(
  "/expression-packs/:packId/:version/archive",
  requireAdminAuth,
  requireAdminRole("SUPER_ADMIN", "OPS_ADMIN"),
  express.raw({
    type: ["application/zip", "application/octet-stream", "application/x-zip-compressed"],
    limit: "64mb"
  }),
  async (req, res) => {
    const parsedParams = expressionPackParamSchema.safeParse(req.params);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      res.status(400).json({ error: "expression_pack_archive_required" });
      return;
    }

    try {
      const pack = await writeAdminExpressionPackArchive({
        id: parsedParams.data.packId,
        version: parsedParams.data.version,
        archiveBytes: req.body as Buffer
      });
      await writeAdminAuditLog({
        actorAdminId: req.adminUserId!,
        action: "expression_pack_archive_uploaded",
        targetType: "expression_pack",
        targetId: `${pack.id}@${pack.version}`,
        reason: "Expression pack zip arsivi yuklendi.",
        metadata: {
          archivePath: pack.archivePath,
          archiveSizeBytes: pack.archiveSizeBytes
        }
      });
      res.json({ data: pack });
    } catch (error) {
      if (error instanceof Error && error.message === "expression_pack_not_found") {
        res.status(404).json({ error: error.message });
        return;
      }
      if (isExpressionPackValidationError(error)) {
        res.status(400).json({ error: error.message });
        return;
      }
      logError("admin expression pack archive upload failed", error);
      res.status(500).json({ error: "failed_to_upload_expression_pack_archive" });
    }
  }
);

adminRouter.get("/country-policies", requireAdminAuth, async (_req, res) => {
  const policies = await prismaCountryPolicy.findMany({
    orderBy: [{ countryName: "asc" }, { countryIso: "asc" }]
  });

  res.json({ data: policies });
});

adminRouter.put(
  "/country-policies/:countryIso",
  requireAdminAuth,
  requireAdminRole("SUPER_ADMIN", "OPS_ADMIN"),
  async (req, res) => {
    const parsedParams = countryPolicyParamSchema.safeParse(req.params);
    const parsedBody = updateCountryPolicySchema.safeParse(req.body);
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
      return;
    }

    const existing = await prismaCountryPolicy.findUnique({
      where: { countryIso: parsedParams.data.countryIso }
    });

    if (!existing && !parsedBody.data.countryName) {
      res.status(400).json({ error: "country_name_required" });
      return;
    }

    const policy = await prismaCountryPolicy.upsert({
      where: { countryIso: parsedParams.data.countryIso },
      update: {
        countryName: parsedBody.data.countryName ?? undefined,
        dialCode: parsedBody.data.dialCode !== undefined ? parsedBody.data.dialCode : undefined,
        isServiceEnabled: parsedBody.data.isServiceEnabled ?? undefined,
        isSignupEnabled: parsedBody.data.isSignupEnabled ?? undefined,
        isLoginEnabled: parsedBody.data.isLoginEnabled ?? undefined,
        isOtpEnabled: parsedBody.data.isOtpEnabled ?? undefined,
        isPhoneChangeEnabled: parsedBody.data.isPhoneChangeEnabled ?? undefined,
        isMessagingEnabled: parsedBody.data.isMessagingEnabled ?? undefined,
        isCallingEnabled: parsedBody.data.isCallingEnabled ?? undefined,
        isMediaUploadEnabled: parsedBody.data.isMediaUploadEnabled ?? undefined,
        smsProvider: parsedBody.data.smsProvider ?? undefined,
        otpCooldownSeconds:
          parsedBody.data.otpCooldownSeconds !== undefined
            ? parsedBody.data.otpCooldownSeconds
            : undefined,
        otpTtlSeconds:
          parsedBody.data.otpTtlSeconds !== undefined ? parsedBody.data.otpTtlSeconds : undefined,
        otpPhoneLimit10m:
          parsedBody.data.otpPhoneLimit10m !== undefined
            ? parsedBody.data.otpPhoneLimit10m
            : undefined,
        otpPhoneLimit24h:
          parsedBody.data.otpPhoneLimit24h !== undefined
            ? parsedBody.data.otpPhoneLimit24h
            : undefined,
        otpIpLimit10m:
          parsedBody.data.otpIpLimit10m !== undefined ? parsedBody.data.otpIpLimit10m : undefined,
        otpIpLimit24h:
          parsedBody.data.otpIpLimit24h !== undefined ? parsedBody.data.otpIpLimit24h : undefined,
        notes: parsedBody.data.notes !== undefined ? parsedBody.data.notes : undefined,
        updatedByAdminId: req.adminUserId!
      },
      create: {
        countryIso: parsedParams.data.countryIso,
        countryName: parsedBody.data.countryName!,
        dialCode: parsedBody.data.dialCode ?? null,
        isServiceEnabled: parsedBody.data.isServiceEnabled ?? true,
        isSignupEnabled: parsedBody.data.isSignupEnabled ?? true,
        isLoginEnabled: parsedBody.data.isLoginEnabled ?? true,
        isOtpEnabled: parsedBody.data.isOtpEnabled ?? true,
        isPhoneChangeEnabled: parsedBody.data.isPhoneChangeEnabled ?? true,
        isMessagingEnabled: parsedBody.data.isMessagingEnabled ?? true,
        isCallingEnabled: parsedBody.data.isCallingEnabled ?? true,
        isMediaUploadEnabled: parsedBody.data.isMediaUploadEnabled ?? true,
        smsProvider: parsedBody.data.smsProvider ?? "NETGSM_BULK",
        otpCooldownSeconds: parsedBody.data.otpCooldownSeconds ?? null,
        otpTtlSeconds: parsedBody.data.otpTtlSeconds ?? null,
        otpPhoneLimit10m: parsedBody.data.otpPhoneLimit10m ?? null,
        otpPhoneLimit24h: parsedBody.data.otpPhoneLimit24h ?? null,
        otpIpLimit10m: parsedBody.data.otpIpLimit10m ?? null,
        otpIpLimit24h: parsedBody.data.otpIpLimit24h ?? null,
        notes: parsedBody.data.notes ?? null,
        updatedByAdminId: req.adminUserId!
      }
    });

    await writeAdminAuditLog({
      actorAdminId: req.adminUserId!,
      action: "country_policy_upserted",
      targetType: "country_policy",
      targetId: policy.countryIso,
      reason: parsedBody.data.reason,
      metadata: {
        countryName: policy.countryName,
        isServiceEnabled: policy.isServiceEnabled,
        isOtpEnabled: policy.isOtpEnabled,
        smsProvider: policy.smsProvider
      }
    });

    res.json({ data: policy });
  }
);

adminRouter.get("/users", requireAdminAuth, async (req, res) => {
  const parsed = listUsersQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const search = parsed.data.q?.trim();
  const users = await prismaUser.findMany({
    where: {
      accountStatus: parsed.data.status,
      ...(search
        ? {
            OR: [
              { displayName: { contains: search, mode: "insensitive" } },
              { username: { contains: search, mode: "insensitive" } },
              { phone: { contains: search, mode: "insensitive" } },
              { email: { contains: search, mode: "insensitive" } }
            ]
          }
        : {})
    },
    orderBy: { createdAt: "desc" },
    take: parsed.data.limit,
    select: {
      id: true,
      username: true,
      displayName: true,
      phone: true,
      email: true,
      avatarUrl: true,
      accountStatus: true,
      accountStatusReason: true,
      otpBlocked: true,
      sendRestricted: true,
      callRestricted: true,
      createdAt: true,
      lastSeenAt: true,
      updatedAt: true
    }
  });

  res.json({
    data: users.map((user: any) => ({
      ...user,
      avatarUrl:
        user.avatarUrl && user.updatedAt
          ? buildAvatarUrl(req, user.id, user.updatedAt)
          : null
    }))
  });
});

adminRouter.get("/users/:userId", requireAdminAuth, async (req, res) => {
  const parsed = userIdParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const user = await prismaUser.findUnique({
    where: { id: parsed.data.userId },
    select: {
      id: true,
      username: true,
      displayName: true,
      phone: true,
      email: true,
      about: true,
      avatarUrl: true,
      accountStatus: true,
      accountStatusReason: true,
      otpBlocked: true,
      sendRestricted: true,
      callRestricted: true,
      onboardingCompletedAt: true,
      createdAt: true,
      updatedAt: true,
      lastSeenAt: true,
      _count: {
        select: {
          memberships: true,
          messages: true,
          devices: true,
          authSessions: true,
          submittedReports: true,
          reportsAgainst: true
        }
      }
    }
  });

  if (!user) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  const activeSessionCount = await prismaAuthSession.count({
    where: {
      userId: user.id,
      revokedAt: null
    }
  });

  const latestSession = await prismaAuthSession.findFirst({
    where: {
      userId: user.id
    },
    orderBy: {
      createdAt: "desc"
    },
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
      lastSeenAt: true,
      revokedAt: true,
      revokeReason: true
    }
  });

  res.json({
    data: {
      ...user,
      avatarUrl:
        user.avatarUrl && user.updatedAt
          ? buildAvatarUrl(req, user.id, user.updatedAt)
          : null,
      activeSessionCount,
      latestSession
    }
  });
});

adminRouter.get("/users/:userId/sessions", requireAdminAuth, async (req, res) => {
  const parsedParams = userIdParamSchema.safeParse(req.params);
  const parsedQuery = listSessionsQuerySchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedParams.error.flatten()
    });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedQuery.error.flatten()
    });
    return;
  }

  const sessions = await prismaAuthSession.findMany({
    where: { userId: parsedParams.data.userId },
    orderBy: [{ revokedAt: "asc" }, { createdAt: "desc" }],
    take: parsedQuery.data.limit,
    select: {
      id: true,
      deviceId: true,
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
      lastSeenAt: true,
      revokedAt: true,
      revokeReason: true
    }
  });

  res.json({ data: sessions });
});

adminRouter.get("/users/:userId/chats", requireAdminAuth, async (req, res) => {
  const parsedParams = userIdParamSchema.safeParse(req.params);
  const parsedQuery = listChatsQuerySchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedParams.error.flatten()
    });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedQuery.error.flatten()
    });
    return;
  }

  const memberships = await prismaChatMember.findMany({
    where: { userId: parsedParams.data.userId },
    orderBy: { joinedAt: "desc" },
    take: parsedQuery.data.limit,
    include: {
      folder: {
        select: {
          id: true,
          name: true
        }
      },
      chat: {
        select: {
          id: true,
          type: true,
          createdAt: true,
          members: {
            select: {
              userId: true,
              user: {
                select: {
                  id: true,
                  displayName: true,
                  username: true,
                  phone: true,
                  avatarUrl: true,
                  updatedAt: true
                }
              }
            }
          },
          messages: {
            take: 1,
            orderBy: { createdAt: "desc" },
            select: {
              id: true,
              text: true,
              createdAt: true,
              senderId: true,
              attachments: {
                select: {
                  kind: true
                }
              }
            }
          }
        }
      }
    }
  });

  res.json({
    data: memberships.map((membership: any) => {
      const peers = (membership.chat?.members ?? [])
        .filter((member: any) => member.userId !== parsedParams.data.userId)
        .map((member: any) => ({
          id: member.user.id,
          displayName: member.user.displayName,
          username: member.user.username,
          phone: member.user.phone,
          avatarUrl:
            member.user.avatarUrl && member.user.updatedAt
              ? buildAvatarUrl(req, member.user.id, member.user.updatedAt)
              : null
        }));
      const lastMessage = membership.chat?.messages?.[0] ?? null;

      return {
        chatId: membership.chatId,
        type: membership.chat?.type?.toLowerCase?.() ?? "direct",
        createdAt: membership.chat?.createdAt?.toISOString?.() ?? null,
        joinedAt: membership.joinedAt?.toISOString?.() ?? null,
        hiddenAt: membership.hiddenAt?.toISOString?.() ?? null,
        clearedAt: membership.clearedAt?.toISOString?.() ?? null,
        archivedAt: membership.archivedAt?.toISOString?.() ?? null,
        muted: membership.muted === true,
        folderId: membership.folderId ?? null,
        folderName: membership.folder?.name ?? null,
        peers,
        lastMessage: lastMessage
          ? {
              id: lastMessage.id,
              senderId: lastMessage.senderId,
              text: summarizeMessage(lastMessage),
              createdAt: lastMessage.createdAt.toISOString()
            }
          : null
      };
    })
  });
});

adminRouter.get("/chats/:chatId/messages", requireAdminAuth, async (req, res) => {
  const parsedParams = chatIdParamSchema.safeParse(req.params);
  const parsedQuery = listMessagesQuerySchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedParams.error.flatten()
    });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedQuery.error.flatten()
    });
    return;
  }

  const messages = await prismaMessage.findMany({
    where: { chatId: parsedParams.data.chatId },
    orderBy: { createdAt: "desc" },
    take: parsedQuery.data.limit,
    include: {
      sender: {
        select: {
          id: true,
          displayName: true,
          username: true,
          phone: true,
          avatarUrl: true,
          updatedAt: true
        }
      },
      attachments: {
        orderBy: { createdAt: "asc" }
      }
    }
  });

  const items = await Promise.all(
    messages
      .reverse()
      .map(async (message: any) => ({
        id: message.id,
        chatId: message.chatId,
        sender: {
          id: message.sender.id,
          displayName: message.sender.displayName,
          username: message.sender.username,
          phone: message.sender.phone,
          avatarUrl:
            message.sender.avatarUrl && message.sender.updatedAt
              ? buildAvatarUrl(req, message.sender.id, message.sender.updatedAt)
              : null
        },
        text: message.text,
        systemType: message.systemType ?? null,
        systemPayload:
          message.systemPayload && typeof message.systemPayload === "object"
            ? message.systemPayload
            : null,
        status: message.status,
        createdAt: message.createdAt.toISOString(),
        readAt: message.readAt?.toISOString?.() ?? null,
        editedAt: message.editedAt?.toISOString?.() ?? null,
        editCount: message.editCount ?? 0,
        isEdited: message.editedAt != null,
        attachments: await Promise.all(
          (message.attachments ?? []).map((attachment: any) =>
            resolveAttachmentAdminPayload(attachment)
          )
        )
      }))
  );

  res.json({ data: items });
});

adminRouter.post(
  "/chats/:chatId/notice",
  requireAdminAuth,
  requireAdminRole("SUPER_ADMIN", "OPS_ADMIN", "SUPPORT_ADMIN", "MODERATOR"),
  async (req, res) => {
    const parsedParams = chatIdParamSchema.safeParse(req.params);
    const parsedBody = sendChatNoticeSchema.safeParse(req.body);
    if (!parsedParams.success) {
      res.status(400).json({
        error: "validation_error",
        details: parsedParams.error.flatten()
      });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({
        error: "validation_error",
        details: parsedBody.error.flatten()
      });
      return;
    }

    const admin = await prismaAdminUser.findUnique({
      where: { id: req.adminUserId! },
      select: {
        id: true,
        displayName: true,
        role: true
      }
    });
    if (!admin) {
      res.status(404).json({ error: "admin_not_found" });
      return;
    }

    try {
      const result = await chatService.createAdminNotice({
        chatId: parsedParams.data.chatId,
        title: parsedBody.data.title ?? null,
        text: parsedBody.data.text,
        icon: parsedBody.data.icon,
        silent: parsedBody.data.silent,
        createdByAdminId: admin.id,
        createdByAdminRole: admin.role,
        createdByAdminDisplayName: admin.displayName
      });

      emitChatMessage(parsedParams.data.chatId, result.message, result.participantIds);
      if (!parsedBody.data.silent) {
        emitInboxUpdate(result.participantIds);
      }

      await writeAdminAuditLog({
        actorAdminId: req.adminUserId!,
        action: "chat_notice_sent",
        targetType: "chat",
        targetId: parsedParams.data.chatId,
        reason: parsedBody.data.reason ?? "Sohbet içi bilgi notu gönderildi.",
        metadata: {
          icon: parsedBody.data.icon,
          title: parsedBody.data.title ?? null,
          silent: parsedBody.data.silent
        }
      });

      res.status(201).json({
        data: {
          message: result.message,
          participantCount: result.participantIds.length
        }
      });
    } catch (error) {
      if (error instanceof Error) {
        switch (error.message) {
          case "chat_not_found":
            res.status(404).json({ error: error.message });
            return;
          case "chat_has_no_members":
          case "admin_notice_text_required":
            res.status(400).json({ error: error.message });
            return;
        }
      }

      logError("admin chat notice failed", error);
      res.status(500).json({ error: "failed_to_send_chat_notice" });
    }
  }
);

adminRouter.get("/users/:userId/media", requireAdminAuth, async (req, res) => {
  const parsedParams = userIdParamSchema.safeParse(req.params);
  const parsedQuery = listMessagesQuerySchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedParams.error.flatten()
    });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({
      error: "validation_error",
      details: parsedQuery.error.flatten()
    });
    return;
  }

  const attachments = await prismaMessageAttachment.findMany({
    where: {
      message: {
        chat: {
          members: {
            some: {
              userId: parsedParams.data.userId
            }
          }
        }
      }
    },
    orderBy: { createdAt: "desc" },
    take: parsedQuery.data.limit,
    include: {
      message: {
        select: {
          id: true,
          chatId: true,
          senderId: true,
          text: true,
          createdAt: true,
          sender: {
            select: {
              id: true,
              displayName: true,
              username: true,
              phone: true,
              avatarUrl: true,
              updatedAt: true
            }
          }
        }
      }
    }
  });

  const items = await Promise.all(
    attachments.map(async (attachment: any) => ({
      ...(await resolveAttachmentAdminPayload(attachment)),
      messageId: attachment.message.id,
      chatId: attachment.message.chatId,
      senderId: attachment.message.senderId,
      isOutgoing: attachment.message.senderId === parsedParams.data.userId,
      sender: attachment.message.sender
        ? {
            id: attachment.message.sender.id,
            displayName: attachment.message.sender.displayName,
            username: attachment.message.sender.username,
            phone: attachment.message.sender.phone,
            avatarUrl:
              attachment.message.sender.avatarUrl && attachment.message.sender.updatedAt
                ? buildAvatarUrl(req, attachment.message.sender.id, attachment.message.sender.updatedAt)
                : null
          }
        : null,
      messageText: attachment.message.text,
      messageCreatedAt: attachment.message.createdAt.toISOString()
    }))
  );

  res.json({ data: items });
});

adminRouter.put("/users/:userId/moderation", requireAdminAuth, async (req, res) => {
  if (!req.adminRole || !canMutateUser(req.adminRole)) {
    res.status(403).json({ error: "admin_forbidden" });
    return;
  }

  const parsedParams = userIdParamSchema.safeParse(req.params);
  const parsedBody = updateModerationSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  const user = await prismaUser.findUnique({
    where: { id: parsedParams.data.userId },
    select: { id: true, accountStatus: true }
  });

  if (!user) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  const updated = await prismaUser.update({
    where: { id: parsedParams.data.userId },
    data: {
      accountStatus: parsedBody.data.accountStatus ?? undefined,
      accountStatusReason:
        parsedBody.data.accountStatusReason !== undefined
          ? parsedBody.data.accountStatusReason
          : parsedBody.data.accountStatus === "ACTIVE"
            ? null
            : undefined,
      otpBlocked: parsedBody.data.otpBlocked ?? undefined,
      sendRestricted: parsedBody.data.sendRestricted ?? undefined,
      callRestricted: parsedBody.data.callRestricted ?? undefined
    },
    select: {
      id: true,
      accountStatus: true,
      accountStatusReason: true,
      otpBlocked: true,
      sendRestricted: true,
      callRestricted: true
    }
  });

  let revokedSessionCount = 0;
  if (updated.accountStatus !== "ACTIVE") {
    revokedSessionCount = await revokeAllAuthSessionsForUser(updated.id, updated.accountStatus.toLowerCase());
  }

  await writeAdminAuditLog({
    actorAdminId: req.adminUserId!,
    action: "user_moderation_updated",
    targetType: "user",
    targetId: updated.id,
    reason: parsedBody.data.reason,
    metadata: {
      accountStatus: updated.accountStatus,
      otpBlocked: updated.otpBlocked,
      sendRestricted: updated.sendRestricted,
      callRestricted: updated.callRestricted,
      revokedSessionCount
    }
  });

  res.json({
    data: {
      ...updated,
      revokedSessionCount
    }
  });
});

adminRouter.post("/users/:userId/revoke-sessions", requireAdminAuth, async (req, res) => {
  if (!req.adminRole || !canMutateUser(req.adminRole)) {
    res.status(403).json({ error: "admin_forbidden" });
    return;
  }

  const parsedParams = userIdParamSchema.safeParse(req.params);
  const parsedBody = revokeSessionsSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  const user = await prismaUser.findUnique({
    where: { id: parsedParams.data.userId },
    select: { id: true }
  });

  if (!user) {
    res.status(404).json({ error: "user_not_found" });
    return;
  }

  const revokedSessionCount = await revokeAllAuthSessionsForUser(user.id, parsedBody.data.reason);

  await writeAdminAuditLog({
    actorAdminId: req.adminUserId!,
    action: "user_sessions_revoked",
    targetType: "user",
    targetId: user.id,
    reason: parsedBody.data.reason,
    metadata: {
      revokedSessionCount
    }
  });

  res.json({
    data: {
      revokedSessionCount
    }
  });
});

adminRouter.get("/reports", requireAdminAuth, async (req, res) => {
  const parsed = listReportsQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const reports = await prismaReportCase.findMany({
    where: {
      status: parsed.data.status,
      targetType: parsed.data.targetType
    },
    orderBy: { createdAt: "desc" },
    take: parsed.data.limit,
    include: {
      reporterUser: {
        select: {
          id: true,
          displayName: true,
          phone: true
        }
      },
      reportedUser: {
        select: {
          id: true,
          displayName: true,
          phone: true
        }
      },
      message: {
        select: {
          id: true,
          chatId: true,
          text: true,
          createdAt: true,
          sender: {
            select: {
              id: true,
              displayName: true,
              phone: true
            }
          }
        }
      },
      resolvedByAdmin: {
        select: {
          id: true,
          displayName: true,
          role: true
        }
      }
    }
  });

  res.json({ data: reports });
});

adminRouter.put("/reports/:reportId", requireAdminAuth, async (req, res) => {
  if (!req.adminRole || !canResolveReports(req.adminRole)) {
    res.status(403).json({ error: "admin_forbidden" });
    return;
  }

  const parsedParams = reportIdParamSchema.safeParse(req.params);
  const parsedBody = updateReportSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  const existing = await prismaReportCase.findUnique({
    where: { id: parsedParams.data.reportId },
    select: { id: true }
  });

  if (!existing) {
    res.status(404).json({ error: "report_not_found" });
    return;
  }

  const finalState = resolveReportFinalState(parsedBody.data.status);
  const report = await prismaReportCase.update({
    where: { id: parsedParams.data.reportId },
    data: {
      status: parsedBody.data.status,
      resolutionNote:
        parsedBody.data.resolutionNote !== undefined ? parsedBody.data.resolutionNote : undefined,
      resolvedAt: finalState.resolvedAt,
      resolvedByAdminId: finalState.resolvedAt ? req.adminUserId! : null
    }
  });

  await writeAdminAuditLog({
    actorAdminId: req.adminUserId!,
    action: "report_updated",
    targetType: "report",
    targetId: report.id,
    reason: parsedBody.data.reason,
    metadata: {
      status: report.status,
      resolvedAt: report.resolvedAt
    }
  });

  res.json({ data: report });
});

adminRouter.get("/audit-logs", requireAdminAuth, async (req, res) => {
  const parsed = listAuditLogsQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const logs = await prismaAdminAuditLog.findMany({
    orderBy: { createdAt: "desc" },
    take: parsed.data.limit,
    include: {
      actorAdmin: {
        select: {
          id: true,
          displayName: true,
          role: true
        }
      }
    }
  });

  res.json({ data: logs });
});

adminRouter.get("/contacts", requireAdminAuth, async (req, res) => {
  const parsed = listGenericQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const search = parsed.data.q?.trim();
  const contacts = await prismaUserContact.findMany({
    where: search
      ? {
          OR: [
            { displayName: { contains: search, mode: "insensitive" } },
            { lookupKey: { contains: search } },
            { owner: { displayName: { contains: search, mode: "insensitive" } } },
            { owner: { username: { contains: search, mode: "insensitive" } } },
            { owner: { phone: { contains: search, mode: "insensitive" } } }
          ]
        }
      : undefined,
    orderBy: { updatedAt: "desc" },
    take: parsed.data.limit,
    include: {
      owner: {
        select: {
          id: true,
          displayName: true,
          username: true,
          phone: true,
          avatarUrl: true,
          updatedAt: true
        }
      }
    }
  });

  const users = await prismaUser.findMany({
    where: { phone: { not: null } },
    select: {
      id: true,
      displayName: true,
      username: true,
      phone: true,
      avatarUrl: true,
      updatedAt: true
    }
  });

  const usersByLookupKey = new Map<string, any>();
  for (const user of users) {
    for (const key of buildPhoneLookupKeys(user.phone)) {
      if (!usersByLookupKey.has(key)) {
        usersByLookupKey.set(key, user);
      }
    }
  }

  res.json({
    data: contacts.map((contact: any) => {
      const matchedUser = usersByLookupKey.get(contact.lookupKey) ?? null;
      return {
        id: contact.id,
        displayName: contact.displayName,
        lookupKey: contact.lookupKey,
        createdAt: contact.createdAt.toISOString(),
        updatedAt: contact.updatedAt.toISOString(),
        owner: toAdminUserSummary(req, contact.owner),
        matchedUser: matchedUser ? toAdminUserSummary(req, matchedUser) : null
      };
    })
  });
});

adminRouter.get("/chats", requireAdminAuth, async (req, res) => {
  const parsed = listGenericQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const chats = await prisma.chat.findMany({
    orderBy: { createdAt: "desc" },
    take: parsed.data.limit,
    include: {
      members: {
        select: {
          userId: true,
          user: {
            select: {
              id: true,
              displayName: true,
              username: true,
              phone: true,
              avatarUrl: true,
              updatedAt: true
            }
          }
        }
      },
      messages: {
        take: 1,
        orderBy: { createdAt: "desc" },
        select: {
          id: true,
          text: true,
          createdAt: true,
          senderId: true,
          attachments: {
            select: { kind: true }
          }
        }
      }
    }
  });

  res.json({
    data: chats.map((chat: any) => ({
      id: chat.id,
      type: chat.type.toLowerCase(),
      createdAt: chat.createdAt.toISOString(),
      memberCount: chat.members.length,
      members: chat.members.map((member: any) => toAdminUserSummary(req, member.user)),
      lastMessage: chat.messages[0]
        ? {
            id: chat.messages[0].id,
            senderId: chat.messages[0].senderId,
            text: summarizeMessage(chat.messages[0]),
            createdAt: chat.messages[0].createdAt.toISOString()
          }
        : null
    }))
  });
});

adminRouter.get("/messages", requireAdminAuth, async (req, res) => {
  const parsed = listGenericQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const search = parsed.data.q?.trim();
  const messages = await prismaMessage.findMany({
    where: search
      ? {
          OR: [
            { text: { contains: search, mode: "insensitive" } },
            { sender: { displayName: { contains: search, mode: "insensitive" } } },
            { sender: { username: { contains: search, mode: "insensitive" } } },
            { sender: { phone: { contains: search, mode: "insensitive" } } }
          ]
        }
      : undefined,
    orderBy: { createdAt: "desc" },
    take: parsed.data.limit,
    include: {
      sender: {
        select: {
          id: true,
          displayName: true,
          username: true,
          phone: true,
          avatarUrl: true,
          updatedAt: true
        }
      },
      attachments: {
        orderBy: { createdAt: "asc" }
      }
    }
  });

  const items = await Promise.all(
    messages.map(async (message: any) => ({
      id: message.id,
      chatId: message.chatId,
        text: message.text,
        systemType: message.systemType ?? null,
        systemPayload:
          message.systemPayload && typeof message.systemPayload === "object"
            ? message.systemPayload
            : null,
        status: message.status,
        createdAt: message.createdAt.toISOString(),
      editedAt: message.editedAt?.toISOString?.() ?? null,
      editCount: message.editCount ?? 0,
      sender: toAdminUserSummary(req, message.sender),
      attachmentCount: message.attachments.length,
      attachmentKinds: message.attachments.map((attachment: any) => attachment.kind.toLowerCase()),
      attachments: await Promise.all(
        (message.attachments ?? []).map((attachment: any) =>
          resolveAttachmentAdminPayload(attachment)
        )
      )
    }))
  );

  res.json({ data: items });
});

adminRouter.get("/media", requireAdminAuth, async (req, res) => {
  const parsed = listGenericQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const search = parsed.data.q?.trim();
  const attachments = await prismaMessageAttachment.findMany({
    where: search
      ? {
          OR: [
            { fileName: { contains: search, mode: "insensitive" } },
            { objectKey: { contains: search, mode: "insensitive" } },
            { message: { sender: { displayName: { contains: search, mode: "insensitive" } } } },
            { message: { sender: { username: { contains: search, mode: "insensitive" } } } },
            { message: { sender: { phone: { contains: search, mode: "insensitive" } } } }
          ]
        }
      : undefined,
    orderBy: { createdAt: "desc" },
    take: parsed.data.limit,
    include: {
      message: {
        select: {
          id: true,
          chatId: true,
          text: true,
          createdAt: true,
          sender: {
            select: {
              id: true,
              displayName: true,
              username: true,
              phone: true,
              avatarUrl: true,
              updatedAt: true
            }
          }
        }
      }
    }
  });

  const items = await Promise.all(
    attachments.map(async (attachment: any) => ({
      ...(await resolveAttachmentAdminPayload(attachment)),
      messageId: attachment.message.id,
      chatId: attachment.message.chatId,
      messageText: attachment.message.text,
      messageCreatedAt: attachment.message.createdAt.toISOString(),
      sender: toAdminUserSummary(req, attachment.message.sender)
    }))
  );

  res.json({ data: items });
});

adminRouter.get("/sessions", requireAdminAuth, async (req, res) => {
  const parsed = listGenericQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const search = parsed.data.q?.trim();
  const sessions = await prismaAuthSession.findMany({
    where: search
      ? {
          OR: [
            { user: { displayName: { contains: search, mode: "insensitive" } } },
            { user: { username: { contains: search, mode: "insensitive" } } },
            { user: { phone: { contains: search, mode: "insensitive" } } },
            { deviceModel: { contains: search, mode: "insensitive" } },
            { ipAddress: { contains: search, mode: "insensitive" } }
          ]
        }
      : undefined,
    orderBy: { lastSeenAt: "desc" },
    take: parsed.data.limit,
    include: {
      user: {
        select: {
          id: true,
          displayName: true,
          username: true,
          phone: true,
          avatarUrl: true,
          updatedAt: true
        }
      }
    }
  });

  res.json({
    data: sessions.map((session: any) => ({
      id: session.id,
      user: toAdminUserSummary(req, session.user),
      deviceId: session.deviceId,
      platform: session.platform,
      deviceModel: session.deviceModel,
      osVersion: session.osVersion,
      appVersion: session.appVersion,
      localeTag: session.localeTag,
      regionCode: session.regionCode,
      connectionType: session.connectionType,
      countryIso: session.countryIso,
      ipCountryIso: session.ipCountryIso,
      ipAddress: session.ipAddress,
      userAgent: session.userAgent,
      createdAt: session.createdAt.toISOString(),
      lastSeenAt: session.lastSeenAt.toISOString(),
      revokedAt: session.revokedAt?.toISOString?.() ?? null,
      revokeReason: session.revokeReason ?? null
    }))
  });
});

adminRouter.get("/calls", requireAdminAuth, async (req, res) => {
  const parsed = listGenericQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const search = parsed.data.q?.trim();
  const calls = await prisma.call.findMany({
    where: search
      ? {
          OR: [
            { caller: { displayName: { contains: search, mode: "insensitive" } } },
            { caller: { username: { contains: search, mode: "insensitive" } } },
            { caller: { phone: { contains: search, mode: "insensitive" } } },
            { callee: { displayName: { contains: search, mode: "insensitive" } } },
            { callee: { username: { contains: search, mode: "insensitive" } } },
            { callee: { phone: { contains: search, mode: "insensitive" } } }
          ]
        }
      : undefined,
    orderBy: { createdAt: "desc" },
    take: parsed.data.limit,
    include: {
      caller: {
        select: {
          id: true,
          displayName: true,
          username: true,
          phone: true,
          avatarUrl: true,
          updatedAt: true
        }
      },
      callee: {
        select: {
          id: true,
          displayName: true,
          username: true,
          phone: true,
          avatarUrl: true,
          updatedAt: true
        }
      }
    }
  });

  res.json({
    data: calls.map((call: any) => ({
      id: call.id,
      type: call.type.toLowerCase(),
      status: call.status.toLowerCase(),
      provider: call.provider.toLowerCase(),
      createdAt: call.createdAt.toISOString(),
      acceptedAt: call.acceptedAt?.toISOString?.() ?? null,
      endedAt: call.endedAt?.toISOString?.() ?? null,
      caller: toAdminUserSummary(req, call.caller),
      callee: toAdminUserSummary(req, call.callee)
    }))
  });
});

adminRouter.get("/push/devices", requireAdminAuth, async (req, res) => {
  const parsed = listGenericQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const search = parsed.data.q?.trim();
  const devices = await prisma.deviceToken.findMany({
    where: search
      ? {
          OR: [
            { user: { displayName: { contains: search, mode: "insensitive" } } },
            { user: { username: { contains: search, mode: "insensitive" } } },
            { user: { phone: { contains: search, mode: "insensitive" } } },
            { deviceLabel: { contains: search, mode: "insensitive" } },
            { token: { contains: search, mode: "insensitive" } }
          ]
        }
      : undefined,
    orderBy: { updatedAt: "desc" },
    take: parsed.data.limit,
    include: {
      user: {
        select: {
          id: true,
          displayName: true,
          username: true,
          phone: true,
          avatarUrl: true,
          updatedAt: true
        }
      }
    }
  });

  res.json({
    data: devices.map((device: any) => ({
      id: device.id,
      user: toAdminUserSummary(req, device.user),
      platform: device.platform.toLowerCase(),
      tokenKind: device.tokenKind.toLowerCase(),
      deviceLabel: device.deviceLabel ?? null,
      isActive: device.isActive,
      createdAt: device.createdAt.toISOString(),
      updatedAt: device.updatedAt.toISOString(),
      tokenPreview: `${String(device.token).slice(0, 12)}...`
    }))
  });
});

adminRouter.get("/otp/settings", requireAdminAuth, async (_req, res) => {
  const [otpLoginFlag, phoneChangeFlag] = await Promise.all([
    prismaFeatureFlag.findUnique({ where: { key: "otp_login_enabled" } }),
    prismaFeatureFlag.findUnique({ where: { key: "phone_change_enabled" } })
  ]);

  res.json({
    data: {
      provider: env.SMS_PROVIDER,
      fixedOtpCodeEnabled: Boolean(env.FIXED_OTP_CODE),
      ttlSeconds: env.OTP_TTL_SECONDS,
      resendCooldownSeconds: env.OTP_RESEND_COOLDOWN_SECONDS,
      maxAttempts: env.OTP_MAX_ATTEMPTS,
      phoneLimit10m: env.OTP_PHONE_LIMIT_10M,
      phoneLimit24h: env.OTP_PHONE_LIMIT_24H,
      ipLimit10m: env.OTP_IP_LIMIT_10M,
      ipLimit24h: env.OTP_IP_LIMIT_24H,
      otpLoginEnabled: otpLoginFlag?.enabled ?? true,
      phoneChangeEnabled: phoneChangeFlag?.enabled ?? true
    }
  });
});

adminRouter.get("/admins", requireAdminAuth, requireAdminRole("SUPER_ADMIN", "OPS_ADMIN"), async (req, res) => {
  const parsed = listGenericQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const search = parsed.data.q?.trim();
  const admins = await prismaAdminUser.findMany({
    where: search
      ? {
          OR: [
            { username: { contains: search, mode: "insensitive" } },
            { displayName: { contains: search, mode: "insensitive" } }
          ]
        }
      : undefined,
    orderBy: { createdAt: "desc" },
    take: parsed.data.limit,
    select: {
      id: true,
      username: true,
      displayName: true,
      role: true,
      isActive: true,
      lastLoginAt: true,
      createdAt: true
    }
  });

  res.json({ data: admins });
});

adminRouter.get("/system/health", requireAdminAuth, async (_req, res) => {
  let redisStatus = "disconnected";
  let databaseStatus = "disconnected";

  try {
    const pong = await redis.ping();
    redisStatus = pong === "PONG" ? "ok" : "unexpected";
  } catch (_) {
    redisStatus = "error";
  }

  try {
    await prisma.$queryRaw`SELECT 1`;
    databaseStatus = "ok";
  } catch (_) {
    databaseStatus = "error";
  }

  res.json({
    data: {
      nodeVersion: process.version,
      environment: env.NODE_ENV,
      uptimeSeconds: Math.floor(process.uptime()),
      smsProvider: env.SMS_PROVIDER,
      fixedOtpCodeEnabled: Boolean(env.FIXED_OTP_CODE),
      databaseStatus,
      redisStatus
    }
  });
});
