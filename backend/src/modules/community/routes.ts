import { Router, type Request } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma.js";
import { logError } from "../../lib/logger.js";
import {
  createCommunityAttachmentUploadUrl,
  createCommunityObjectReadUrl,
  isCommunityAttachmentKeyOwnedByUser,
  isCommunityStorageConfigured
} from "../../lib/storage.js";
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
  emitCommunityMessageUpdate,
  emitCommunityNotification,
  emitCommunityThreadMessage,
  emitCommunityThreadUpdate
} from "./community.realtime.js";
import { chatService } from "../chat/chat.service.js";

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
const prismaCommunityDmRequest = (prisma as unknown as { communityDmRequest: any }).communityDmRequest;
const prismaCommunityBan = (prisma as unknown as { communityBan: any }).communityBan;
const prismaCommunityTopicEventPreference = (prisma as unknown as {
  communityTopicEventPreference: any;
}).communityTopicEventPreference;
const prismaCommunityMessageReaction = (prisma as unknown as {
  communityMessageReaction: any;
}).communityMessageReaction;
const prismaCommunityReport = (prisma as unknown as { communityReport: any }).communityReport;

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

const communityMemberActionParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  userId: z.string().trim().min(1).max(255)
});

const communityMessageActionParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  channelId: z.string().trim().min(1).max(255),
  messageId: z.string().trim().min(1).max(255)
});

const communityDmRequestParamSchema = z.object({
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
  text: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().max(4000).optional().nullable()
    ),
  attachments: z
    .array(
      z.object({
        objectKey: z.string().trim().min(1).max(512),
        kind: z.enum(["image", "video", "file"]),
        fileName: z.string().trim().min(1).max(255).nullable().optional(),
        contentType: z.string().trim().min(1).max(100),
        sizeBytes: z.coerce
          .number()
          .int()
          .min(0)
          .max(500 * 1024 * 1024)
          .nullable()
          .optional(),
        width: z.coerce.number().int().min(0).max(10000).nullable().optional(),
        height: z.coerce.number().int().min(0).max(10000).nullable().optional(),
        durationSeconds: z.coerce
          .number()
          .int()
          .min(0)
          .max(24 * 60 * 60)
          .nullable()
          .optional()
      })
    )
    .max(20)
    .optional()
    .default([]),
  replyToMessageId: z.string().trim().min(1).max(255).optional()
}).superRefine((value, ctx) => {
  if ((value.text?.length ?? 0) > 0 || value.attachments.length > 0) {
    return;
  }

  ctx.addIssue({
    code: z.ZodIssueCode.custom,
    message: "text_or_attachment_required",
    path: ["text"]
  });
});

const communityAttachmentUploadInitSchema = z.object({
  kind: z.enum(["image", "video", "file"]),
  contentType: z.string().trim().min(1).max(100),
  fileName: z.string().trim().min(1).max(255).optional()
}).superRefine((value, ctx) => {
  if (value.kind === "image" && !value.contentType.startsWith("image/")) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "image_content_type_required",
      path: ["contentType"]
    });
  }
  if (value.kind === "video" && !value.contentType.startsWith("video/")) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "video_content_type_required",
      path: ["contentType"]
    });
  }
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
  resourceCategory: z.string().trim().max(60).optional(),
  eventStartsAt: z.string().trim().max(64).optional(),
  eventLocation: z.string().trim().max(160).optional(),
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

const communityTopicEventRsvpSchema = z.object({
  status: z.enum(["going", "maybe", "not_going"])
});

const communityTopicEventReminderSchema = z.object({
  enabled: z.boolean().optional().default(true)
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

const communityInviteListQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  status: z.enum(["pending", "accepted", "rejected"]).optional()
});

const communityDmRequestListQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20)
});

const communityBanListQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(30)
});

const communityDmRequestCreateSchema = z.object({
  userId: z.string().trim().min(1).max(255),
  note: z.string().trim().max(240).optional()
});

const communityMessageReactionSchema = z.object({
  emoji: z.string().trim().min(1).max(16)
});

const communityMessagePinSchema = z.object({
  pinned: z.boolean().optional()
});

const communityReportCreateSchema = z.object({
  reasonCode: z.string().trim().min(2).max(50),
  details: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : value),
      z.string().max(1000).nullable().optional()
    )
});

const communityReportParamSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  reportId: z.string().trim().min(1).max(255)
});

const communityReportListQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  status: z
    .enum(["active", "open", "under_review", "actioned", "rejected", "resolved"])
    .optional()
});

const communityReportStatusSchema = z.object({
  status: z.enum(["under_review", "actioned", "rejected", "resolved"])
});

const communityMuteMemberSchema = z.object({
  minutes: z.coerce.number().int().min(0).max(60 * 24 * 30).default(24 * 60),
  reason: z.string().trim().max(240).optional()
});

const communityBanMemberSchema = z.object({
  reason: z.string().trim().max(240).optional()
});

