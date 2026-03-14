import { Router, type Request } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma.js";
import { logError } from "../../lib/logger.js";
import { requireAuth } from "../../middleware/auth.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";
import {
  createCommunityNotifications,
  extractMentionedUsernames,
  listCommunityNotifications,
  type CreateCommunityNotificationInput
} from "./community.notifications.js";
import {
  emitCommunityChannelMessage,
  emitCommunityNotification,
  emitCommunityThreadMessage,
  emitCommunityThreadUpdate
} from "./community.realtime.js";

export const communityRouter = Router();

const prismaCommunity = (prisma as unknown as { community: any }).community;
const prismaUser = (prisma as unknown as { user: any }).user;
const prismaCommunityMembership = (prisma as unknown as { communityMembership: any }).communityMembership;
const prismaCommunityChannel = (prisma as unknown as { communityChannel: any }).communityChannel;
const prismaCommunityMessage = (prisma as unknown as { communityMessage: any }).communityMessage;
const prismaCommunityTopic = (prisma as unknown as { communityTopic: any }).communityTopic;
const prismaCommunityTopicReply = (prisma as unknown as { communityTopicReply: any }).communityTopicReply;
const prismaCommunityJoinRequest = (prisma as unknown as { communityJoinRequest: any }).communityJoinRequest;
const prismaCommunityInvite = (prisma as unknown as { communityInvite: any }).communityInvite;

const communityListQuerySchema = z.object({
  q: z.string().trim().max(80).optional(),
  limit: z.coerce.number().int().min(1).max(40).default(20),
  visibility: z.enum(["public", "request_only", "invite_only"]).optional()
});

const communityParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255)
});

const communityChannelParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  channelId: z.string().trim().min(1).max(255)
});

const communityThreadParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  channelId: z.string().trim().min(1).max(255),
  messageId: z.string().trim().min(1).max(255)
});

const communityTopicParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  topicId: z.string().trim().min(1).max(255)
});

const communityTopicReplyParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  topicId: z.string().trim().min(1).max(255),
  replyId: z.string().trim().min(1).max(255)
});

const communityJoinRequestParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  requestId: z.string().trim().min(1).max(255)
});

const communityListLimitSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(40)
});

const communityMemberListQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(40),
  q: z.string().trim().max(80).optional(),
  role: z.enum(["owner", "admin", "moderator", "mentor", "member"]).optional()
});

const communitySendMessageSchema = z.object({
  text: z.string().trim().min(1).max(4000),
  replyToMessageId: z.string().trim().min(1).max(255).optional()
});

const communityTopicsQuerySchema = z.object({
  type: z.enum(["question", "resource", "event"]),
  limit: z.coerce.number().int().min(1).max(100).default(30),
  q: z.string().trim().max(120).optional(),
  solved: z.enum(["true", "false"]).optional()
});

const communitySearchQuerySchema = z.object({
  q: z.string().trim().min(1).max(120),
  limit: z.coerce.number().int().min(1).max(12).default(6)
});

const communityCreateTopicSchema = z.object({
  type: z.enum(["question", "resource", "event"]),
  title: z.string().trim().min(3).max(180),
  body: z.string().trim().max(4000).optional(),
  channelId: z.string().trim().min(1).max(255).optional(),
  tags: z.array(z.string().trim().min(1).max(40)).max(8).optional().default([]),
  eventStartsAt: z.string().trim().max(64).optional(),
  isPinned: z.boolean().optional()
});

const communityCreateTopicReplySchema = z.object({
  body: z.string().trim().min(1).max(4000)
});

const communityTopicSolvedSchema = z.object({
  solved: z.boolean().optional().default(true)
});

const communityTopicPinSchema = z.object({
  pinned: z.boolean().optional().default(true)
});

const communityJoinRequestCreateSchema = z.object({
  note: z.string().trim().max(240).optional()
});

const communityInviteCreateSchema = z.object({
  userId: z.string().trim().min(1).max(255),
  note: z.string().trim().max(240).optional()
});

const communityJoinRequestListQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  status: z.enum(["pending", "approved", "rejected"]).optional()
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

type CommunityJoinRequestRow = {
  id: string;
  note: string | null;
  status: string;
  createdAt: Date;
  updatedAt: Date;
  requester: CommunityUserRow;
};

