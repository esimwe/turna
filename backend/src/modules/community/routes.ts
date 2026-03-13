import { Router, type Request } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma.js";
import { logError } from "../../lib/logger.js";
import { requireAuth } from "../../middleware/auth.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";

export const communityRouter = Router();

const prismaCommunity = (prisma as unknown as { community: any }).community;
const prismaCommunityMembership = (prisma as unknown as { communityMembership: any }).communityMembership;
const prismaCommunityChannel = (prisma as unknown as { communityChannel: any }).communityChannel;
const prismaCommunityMessage = (prisma as unknown as { communityMessage: any }).communityMessage;
const prismaCommunityTopic = (prisma as unknown as { communityTopic: any }).communityTopic;

const communityListQuerySchema = z.object({
  q: z.string().trim().max(80).optional(),
  limit: z.coerce.number().int().min(1).max(40).default(20)
});

const communityParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255)
});

const communityChannelParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  channelId: z.string().trim().min(1).max(255)
});

const communityListLimitSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(40)
});

const communitySendMessageSchema = z.object({
  text: z.string().trim().min(1).max(4000),
  replyToMessageId: z.string().trim().min(1).max(255).optional()
});

const communityTopicsQuerySchema = z.object({
  type: z.enum(["question", "resource", "event"]),
  limit: z.coerce.number().int().min(1).max(100).default(30)
});

type CommunityUserRow = {
  id: string;
  displayName: string;
  username: string | null;
  avatarUrl: string | null;
  about?: string | null;
  city?: string | null;
  country?: string | null;
  expertise?: string | null;
  communityRole?: string | null;
  updatedAt: Date;
};

type CommunityMembershipRow = {
  role: string;
  joinedAt: Date;
  user: CommunityUserRow;
};

type CommunityTopicReplyRow = {
  id: string;
  body: string;
  isAccepted: boolean;
  createdAt: Date;
  author: {
    id: string;
    displayName: string;
    username: string | null;
    avatarUrl: string | null;
    updatedAt: Date;
  };
};

type CommunityTopicRow = {
  id: string;
  title: string;
  body: string | null;
  type: string;
  tags?: unknown;
  isPinned: boolean;
  isSolved: boolean;
  eventStartsAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  channel?: {
    id: string;
    slug: string;
    name: string;
    type: string;
  } | null;
  author: CommunityUserRow;
  replies?: CommunityTopicReplyRow[];
  _count?: {
    replies?: number;
  };
};

type CommunityMessageRow = {
  id: string;
  text: string | null;
  attachments?: unknown;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
  replyToMessageId: string | null;
  author: CommunityUserRow;
  replyToMessage?: {
    id: string;
    text: string | null;
    author: {
      id: string;
      displayName: string;
      username: string | null;
      avatarUrl: string | null;
      updatedAt: Date;
    };
  } | null;
};

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

function toApiTopicType(value: string | null | undefined): "question" | "resource" | "event" {
  switch ((value ?? "").toUpperCase()) {
    case "RESOURCE":
      return "resource";
    case "EVENT":
      return "event";
    default:
      return "question";
  }
}

function normalizeRolePriority(value: string | null | undefined): number {
  switch ((value ?? "").toUpperCase()) {
    case "OWNER":
      return 0;
    case "ADMIN":
      return 1;
    case "MODERATOR":
      return 2;
    case "MENTOR":
      return 3;
    default:
      return 4;
  }
}