const communityChannelRestrictionSchema = z.object({
  channelIds: z.array(z.string().trim().min(1).max(255)).max(40).default([])
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
  memberships?: Array<{
    communityRole?: string | null;
  }>;
  updatedAt: Date;
};

type CommunityMembershipRow = {
  role: string;
  communityRole?: string | null;
  joinedAt: Date;
  mutedUntil?: Date | null;
  muteReason?: string | null;
  restrictedChannelIds?: unknown;
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

type CommunityTopicEventPreferenceRow = {
  userId: string;
  status: string | null;
  reminderEnabled: boolean;
};

type CommunityTopicRow = {
  id: string;
  title: string;
  body: string | null;
  type: string;
  tags?: unknown;
  resourceCategory: string | null;
  eventLocation: string | null;
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
  eventPreferences?: CommunityTopicEventPreferenceRow[];
  _count?: {
    replies?: number;
  };
};

type CommunityInviteRow = {
  id: string;
  status: string;
  createdAt: Date;
};

type CommunityInviteListRow = {
  id: string;
  status: string;
  note: string | null;
  createdAt: Date;
  respondedAt: Date | null;
  invitedUser: CommunityUserRow;
  createdBy: CommunityUserRow;
};

type CommunityBanListRow = {
  id: string;
  reason: string | null;
  bannedByUserId: string | null;
  createdAt: Date;
  updatedAt: Date;
  user: CommunityUserRow;
};

type CommunityDmRequestRow = {
  id: string;
  status: string;
  note: string | null;
  createdAt: Date;
  updatedAt: Date;
  requester: CommunityUserRow;
  target: CommunityUserRow;
};

type CommunityMessageRow = {
  id: string;
  text: string | null;
  attachments?: unknown;
  isPinned?: boolean;
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
  reactions?: Array<{
    emoji: string;
    userId: string;
  }>;
  _count?: {
    replies?: number;
  };
};

type CommunityPinnedMessageRow = CommunityMessageRow & {
  channel: {
    id: string;
    slug: string;
    name: string;
    type: string;
  };
};

type CommunityReportRow = {
  id: string;
  reasonCode: string;
  details: string | null;
  status: string;
  createdAt: Date;
  updatedAt: Date;
  reporterUser: CommunityUserRow;
  reportedUser: CommunityUserRow | null;
  message: (CommunityMessageRow & {
    channel: {
      id: string;
      slug: string;
      name: string;
      type: string;
    };
  }) | null;
};

type CommunityMessageAttachment = {
  objectKey: string;
  kind: "image" | "video" | "file";
  fileName: string | null;
  contentType: string;
  sizeBytes: number | null;
  width: number | null;
  height: number | null;
  durationSeconds: number | null;
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

function normalizeUniqueStringList(value: unknown): string[] {
  return [...new Set(normalizeStringList(value))];
}

function communityUserSelectForContext(communityId: string | null | undefined) {
  return {
    id: true,
    displayName: true,
    username: true,
    avatarUrl: true,
    about: true,
    city: true,
    country: true,
    expertise: true,
    communityRole: true,
    updatedAt: true,
    ...(communityId
      ? {
          memberships: {
            where: { communityId },
            take: 1,
            select: {
              communityRole: true
            }
          }
        }
      : {})
  } as const;
}

function normalizeNullableInteger(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.max(0, Math.trunc(value));
}

function normalizeCommunityAttachments(value: unknown): CommunityMessageAttachment[] {
  if (!Array.isArray(value)) return [];

  return value.flatMap<CommunityMessageAttachment>((item) => {
    if (typeof item === "string") {
      const objectKey = item.trim();
      if (!objectKey) return [];
      return [
        {
          objectKey,
          kind: "file",
          fileName: null,
          contentType: "application/octet-stream",
          sizeBytes: null,
          width: null,
          height: null,
          durationSeconds: null
        }
      ];
    }

    if (!item || typeof item !== "object") return [];
    const map = item as Record<string, unknown>;
    const objectKey = typeof map.objectKey === "string" ? map.objectKey.trim() : "";
    if (!objectKey) return [];

    const rawKind = typeof map.kind === "string" ? map.kind.trim().toLowerCase() : "";
    const kind: CommunityMessageAttachment["kind"] =
      rawKind === "image" || rawKind === "video" ? rawKind : "file";

    const contentType = typeof map.contentType === "string" ? map.contentType.trim() : "";
    const fileName =
      typeof map.fileName === "string" && map.fileName.trim().length > 0
        ? map.fileName.trim()
        : null;

    return [
      {
        objectKey,
        kind,
        fileName,
        contentType: contentType || "application/octet-stream",
        sizeBytes: normalizeNullableInteger(map.sizeBytes),
        width: normalizeNullableInteger(map.width),
        height: normalizeNullableInteger(map.height),
        durationSeconds: normalizeNullableInteger(map.durationSeconds)
      }
    ];
  });
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

function toApiEventRsvpStatus(
  value: string | null | undefined
): "going" | "maybe" | "not_going" | null {
  switch ((value ?? "").toUpperCase()) {
    case "GOING":
      return "going";
    case "MAYBE":
      return "maybe";
    case "NOT_GOING":
      return "not_going";
    default:
      return null;
  }
}

function toDbEventRsvpStatus(value: "going" | "maybe" | "not_going"): "GOING" | "MAYBE" | "NOT_GOING" {
  switch (value) {
    case "going":
      return "GOING";
    case "maybe":
      return "MAYBE";
    default:
      return "NOT_GOING";
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

function canModerateCommunityMember(params: {
  viewerRole: string | null | undefined;
  viewerUserId: string;
  targetRole: string | null | undefined;
  targetUserId: string;
}): boolean {
  if (!canManageCommunity(params.viewerRole)) return false;
  if (params.viewerUserId === params.targetUserId) return false;
  return normalizeRolePriority(params.viewerRole) < normalizeRolePriority(params.targetRole);
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

function isCommunityMemberRestrictedFromChannel(
  membership:
    | {
        restrictedChannelIds?: unknown;
      }
    | null
    | undefined,
  channelId: string | null | undefined
) {
  const normalizedChannelId = channelId?.trim();
  if (!normalizedChannelId || !membership) return false;
  return normalizeUniqueStringList(membership.restrictedChannelIds).includes(normalizedChannelId);
}

function canPostCommunityChannel(
  channelType: string | null | undefined,
  role: string | null | undefined,
  options?: {
    channelId?: string | null | undefined;
    membership?:
      | {
          restrictedChannelIds?: unknown;
        }
      | null
      | undefined;
  }
) {
  const normalizedChannel = (channelType ?? "").toUpperCase();
  const normalizedRole = (role ?? "").toUpperCase();
  if (normalizedChannel === "ANNOUNCEMENT") {
    return ["OWNER", "ADMIN", "MODERATOR", "MENTOR"].includes(normalizedRole);
  }
  if (normalizedChannel !== "CHAT") {
    return false;
  }
  return !isCommunityMemberRestrictedFromChannel(options?.membership, options?.channelId);
}

function canPinCommunityMessage(role: string | null | undefined): boolean {
  return ["OWNER", "ADMIN", "MODERATOR", "MENTOR"].includes((role ?? "").toUpperCase());
}

function buildDirectChatId(userA: string, userB: string): string {
  const sorted = [userA, userB].sort();
  return `direct_${sorted[0]}_${sorted[1]}`;
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
        communityRole: true,
        joinedAt: true,
        mutedUntil: true,
        muteReason: true,
        restrictedChannelIds: true
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
      communityRole?: string | null;
      joinedAt: Date;
      mutedUntil?: Date | null;
      muteReason?: string | null;
      restrictedChannelIds?: unknown;
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
    restrictedChannelIds: membership
      ? normalizeUniqueStringList(membership.restrictedChannelIds)
      : [],
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
          communityRole: true,
          joinedAt: true,
          mutedUntil: true,
          muteReason: true,
          restrictedChannelIds: true
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

async function findUserCommunityProfileRole(userId: string): Promise<string | null> {
  const user = await prismaUser.findUnique({
    where: { id: userId },
    select: {
      communityRole: true
    }
  });
  const role = user?.communityRole?.trim();
  return role ? role : null;
}

function toCommunityUserDto(
  req: Request,
  user: CommunityUserRow,
  options?: {
    communityRole?: string | null;
  }
) {
  const membershipRole = options?.communityRole ?? user.memberships?.[0]?.communityRole ?? user.communityRole ?? null;
  return {
    id: user.id,
    displayName: user.displayName,
    username: user.username,
    avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null,
    about: user.about ?? null,
    city: user.city ?? null,
    country: user.country ?? null,
    expertise: user.expertise ?? null,
    communityRole: membershipRole
  };
}

async function toCommunityAttachmentDto(attachment: CommunityMessageAttachment) {
  let url: string | null = null;
  try {
    url = await createCommunityObjectReadUrl(attachment.objectKey);
  } catch (error) {
    logError("community attachment read url failed", {
      objectKey: attachment.objectKey,
      message: error instanceof Error ? error.message : String(error)
    });
  }

  return {
    objectKey: attachment.objectKey,
    kind: attachment.kind,
    fileName: attachment.fileName,
    contentType: attachment.contentType,
    sizeBytes: attachment.sizeBytes,
    width: attachment.width,
    height: attachment.height,
    durationSeconds: attachment.durationSeconds,
    url
  };
}

async function toCommunityMessageDto(
  req: Request,
  row: CommunityMessageRow,
  options?: {
    viewerUserId?: string | null;
  }
) {
  const attachments = normalizeCommunityAttachments(row.attachments);
  const viewerUserId = options?.viewerUserId ?? null;
  const reactionMap = new Map<string, { emoji: string; count: number; reacted: boolean }>();
  for (const reaction of row.reactions ?? []) {
    const emoji = (reaction.emoji ?? "").trim();
    if (!emoji) continue;
    const current = reactionMap.get(emoji) ?? {
      emoji,
      count: 0,
      reacted: false
    };
    current.count += 1;
    if (viewerUserId != null && reaction.userId === viewerUserId) {
      current.reacted = true;
    }
    reactionMap.set(emoji, current);
  }

  return {
    id: row.id,
    text: row.text,
    attachments: await Promise.all(
      attachments.map((attachment) => toCommunityAttachmentDto(attachment))
    ),
    isPinned: Boolean(row.isPinned),
    reactions: Array.from(reactionMap.values()).sort((left, right) => {
      if (left.count != right.count) return right.count - left.count;
      return left.emoji.localeCompare(right.emoji);
    }),
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
  const normalizedTags = normalizeStringList(row.tags);
  const viewerEventPreference =
    viewerUserId == null
      ? null
      : (row.eventPreferences ?? []).find((item) => item.userId === viewerUserId) ?? null;
  const goingCount = (row.eventPreferences ?? []).filter((item) => item.status === "GOING").length;
  const maybeCount = (row.eventPreferences ?? []).filter((item) => item.status === "MAYBE").length;
  const notGoingCount = (row.eventPreferences ?? []).filter((item) => item.status === "NOT_GOING").length;
  const resourceCategory =
    (row.resourceCategory ?? "").trim() ||
    (toApiTopicType(row.type) === "resource" ? normalizedTags[0] ?? "" : "");
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    type: toApiTopicType(row.type),
    tags: normalizedTags,
    resourceCategory: resourceCategory.trim().length === 0 ? null : resourceCategory.trim(),
    eventLocation: row.eventLocation?.trim() || null,
    isPinned: row.isPinned,
    isSolved: row.isSolved,
    eventStartsAt: row.eventStartsAt ? row.eventStartsAt.toISOString() : null,
    event:
      toApiTopicType(row.type) === "event"
        ? {
            counts: {
              going: goingCount,
              maybe: maybeCount,
              notGoing: notGoingCount,
              total: goingCount + maybeCount + notGoingCount
            },
            viewerStatus: toApiEventRsvpStatus(viewerEventPreference?.status),
            reminderEnabled: viewerEventPreference?.reminderEnabled === true
          }
        : null,
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

function toCommunityDmRequestDto(req: Request, row: CommunityDmRequestRow) {
  return {
    id: row.id,
    status: (row.status ?? "").toLowerCase(),
    note: row.note,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    requester: toCommunityUserDto(req, row.requester),
    target: toCommunityUserDto(req, row.target)
  };
}

function toApiInviteStatus(
  value: string | null | undefined
): "pending" | "accepted" | "rejected" {
  switch ((value ?? "").toUpperCase()) {
    case "ACCEPTED":
      return "accepted";
    case "REJECTED":
      return "rejected";
    default:
      return "pending";
  }
}

function toCommunityInviteDto(req: Request, row: CommunityInviteListRow) {
  return {
    id: row.id,
    status: toApiInviteStatus(row.status),
    note: row.note,
    createdAt: row.createdAt.toISOString(),
    respondedAt: row.respondedAt ? row.respondedAt.toISOString() : null,
    invitedUser: toCommunityUserDto(req, row.invitedUser),
    createdBy: toCommunityUserDto(req, row.createdBy)
  };
}

function toCommunityBanDto(req: Request, row: CommunityBanListRow) {
  return {
    id: row.id,
    reason: row.reason,
    bannedByUserId: row.bannedByUserId,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    user: toCommunityUserDto(req, row.user)
  };
}

function toApiReportStatus(
  value: string | null | undefined
): "open" | "under_review" | "actioned" | "rejected" | "resolved" {
  switch ((value ?? "").toUpperCase()) {
    case "UNDER_REVIEW":
      return "under_review";
    case "ACTIONED":
      return "actioned";
    case "REJECTED":
      return "rejected";
    case "RESOLVED":
      return "resolved";
    default:
      return "open";
  }
}

function toDbReportStatus(
  value: "under_review" | "actioned" | "rejected" | "resolved"
): "UNDER_REVIEW" | "ACTIONED" | "REJECTED" | "RESOLVED" {
  switch (value) {
    case "under_review":
      return "UNDER_REVIEW";
    case "actioned":
      return "ACTIONED";
    case "rejected":
      return "REJECTED";
    case "resolved":
      return "RESOLVED";
  }
}

function communityReportWhereByStatus(
  value: "active" | "open" | "under_review" | "actioned" | "rejected" | "resolved" | undefined
) {
  switch (value) {
    case "open":
      return { status: "OPEN" as const };
    case "under_review":
      return { status: "UNDER_REVIEW" as const };
    case "actioned":
      return { status: "ACTIONED" as const };
    case "rejected":
      return { status: "REJECTED" as const };
    case "resolved":
      return { status: "RESOLVED" as const };
    default:
      return { status: { in: ["OPEN", "UNDER_REVIEW"] as const } };
  }
}

async function toCommunityPinnedMessageDto(
  req: Request,
  row: CommunityPinnedMessageRow,
  options?: {
    viewerUserId?: string | null;
  }
) {
  return {
    channel: {
      id: row.channel.id,
      slug: row.channel.slug,
      name: row.channel.name,
      type: toApiChannelType(row.channel.type)
    },
    message: await toCommunityMessageDto(req, row, options)
  };
}

async function toCommunityReportDto(
  req: Request,
  row: CommunityReportRow,
  options?: {
    viewerUserId?: string | null;
  }
) {
  return {
    id: row.id,
    reasonCode: row.reasonCode,
    details: row.details,
    status: toApiReportStatus(row.status),
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    reporter: toCommunityUserDto(req, row.reporterUser),
    reportedUser: row.reportedUser ? toCommunityUserDto(req, row.reportedUser) : null,
    channel: row.message?.channel
      ? {
          id: row.message.channel.id,
          slug: row.message.channel.slug,
          name: row.message.channel.name,
          type: toApiChannelType(row.message.channel.type)
        }
      : null,
    message: row.message
      ? await toCommunityMessageDto(req, row.message, options)
      : null
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

function describeCommunityMessage(
  text: string | null | undefined,
  attachments: CommunityMessageAttachment[]
): string {
  const summary = truncateCommunityText(text, 120);
  if (summary) return summary;
  if (attachments.length === 0) return "";
  if (attachments.length === 1) {
    const attachment = attachments[0];
    if (attachment.kind === "image") return "Bir gorsel paylasti";
    if (attachment.kind === "video") return "Bir video paylasti";
    return attachment.fileName?.trim() || "Bir dosya paylasti";
  }
  return `${attachments.length} medya paylasti`;
}

function isCommunityMemberMuted(mutedUntil: Date | null | undefined): boolean {
  return mutedUntil != null && mutedUntil.getTime() > Date.now();
}

function communityMessageSelect(communityId: string | null | undefined = null) {
  return {
    id: true,
    text: true,
    attachments: true,
    isPinned: true,
    createdAt: true,
    updatedAt: true,
    deletedAt: true,
    replyToMessageId: true,
    author: {
      select: communityUserSelectForContext(communityId)
    },
    replyToMessage: {
      select: {
        id: true,
        text: true,
        author: {
          select: communityUserSelectForContext(communityId)
        }
      }
    },
    reactions: {
      select: {
        emoji: true,
        userId: true
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
  } as const;
}

function communityTopicSelect(replyTake: number | null, communityId: string | null | undefined = null) {
  return {
    id: true,
    title: true,
    body: true,
    type: true,
    tags: true,
    resourceCategory: true,
    eventLocation: true,
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
      select: communityUserSelectForContext(communityId)
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
          select: communityUserSelectForContext(communityId)
        }
      }
    },
    eventPreferences: {
      select: {
        userId: true,
        status: true,
        reminderEnabled: true
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
            type: "RESOURCE"
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
            communityRole: true,
            joinedAt: true,
            user: {
              select: communityUserSelectForContext(null)
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
          user: toCommunityUserDto(req, item.user, {
            communityRole: item.communityRole ?? null
          })
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
        },
        bans: {
          where: {
            userId: req.authUserId!
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

    if (community.bans?.[0]) {
      res.status(403).json({ error: "community_banned" });
      return;
    }

    const visibility = community.visibility ?? "PUBLIC";
    const pendingInvite = community.invites?.[0] ?? null;

    if (visibility === "INVITE_ONLY" && !pendingInvite) {
      res.status(403).json({ error: "community_invite_required" });
      return;
    }

    if (visibility === "REQUEST_ONLY" && !pendingInvite) {
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

    const joiningCommunityRole = await findUserCommunityProfileRole(req.authUserId!);
    const now = new Date();
    await prisma.$transaction(async (tx: any) => {
      await tx.communityMembership.upsert({
        where: {
          communityId_userId: {
            communityId: community.id,
            userId: req.authUserId!
          }
        },
        create: {
          communityId: community.id,
          userId: req.authUserId!,
          communityRole: joiningCommunityRole
        },
        update: {
          ...(joiningCommunityRole ? { communityRole: joiningCommunityRole } : {})
        }
      });
      if (pendingInvite) {
        await tx.communityInvite.update({
          where: { id: pendingInvite.id },
          data: {
            status: "ACCEPTED",
            respondedAt: now
          }
        });
      }
      await tx.communityJoinRequest.deleteMany({
        where: {
          communityId: community.id,
          requesterUserId: req.authUserId!,
          status: "PENDING"
        }
      });
    });

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
        communityRole: true,
        joinedAt: true,
        mutedUntil: true,
        muteReason: true,
        restrictedChannelIds: true,
        user: {
          select: communityUserSelectForContext(access.id)
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
        mutedUntil: item.mutedUntil ? item.mutedUntil.toISOString() : null,
        muteReason: item.muteReason ?? null,
        restrictedChannelIds: normalizeUniqueStringList(item.restrictedChannelIds),
        user: toCommunityUserDto(req, item.user, {
          communityRole: item.communityRole ?? null
        })
      }));

    res.json({ data });
  } catch (error) {
    logError("community members failed", error);
    res.status(500).json({ error: "community_members_failed" });
  }
});

communityRouter.post("/:communityId/members/:userId/mute", requireAuth, async (req, res) => {
  const parsedParams = communityMemberActionParamSchema.safeParse(req.params);
  const parsedBody = communityMuteMemberSchema.safeParse(req.body ?? {});
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
      return;
    }

    const targetMembership = await prismaCommunityMembership.findUnique({
      where: {
        communityId_userId: {
          communityId: access.id,
          userId: parsedParams.data.userId
        }
      },
      select: {
        role: true
      }
    });
    if (!targetMembership) {
      res.status(404).json({ error: "community_member_not_found" });
      return;
    }
    if (
      !canModerateCommunityMember({
        viewerRole: membership.role,
        viewerUserId: req.authUserId!,
        targetRole: targetMembership.role,
        targetUserId: parsedParams.data.userId
      })
    ) {
      res.status(403).json({ error: "community_member_moderation_forbidden" });
      return;
    }

    const mutedUntil =
      parsedBody.data.minutes > 0
        ? new Date(Date.now() + parsedBody.data.minutes * 60 * 1000)
        : null;
    await prismaCommunityMembership.update({
      where: {
        communityId_userId: {
          communityId: access.id,
          userId: parsedParams.data.userId
        }
      },
      data: {
        mutedUntil,
        muteReason: mutedUntil ? parsedBody.data.reason?.trim() || null : null
      }
    });

    res.json({
      data: {
        muted: mutedUntil != null,
        mutedUntil: mutedUntil ? mutedUntil.toISOString() : null
      }
    });
  } catch (error) {
    logError("community member mute failed", error);
    res.status(500).json({ error: "community_member_mute_failed" });
  }
});

communityRouter.post(
  "/:communityId/members/:userId/channel-restrictions",
  requireAuth,
  async (req, res) => {
    const parsedParams = communityMemberActionParamSchema.safeParse(req.params);
    const parsedBody = communityChannelRestrictionSchema.safeParse(req.body ?? {});
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
      if (isCommunityMemberMuted(membership.mutedUntil)) {
        res.status(403).json({ error: "community_member_muted" });
        return;
      }

      const targetMembership = await prismaCommunityMembership.findUnique({
        where: {
          communityId_userId: {
            communityId: access.id,
            userId: parsedParams.data.userId
          }
        },
        select: {
          role: true
        }
      });
      if (!targetMembership) {
        res.status(404).json({ error: "community_member_not_found" });
        return;
      }
      if (
        !canModerateCommunityMember({
          viewerRole: membership.role,
          viewerUserId: req.authUserId!,
          targetRole: targetMembership.role,
          targetUserId: parsedParams.data.userId
        })
      ) {
        res.status(403).json({ error: "community_member_moderation_forbidden" });
        return;
      }

      const requestedChannelIds = normalizeUniqueStringList(parsedBody.data.channelIds);
      if (requestedChannelIds.length > 0) {
        const channels = await prismaCommunityChannel.findMany({
          where: {
            communityId: access.id,
            id: { in: requestedChannelIds },
            type: "CHAT"
          },
          select: {
            id: true
          }
        });
        if (channels.length !== requestedChannelIds.length) {
          res.status(400).json({ error: "community_channel_restrictions_invalid" });
          return;
        }
      }

      await prismaCommunityMembership.update({
        where: {
          communityId_userId: {
            communityId: access.id,
            userId: parsedParams.data.userId
          }
        },
        data: {
          restrictedChannelIds:
            requestedChannelIds.length > 0 ? requestedChannelIds : null
        }
      });

      res.json({
        data: {
          userId: parsedParams.data.userId,
          restrictedChannelIds: requestedChannelIds
        }
      });
    } catch (error) {
      logError("community member channel restrictions failed", error);
      res.status(500).json({ error: "community_member_channel_restrictions_failed" });
    }
  }
);

communityRouter.post("/:communityId/members/:userId/ban", requireAuth, async (req, res) => {
  const parsedParams = communityMemberActionParamSchema.safeParse(req.params);
  const parsedBody = communityBanMemberSchema.safeParse(req.body ?? {});
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
      return;
    }

    const targetMembership = await prismaCommunityMembership.findUnique({
      where: {
        communityId_userId: {
          communityId: access.id,
          userId: parsedParams.data.userId
        }
      },
      select: {
        role: true
      }
    });
    if (!targetMembership) {
      res.status(404).json({ error: "community_member_not_found" });
      return;
    }
    if (
      !canModerateCommunityMember({
        viewerRole: membership.role,
        viewerUserId: req.authUserId!,
        targetRole: targetMembership.role,
        targetUserId: parsedParams.data.userId
      })
    ) {
      res.status(403).json({ error: "community_member_moderation_forbidden" });
      return;
    }

    await prisma.$transaction(async (tx: any) => {
      await tx.communityBan.upsert({
        where: {
          communityId_userId: {
            communityId: access.id,
            userId: parsedParams.data.userId
          }
        },
        create: {
          communityId: access.id,
          userId: parsedParams.data.userId,
          reason: parsedBody.data.reason?.trim() || null,
          bannedByUserId: req.authUserId!
        },
        update: {
          reason: parsedBody.data.reason?.trim() || null,
          bannedByUserId: req.authUserId!
        }
      });
      await tx.communityMembership.delete({
        where: {
          communityId_userId: {
            communityId: access.id,
            userId: parsedParams.data.userId
          }
        }
      });
      await tx.communityDmRequest.updateMany({
        where: {
          communityId: access.id,
          OR: [
            { requesterUserId: parsedParams.data.userId, status: "PENDING" },
            { targetUserId: parsedParams.data.userId, status: "PENDING" }
          ]
        },
        data: {
          status: "REJECTED",
          respondedAt: new Date()
        }
      });
    });

    res.json({ data: { banned: true } });
  } catch (error) {
    logError("community member ban failed", error);
    res.status(500).json({ error: "community_member_ban_failed" });
  }
});

communityRouter.post("/:communityId/members/:userId/unban", requireAuth, async (req, res) => {
  const parsedParams = communityMemberActionParamSchema.safeParse(req.params);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
      return;
    }
    if (!canManageCommunity(membership.role)) {
      res.status(403).json({ error: "community_member_moderation_forbidden" });
      return;
    }

    const activeBan = await prismaCommunityBan.findUnique({
      where: {
        communityId_userId: {
          communityId: access.id,
          userId: parsedParams.data.userId
        }
      },
      select: { id: true }
    });
    if (!activeBan) {
      res.status(404).json({ error: "community_ban_not_found" });
      return;
    }

    await prismaCommunityBan.delete({
      where: {
        communityId_userId: {
          communityId: access.id,
          userId: parsedParams.data.userId
        }
      }
    });

    res.json({ data: { unbanned: true } });
  } catch (error) {
    logError("community member unban failed", error);
    res.status(500).json({ error: "community_member_unban_failed" });
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
                { body: { contains: parsedQuery.data.q, mode: "insensitive" } },
                { resourceCategory: { contains: parsedQuery.data.q, mode: "insensitive" } },
                { eventLocation: { contains: parsedQuery.data.q, mode: "insensitive" } }
              ]
            }
          : {})
      },
      take: parsedQuery.data.limit,
      orderBy: [{ isPinned: "desc" }, { createdAt: "desc" }],
      select: communityTopicSelect(2, access.id)
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
      orderBy: [{ isPinned: "desc" }, { createdAt: "desc" }],
      select: communityMessageSelect(access.community.id)
    });

    const items = await Promise.all(
      messages
        .reverse()
        .map((item: CommunityMessageRow) =>
          toCommunityMessageDto(req, item, {
            viewerUserId: req.authUserId!
          })
        )
    );
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
          select: communityMessageSelect(access.community.id)
        }),
        prismaCommunityMessage.findMany({
          where: {
            channelId: access.channel.id,
            deletedAt: null,
            replyToMessageId: rootMessageId
          },
          orderBy: [{ createdAt: "asc" }],
          select: communityMessageSelect(access.community.id)
        })
      ]);

      if (!root) {
        res.status(404).json({ error: "community_message_not_found" });
        return;
      }

      res.json({
        data: {
          root: await toCommunityMessageDto(req, root, {
            viewerUserId: req.authUserId!
          }),
          replies: await Promise.all(
            replies.map((item: CommunityMessageRow) =>
              toCommunityMessageDto(req, item, {
                viewerUserId: req.authUserId!
              })
            )
          )
        }
      });
    } catch (error) {
      logError("community thread failed", error);
      res.status(500).json({ error: "community_thread_failed" });
    }
  }
);

