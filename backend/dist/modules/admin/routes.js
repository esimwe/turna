import bcrypt from "bcryptjs";
import { Router } from "express";
import { z } from "zod";
import { REPORT_STATUSES, REPORT_TARGET_TYPES, SMS_PROVIDERS, USER_ACCOUNT_STATUSES } from "../../lib/admin-types.js";
import { env } from "../../config/env.js";
import { revokeAllAuthSessionsForUser } from "../../lib/auth-sessions.js";
import { signAdminAccessToken } from "../../lib/jwt.js";
import { prisma } from "../../lib/prisma.js";
import { writeAdminAuditLog } from "../../lib/admin-audit.js";
import { requireAdminAuth, requireAdminRole } from "../../middleware/admin-auth.js";
export const adminRouter = Router();
const prismaUser = prisma.user;
const prismaAdminUser = prisma.adminUser;
const prismaAuthSession = prisma.authSession;
const prismaFeatureFlag = prisma.featureFlag;
const prismaCountryPolicy = prisma.countryPolicy;
const prismaReportCase = prisma.reportCase;
const prismaAdminAuditLog = prisma.adminAuditLog;
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
    if (value.accountStatus === undefined &&
        value.accountStatusReason === undefined &&
        value.otpBlocked === undefined &&
        value.sendRestricted === undefined &&
        value.callRestricted === undefined) {
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
async function ensureBootstrapAdmin() {
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
function canMutateUser(role) {
    return ["SUPER_ADMIN", "OPS_ADMIN", "MODERATOR"].includes(role);
}
function canResolveReports(role) {
    return ["SUPER_ADMIN", "OPS_ADMIN", "MODERATOR", "SUPPORT_ADMIN"].includes(role);
}
function normalizeUsername(value) {
    return value.trim().toLowerCase();
}
function resolveReportFinalState(status) {
    if (["ACTIONED", "REJECTED", "RESOLVED"].includes(status)) {
        return { resolvedAt: new Date(), resolvedByAdminId: null };
    }
    return { resolvedAt: null, resolvedByAdminId: null };
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
        where: { id: req.adminUserId },
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
    const [totalUsers, suspendedUsers, bannedUsers, activeSessions, totalChats, messagesLast24h, callsLast24h, openReports, activeDeviceTokens, enabledFeatureFlags, countryPolicyCount] = await prisma.$transaction([
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
adminRouter.put("/feature-flags/:key", requireAdminAuth, requireAdminRole("SUPER_ADMIN", "OPS_ADMIN"), async (req, res) => {
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
            description: parsedBody.data.description !== undefined ? parsedBody.data.description : undefined,
            metadata: parsedBody.data.metadata !== undefined ? parsedBody.data.metadata : undefined,
            updatedByAdminId: req.adminUserId
        },
        create: {
            key: parsedParams.data.key,
            enabled: parsedBody.data.enabled,
            description: parsedBody.data.description ?? null,
            metadata: parsedBody.data.metadata ?? null,
            updatedByAdminId: req.adminUserId
        }
    });
    await writeAdminAuditLog({
        actorAdminId: req.adminUserId,
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
});
adminRouter.get("/country-policies", requireAdminAuth, async (_req, res) => {
    const policies = await prismaCountryPolicy.findMany({
        orderBy: [{ countryName: "asc" }, { countryIso: "asc" }]
    });
    res.json({ data: policies });
});
adminRouter.put("/country-policies/:countryIso", requireAdminAuth, requireAdminRole("SUPER_ADMIN", "OPS_ADMIN"), async (req, res) => {
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
            otpCooldownSeconds: parsedBody.data.otpCooldownSeconds !== undefined
                ? parsedBody.data.otpCooldownSeconds
                : undefined,
            otpTtlSeconds: parsedBody.data.otpTtlSeconds !== undefined ? parsedBody.data.otpTtlSeconds : undefined,
            otpPhoneLimit10m: parsedBody.data.otpPhoneLimit10m !== undefined
                ? parsedBody.data.otpPhoneLimit10m
                : undefined,
            otpPhoneLimit24h: parsedBody.data.otpPhoneLimit24h !== undefined
                ? parsedBody.data.otpPhoneLimit24h
                : undefined,
            otpIpLimit10m: parsedBody.data.otpIpLimit10m !== undefined ? parsedBody.data.otpIpLimit10m : undefined,
            otpIpLimit24h: parsedBody.data.otpIpLimit24h !== undefined ? parsedBody.data.otpIpLimit24h : undefined,
            notes: parsedBody.data.notes !== undefined ? parsedBody.data.notes : undefined,
            updatedByAdminId: req.adminUserId
        },
        create: {
            countryIso: parsedParams.data.countryIso,
            countryName: parsedBody.data.countryName,
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
            updatedByAdminId: req.adminUserId
        }
    });
    await writeAdminAuditLog({
        actorAdminId: req.adminUserId,
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
});
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
            accountStatus: true,
            accountStatusReason: true,
            otpBlocked: true,
            sendRestricted: true,
            callRestricted: true,
            createdAt: true,
            lastSeenAt: true
        }
    });
    res.json({ data: users });
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
    res.json({
        data: {
            ...user,
            activeSessionCount
        }
    });
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
            accountStatusReason: parsedBody.data.accountStatusReason !== undefined
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
        actorAdminId: req.adminUserId,
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
        actorAdminId: req.adminUserId,
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
            resolutionNote: parsedBody.data.resolutionNote !== undefined ? parsedBody.data.resolutionNote : undefined,
            resolvedAt: finalState.resolvedAt,
            resolvedByAdminId: finalState.resolvedAt ? req.adminUserId : null
        }
    });
    await writeAdminAuditLog({
        actorAdminId: req.adminUserId,
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
