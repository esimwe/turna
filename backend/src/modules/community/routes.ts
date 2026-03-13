import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma.js";
import { logError } from "../../lib/logger.js";
import { requireAuth } from "../../middleware/auth.js";

export const communityRouter = Router();

const prismaCommunity = (prisma as unknown as { community: any }).community;
const prismaCommunityMembership = (prisma as unknown as { communityMembership: any }).communityMembership;

const communityListQuerySchema = z.object({
  q: z.string().trim().max(80).optional(),
  limit: z.coerce.number().int().min(1).max(40).default(20)
});

const communityParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255)
});

function toApiVisibility(
  value: string | null | undefined
): "public" | "request_only" | "invite_only" {
  switch ((value ?? "").toUpperCase()) {
    case "REQUEST_ONLY":
      return "request_only";
    case "INVITE_ONLY":
      return "invite_only";
    default:
      return "public";
  }
}

function toApiRole(
  value: string | null | undefined
): "owner" | "admin" | "moderator" | "mentor" | "member" | null {
  switch ((value ?? "").toUpperCase()) {
    case "OWNER":
      return "owner";
    case "ADMIN":
      return "admin";
    case "MODERATOR":
      return "moderator";
    case "MENTOR":
      return "mentor";
    case "MEMBER":
      return "member";
    default:
      return null;
  }
}

function toApiChannelType(
  value: string | null | undefined
): "chat" | "announcement" | "question" | "resource" | "event" {
  switch ((value ?? "").toUpperCase()) {
    case "ANNOUNCEMENT":
      return "announcement";
    case "QUESTION":
      return "question";
    case "RESOURCE":
      return "resource";
    case "EVENT":
      return "event";
    default:
      return "chat";
  }
}

function normalizeStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter((item) => item.length > 0);
}

function communitySelectForUser(userId: string) {
  return {
    id: true,
    slug: true,
    name: true,
    tagline: true,
    description: true,
    emoji: true,
    coverGradientFrom: true,
    coverGradientTo: true,
    welcomeTitle: true,
    welcomeDescription: true,
    entryChecklist: true,
    rules: true,
    visibility: true,
    createdAt: true,
    updatedAt: true,
    channels: {
      orderBy: { sortOrder: "asc" },
      select: {
        id: true,
        slug: true,
        name: true,
        description: true,
        type: true,
        sortOrder: true,
        isDefault: true
      }
    },
    memberships: {
      where: { userId },
      select: {
        userId: true,
        role: true,
        joinedAt: true
      }
    },
    _count: {
      select: {
        memberships: true
      }
    }
  } as const;
}

function toCommunityDto(
  row: {
    id: string;
    slug: string;
    name: string;
    tagline: string | null;
    description: string | null;
    emoji: string | null;
    coverGradientFrom: string | null;
    coverGradientTo: string | null;
    welcomeTitle: string | null;
    welcomeDescription: string | null;
    entryChecklist?: unknown;
    rules?: unknown;
    visibility: string;
    channels?: Array<{
      id: string;
      slug: string;
      name: string;
      description: string | null;
      type: string;
      sortOrder: number;
      isDefault: boolean;
    }>;
    memberships?: Array<{
      userId: string;
      role: string;
      joinedAt: Date;
    }>;
    _count?: {
      memberships?: number;
    };
  }
) {
  const membership = row.memberships?.[0] ?? null;
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    tagline: row.tagline,
    description: row.description,
    emoji: row.emoji,
    coverGradientFrom: row.coverGradientFrom,
    coverGradientTo: row.coverGradientTo,
    welcomeTitle: row.welcomeTitle,
    welcomeDescription: row.welcomeDescription,
    entryChecklist: normalizeStringList(row.entryChecklist),
    rules: normalizeStringList(row.rules),
    visibility: toApiVisibility(row.visibility),
    memberCount: row._count?.memberships ?? 0,
    isMember: membership != null,
    role: membership ? toApiRole(membership.role) : null,
    joinedAt: membership ? membership.joinedAt.toISOString() : null,
    channels: (row.channels ?? []).map((channel) => ({
      id: channel.id,
      slug: channel.slug,
      name: channel.name,
      description: channel.description,
      type: toApiChannelType(channel.type),
      sortOrder: channel.sortOrder,
      isDefault: channel.isDefault
    }))
  };
}