communityRouter.post(
  "/:communityId/channels/:channelId/attachments/upload-url",
  requireAuth,
  async (req, res) => {
    if (!isCommunityStorageConfigured()) {
      res.status(503).json({ error: "community_storage_not_configured" });
      return;
    }

    const parsedParams = communityChannelParamSchema.safeParse(req.params);
    const parsedBody = communityAttachmentUploadInitSchema.safeParse(req.body);
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
      if (
        !canPostCommunityChannel(access.channel.type, access.membership.role, {
          channelId: access.channel.id,
          membership: access.membership
        })
      ) {
        res.status(403).json({
          error: isCommunityMemberRestrictedFromChannel(access.membership, access.channel.id)
            ? "community_member_channel_restricted"
            : "community_channel_write_forbidden"
        });
        return;
      }

      const upload = await createCommunityAttachmentUploadUrl({
        communityId: access.community.id,
        userId: req.authUserId!,
        kind: parsedBody.data.kind,
        contentType: parsedBody.data.contentType,
        fileName: parsedBody.data.fileName
      });

      res.json({
        data: {
          objectKey: upload.objectKey,
          uploadUrl: upload.uploadUrl,
          headers: upload.headers
        }
      });
    } catch (error) {
      logError("community attachment upload init failed", error);
      res.status(500).json({ error: "community_attachment_upload_init_failed" });
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
    const attachments = parsedBody.data.attachments.map((attachment) => ({
      objectKey: attachment.objectKey,
      kind: attachment.kind,
      fileName: attachment.fileName ?? null,
      contentType: attachment.contentType,
      sizeBytes: attachment.sizeBytes ?? null,
      width: attachment.width ?? null,
      height: attachment.height ?? null,
      durationSeconds: attachment.durationSeconds ?? null
    }));

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
    if (
      !canPostCommunityChannel(access.channel.type, access.membership.role, {
        channelId: access.channel.id,
        membership: access.membership
      })
    ) {
      res.status(403).json({
        error: isCommunityMemberRestrictedFromChannel(access.membership, access.channel.id)
          ? "community_member_channel_restricted"
          : "community_channel_write_forbidden"
      });
      return;
    }
    if (isCommunityMemberMuted(access.membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
      return;
    }

    for (const attachment of attachments) {
      if (
        !isCommunityAttachmentKeyOwnedByUser({
          communityId: access.community.id,
          userId: req.authUserId!,
          objectKey: attachment.objectKey
        })
      ) {
        res.status(403).json({ error: "invalid_attachment_key" });
        return;
      }
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
        text: parsedBody.data.text ?? null,
        replyToMessageId,
        attachments
      },
      select: communityMessageSelect(access.community.id)
    });

    const senderDisplayName = created.author.displayName.trim() || "Bir uye";
    const messageSummary = describeCommunityMessage(parsedBody.data.text, attachments);
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
        body: messageSummary,
        metadata: {
          channelName: access.channel.name,
          communityName: access.community.name
        }
      });
      notifiedUserIds.add(replyTarget.authorUserId);
    }

    const mentionedUsernames = extractMentionedUsernames(parsedBody.data.text ?? "");
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
          body: messageSummary,
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
          body: messageSummary,
          metadata: {
            channelName: access.channel.name,
            communityName: access.community.name
          }
        });
      }
    }

    await createCommunityNotifications(notificationInputs);

    const createdDto = await toCommunityMessageDto(req, created, {
      viewerUserId: req.authUserId!
    });
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