type CommunityPendingJoinRequestRow = {
  id: string;
  status: string;
  createdAt: Date;
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

type CommunityInviteRow = {
  id: string;
  status: string;
  createdAt: Date;
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
  _count?: {
    replies?: number;
  };
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

function parseCommunityVisibilityFilter(
  value: "public" | "request_only" | "invite_only" | undefined
): "PUBLIC" | "REQUEST_ONLY" | "INVITE_ONLY" | null {
  switch (value) {
    case "request_only":
      return "REQUEST_ONLY";
    case "invite_only":
      return "INVITE_ONLY";
    case "public":
      return "PUBLIC";
    default:
      return null;
  }
}

function parseCommunityRoleFilter(
  value: "owner" | "admin" | "moderator" | "mentor" | "member" | undefined
): "OWNER" | "ADMIN" | "MODERATOR" | "MENTOR" | "MEMBER" | null {
  switch (value) {
    case "owner":
      return "OWNER";
    case "admin":
      return "ADMIN";
    case "moderator":
      return "MODERATOR";
    case "mentor":
      return "MENTOR";
    case "member":
      return "MEMBER";
    default:
      return null;
  }
}

function canManageCommunity(role: string | null | undefined): boolean {
  return ["OWNER", "ADMIN", "MODERATOR"].includes((role ?? "").toUpperCase());
}

function canInviteCommunityMembers(role: string | null | undefined): boolean {
  return canManageCommunity(role);
}

function canPinCommunityTopic(role: string | null | undefined): boolean {
  return ["OWNER", "ADMIN", "MODERATOR", "MENTOR"].includes((role ?? "").toUpperCase());
}

function canCreateCommunityTopic(type: string, role: string | null | undefined): boolean {
  const normalizedRole = (role ?? "").toUpperCase();
  const normalizedType = type.toUpperCase();
  if (normalizedType === "QUESTION") {
    return ["OWNER", "ADMIN", "MODERATOR", "MENTOR", "MEMBER"].includes(normalizedRole);
  }
  return ["OWNER", "ADMIN", "MODERATOR", "MENTOR"].includes(normalizedRole);
}

function canAcceptCommunityTopicReply(params: {
  topicAuthorId: string;
  viewerUserId: string;
  viewerRole: string | null | undefined;
}): boolean {
  if (params.topicAuthorId === params.viewerUserId) return true;
  return canManageCommunity(params.viewerRole);
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
    joinRequests: {
      where: {
        requesterUserId: userId,
        status: "PENDING"
      },
      take: 1,
      select: {
        id: true,
        status: true,
        createdAt: true
      }
    },
    invites: {
      where: {
        invitedUserId: userId,
        status: "PENDING"
      },
      take: 1,
      select: {
        id: true,
        status: true,
        createdAt: true
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
    joinRequests?: CommunityPendingJoinRequestRow[];
    invites?: CommunityInviteRow[];
    _count?: {
      memberships?: number;
    };
  }
) {
  const membership = row.memberships?.[0] ?? null;
  const pendingJoinRequest = row.joinRequests?.[0] ?? null;
  const pendingInvite = row.invites?.[0] ?? null;
  const viewerRole = membership?.role ?? null;
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
    hasPendingJoinRequest: pendingJoinRequest != null,
    hasInvite: pendingInvite != null,
    joinState: membership
      ? "joined"
      : pendingJoinRequest
      ? "pending"
      : pendingInvite
      ? "invited"
      : toApiVisibility(row.visibility) === "public"
      ? "open"
      : toApiVisibility(row.visibility) === "request_only"
      ? "approval"
      : "invite_only",
    permissions: {
      canManageCommunity: canManageCommunity(viewerRole),
      canInviteMembers: canInviteCommunityMembers(viewerRole),
      canCreateQuestion: membership != null && canCreateCommunityTopic("QUESTION", viewerRole),
      canCreateResource: membership != null && canCreateCommunityTopic("RESOURCE", viewerRole),
      canCreateEvent: membership != null && canCreateCommunityTopic("EVENT", viewerRole),
      canPinTopic: membership != null && canPinCommunityTopic(viewerRole)
    },
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
    replyCount: row._count?.replies ?? 0,
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
  row: CommunityTopicRow,
  options?: {
    viewerUserId?: string | null;
    viewerRole?: string | null;
  }
) {
  const viewerUserId = options?.viewerUserId ?? null;
  const viewerRole = options?.viewerRole ?? null;
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
    permissions: {
      canReply: viewerUserId != null,
      canAcceptAnswer:
        viewerUserId != null &&
        canAcceptCommunityTopicReply({
          topicAuthorId: row.author.id,
          viewerUserId,
          viewerRole
        }),
      canChangeSolvedState:
        viewerUserId != null &&
        canAcceptCommunityTopicReply({
          topicAuthorId: row.author.id,
          viewerUserId,
          viewerRole
        }),
      canPin: viewerUserId != null && canPinCommunityTopic(viewerRole)
    },
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

function toCommunityJoinRequestDto(req: Request, row: CommunityJoinRequestRow) {
  return {
    id: row.id,
    note: row.note,
    status: (row.status ?? "").toLowerCase(),
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    requester: toCommunityUserDto(req, row.requester)
  };
}

function toCommunityNotificationType(
  value: string | null | undefined
): "reply" | "mention" | "announcement" | "dm_request" {
  switch ((value ?? "").toUpperCase()) {
    case "MENTION":
      return "mention";
    case "ANNOUNCEMENT":
      return "announcement";
    case "DM_REQUEST":
      return "dm_request";
    default:
      return "reply";
  }
}

function toCommunityNotificationDto(row: {
  id: string;
  type: string;
  communityId: string | null;
  channelId: string | null;
  messageId: string | null;
  topicId: string | null;
  title: string;
  body: string | null;
  readAt: Date | null;
  createdAt: Date;
}) {
  return {
    id: row.id,
    type: toCommunityNotificationType(row.type),
    communityId: row.communityId,
    channelId: row.channelId,
    messageId: row.messageId,
    topicId: row.topicId,
    title: row.title,
    body: row.body,
    readAt: row.readAt ? row.readAt.toISOString() : null,
    createdAt: row.createdAt.toISOString()
  };
}

function truncateCommunityText(text: string | null | undefined, maxLength = 140): string {
  const normalized = (text ?? "").trim().replace(/\s+/g, " ");
  if (!normalized) return "";
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
}

function communityTopicSelect(replyTake: number | null) {
  return {
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
      ...(replyTake == null ? {} : { take: replyTake }),
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
  } as const;
}

function parseOptionalDate(value: string | undefined): Date | null {
  const text = value?.trim();
  if (!text) return null;
  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed;
}

async function createTopicMentionNotifications(params: {
  text: string | null | undefined;
  actorUserId: string;
  actorDisplayName: string;
  communityId: string;
  communityName: string;
  topicId: string;
  title: string;
}): Promise<CreateCommunityNotificationInput[]> {
  const mentionedUsernames = extractMentionedUsernames(params.text ?? "");
  if (mentionedUsernames.length === 0) return [];

  const memberships = await prismaCommunityMembership.findMany({
    where: {
      communityId: params.communityId,
      userId: { not: params.actorUserId },
      user: {
        username: {
          in: mentionedUsernames
        }
      }
    },
    select: {
      userId: true,
      user: {
        select: {
          username: true
        }
      }
    }
  });

  return memberships.map((membership: { userId: string; user: { username: string | null } }) => ({
    userId: membership.userId,
    type: "MENTION",
    communityId: params.communityId,
    topicId: params.topicId,
    title: `${params.actorDisplayName} seni bir konuda andi`,
    body: truncateCommunityText(params.title, 120),
    metadata: {
      communityName: params.communityName,
      username: membership.user.username ?? null
    }
  }));
}

communityRouter.get("/explore", requireAuth, async (req, res) => {
  const parsed = communityListQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const { q, limit, visibility } = parsed.data;
  const visibilityFilter = parseCommunityVisibilityFilter(visibility);

  try {
    const communities = await prismaCommunity.findMany({
      where: {
        isListed: true,
        ...(visibilityFilter ? { visibility: visibilityFilter } : {}),
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

communityRouter.get("/home", requireAuth, async (req, res) => {
  try {
    const [explore, mine] = await Promise.all([
      prismaCommunity.findMany({
        where: {
          isListed: true
        },
        take: 8,
        orderBy: [{ createdAt: "desc" }],
        select: communitySelectForUser(req.authUserId!)
      }),
      prismaCommunity.findMany({
        where: {
          memberships: {
            some: { userId: req.authUserId! }
          }
        },
        take: 8,
        orderBy: [{ updatedAt: "desc" }],
        select: communitySelectForUser(req.authUserId!)
      })
    ]);

    const mineIds = (mine as Array<{ id: string }>).map((community) => community.id);
    let upcomingEvent: CommunityTopicRow | null = null;
    let openQuestion: CommunityTopicRow | null = null;
    let featuredResource: CommunityTopicRow | null = null;
    let suggestedMembers: CommunityMembershipRow[] = [];

    if (mineIds.length > 0) {
      const [eventRow, questionRow, resourceRow, memberRows] = await Promise.all([
        prismaCommunityTopic.findFirst({
          where: {
            communityId: { in: mineIds },
            type: "EVENT",
            eventStartsAt: { gte: new Date() }
          },
          orderBy: [{ eventStartsAt: "asc" }, { createdAt: "asc" }],
          select: communityTopicSelect(0)
        }),
        prismaCommunityTopic.findFirst({
          where: {
            communityId: { in: mineIds },
            type: "QUESTION",
            isSolved: false
          },
          orderBy: [{ isPinned: "desc" }, { updatedAt: "desc" }],
          select: communityTopicSelect(1)
        }),
        prismaCommunityTopic.findFirst({
          where: {
            communityId: { in: mineIds },
            type: { in: ["RESOURCE", "EVENT"] }
          },
          orderBy: [{ isPinned: "desc" }, { updatedAt: "desc" }],
          select: communityTopicSelect(1)
        }),
        prismaCommunityMembership.findMany({
          where: {
            communityId: { in: mineIds },
            userId: { not: req.authUserId! }
          },
          take: 12,
          orderBy: [{ joinedAt: "desc" }],
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
        })
      ]);

      upcomingEvent = eventRow;
      openQuestion = questionRow;
      featuredResource = resourceRow;
      const uniqueMembers = new Map<string, CommunityMembershipRow>();
      for (const member of memberRows as CommunityMembershipRow[]) {
        if (!uniqueMembers.has(member.user.id)) {
          uniqueMembers.set(member.user.id, member);
        }
      }
      suggestedMembers = [...uniqueMembers.values()].slice(0, 6);
    }

    res.json({
      data: {
        explore: explore.map(toCommunityDto),
        mine: mine.map(toCommunityDto),
        upcomingEvent: upcomingEvent ? toCommunityTopicDto(req, upcomingEvent) : null,
        openQuestion: openQuestion ? toCommunityTopicDto(req, openQuestion) : null,
        featuredResource: featuredResource ? toCommunityTopicDto(req, featuredResource) : null,
        suggestedMembers: suggestedMembers.map((item) => ({
          role: toApiRole(item.role),
          joinedAt: item.joinedAt.toISOString(),
          user: toCommunityUserDto(req, item.user)
        }))
      }
    });
  } catch (error) {
    logError("community home failed", error);
    res.status(500).json({ error: "community_home_failed" });
  }
});

communityRouter.get("/notifications", requireAuth, async (req, res) => {
  const parsed = communityListLimitSchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const notifications = await listCommunityNotifications({
      userId: req.authUserId!,
      limit: parsed.data.limit
    });
    res.json({
      data: notifications.map(toCommunityNotificationDto)
    });
  } catch (error) {
    logError("community notifications failed", error);
    res.status(500).json({ error: "community_notifications_failed" });
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
  const parsedBody = communityJoinRequestCreateSchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const community = await prismaCommunity.findFirst({
      where: {
        OR: [{ id: parsed.data.communityId }, { slug: parsed.data.communityId }]
      },
      select: {
        id: true,
        visibility: true,
        memberships: {
          where: { userId: req.authUserId! },
          select: {
            userId: true,
            role: true,
            joinedAt: true
          }
        },
        joinRequests: {
          where: {
            requesterUserId: req.authUserId!,
            status: "PENDING"
          },
          take: 1,
          select: {
            id: true
          }
        },
        invites: {
          where: {
            invitedUserId: req.authUserId!,
            status: "PENDING"
          },
          take: 1,
          select: {
            id: true
          }
        }
      }
    });

    if (!community) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }

    if (community.memberships?.[0]) {
      const updated = await findCommunityForUser(community.id, req.authUserId!);
      res.json({ data: updated ? toCommunityDto(updated) : null });
      return;
    }

    if ((community.visibility ?? "PUBLIC") === "REQUEST_ONLY") {
      if (!community.joinRequests?.[0]) {
        await prismaCommunityJoinRequest.create({
          data: {
            communityId: community.id,
            requesterUserId: req.authUserId!,
            note: parsedBody.data.note?.trim() || null
          }
        });
      }
      const updated = await findCommunityForUser(community.id, req.authUserId!);
      res.status(202).json({ data: updated ? toCommunityDto(updated) : null });
      return;
    }

    if ((community.visibility ?? "PUBLIC") === "INVITE_ONLY") {
      const pendingInvite = community.invites?.[0] ?? null;
      if (!pendingInvite) {
        res.status(403).json({ error: "community_invite_required" });
        return;
      }
      await prismaCommunityMembership.create({
        data: {
          communityId: community.id,
          userId: req.authUserId!
        }
      });
      await prismaCommunityInvite.update({
        where: { id: pendingInvite.id },
        data: {
          status: "ACCEPTED",
          respondedAt: new Date()
        }
      });
      const updated = await findCommunityForUser(community.id, req.authUserId!);
      res.json({ data: updated ? toCommunityDto(updated) : null });
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
  const parsedQuery = communityMemberListQuerySchema.safeParse(req.query);
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
        communityId: access.id,
        ...(parseCommunityRoleFilter(parsedQuery.data.role)
          ? { role: parseCommunityRoleFilter(parsedQuery.data.role)! }
          : {}),
        ...(parsedQuery.data.q
          ? {
              OR: [
                { user: { displayName: { contains: parsedQuery.data.q, mode: "insensitive" } } },
                { user: { username: { contains: parsedQuery.data.q, mode: "insensitive" } } },
                { user: { about: { contains: parsedQuery.data.q, mode: "insensitive" } } },
                { user: { city: { contains: parsedQuery.data.q, mode: "insensitive" } } },
                { user: { country: { contains: parsedQuery.data.q, mode: "insensitive" } } },
                { user: { expertise: { contains: parsedQuery.data.q, mode: "insensitive" } } }
              ]
            }
          : {})
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
        type: dbType,
        ...(parsedQuery.data.solved === "true"
          ? { isSolved: true }
          : parsedQuery.data.solved === "false"
          ? { isSolved: false }
          : {}),
        ...(parsedQuery.data.q
          ? {
              OR: [
                { title: { contains: parsedQuery.data.q, mode: "insensitive" } },
                { body: { contains: parsedQuery.data.q, mode: "insensitive" } }
              ]
            }
          : {})
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

    res.json({
      data: topics.map((topic: CommunityTopicRow) =>
        toCommunityTopicDto(req, topic, {
          viewerUserId: req.authUserId!,
          viewerRole: access.memberships?.[0]?.role ?? null
        })
      )
    });
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
        deletedAt: null,
        replyToMessageId: null
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
        },
        _count: {
          select: {
            replies: {
              where: {
                deletedAt: null
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

communityRouter.get(
  "/:communityId/channels/:channelId/messages/:messageId/thread",
  requireAuth,
  async (req, res) => {
    const parsedParams = communityThreadParamSchema.safeParse(req.params);
    if (!parsedParams.success) {
      res
        .status(400)
        .json({ error: "validation_error", details: parsedParams.error.flatten() });
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

      const anchorMessage = await prismaCommunityMessage.findFirst({
        where: {
          id: parsedParams.data.messageId,
          channelId: access.channel.id,
          deletedAt: null
        },
        select: {
          id: true,
          replyToMessageId: true
        }
      });

      if (!anchorMessage) {
        res.status(404).json({ error: "community_message_not_found" });
        return;
      }

      const rootMessageId = anchorMessage.replyToMessageId ?? anchorMessage.id;
      const [root, replies] = await Promise.all([
        prismaCommunityMessage.findFirst({
          where: {
            id: rootMessageId,
            channelId: access.channel.id,
            deletedAt: null
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
            },
            _count: {
              select: {
                replies: {
                  where: {
                    deletedAt: null
                  }
                }
              }
            }
          }
        }),
        prismaCommunityMessage.findMany({
          where: {
            channelId: access.channel.id,
            deletedAt: null,
            replyToMessageId: rootMessageId
          },
          orderBy: [{ createdAt: "asc" }],
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
            },
            _count: {
              select: {
                replies: {
                  where: {
                    deletedAt: null
                  }
                }
              }
            }
          }
        })
      ]);

      if (!root) {
        res.status(404).json({ error: "community_message_not_found" });
        return;
      }

      res.json({
        data: {
          root: toCommunityMessageDto(req, root),
          replies: replies.map((item: CommunityMessageRow) => toCommunityMessageDto(req, item))
        }
      });
    } catch (error) {
      logError("community thread failed", error);
      res.status(500).json({ error: "community_thread_failed" });
    }
  }
);

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
    let rootThreadMessageId: string | null = null;
    let replyTarget:
      | {
          id: string;
          authorUserId: string;
          replyToMessageId: string | null;
          text: string | null;
        }
      | null = null;
    if (parsedBody.data.replyToMessageId) {
      replyTarget = await prismaCommunityMessage.findFirst({
        where: {
          id: parsedBody.data.replyToMessageId,
          channelId: access.channel.id,
          deletedAt: null
        },
        select: {
          id: true,
          authorUserId: true,
          replyToMessageId: true,
          text: true
        }
      });
      if (!replyTarget) {
        res.status(404).json({ error: "community_reply_target_not_found" });
        return;
      }
      rootThreadMessageId = replyTarget.replyToMessageId ?? replyTarget.id;
      replyToMessageId = rootThreadMessageId;
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
        },
        _count: {
          select: {
            replies: {
              where: {
                deletedAt: null
              }
            }
          }
        }
      }
    });

    const senderDisplayName = created.author.displayName.trim() || "Bir uye";
    const notificationInputs: CreateCommunityNotificationInput[] = [];
    const notifiedUserIds = new Set<string>();

    if (replyTarget && replyTarget.authorUserId !== req.authUserId!) {
      notificationInputs.push({
        userId: replyTarget.authorUserId,
        type: "REPLY",
        communityId: access.community.id,
        channelId: access.channel.id,
        messageId: created.id,
        title: `${senderDisplayName} mesajina yanit verdi`,
        body: truncateCommunityText(parsedBody.data.text, 120),
        metadata: {
          channelName: access.channel.name,
          communityName: access.community.name
        }
      });
      notifiedUserIds.add(replyTarget.authorUserId);
    }

    const mentionedUsernames = extractMentionedUsernames(parsedBody.data.text);
    if (mentionedUsernames.length > 0) {
      const mentionedMemberships = await prismaCommunityMembership.findMany({
        where: {
          communityId: access.community.id,
          userId: { not: req.authUserId! },
          user: {
            username: {
              in: mentionedUsernames
            }
          }
        },
        select: {
          userId: true,
          user: {
            select: {
              username: true
            }
          }
        }
      });

      for (const membership of mentionedMemberships) {
        if (notifiedUserIds.has(membership.userId)) continue;
        notificationInputs.push({
          userId: membership.userId,
          type: "MENTION",
          communityId: access.community.id,
          channelId: access.channel.id,
          messageId: created.id,
          title: `${senderDisplayName} seni andi`,
          body: truncateCommunityText(parsedBody.data.text, 120),
          metadata: {
            channelName: access.channel.name,
            communityName: access.community.name,
            username: membership.user.username ?? null
          }
        });
        notifiedUserIds.add(membership.userId);
      }
    }

    if ((access.channel.type ?? "").toUpperCase() === "ANNOUNCEMENT") {
      const memberships = await prismaCommunityMembership.findMany({
        where: {
          communityId: access.community.id,
          userId: { not: req.authUserId! }
        },
        select: {
          userId: true
        }
      });

      for (const membership of memberships) {
        notificationInputs.push({
          userId: membership.userId,
          type: "ANNOUNCEMENT",
          communityId: access.community.id,
          channelId: access.channel.id,
          messageId: created.id,
          title: `${access.community.name} toplulugunda yeni duyuru`,
          body: truncateCommunityText(parsedBody.data.text, 120),
          metadata: {
            channelName: access.channel.name,
            communityName: access.community.name
          }
        });
      }
    }

    await createCommunityNotifications(notificationInputs);

    const createdDto = toCommunityMessageDto(req, created);
    if (rootThreadMessageId) {
      const replyCount = await prismaCommunityMessage.count({
        where: {
          channelId: access.channel.id,
          deletedAt: null,
          replyToMessageId: rootThreadMessageId
        }
      });
      emitCommunityThreadMessage({
        communityId: access.community.id,
        channelId: access.channel.id,
        rootMessageId: rootThreadMessageId,
        message: createdDto
      });
      emitCommunityThreadUpdate({
        communityId: access.community.id,
        channelId: access.channel.id,
        rootMessageId: rootThreadMessageId,
        replyCount
      });
    } else {
      emitCommunityChannelMessage({
        communityId: access.community.id,
        channelId: access.channel.id,
        message: createdDto
      });
    }
    for (const notificationInput of notificationInputs) {
      emitCommunityNotification([notificationInput.userId], {
        type: notificationInput.type.toLowerCase(),
        communityId: notificationInput.communityId ?? null,
        channelId: notificationInput.channelId ?? null,
        messageId: notificationInput.messageId ?? null,
        title: notificationInput.title,
        body: notificationInput.body ?? null,
        createdAt: created.createdAt.toISOString()
      });
    }

    res.status(201).json({ data: createdDto });
  } catch (error) {
    logError("community send message failed", error);
    res.status(500).json({ error: "community_send_message_failed" });
  }
});

communityRouter.get("/:communityId/search", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedQuery = communitySearchQuerySchema.safeParse(req.query);
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

    const [channels, topics, members] = await Promise.all([
      prismaCommunityChannel.findMany({
        where: {
          communityId: access.id,
          OR: [
            { name: { contains: parsedQuery.data.q, mode: "insensitive" } },
            { description: { contains: parsedQuery.data.q, mode: "insensitive" } }
          ]
        },
        take: parsedQuery.data.limit,
        orderBy: [{ sortOrder: "asc" }],
        select: {
          id: true,
          slug: true,
          name: true,
          description: true,
          type: true,
          sortOrder: true,
          isDefault: true
        }
      }),
      prismaCommunityTopic.findMany({
        where: {
          communityId: access.id,
          OR: [
            { title: { contains: parsedQuery.data.q, mode: "insensitive" } },
            { body: { contains: parsedQuery.data.q, mode: "insensitive" } }
          ]
        },
        take: parsedQuery.data.limit,
        orderBy: [{ isPinned: "desc" }, { updatedAt: "desc" }],
        select: communityTopicSelect(1)
      }),
      prismaCommunityMembership.findMany({
        where: {
          communityId: access.id,
          OR: [
            { user: { displayName: { contains: parsedQuery.data.q, mode: "insensitive" } } },
            { user: { username: { contains: parsedQuery.data.q, mode: "insensitive" } } },
            { user: { about: { contains: parsedQuery.data.q, mode: "insensitive" } } },
            { user: { expertise: { contains: parsedQuery.data.q, mode: "insensitive" } } },
            { user: { city: { contains: parsedQuery.data.q, mode: "insensitive" } } },
            { user: { country: { contains: parsedQuery.data.q, mode: "insensitive" } } }
          ]
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
      })
    ]);

    res.json({
      data: {
        channels: channels.map((channel: any) => ({
          id: channel.id,
          slug: channel.slug,
          name: channel.name,
          description: channel.description,
          type: toApiChannelType(channel.type),
          isDefault: channel.isDefault
        })),
        topics: topics.map((topic: CommunityTopicRow) =>
          toCommunityTopicDto(req, topic, {
            viewerUserId: req.authUserId!,
            viewerRole: access.memberships?.[0]?.role ?? null
          })
        ),
        members: (members as CommunityMembershipRow[]).map((item) => ({
          role: toApiRole(item.role),
          joinedAt: item.joinedAt.toISOString(),
          user: toCommunityUserDto(req, item.user)
        }))
      }
    });
  } catch (error) {
    logError("community search failed", error);
    res.status(500).json({ error: "community_search_failed" });
  }
});

communityRouter.get("/:communityId/join-requests", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedQuery = communityJoinRequestListQuerySchema.safeParse(req.query);
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
    const membership = access.memberships?.[0] ?? null;
    if (!membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }
    if (!canManageCommunity(membership.role)) {
      res.status(403).json({ error: "community_join_request_review_forbidden" });
      return;
    }

    const status =
      parsedQuery.data.status === "approved"
        ? "APPROVED"
        : parsedQuery.data.status === "rejected"
        ? "REJECTED"
        : "PENDING";

    const requests: CommunityJoinRequestRow[] = await prismaCommunityJoinRequest.findMany({
      where: {
        communityId: access.id,
        status
      },
      take: parsedQuery.data.limit,
      orderBy: [{ createdAt: "desc" }],
      select: {
        id: true,
        note: true,
        status: true,
        createdAt: true,
        updatedAt: true,
        requester: {
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

    res.json({ data: requests.map((item) => toCommunityJoinRequestDto(req, item)) });
  } catch (error) {
    logError("community join requests failed", error);
    res.status(500).json({ error: "community_join_requests_failed" });
  }
});

communityRouter.post("/:communityId/join-requests/:requestId/approve", requireAuth, async (req, res) => {
  const parsed = communityJoinRequestParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsed.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    const membership = access.memberships?.[0] ?? null;
    if (!membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }
    if (!canManageCommunity(membership.role)) {
      res.status(403).json({ error: "community_join_request_review_forbidden" });
      return;
    }

    const requestRow = await prismaCommunityJoinRequest.findFirst({
      where: {
        id: parsed.data.requestId,
        communityId: access.id,
        status: "PENDING"
      },
      select: {
        id: true,
        requesterUserId: true
      }
    });
    if (!requestRow) {
      res.status(404).json({ error: "community_join_request_not_found" });
      return;
    }

    await prismaCommunityMembership.upsert({
      where: {
        communityId_userId: {
          communityId: access.id,
          userId: requestRow.requesterUserId
        }
      },
      create: {
        communityId: access.id,
        userId: requestRow.requesterUserId
      },
      update: {}
    });

    await prismaCommunityJoinRequest.update({
      where: { id: requestRow.id },
      data: {
        status: "APPROVED",
        reviewedByUserId: req.authUserId!,
        reviewedAt: new Date()
      }
    });

    res.json({ data: { approved: true, requestId: requestRow.id } });
  } catch (error) {
    logError("community join request approve failed", error);
    res.status(500).json({ error: "community_join_request_approve_failed" });
  }
});

communityRouter.post("/:communityId/join-requests/:requestId/reject", requireAuth, async (req, res) => {
  const parsed = communityJoinRequestParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsed.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    const membership = access.memberships?.[0] ?? null;
    if (!membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }
    if (!canManageCommunity(membership.role)) {
      res.status(403).json({ error: "community_join_request_review_forbidden" });
      return;
    }

    const requestRow = await prismaCommunityJoinRequest.findFirst({
      where: {
        id: parsed.data.requestId,
        communityId: access.id,
        status: "PENDING"
      },
      select: {
        id: true
      }
    });
    if (!requestRow) {
      res.status(404).json({ error: "community_join_request_not_found" });
      return;
    }

    await prismaCommunityJoinRequest.update({
      where: { id: requestRow.id },
      data: {
        status: "REJECTED",
        reviewedByUserId: req.authUserId!,
        reviewedAt: new Date()
      }
    });

    res.json({ data: { rejected: true, requestId: requestRow.id } });
  } catch (error) {
    logError("community join request reject failed", error);
    res.status(500).json({ error: "community_join_request_reject_failed" });
  }
});

communityRouter.post("/:communityId/invites", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedBody = communityInviteCreateSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsedParams.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    const membership = access.memberships?.[0] ?? null;
    if (!membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }
    if (!canInviteCommunityMembers(membership.role)) {
      res.status(403).json({ error: "community_invite_forbidden" });
      return;
    }

    const targetUser = await prismaUser.findUnique({
      where: {
        id: parsedBody.data.userId
      },
      select: {
        id: true
      }
    });
    if (!targetUser) {
      res.status(404).json({ error: "community_invite_target_not_found" });
      return;
    }

    const existingMembership = await prismaCommunityMembership.findUnique({
      where: {
        communityId_userId: {
          communityId: access.id,
          userId: targetUser.id
        }
      }
    });
    if (existingMembership) {
      res.status(409).json({ error: "community_invite_target_already_member" });
      return;
    }

    const existingInvite = await prismaCommunityInvite.findFirst({
      where: {
        communityId: access.id,
        invitedUserId: targetUser.id,
        status: "PENDING"
      },
      select: {
        id: true
      }
    });

    const invite = existingInvite
      ? await prismaCommunityInvite.update({
          where: { id: existingInvite.id },
          data: {
            note: parsedBody.data.note?.trim() || null
          },
          select: {
            id: true,
            status: true,
            createdAt: true
          }
        })
      : await prismaCommunityInvite.create({
          data: {
            communityId: access.id,
            invitedUserId: targetUser.id,
            createdByUserId: req.authUserId!,
            note: parsedBody.data.note?.trim() || null
          },
          select: {
            id: true,
            status: true,
            createdAt: true
          }
        });

    res.status(201).json({
      data: {
        id: invite.id,
        status: (invite.status ?? "").toLowerCase(),
        createdAt: invite.createdAt.toISOString(),
        userId: targetUser.id
      }
    });
  } catch (error) {
    logError("community invite create failed", error);
    res.status(500).json({ error: "community_invite_create_failed" });
  }
});

communityRouter.get("/:communityId/topics/:topicId", requireAuth, async (req, res) => {
  const parsed = communityTopicParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsed.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    const membership = access.memberships?.[0] ?? null;
    if (!membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }

    const topic: CommunityTopicRow | null = await prismaCommunityTopic.findFirst({
      where: {
        id: parsed.data.topicId,
        communityId: access.id
      },
      select: communityTopicSelect(null)
    });
    if (!topic) {
      res.status(404).json({ error: "community_topic_not_found" });
      return;
    }

    res.json({
      data: toCommunityTopicDto(req, topic, {
        viewerUserId: req.authUserId!,
        viewerRole: membership.role
      })
    });
  } catch (error) {
    logError("community topic detail failed", error);
    res.status(500).json({ error: "community_topic_detail_failed" });
  }
});

communityRouter.post("/:communityId/topics", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedBody = communityCreateTopicSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsedParams.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    const membership = access.memberships?.[0] ?? null;
    if (!membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }

    const dbType =
      parsedBody.data.type === "resource"
        ? "RESOURCE"
        : parsedBody.data.type === "event"
        ? "EVENT"
        : "QUESTION";

    if (!canCreateCommunityTopic(dbType, membership.role)) {
      res.status(403).json({ error: "community_topic_create_forbidden" });
      return;
    }

    const eventStartsAt = parseOptionalDate(parsedBody.data.eventStartsAt);
    if (parsedBody.data.type === "event" && !eventStartsAt) {
      res.status(400).json({ error: "community_event_start_required" });
      return;
    }

    let channelId: string | null = null;
    if (parsedBody.data.channelId) {
      const channel = await prismaCommunityChannel.findFirst({
        where: {
          communityId: access.id,
          OR: [{ id: parsedBody.data.channelId }, { slug: parsedBody.data.channelId }]
        },
        select: {
          id: true
        }
      });
      if (!channel) {
        res.status(404).json({ error: "community_channel_not_found" });
        return;
      }
      channelId = channel.id;
    }

    const created: CommunityTopicRow = await prismaCommunityTopic.create({
      data: {
        communityId: access.id,
        channelId,
        type: dbType,
        title: parsedBody.data.title.trim(),
        body: parsedBody.data.body?.trim() || null,
        authorUserId: req.authUserId!,
        tags: parsedBody.data.tags,
        eventStartsAt,
        isPinned: parsedBody.data.isPinned === true && canPinCommunityTopic(membership.role)
      },
      select: communityTopicSelect(null)
    });

    const actorName = created.author.displayName.trim() || "Bir uye";
    const notificationInputs = await createTopicMentionNotifications({
      text: created.body,
      actorUserId: req.authUserId!,
      actorDisplayName: actorName,
      communityId: access.id,
      communityName: access.name,
      topicId: created.id,
      title: created.title
    });
    await createCommunityNotifications(notificationInputs);
    for (const notificationInput of notificationInputs) {
      emitCommunityNotification([notificationInput.userId], {
        type: notificationInput.type.toLowerCase(),
        communityId: notificationInput.communityId ?? null,
        topicId: notificationInput.topicId ?? null,
        title: notificationInput.title,
        body: notificationInput.body ?? null,
        createdAt: created.createdAt.toISOString()
      });
    }

    res.status(201).json({
      data: toCommunityTopicDto(req, created, {
        viewerUserId: req.authUserId!,
        viewerRole: membership.role
      })
    });
  } catch (error) {
    logError("community topic create failed", error);
    res.status(500).json({ error: "community_topic_create_failed" });
  }
});