function canPostCommunityChannel(channelType: string | null | undefined, role: string | null | undefined) {
  const normalizedChannel = (channelType ?? "").toUpperCase();
  const normalizedRole = (role ?? "").toUpperCase();
  if (normalizedChannel === "ANNOUNCEMENT") {
    return ["OWNER", "ADMIN", "MODERATOR", "MENTOR"].includes(normalizedRole);
  }
  return normalizedChannel === "CHAT";
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

async function findCommunityAccess(communityIdOrSlug: string, userId: string) {
  return prismaCommunity.findFirst({
    where: {
      OR: [{ id: communityIdOrSlug }, { slug: communityIdOrSlug }]
    },
    select: {
      id: true,
      slug: true,
      name: true,
      memberships: {
        where: { userId },
        select: {
          userId: true,
          role: true,
          joinedAt: true
        }
      }
    }
  });
}

async function findCommunityChannelForUser(
  communityIdOrSlug: string,
  channelIdOrSlug: string,
  userId: string
) {
  const access = await findCommunityAccess(communityIdOrSlug, userId);
  if (!access) {
    return { community: null, membership: null, channel: null };
  }

  const membership = access.memberships?.[0] ?? null;
  const channel = await prismaCommunityChannel.findFirst({
    where: {
      communityId: access.id,
      OR: [{ id: channelIdOrSlug }, { slug: channelIdOrSlug }]
    },
    select: {
      id: true,
      slug: true,
      name: true,
      description: true,
      type: true,
      sortOrder: true,
      isDefault: true
    }
  });

  return {
    community: access,
    membership,
    channel
  };
}

function toCommunityUserDto(
  req: Request,
  user: CommunityUserRow
) {
  return {
    id: user.id,
    displayName: user.displayName,
    username: user.username,
    avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null,
    about: user.about ?? null,
    city: user.city ?? null,
    country: user.country ?? null,
    expertise: user.expertise ?? null,
    communityRole: user.communityRole ?? null
  };
}

function toCommunityMessageDto(
  req: Request,
  row: CommunityMessageRow
) {
  return {
    id: row.id,
    text: row.text,
    attachments: normalizeStringList(row.attachments),
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt ? row.deletedAt.toISOString() : null,
    replyToMessageId: row.replyToMessageId,
    author: toCommunityUserDto(req, row.author),
    replyToMessage: row.replyToMessage
      ? {
          id: row.replyToMessage.id,
          text: row.replyToMessage.text,
          author: {
            id: row.replyToMessage.author.id,
            displayName: row.replyToMessage.author.displayName,
            username: row.replyToMessage.author.username,
            avatarUrl: row.replyToMessage.author.avatarUrl
              ? buildAvatarUrl(req, row.replyToMessage.author.id, row.replyToMessage.author.updatedAt)
              : null
          }
        }
      : null
  };
}

function toCommunityTopicDto(
  req: Request,
  row: CommunityTopicRow
) {
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    type: toApiTopicType(row.type),
    tags: normalizeStringList(row.tags),
    isPinned: row.isPinned,
    isSolved: row.isSolved,
    eventStartsAt: row.eventStartsAt ? row.eventStartsAt.toISOString() : null,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    replyCount: row._count?.replies ?? 0,
    channel: row.channel
      ? {
          id: row.channel.id,
          slug: row.channel.slug,
          name: row.channel.name,
          type: toApiChannelType(row.channel.type)
        }
      : null,
    author: toCommunityUserDto(req, row.author),
    replies: (row.replies ?? []).map((reply) => ({
      id: reply.id,
      body: reply.body,
      isAccepted: reply.isAccepted,
      createdAt: reply.createdAt.toISOString(),
      author: {
        id: reply.author.id,
        displayName: reply.author.displayName,
        username: reply.author.username,
        avatarUrl: reply.author.avatarUrl
          ? buildAvatarUrl(req, reply.author.id, reply.author.updatedAt)
          : null
      }
    }))
  };
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

communityRouter.get("/:communityId/members", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedQuery = communityListLimitSchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({ error: "validation_error", details: parsedQuery.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsedParams.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    if (!access.memberships?.[0]) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }

    const memberships: CommunityMembershipRow[] = await prismaCommunityMembership.findMany({
      where: {
        communityId: access.id
      },
      take: parsedQuery.data.limit,
      orderBy: [{ joinedAt: "asc" }],
      select: {
        role: true,
        joinedAt: true,
        user: {
          select: {
            id: true,
            displayName: true,
            username: true,
            avatarUrl: true,
            about: true,
            city: true,
            country: true,
            expertise: true,
            communityRole: true,
            updatedAt: true
          }
        }
      }
    });

    const data = memberships
      .sort((left: CommunityMembershipRow, right: CommunityMembershipRow) => {
        const byRole = normalizeRolePriority(left.role) - normalizeRolePriority(right.role);
        if (byRole !== 0) return byRole;
        return left.joinedAt.getTime() - right.joinedAt.getTime();
      })
      .map((item: CommunityMembershipRow) => ({
        role: toApiRole(item.role),
        joinedAt: item.joinedAt.toISOString(),
        user: toCommunityUserDto(req, item.user)
      }));

    res.json({ data });
  } catch (error) {
    logError("community members failed", error);
    res.status(500).json({ error: "community_members_failed" });
  }
});

communityRouter.get("/:communityId/topics", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedQuery = communityTopicsQuerySchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({ error: "validation_error", details: parsedQuery.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsedParams.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    if (!access.memberships?.[0]) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }

    const dbType: "QUESTION" | "RESOURCE" | "EVENT" =
      parsedQuery.data.type === "resource"
        ? "RESOURCE"
        : parsedQuery.data.type === "event"
        ? "EVENT"
        : "QUESTION";

    const topics: CommunityTopicRow[] = await prismaCommunityTopic.findMany({
      where: {
        communityId: access.id,
        type: dbType
      },
      take: parsedQuery.data.limit,
      orderBy: [{ isPinned: "desc" }, { createdAt: "desc" }],
      select: {
        id: true,
        title: true,
        body: true,
        type: true,
        tags: true,
        isPinned: true,
        isSolved: true,
        eventStartsAt: true,
        createdAt: true,
        updatedAt: true,
        channel: {
          select: {
            id: true,
            slug: true,
            name: true,
            type: true
          }
        },
        author: {
          select: {
            id: true,
            displayName: true,
            username: true,
            avatarUrl: true,
            about: true,
            city: true,
            country: true,
            expertise: true,
            communityRole: true,
            updatedAt: true
          }
        },
        replies: {
          take: 2,
          orderBy: [{ isAccepted: "desc" }, { createdAt: "asc" }],
          select: {
            id: true,
            body: true,
            isAccepted: true,
            createdAt: true,
            author: {
              select: {
                id: true,
                displayName: true,
                username: true,
                avatarUrl: true,
                updatedAt: true
              }
            }
          }
        },
        _count: {
          select: {
            replies: true
          }
        }
      }
    });

    res.json({ data: topics.map((topic: CommunityTopicRow) => toCommunityTopicDto(req, topic)) });
  } catch (error) {
    logError("community topics failed", error);
    res.status(500).json({ error: "community_topics_failed" });
  }
});