communityRouter.post(
  "/:communityId/channels/:channelId/messages/:messageId/reactions",
  requireAuth,
  async (req, res) => {
    const parsedParams = communityMessageActionParamSchema.safeParse(req.params);
    const parsedBody = communityMessageReactionSchema.safeParse(req.body);
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

      const message = await prismaCommunityMessage.findFirst({
        where: {
          id: parsedParams.data.messageId,
          channelId: access.channel?.id ?? ""
        },
        select: communityMessageSelect(access.community.id)
      });
      if (!message) {
        res.status(404).json({ error: "community_message_not_found" });
        return;
      }

      const emoji = parsedBody.data.emoji.trim();
      const existing = await prismaCommunityMessageReaction.findFirst({
        where: {
          messageId: message.id,
          userId: req.authUserId!,
          emoji
        },
        select: { id: true }
      });

      if (existing) {
        await prismaCommunityMessageReaction.delete({
          where: { id: existing.id }
        });
      } else {
        await prismaCommunityMessageReaction.create({
          data: {
            messageId: message.id,
            userId: req.authUserId!,
            emoji
          }
        });
      }

      const updated = await prismaCommunityMessage.findFirst({
        where: { id: message.id },
        select: communityMessageSelect(access.community.id)
      });
      if (!updated || !access.channel) {
        res.status(404).json({ error: "community_message_not_found" });
        return;
      }

      const rootMessageId = updated.replyToMessageId ?? updated.id;
      const dto = await toCommunityMessageDto(req, updated as CommunityMessageRow, {
        viewerUserId: req.authUserId!
      });
      emitCommunityMessageUpdate({
        communityId: access.community.id,
        channelId: access.channel.id,
        rootMessageId,
        message: dto
      });

      res.json({ data: dto });
    } catch (error) {
      logError("community message reaction failed", error);
      res.status(500).json({ error: "community_message_reaction_failed" });
    }
  }
);