communityRouter.post("/:communityId/topics/:topicId/replies", requireAuth, async (req, res) => {
  const parsedParams = communityTopicParamSchema.safeParse(req.params);
  const parsedBody = communityCreateTopicReplySchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsedParams.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    const membership = access.memberships?.[0] ?? null;
    if (!membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }

    const topic = await prismaCommunityTopic.findFirst({
      where: {
        id: parsedParams.data.topicId,
        communityId: access.id
      },
      select: {
        id: true,
        title: true,
        authorUserId: true
      }
    });
    if (!topic) {
      res.status(404).json({ error: "community_topic_not_found" });
      return;
    }

    await prismaCommunityTopicReply.create({
      data: {
        topicId: topic.id,
        authorUserId: req.authUserId!,
        body: parsedBody.data.body.trim()
      }
    });

    const actor = await prismaUser.findUnique({
      where: { id: req.authUserId! },
      select: {
        displayName: true
      }
    });
    const actorName = actor?.displayName?.trim() || "Bir uye";

    const notificationInputs: CreateCommunityNotificationInput[] = [];
    if (topic.authorUserId !== req.authUserId!) {
      notificationInputs.push({
        userId: topic.authorUserId,
        type: "REPLY",
        communityId: access.id,
        topicId: topic.id,
        title: `${actorName} soruna cevap yazdi`,
        body: truncateCommunityText(parsedBody.data.body, 120),
        metadata: {
          communityName: access.name,
          topicTitle: topic.title
        }
      });
    }
    notificationInputs.push(
      ...(await createTopicMentionNotifications({
        text: parsedBody.data.body,
        actorUserId: req.authUserId!,
        actorDisplayName: actorName,
        communityId: access.id,
        communityName: access.name,
        topicId: topic.id,
        title: topic.title
      }))
    );
    await createCommunityNotifications(notificationInputs);
    for (const notificationInput of notificationInputs) {
      emitCommunityNotification([notificationInput.userId], {
        type: notificationInput.type.toLowerCase(),
        communityId: notificationInput.communityId ?? null,
        topicId: notificationInput.topicId ?? null,
        title: notificationInput.title,
        body: notificationInput.body ?? null,
        createdAt: new Date().toISOString()
      });
    }

    const updated: CommunityTopicRow | null = await prismaCommunityTopic.findFirst({
      where: {
        id: topic.id,
        communityId: access.id
      },
      select: communityTopicSelect(null)
    });

    res.status(201).json({
      data: updated
        ? toCommunityTopicDto(req, updated, {
            viewerUserId: req.authUserId!,
            viewerRole: membership.role
          })
        : null
    });
  } catch (error) {
    logError("community topic reply create failed", error);
    res.status(500).json({ error: "community_topic_reply_create_failed" });
  }
});