async function findCommunityForUser(communityIdOrSlug: string, userId: string) {
  return prismaCommunity.findFirst({
    where: {
      OR: [{ id: communityIdOrSlug }, { slug: communityIdOrSlug }]
    },
    select: communitySelectForUser(userId)
  });
}

communityRouter.get("/explore", requireAuth, async (req, res) => {
  const parsed = communityListQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const { q, limit } = parsed.data;

  try {
    const communities = await prismaCommunity.findMany({
      where: {
        isListed: true,
        ...(q
          ? {
              OR: [
                { name: { contains: q, mode: "insensitive" } },
                { slug: { contains: q, mode: "insensitive" } },
                { tagline: { contains: q, mode: "insensitive" } },
                { description: { contains: q, mode: "insensitive" } }
              ]
            }
          : {})
      },
      take: limit,
      orderBy: [{ createdAt: "desc" }],
      select: communitySelectForUser(req.authUserId!)
    });

    res.json({ data: communities.map(toCommunityDto) });
  } catch (error) {
    logError("community explore failed", error);
    res.status(500).json({ error: "community_explore_failed" });
  }
});

communityRouter.get("/mine", requireAuth, async (req, res) => {
  try {
    const communities = await prismaCommunity.findMany({
      where: {
        memberships: {
          some: { userId: req.authUserId! }
        }
      },
      orderBy: [{ updatedAt: "desc" }],
      select: communitySelectForUser(req.authUserId!)
    });

    res.json({ data: communities.map(toCommunityDto) });
  } catch (error) {
    logError("community mine failed", error);
    res.status(500).json({ error: "community_mine_failed" });
  }
});

communityRouter.get("/:communityId", requireAuth, async (req, res) => {
  const parsed = communityParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const community = await findCommunityForUser(parsed.data.communityId, req.authUserId!);
    if (!community) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }

    res.json({ data: toCommunityDto(community) });
  } catch (error) {
    logError("community detail failed", error);
    res.status(500).json({ error: "community_detail_failed" });
  }
});

communityRouter.post("/:communityId/join", requireAuth, async (req, res) => {
  const parsed = communityParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const community = await prismaCommunity.findFirst({
      where: {
        OR: [{ id: parsed.data.communityId }, { slug: parsed.data.communityId }]
      },
      select: { id: true, visibility: true }
    });

    if (!community) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }

    if ((community.visibility ?? "PUBLIC") !== "PUBLIC") {
      res.status(403).json({ error: "community_join_request_required" });
      return;
    }

    const existing = await prismaCommunityMembership.findUnique({
      where: {
        communityId_userId: {
          communityId: community.id,
          userId: req.authUserId!
        }
      }
    });

    if (!existing) {
      await prismaCommunityMembership.create({
        data: {
          communityId: community.id,
          userId: req.authUserId!
        }
      });
    }

    const updated = await findCommunityForUser(community.id, req.authUserId!);
    res.json({ data: updated ? toCommunityDto(updated) : null });
  } catch (error) {
    logError("community join failed", error);
    res.status(500).json({ error: "community_join_failed" });
  }
});

communityRouter.post("/:communityId/leave", requireAuth, async (req, res) => {
  const parsed = communityParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const community = await prismaCommunity.findFirst({
      where: {
        OR: [{ id: parsed.data.communityId }, { slug: parsed.data.communityId }]
      },
      select: { id: true }
    });

    if (!community) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }

    const existing = await prismaCommunityMembership.findUnique({
      where: {
        communityId_userId: {
          communityId: community.id,
          userId: req.authUserId!
        }
      }
    });

    if (!existing) {
      res.status(404).json({ error: "community_membership_not_found" });
      return;
    }

    if ((existing.role ?? "MEMBER") === "OWNER") {
      res.status(400).json({ error: "community_owner_cannot_leave" });
      return;
    }

    await prismaCommunityMembership.delete({
      where: {
        communityId_userId: {
          communityId: community.id,
          userId: req.authUserId!
        }
      }
    });

    res.json({ data: { left: true, communityId: community.id } });
  } catch (error) {
    logError("community leave failed", error);
    res.status(500).json({ error: "community_leave_failed" });
  }
});