communityRouter.post(
  "/:communityId/channels/:channelId/messages/:messageId/pin",
  requireAuth,
  async (req, res) => {
    const parsedParams = communityMessageActionParamSchema.safeParse(req.params);
    const parsedBody = communityMessagePinSchema.safeParse(req.body ?? {});
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
      if (!canPinCommunityMessage(access.membership.role)) {
        res.status(403).json({ error: "community_message_pin_forbidden" });
        return;
      }

      const existing = await prismaCommunityMessage.findFirst({
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
      if (!existing) {
        res.status(404).json({ error: "community_message_not_found" });
        return;
      }

      await prismaCommunityMessage.update({
        where: { id: existing.id },
        data: {
          isPinned: parsedBody.data.pinned ?? true
        }
      });

      const updated = await prismaCommunityMessage.findFirst({
        where: { id: existing.id },
        select: communityMessageSelect(access.community.id)
      });
      if (!updated) {
        res.status(404).json({ error: "community_message_not_found" });
        return;
      }

      const rootMessageId = updated.replyToMessageId ?? updated.id;
      const dto = await toCommunityMessageDto(req, updated as CommunityMessageRow, {
        viewerUserId: req.authUserId!
      });
      emitCommunityMessageUpdate({
        communityId: access.community.id,
        channelId: access.channel.id,
        rootMessageId,
        message: dto
      });

      res.json({ data: dto });
    } catch (error) {
      logError("community message pin failed", error);
      res.status(500).json({ error: "community_message_pin_failed" });
    }
  }
);

communityRouter.post(
  "/:communityId/channels/:channelId/messages/:messageId/report",
  requireAuth,
  async (req, res) => {
    const parsedParams = communityMessageActionParamSchema.safeParse(req.params);
    const parsedBody = communityReportCreateSchema.safeParse(req.body);
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

      const message = await prismaCommunityMessage.findFirst({
        where: {
          id: parsedParams.data.messageId,
          channelId: access.channel.id,
          deletedAt: null
        },
        select: {
          id: true,
          authorUserId: true
        }
      });
      if (!message) {
        res.status(404).json({ error: "community_message_not_found" });
        return;
      }
      if (message.authorUserId === req.authUserId!) {
        res.status(400).json({ error: "community_report_self_forbidden" });
        return;
      }

      await prismaCommunityReport.create({
        data: {
          communityId: access.community.id,
          reporterUserId: req.authUserId!,
          reportedUserId: message.authorUserId,
          messageId: message.id,
          reasonCode: parsedBody.data.reasonCode,
          details: parsedBody.data.details?.trim() || null
        }
      });

      res.status(201).json({ data: { reported: true } });
    } catch (error) {
      logError("community message report failed", error);
      res.status(500).json({ error: "community_message_report_failed" });
    }
  }
);