communityRouter.post(
  "/:communityId/topics/:topicId/replies/:replyId/accept",
  requireAuth,
  async (req, res) => {
    const parsed = communityTopicReplyParamSchema.safeParse(req.params);
    if (!parsed.success) {
      res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
      return;
    }

    try {
      const access = await findCommunityAccess(parsed.data.communityId, req.authUserId!);
      if (!access) {
        res.status(404).json({ error: "community_not_found" });
        return;
      }
      const membership = access.memberships?.[0] ?? null;
      if (!membership) {
        res.status(403).json({ error: "community_membership_required" });
        return;
      }

      const topic = await prismaCommunityTopic.findFirst({
        where: {
          id: parsed.data.topicId,
          communityId: access.id
        },
        select: {
          id: true,
          title: true,
          authorUserId: true
        }
      });
      if (!topic) {
        res.status(404).json({ error: "community_topic_not_found" });
        return;
      }
      if (
        !canAcceptCommunityTopicReply({
          topicAuthorId: topic.authorUserId,
          viewerUserId: req.authUserId!,
          viewerRole: membership.role
        })
      ) {
        res.status(403).json({ error: "community_topic_accept_forbidden" });
        return;
      }

      const reply = await prismaCommunityTopicReply.findFirst({
        where: {
          id: parsed.data.replyId,
          topicId: topic.id
        },
        select: {
          id: true,
          authorUserId: true
        }
      });
      if (!reply) {
        res.status(404).json({ error: "community_topic_reply_not_found" });
        return;
      }

      await prismaCommunityTopicReply.updateMany({
        where: {
          topicId: topic.id
        },
        data: {
          isAccepted: false
        }
      });
      await prismaCommunityTopicReply.update({
        where: { id: reply.id },
        data: {
          isAccepted: true
        }
      });
      await prismaCommunityTopic.update({
        where: { id: topic.id },
        data: {
          isSolved: true
        }
      });

      if (reply.authorUserId !== req.authUserId!) {
        const actor = await prismaUser.findUnique({
          where: { id: req.authUserId! },
          select: { displayName: true }
        });
        const actorName = actor?.displayName?.trim() || "Bir uye";
        const notificationInput: CreateCommunityNotificationInput = {
          userId: reply.authorUserId,
          type: "REPLY",
          communityId: access.id,
          topicId: topic.id,
          title: `${actorName} cevabini kabul etti`,
          body: truncateCommunityText(topic.title, 120),
          metadata: {
            communityName: access.name
          }
        };
        await createCommunityNotifications([notificationInput]);
        emitCommunityNotification([notificationInput.userId], {
          type: notificationInput.type.toLowerCase(),
          communityId: notificationInput.communityId ?? null,
          topicId: notificationInput.topicId ?? null,
          title: notificationInput.title,
          body: notificationInput.body ?? null,
          createdAt: new Date().toISOString()
        });
      }

      const updated: CommunityTopicRow | null = await prismaCommunityTopic.findFirst({
        where: {
          id: topic.id,
          communityId: access.id
        },
        select: communityTopicSelect(null)
      });

      res.json({
        data: updated
          ? toCommunityTopicDto(req, updated, {
              viewerUserId: req.authUserId!,
              viewerRole: membership.role
            })
          : null
      });
    } catch (error) {
      logError("community topic reply accept failed", error);
      res.status(500).json({ error: "community_topic_reply_accept_failed" });
    }
  }
);