communityRouter.get("/:communityId/channels/:channelId/messages", requireAuth, async (req, res) => {
  const parsedParams = communityChannelParamSchema.safeParse(req.params);
  const parsedQuery = communityListLimitSchema.safeParse(req.query);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedQuery.success) {
    res.status(400).json({ error: "validation_error", details: parsedQuery.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityChannelForUser(
      parsedParams.data.communityId,
      parsedParams.data.channelId,
      req.authUserId!
    );
    if (!access.community) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    if (!access.membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }
    if (!access.channel) {
      res.status(404).json({ error: "community_channel_not_found" });
      return;
    }

    const messages: CommunityMessageRow[] = await prismaCommunityMessage.findMany({
      where: {
        channelId: access.channel.id,
        deletedAt: null
      },
      take: parsedQuery.data.limit,
      orderBy: [{ createdAt: "desc" }],
      select: {
        id: true,
        text: true,
        attachments: true,
        createdAt: true,
        updatedAt: true,
        deletedAt: true,
        replyToMessageId: true,
        author: {
          select: {
            id: true,
            displayName: true,
            username: true,
            avatarUrl: true,
            about: true,
            city: true,
            country: true,
            expertise: true,
            communityRole: true,
            updatedAt: true
          }
        },
        replyToMessage: {
          select: {
            id: true,
            text: true,
            author: {
              select: {
                id: true,
                displayName: true,
                username: true,
                avatarUrl: true,
                updatedAt: true
              }
            }
          }
        }
      }
    });

    const items = messages
      .reverse()
      .map((item: CommunityMessageRow) => toCommunityMessageDto(req, item));
    res.json({
      data: {
        channel: {
          id: access.channel.id,
          slug: access.channel.slug,
          name: access.channel.name,
          type: toApiChannelType(access.channel.type),
          isDefault: access.channel.isDefault
        },
        items
      }
    });
  } catch (error) {
    logError("community channel messages failed", error);
    res.status(500).json({ error: "community_channel_messages_failed" });
  }
});

communityRouter.post("/:communityId/channels/:channelId/messages", requireAuth, async (req, res) => {
  const parsedParams = communityChannelParamSchema.safeParse(req.params);
  const parsedBody = communitySendMessageSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityChannelForUser(
      parsedParams.data.communityId,
      parsedParams.data.channelId,
      req.authUserId!
    );
    if (!access.community) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    if (!access.membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }
    if (!access.channel) {
      res.status(404).json({ error: "community_channel_not_found" });
      return;
    }
    if (!canPostCommunityChannel(access.channel.type, access.membership.role)) {
      res.status(403).json({ error: "community_channel_write_forbidden" });
      return;
    }

    let replyToMessageId: string | null = null;
    if (parsedBody.data.replyToMessageId) {
      const replyTarget = await prismaCommunityMessage.findFirst({
        where: {
          id: parsedBody.data.replyToMessageId,
          channelId: access.channel.id,
          deletedAt: null
        },
        select: { id: true }
      });
      if (!replyTarget) {
        res.status(404).json({ error: "community_reply_target_not_found" });
        return;
      }
      replyToMessageId = replyTarget.id;
    }

    const created = await prismaCommunityMessage.create({
      data: {
        channelId: access.channel.id,
        authorUserId: req.authUserId!,
        text: parsedBody.data.text,
        replyToMessageId,
        attachments: []
      },
      select: {
        id: true,
        text: true,
        attachments: true,
        createdAt: true,
        updatedAt: true,
        deletedAt: true,
        replyToMessageId: true,
        author: {
          select: {
            id: true,
            displayName: true,
            username: true,
            avatarUrl: true,
            about: true,
            city: true,
            country: true,
            expertise: true,
            communityRole: true,
            updatedAt: true
          }
        },
        replyToMessage: {
          select: {
            id: true,
            text: true,
            author: {
              select: {
                id: true,
                displayName: true,
                username: true,
                avatarUrl: true,
                updatedAt: true
              }
            }
          }
        }
      }
    });

    res.status(201).json({ data: toCommunityMessageDto(req, created) });
  } catch (error) {
    logError("community send message failed", error);
    res.status(500).json({ error: "community_send_message_failed" });
  }
});