communityRouter.get("/:communityId/pinned-messages", requireAuth, async (req, res) => {
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

    const messages: CommunityPinnedMessageRow[] = await prismaCommunityMessage.findMany({
      where: {
        channel: {
          communityId: access.id
        },
        isPinned: true,
        replyToMessageId: null,
        deletedAt: null
      },
      take: parsedQuery.data.limit,
      orderBy: [{ updatedAt: "desc" }],
      select: {
        ...communityMessageSelect(access.id),
        channel: {
          select: {
            id: true,
            slug: true,
            name: true,
            type: true
          }
        }
      }
    });

    res.json({
      data: await Promise.all(
        messages.map((item) =>
          toCommunityPinnedMessageDto(req, item, {
            viewerUserId: req.authUserId!
          })
        )
      )
    });
  } catch (error) {
    logError("community pinned messages failed", error);
    res.status(500).json({ error: "community_pinned_messages_failed" });
  }
});

communityRouter.get("/:communityId/reports", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedQuery = communityReportListQuerySchema.safeParse(req.query);
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
      return;
    }
    if (!canManageCommunity(membership.role)) {
      res.status(403).json({ error: "community_report_review_forbidden" });
      return;
    }

    const reports: CommunityReportRow[] = await prismaCommunityReport.findMany({
      where: {
        communityId: access.id,
        ...communityReportWhereByStatus(parsedQuery.data.status)
      },
      take: parsedQuery.data.limit,
      orderBy: [{ createdAt: "desc" }],
      select: {
        id: true,
        reasonCode: true,
        details: true,
        status: true,
        createdAt: true,
        updatedAt: true,
        reporterUser: {
          select: communityUserSelectForContext(access.id)
        },
        reportedUser: {
          select: communityUserSelectForContext(access.id)
        },
        message: {
          select: {
            ...communityMessageSelect(access.id),
            channel: {
              select: {
                id: true,
                slug: true,
                name: true,
                type: true
              }
            }
          }
        }
      }
    });

    res.json({
      data: await Promise.all(
        reports.map((item) =>
          toCommunityReportDto(req, item, {
            viewerUserId: req.authUserId!
          })
        )
      )
    });
  } catch (error) {
    logError("community reports failed", error);
    res.status(500).json({ error: "community_reports_failed" });
  }
});