communityRouter.post("/:communityId/topics/:topicId/solve", requireAuth, async (req, res) => {
  const parsedParams = communityTopicParamSchema.safeParse(req.params);
  const parsedBody = communityTopicSolvedSchema.safeParse(req.body ?? {});
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsedParams.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    const membership = access.memberships?.[0] ?? null;
    if (!membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }

    const topic = await prismaCommunityTopic.findFirst({
      where: {
        id: parsedParams.data.topicId,
        communityId: access.id
      },
      select: {
        id: true,
        authorUserId: true
      }
    });
    if (!topic) {
      res.status(404).json({ error: "community_topic_not_found" });
      return;
    }
    if (
      !canAcceptCommunityTopicReply({
        topicAuthorId: topic.authorUserId,
        viewerUserId: req.authUserId!,
        viewerRole: membership.role
      })
    ) {
      res.status(403).json({ error: "community_topic_solve_forbidden" });
      return;
    }

    await prismaCommunityTopic.update({
      where: { id: topic.id },
      data: {
        isSolved: parsedBody.data.solved
      }
    });

    const updated: CommunityTopicRow | null = await prismaCommunityTopic.findFirst({
      where: {
        id: topic.id,
        communityId: access.id
      },
      select: communityTopicSelect(null)
    });

    res.json({
      data: updated
        ? toCommunityTopicDto(req, updated, {
            viewerUserId: req.authUserId!,
            viewerRole: membership.role
          })
        : null
    });
  } catch (error) {
    logError("community topic solve failed", error);
    res.status(500).json({ error: "community_topic_solve_failed" });
  }
});

communityRouter.post("/:communityId/topics/:topicId/pin", requireAuth, async (req, res) => {
  const parsedParams = communityTopicParamSchema.safeParse(req.params);
  const parsedBody = communityTopicPinSchema.safeParse(req.body ?? {});
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const access = await findCommunityAccess(parsedParams.data.communityId, req.authUserId!);
    if (!access) {
      res.status(404).json({ error: "community_not_found" });
      return;
    }
    const membership = access.memberships?.[0] ?? null;
    if (!membership) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }
    if (!canPinCommunityTopic(membership.role)) {
      res.status(403).json({ error: "community_topic_pin_forbidden" });
      return;
    }

    const topic = await prismaCommunityTopic.findFirst({
      where: {
        id: parsedParams.data.topicId,
        communityId: access.id
      },
      select: {
        id: true
      }
    });
    if (!topic) {
      res.status(404).json({ error: "community_topic_not_found" });
      return;
    }

    await prismaCommunityTopic.update({
      where: { id: topic.id },
      data: {
        isPinned: parsedBody.data.pinned
      }
    });

    const updated: CommunityTopicRow | null = await prismaCommunityTopic.findFirst({
      where: {
        id: topic.id,
        communityId: access.id
      },
      select: communityTopicSelect(null)
    });

    res.json({
      data: updated
        ? toCommunityTopicDto(req, updated, {
            viewerUserId: req.authUserId!,
            viewerRole: membership.role
          })
        : null
    });
  } catch (error) {
    logError("community topic pin failed", error);
    res.status(500).json({ error: "community_topic_pin_failed" });
  }
});