communityRouter.post("/:communityId/reports/:reportId/status", requireAuth, async (req, res) => {
  const parsedParams = communityReportParamSchema.safeParse(req.params);
  const parsedBody = communityReportStatusSchema.safeParse(req.body);
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
      return;
    }
    if (!canManageCommunity(membership.role)) {
      res.status(403).json({ error: "community_report_review_forbidden" });
      return;
    }

    const existing = await prismaCommunityReport.findFirst({
      where: {
        id: parsedParams.data.reportId,
        communityId: access.id
      },
      select: {
        id: true
      }
    });
    if (!existing) {
      res.status(404).json({ error: "community_report_not_found" });
      return;
    }

    const updated = await prismaCommunityReport.update({
      where: { id: existing.id },
      data: {
        status: toDbReportStatus(parsedBody.data.status)
      },
      select: {
        id: true,
        status: true,
        updatedAt: true
      }
    });

    res.json({
      data: {
        id: updated.id,
        status: toApiReportStatus(updated.status),
        updatedAt: updated.updatedAt.toISOString()
      }
    });
  } catch (error) {
    logError("community report update failed", error);
    res.status(500).json({ error: "community_report_update_failed" });
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
            { body: { contains: parsedQuery.data.q, mode: "insensitive" } },
            { resourceCategory: { contains: parsedQuery.data.q, mode: "insensitive" } },
            { eventLocation: { contains: parsedQuery.data.q, mode: "insensitive" } }
          ]
        },
        take: parsedQuery.data.limit,
        orderBy: [{ isPinned: "desc" }, { updatedAt: "desc" }],
        select: communityTopicSelect(1, access.id)
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
          communityRole: true,
          joinedAt: true,
          user: {
            select: communityUserSelectForContext(access.id)
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
          user: toCommunityUserDto(req, item.user, {
            communityRole: item.communityRole ?? null
          })
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
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
          select: communityUserSelectForContext(access.id)
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
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

    const requesterCommunityRole = await findUserCommunityProfileRole(requestRow.requesterUserId);
    await prismaCommunityMembership.upsert({
      where: {
        communityId_userId: {
          communityId: access.id,
          userId: requestRow.requesterUserId
        }
      },
      create: {
        communityId: access.id,
        userId: requestRow.requesterUserId,
        communityRole: requesterCommunityRole
      },
      update: {
        ...(requesterCommunityRole ? { communityRole: requesterCommunityRole } : {})
      }
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
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

communityRouter.get("/:communityId/invites", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedQuery = communityInviteListQuerySchema.safeParse(req.query);
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
      return;
    }
    if (!canInviteCommunityMembers(membership.role)) {
      res.status(403).json({ error: "community_invite_forbidden" });
      return;
    }

    const statusWhere =
      parsedQuery.data.status === "accepted"
        ? { status: "ACCEPTED" as const }
        : parsedQuery.data.status === "rejected"
        ? { status: "REJECTED" as const }
        : parsedQuery.data.status === "pending"
        ? { status: "PENDING" as const }
        : {};

    const invites: CommunityInviteListRow[] = await prismaCommunityInvite.findMany({
      where: {
        communityId: access.id,
        ...statusWhere
      },
      take: parsedQuery.data.limit,
      orderBy: [{ updatedAt: "desc" }],
      select: {
        id: true,
        status: true,
        note: true,
        createdAt: true,
        respondedAt: true,
        invitedUser: {
          select: communityUserSelectForContext(access.id)
        },
        createdBy: {
          select: communityUserSelectForContext(access.id)
        }
      }
    });

    res.json({ data: invites.map((item) => toCommunityInviteDto(req, item)) });
  } catch (error) {
    logError("community invites failed", error);
    res.status(500).json({ error: "community_invites_failed" });
  }
});

communityRouter.get("/:communityId/bans", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedQuery = communityBanListQuerySchema.safeParse(req.query);
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
    if (isCommunityMemberMuted(membership.mutedUntil)) {
      res.status(403).json({ error: "community_member_muted" });
      return;
    }
    if (!canManageCommunity(membership.role)) {
      res.status(403).json({ error: "community_member_moderation_forbidden" });
      return;
    }

    const bans: CommunityBanListRow[] = await prismaCommunityBan.findMany({
      where: {
        communityId: access.id
      },
      take: parsedQuery.data.limit,
      orderBy: [{ createdAt: "desc" }],
      select: {
        id: true,
        reason: true,
        bannedByUserId: true,
        createdAt: true,
        updatedAt: true,
        user: {
          select: communityUserSelectForContext(access.id)
        }
      }
    });

    res.json({ data: bans.map((item) => toCommunityBanDto(req, item)) });
  } catch (error) {
    logError("community bans failed", error);
    res.status(500).json({ error: "community_bans_failed" });
  }
});

communityRouter.get("/:communityId/dm-requests", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedQuery = communityDmRequestListQuerySchema.safeParse(req.query);
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

    const [incomingRows, sentRows] = await Promise.all([
      prismaCommunityDmRequest.findMany({
        where: {
          communityId: access.id,
          targetUserId: req.authUserId!,
          status: "PENDING"
        },
        take: parsedQuery.data.limit,
        orderBy: [{ createdAt: "desc" }],
        select: {
          id: true,
          status: true,
          note: true,
          createdAt: true,
          updatedAt: true,
          requester: {
            select: communityUserSelectForContext(access.id)
          },
          target: {
            select: communityUserSelectForContext(access.id)
          }
        }
      }),
      prismaCommunityDmRequest.findMany({
        where: {
          communityId: access.id,
          requesterUserId: req.authUserId!,
          status: "PENDING"
        },
        take: parsedQuery.data.limit,
        orderBy: [{ createdAt: "desc" }],
        select: {
          id: true,
          status: true,
          note: true,
          createdAt: true,
          updatedAt: true,
          requester: {
            select: communityUserSelectForContext(access.id)
          },
          target: {
            select: communityUserSelectForContext(access.id)
          }
        }
      })
    ]);

    res.json({
      data: {
        incoming: (incomingRows as CommunityDmRequestRow[]).map((row) =>
          toCommunityDmRequestDto(req, row)
        ),
        sent: (sentRows as CommunityDmRequestRow[]).map((row) =>
          toCommunityDmRequestDto(req, row)
        )
      }
    });
  } catch (error) {
    logError("community dm requests failed", error);
    res.status(500).json({ error: "community_dm_requests_failed" });
  }
});

communityRouter.post("/:communityId/dm-requests", requireAuth, async (req, res) => {
  const parsedParams = communityParamSchema.safeParse(req.params);
  const parsedBody = communityDmRequestCreateSchema.safeParse(req.body);
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
    if (!access.memberships?.[0]) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }
    if (parsedBody.data.userId === req.authUserId!) {
      res.status(400).json({ error: "community_dm_request_self_forbidden" });
      return;
    }

    const [targetMembership, activeBan, existingPending, recentRejection, recentByRequester] =
      await Promise.all([
        prismaCommunityMembership.findUnique({
          where: {
            communityId_userId: {
              communityId: access.id,
              userId: parsedBody.data.userId
            }
          },
          select: {
            userId: true,
            role: true,
            joinedAt: true,
            mutedUntil: true,
            muteReason: true,
            user: {
              select: communityUserSelectForContext(access.id)
            }
          }
        }),
        prismaCommunityBan.findUnique({
          where: {
            communityId_userId: {
              communityId: access.id,
              userId: parsedBody.data.userId
            }
          },
          select: { id: true }
        }),
        prismaCommunityDmRequest.findFirst({
          where: {
            communityId: access.id,
            requesterUserId: req.authUserId!,
            targetUserId: parsedBody.data.userId,
            status: "PENDING"
          },
          select: { id: true }
        }),
        prismaCommunityDmRequest.findFirst({
          where: {
            communityId: access.id,
            requesterUserId: req.authUserId!,
            targetUserId: parsedBody.data.userId,
            status: "REJECTED",
            updatedAt: {
              gt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
            }
          },
          select: { id: true }
        }),
        prismaCommunityDmRequest.count({
          where: {
            communityId: access.id,
            requesterUserId: req.authUserId!,
            createdAt: {
              gt: new Date(Date.now() - 24 * 60 * 60 * 1000)
            }
          }
        })
      ]);

    if (!targetMembership || activeBan) {
      res.status(404).json({ error: "community_dm_request_target_not_found" });
      return;
    }
    if (existingPending) {
      res.status(409).json({ error: "community_dm_request_already_pending" });
      return;
    }
    if (recentRejection) {
      res.status(429).json({ error: "community_dm_request_cooldown_active" });
      return;
    }
    if (recentByRequester >= 15) {
      res.status(429).json({ error: "community_dm_request_rate_limited" });
      return;
    }

    const created = await prismaCommunityDmRequest.create({
      data: {
        communityId: access.id,
        requesterUserId: req.authUserId!,
        targetUserId: parsedBody.data.userId,
        note: parsedBody.data.note?.trim() || null
      },
      select: {
        id: true,
        status: true,
        note: true,
        createdAt: true,
        updatedAt: true,
        requester: {
          select: communityUserSelectForContext(access.id)
        },
        target: {
          select: communityUserSelectForContext(access.id)
        }
      }
    });

    const senderLabel = created.requester.displayName.trim() || "Bir uye";
    const notification = {
      userId: parsedBody.data.userId,
      type: "DM_REQUEST" as const,
      communityId: access.id,
      title: `${senderLabel} senden DM izni istedi`,
      body: truncateCommunityText(parsedBody.data.note, 120),
      metadata: {
        requesterUserId: req.authUserId!,
        targetUserId: parsedBody.data.userId,
        communityName: access.name
      }
    };
    await createCommunityNotifications([notification]);
    emitCommunityNotification([parsedBody.data.userId], {
      type: "dm_request",
      communityId: access.id,
      channelId: null,
      messageId: null,
      title: notification.title,
      body: notification.body ?? null,
      createdAt: created.createdAt.toISOString()
    });

    res.status(201).json({ data: toCommunityDmRequestDto(req, created as CommunityDmRequestRow) });
  } catch (error) {
    logError("community dm request create failed", error);
    res.status(500).json({ error: "community_dm_request_create_failed" });
  }
});

communityRouter.post("/:communityId/dm-requests/:requestId/accept", requireAuth, async (req, res) => {
  const parsed = communityDmRequestParamSchema.safeParse(req.params);
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
    if (!access.memberships?.[0]) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }

    const requestRow = await prismaCommunityDmRequest.findFirst({
      where: {
        id: parsed.data.requestId,
        communityId: access.id,
        targetUserId: req.authUserId!,
        status: "PENDING"
      },
      select: {
        id: true,
        requesterUserId: true
      }
    });
    if (!requestRow) {
      res.status(404).json({ error: "community_dm_request_not_found" });
      return;
    }

    const chatId = buildDirectChatId(requestRow.requesterUserId, req.authUserId!);
    await chatService.ensureChatAccess(chatId, req.authUserId!);
    await prismaCommunityDmRequest.update({
      where: { id: requestRow.id },
      data: {
        status: "ACCEPTED",
        respondedAt: new Date()
      }
    });

    const notification = {
      userId: requestRow.requesterUserId,
      type: "DM_REQUEST" as const,
      communityId: access.id,
      title: "DM istegin kabul edildi",
      body: `${access.name} toplulugunda mesajlasma acildi.`,
      metadata: {
        chatId,
        communityName: access.name
      }
    };
    await createCommunityNotifications([notification]);
    emitCommunityNotification([requestRow.requesterUserId], {
      type: "dm_request",
      communityId: access.id,
      channelId: null,
      messageId: null,
      title: notification.title,
      body: notification.body,
      createdAt: new Date().toISOString()
    });

    res.json({ data: { accepted: true, chatId } });
  } catch (error) {
    logError("community dm request accept failed", error);
    res.status(500).json({ error: "community_dm_request_accept_failed" });
  }
});

communityRouter.post("/:communityId/dm-requests/:requestId/reject", requireAuth, async (req, res) => {
  const parsed = communityDmRequestParamSchema.safeParse(req.params);
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
    if (!access.memberships?.[0]) {
      res.status(403).json({ error: "community_membership_required" });
      return;
    }

    const requestRow = await prismaCommunityDmRequest.findFirst({
      where: {
        id: parsed.data.requestId,
        communityId: access.id,
        targetUserId: req.authUserId!,
        status: "PENDING"
      },
      select: {
        id: true
      }
    });
    if (!requestRow) {
      res.status(404).json({ error: "community_dm_request_not_found" });
      return;
    }

    await prismaCommunityDmRequest.update({
      where: { id: requestRow.id },
      data: {
        status: "REJECTED",
        respondedAt: new Date()
      }
    });

    res.json({ data: { rejected: true } });
  } catch (error) {
    logError("community dm request reject failed", error);
    res.status(500).json({ error: "community_dm_request_reject_failed" });
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
      select: communityTopicSelect(null, access.id)
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

communityRouter.post("/:communityId/topics/:topicId/rsvp", requireAuth, async (req, res) => {
  const parsedParams = communityTopicParamSchema.safeParse(req.params);
  const parsedBody = communityTopicEventRsvpSchema.safeParse(req.body ?? {});
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
        type: true
      }
    });
    if (!topic) {
      res.status(404).json({ error: "community_topic_not_found" });
      return;
    }
    if ((topic.type ?? "").toUpperCase() !== "EVENT") {
      res.status(400).json({ error: "community_topic_event_required" });
      return;
    }

    await prismaCommunityTopicEventPreference.upsert({
      where: {
        topicId_userId: {
          topicId: topic.id,
          userId: req.authUserId!
        }
      },
      create: {
        topicId: topic.id,
        userId: req.authUserId!,
        status: toDbEventRsvpStatus(parsedBody.data.status)
      },
      update: {
        status: toDbEventRsvpStatus(parsedBody.data.status)
      }
    });

    const updated: CommunityTopicRow | null = await prismaCommunityTopic.findFirst({
      where: {
        id: topic.id,
        communityId: access.id
      },
      select: communityTopicSelect(null, access.id)
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
    logError("community topic rsvp failed", error);
    res.status(500).json({ error: "community_topic_rsvp_failed" });
  }
});

communityRouter.post("/:communityId/topics/:topicId/reminder", requireAuth, async (req, res) => {
  const parsedParams = communityTopicParamSchema.safeParse(req.params);
  const parsedBody = communityTopicEventReminderSchema.safeParse(req.body ?? {});
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
        type: true
      }
    });
    if (!topic) {
      res.status(404).json({ error: "community_topic_not_found" });
      return;
    }
    if ((topic.type ?? "").toUpperCase() !== "EVENT") {
      res.status(400).json({ error: "community_topic_event_required" });
      return;
    }

    const existingPreference = await prismaCommunityTopicEventPreference.findUnique({
      where: {
        topicId_userId: {
          topicId: topic.id,
          userId: req.authUserId!
        }
      },
      select: {
        status: true
      }
    });

    if (existingPreference) {
      if (!parsedBody.data.enabled && existingPreference.status == null) {
        await prismaCommunityTopicEventPreference.delete({
          where: {
            topicId_userId: {
              topicId: topic.id,
              userId: req.authUserId!
            }
          }
        });
      } else {
        await prismaCommunityTopicEventPreference.update({
          where: {
            topicId_userId: {
              topicId: topic.id,
              userId: req.authUserId!
            }
          },
          data: {
            reminderEnabled: parsedBody.data.enabled
          }
        });
      }
    } else if (parsedBody.data.enabled) {
      await prismaCommunityTopicEventPreference.create({
        data: {
          topicId: topic.id,
          userId: req.authUserId!,
          reminderEnabled: true
        }
      });
    }

    const updated: CommunityTopicRow | null = await prismaCommunityTopic.findFirst({
      where: {
        id: topic.id,
        communityId: access.id
      },
      select: communityTopicSelect(null, access.id)
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
    logError("community topic reminder failed", error);
    res.status(500).json({ error: "community_topic_reminder_failed" });
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
    const resourceCategory =
      parsedBody.data.type === "resource"
        ? parsedBody.data.resourceCategory?.trim() || null
        : null;
    const eventLocation =
      parsedBody.data.type === "event"
        ? parsedBody.data.eventLocation?.trim() || null
        : null;

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
        resourceCategory,
        eventStartsAt,
        eventLocation,
        isPinned: parsedBody.data.isPinned === true && canPinCommunityTopic(membership.role)
      },
      select: communityTopicSelect(null, access.id)
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
      select: communityTopicSelect(null, access.id)
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
        select: communityTopicSelect(null, access.id)
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
      select: communityTopicSelect(null, access.id)
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
      select: communityTopicSelect(null, access.id)
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
