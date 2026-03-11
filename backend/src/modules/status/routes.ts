import { Router } from "express";
import { z } from "zod";
import { logError } from "../../lib/logger.js";
import { prisma } from "../../lib/prisma.js";
import {
  assertObjectExists,
  createObjectReadUrl,
  createStatusAttachmentUploadUrl,
  deleteObject,
  isStatusAttachmentKeyOwnedByUser,
  isStorageConfigured
} from "../../lib/storage.js";
import { requireAuth, requireMessagingAccess } from "../../middleware/auth.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";
import { buildPhoneLookupKeys } from "../profile/contact-lookup.js";

export const statusRouter = Router();

const prismaUser = (prisma as unknown as { user: any }).user;
const prismaUserContact = (prisma as unknown as { userContact: any }).userContact;
const prismaUserBlock = (prisma as unknown as { userBlock: any }).userBlock;
const prismaStatusItem = (prisma as unknown as { statusItem: any }).statusItem;
const prismaStatusView = (prisma as unknown as { statusView: any }).statusView;
const prismaStatusPreference = (prisma as unknown as { statusPreference: any }).statusPreference;

const STATUS_TTL_MS = 24 * 60 * 60 * 1000;
const TEXT_STATUS_COLORS = {
  background: "#1F6FEB",
  text: "#FFFFFF"
} as const;

const privacyModeValues = ["MY_CONTACTS", "EXCLUDED_CONTACTS", "ONLY_SHARED_WITH"] as const;
const mediaStatusTypeValues = ["IMAGE", "VIDEO"] as const;

const statusUploadInitSchema = z.object({
  type: z.enum(["image", "video"]),
  contentType: z.string().trim().min(1).max(100),
  fileName: z.string().trim().min(1).max(255).optional()
}).superRefine((value, ctx) => {
  if (value.type === "image" && !value.contentType.startsWith("image/")) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "image_content_type_required",
      path: ["contentType"]
    });
  }
  if (value.type === "video" && !value.contentType.startsWith("video/")) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "video_content_type_required",
      path: ["contentType"]
    });
  }
});

const createTextStatusSchema = z.object({
  type: z.literal("text"),
  text: z.preprocess(
    (value) => (typeof value === "string" ? value.trim() : value),
    z.string().min(1).max(700)
  ),
  backgroundColor: z.string().trim().max(32).optional(),
  textColor: z.string().trim().max(32).optional()
});

const createMediaStatusSchema = z.object({
  type: z.enum(["image", "video"]),
  objectKey: z.string().trim().min(1).max(512),
  contentType: z.string().trim().min(1).max(100),
  fileName: z.string().trim().min(1).max(255).optional(),
  sizeBytes: z.coerce.number().int().min(0).max(500 * 1024 * 1024).optional(),
  width: z.coerce.number().int().min(1).max(10000).optional(),
  height: z.coerce.number().int().min(1).max(10000).optional(),
  durationSeconds: z.coerce.number().int().min(0).max(60).optional()
}).superRefine((value, ctx) => {
  if (value.type === "image" && !value.contentType.startsWith("image/")) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "image_content_type_required",
      path: ["contentType"]
    });
  }
  if (value.type === "video" && !value.contentType.startsWith("video/")) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "video_content_type_required",
      path: ["contentType"]
    });
  }
});

const updateStatusPreferenceSchema = z.object({
  mode: z.enum(["my_contacts", "excluded_contacts", "only_shared_with"]),
  targetUserIds: z.array(z.string().trim().min(1).max(255)).max(500).default([])
});

const setStatusMutedSchema = z.object({
  muted: z.boolean()
});

const userIdParamSchema = z.object({
  userId: z.string().trim().min(1).max(255)
});

const statusIdParamSchema = z.object({
  statusId: z.string().trim().min(1).max(255)
});

function parseStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const unique = new Set<string>();
  for (const item of value) {
    const normalized = item?.toString().trim();
    if (!normalized) continue;
    unique.add(normalized);
  }
  return [...unique];
}

function sanitizeHexColor(
  value: string | null | undefined,
  fallback: string
): string {
  const trimmed = value?.trim() ?? "";
  if (/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(trimmed)) {
    return trimmed.toUpperCase();
  }
  return fallback;
}

function toApiPrivacyMode(value: typeof privacyModeValues[number] | null | undefined): "my_contacts" | "excluded_contacts" | "only_shared_with" {
  switch (value) {
    case "EXCLUDED_CONTACTS":
      return "excluded_contacts";
    case "ONLY_SHARED_WITH":
      return "only_shared_with";
    default:
      return "my_contacts";
  }
}

function toDbPrivacyMode(value: "my_contacts" | "excluded_contacts" | "only_shared_with"): typeof privacyModeValues[number] {
  switch (value) {
    case "excluded_contacts":
      return "EXCLUDED_CONTACTS";
    case "only_shared_with":
      return "ONLY_SHARED_WITH";
    default:
      return "MY_CONTACTS";
  }
}

function toApiStatusType(value: string | null | undefined): "text" | "image" | "video" {
  switch ((value ?? "").toUpperCase()) {
    case "IMAGE":
      return "image";
    case "VIDEO":
      return "video";
    default:
      return "text";
  }
}

function buildStatusPreview(row: {
  type: string;
  text?: string | null;
}): string {
  const trimmed = row.text?.trim() ?? "";
  if (trimmed.length > 0) {
    return trimmed.length > 72 ? `${trimmed.slice(0, 69)}...` : trimmed;
  }
  switch (row.type) {
    case "IMAGE":
      return "Fotoğraf";
    case "VIDEO":
      return "Video";
    default:
      return "Durum";
  }
}

async function cleanupExpiredStatuses(): Promise<void> {
  const expiredItems = await prismaStatusItem.findMany({
    where: { expiresAt: { lte: new Date() } },
    select: { id: true, objectKey: true },
    take: 200
  });

  if (expiredItems.length === 0) {
    return;
  }

  await prismaStatusItem.deleteMany({
    where: { id: { in: expiredItems.map((item: { id: string }) => item.id) } }
  });

  if (!isStorageConfigured()) {
    return;
  }

  for (const item of expiredItems) {
    const objectKey = item.objectKey?.toString().trim();
    if (!objectKey) continue;
    deleteObject(objectKey).catch((error: unknown) => {
      logError("expired status object delete failed", error);
    });
  }
}

async function filterStatusTargetUserIdsToContacts(
  ownerUserId: string,
  candidateUserIds: string[]
): Promise<string[]> {
  const normalizedIds = [...new Set(candidateUserIds.filter(Boolean))];
  if (normalizedIds.length === 0) {
    return [];
  }

  const users = await prismaUser.findMany({
    where: {
      id: { in: normalizedIds },
      phone: { not: null }
    },
    select: {
      id: true,
      phone: true
    }
  });

  if (users.length === 0) {
    return [];
  }

  const lookupEntries = users.flatMap((user: { id: string; phone: string | null }) =>
    buildPhoneLookupKeys(user.phone).map((lookupKey) => ({
      userId: user.id,
      lookupKey
    }))
  );

  if (lookupEntries.length === 0) {
    return [];
  }

  const lookupRows = await prismaUserContact.findMany({
    where: {
      ownerId: ownerUserId,
      lookupKey: {
        in: lookupEntries.map((entry: { lookupKey: string }) => entry.lookupKey)
      }
    },
    select: {
      lookupKey: true
    }
  });

  const allowedLookupKeys = new Set(
    lookupRows.map((row: { lookupKey: string }) => row.lookupKey)
  );

  const allowedUserIds = new Set<string>();
  for (const entry of lookupEntries) {
    if (allowedLookupKeys.has(entry.lookupKey)) {
      allowedUserIds.add(entry.userId);
    }
  }

  return normalizedIds.filter((userId) => allowedUserIds.has(userId));
}

async function getStatusPreference(userId: string): Promise<{
  privacyMode: typeof privacyModeValues[number];
  targetUserIds: string[];
  mutedUserIds: string[];
}> {
  const existing = await prismaStatusPreference.findUnique({
    where: { userId },
    select: {
      privacyMode: true,
      targetUserIds: true,
      mutedUserIds: true
    }
  });

  return {
    privacyMode: existing?.privacyMode ?? "MY_CONTACTS",
    targetUserIds: parseStringArray(existing?.targetUserIds),
    mutedUserIds: parseStringArray(existing?.mutedUserIds)
  };
}

async function buildAuthorVisibilityMap(viewerId: string, authorIds: string[]): Promise<Map<string, boolean>> {
  const uniqueAuthorIds = [...new Set(authorIds.filter((authorId) => authorId && authorId !== viewerId))];
  if (uniqueAuthorIds.length === 0) {
    return new Map<string, boolean>();
  }

  const [viewer, authorPreferences, blockRows] = await Promise.all([
    prismaUser.findUnique({
      where: { id: viewerId },
      select: { phone: true }
    }),
    prismaStatusPreference.findMany({
      where: { userId: { in: uniqueAuthorIds } },
      select: {
        userId: true,
        privacyMode: true,
        targetUserIds: true
      }
    }),
    prismaUserBlock.findMany({
      where: {
        OR: [
          {
            blockerId: viewerId,
            blockedUserId: { in: uniqueAuthorIds }
          },
          {
            blockerId: { in: uniqueAuthorIds },
            blockedUserId: viewerId
          }
        ]
      },
      select: {
        blockerId: true,
        blockedUserId: true
      }
    })
  ]);

  const blockedAuthorIds = new Set<string>();
  for (const row of blockRows) {
    if (row.blockerId === viewerId) {
      blockedAuthorIds.add(row.blockedUserId);
    } else if (row.blockedUserId === viewerId) {
      blockedAuthorIds.add(row.blockerId);
    }
  }

  const viewerPhoneLookupKeys = buildPhoneLookupKeys(viewer?.phone);
  const visibleByContact = new Set<string>();
  if (viewerPhoneLookupKeys.length > 0) {
    const contactRows = await prismaUserContact.findMany({
      where: {
        ownerId: { in: uniqueAuthorIds },
        lookupKey: { in: viewerPhoneLookupKeys }
      },
      select: {
        ownerId: true
      }
    });

    for (const row of contactRows) {
      visibleByContact.add(row.ownerId);
    }
  }

  const preferencesByUserId = new Map<
    string,
    { privacyMode: typeof privacyModeValues[number]; targetUserIds: string[] }
  >(
    authorPreferences.map((row: {
      userId: string;
      privacyMode: typeof privacyModeValues[number];
      targetUserIds: unknown;
    }) => [
      row.userId,
      {
        privacyMode: row.privacyMode,
        targetUserIds: parseStringArray(row.targetUserIds)
      }
    ])
  );

  const visibleMap = new Map<string, boolean>();
  for (const authorId of uniqueAuthorIds) {
    if (blockedAuthorIds.has(authorId) || !visibleByContact.has(authorId)) {
      visibleMap.set(authorId, false);
      continue;
    }

    const preference = preferencesByUserId.get(authorId);
    if (!preference || preference.privacyMode === "MY_CONTACTS") {
      visibleMap.set(authorId, true);
      continue;
    }

    const targetIds = new Set(preference.targetUserIds);
    if (preference.privacyMode === "EXCLUDED_CONTACTS") {
      visibleMap.set(authorId, !targetIds.has(viewerId));
      continue;
    }

    visibleMap.set(authorId, targetIds.has(viewerId));
  }

  return visibleMap;
}

function serializeStatusUser(
  req: Parameters<typeof buildAvatarUrl>[0],
  user: {
    id: string;
    displayName: string;
    phone: string | null;
    avatarUrl: string | null;
    updatedAt: Date;
  }
) {
  return {
    id: user.id,
    displayName: user.displayName,
    phone: user.phone ?? null,
    avatarUrl: user.avatarUrl ? buildAvatarUrl(req, user.id, user.updatedAt) : null
  };
}

async function serializeStatusItem(
  req: Parameters<typeof buildAvatarUrl>[0],
  row: {
    id: string;
    type: string;
    text: string | null;
    backgroundColor: string | null;
    textColor: string | null;
    objectKey: string | null;
    contentType: string | null;
    fileName: string | null;
    sizeBytes: number | null;
    width: number | null;
    height: number | null;
    durationSeconds: number | null;
    createdAt: Date;
    expiresAt: Date;
    author: {
      id: string;
      displayName: string;
      phone: string | null;
      avatarUrl: string | null;
      updatedAt: Date;
    };
    views?: Array<{ viewerUserId: string }>;
    _count?: { views: number };
  }
) {
  let mediaUrl: string | null = null;
  if (row.objectKey) {
    try {
      mediaUrl = await createObjectReadUrl(row.objectKey);
    } catch (error) {
      logError("status media signed url failed", error);
    }
  }

  return {
    id: row.id,
    type: toApiStatusType(row.type),
    text: row.text,
    backgroundColor:
      row.backgroundColor ?? (row.type === "TEXT" ? TEXT_STATUS_COLORS.background : null),
    textColor: row.textColor ?? (row.type === "TEXT" ? TEXT_STATUS_COLORS.text : null),
    objectKey: row.objectKey,
    url: mediaUrl,
    contentType: row.contentType,
    fileName: row.fileName,
    sizeBytes: row.sizeBytes,
    width: row.width,
    height: row.height,
    durationSeconds: row.durationSeconds,
    createdAt: row.createdAt.toISOString(),
    expiresAt: row.expiresAt.toISOString(),
    viewedByMe: (row.views?.length ?? 0) > 0,
    viewedCount: row._count?.views ?? 0,
    author: serializeStatusUser(req, row.author)
  };
}

statusRouter.get("/", requireAuth, async (req, res) => {
  await cleanupExpiredStatuses();

  const userId = req.authUserId!;

  try {
    const [myPreference, myRows, otherRows] = await Promise.all([
      getStatusPreference(userId),
      prismaStatusItem.findMany({
        where: {
          authorId: userId,
          expiresAt: { gt: new Date() }
        },
        orderBy: { createdAt: "desc" },
        select: {
          id: true,
          type: true,
          text: true,
          createdAt: true
        }
      }),
      prismaStatusItem.findMany({
        where: {
          authorId: { not: userId },
          expiresAt: { gt: new Date() }
        },
        orderBy: [
          { authorId: "asc" },
          { createdAt: "asc" }
        ],
        select: {
          id: true,
          type: true,
          text: true,
          createdAt: true,
          authorId: true,
          author: {
            select: {
              id: true,
              displayName: true,
              phone: true,
              avatarUrl: true,
              updatedAt: true
            }
          },
          views: {
            where: {
              viewerUserId: userId
            },
            select: {
              viewerUserId: true
            }
          }
        }
      })
    ]);

    const visibilityByAuthor = await buildAuthorVisibilityMap(
      userId,
      otherRows.map((row: { authorId: string }) => row.authorId)
    );

    const grouped = new Map<
      string,
      {
        author: (typeof otherRows)[number]["author"];
        items: typeof otherRows;
      }
    >();

    for (const row of otherRows) {
      if (!visibilityByAuthor.get(row.authorId)) {
        continue;
      }

      const current = grouped.get(row.authorId);
      if (current) {
        current.items.push(row);
        continue;
      }
      grouped.set(row.authorId, {
        author: row.author,
        items: [row] as unknown as typeof otherRows
      });
    }

    const mutedUserIds = new Set(myPreference.mutedUserIds);
    const summaries = [...grouped.entries()]
      .map(([authorId, group]) => {
        const latest = group.items[group.items.length - 1];
        const hasUnviewed = group.items.some(
          (item: { views: Array<{ viewerUserId: string }> }) =>
            item.views.length === 0
        );
        return {
          user: serializeStatusUser(req, group.author),
          latestAt: latest.createdAt.toISOString(),
          latestType: toApiStatusType(latest.type),
          previewText: buildStatusPreview(latest),
          itemCount: group.items.length,
          hasUnviewed,
          muted: mutedUserIds.has(authorId)
        };
      })
      .sort((left, right) => right.latestAt.localeCompare(left.latestAt));

    res.json({
      data: {
        mine: {
          count: myRows.length,
          latestAt: myRows[0]?.createdAt?.toISOString() ?? null,
          latestType: myRows[0] ? toApiStatusType(myRows[0].type) : null,
          previewText: myRows[0] ? buildStatusPreview(myRows[0]) : null
        },
        privacy: {
          mode: toApiPrivacyMode(myPreference.privacyMode),
          targetUserIds: myPreference.targetUserIds
        },
        updates: summaries.filter((item) => !item.muted),
        muted: summaries.filter((item) => item.muted)
      }
    });
  } catch (error) {
    logError("status feed failed", error);
    res.status(500).json({ error: "failed_to_load_status_feed" });
  }
});

statusRouter.get("/preferences", requireAuth, async (req, res) => {
  try {
    const preference = await getStatusPreference(req.authUserId!);
    res.json({
      data: {
        mode: toApiPrivacyMode(preference.privacyMode),
        targetUserIds: preference.targetUserIds,
        mutedUserIds: preference.mutedUserIds
      }
    });
  } catch (error) {
    logError("status preference get failed", error);
    res.status(500).json({ error: "failed_to_load_status_preferences" });
  }
});

statusRouter.post("/preferences", requireAuth, async (req, res) => {
  const parsed = updateStatusPreferenceSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const allowedTargetUserIds = await filterStatusTargetUserIdsToContacts(
      req.authUserId!,
      parsed.data.targetUserIds
    );

    const updated = await prismaStatusPreference.upsert({
      where: { userId: req.authUserId! },
      create: {
        userId: req.authUserId!,
        privacyMode: toDbPrivacyMode(parsed.data.mode),
        targetUserIds: allowedTargetUserIds,
        mutedUserIds: []
      },
      update: {
        privacyMode: toDbPrivacyMode(parsed.data.mode),
        targetUserIds: allowedTargetUserIds
      },
      select: {
        privacyMode: true,
        targetUserIds: true,
        mutedUserIds: true
      }
    });

    res.json({
      data: {
        mode: toApiPrivacyMode(updated.privacyMode),
        targetUserIds: parseStringArray(updated.targetUserIds),
        mutedUserIds: parseStringArray(updated.mutedUserIds)
      }
    });
  } catch (error) {
    logError("status preference update failed", error);
    res.status(500).json({ error: "failed_to_update_status_preferences" });
  }
});

statusRouter.post("/upload-url", requireAuth, requireMessagingAccess, async (req, res) => {
  if (!isStorageConfigured()) {
    res.status(503).json({ error: "storage_not_configured" });
    return;
  }

  const parsed = statusUploadInitSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const upload = await createStatusAttachmentUploadUrl({
      userId: req.authUserId!,
      kind: parsed.data.type,
      contentType: parsed.data.contentType,
      fileName: parsed.data.fileName
    });
    res.status(201).json({
      data: {
        objectKey: upload.objectKey,
        uploadUrl: upload.uploadUrl,
        headers: upload.headers
      }
    });
  } catch (error) {
    logError("status upload url failed", error);
    res.status(500).json({ error: "failed_to_prepare_status_upload" });
  }
});

statusRouter.post("/", requireAuth, requireMessagingAccess, async (req, res) => {
  await cleanupExpiredStatuses();

  const parsed =
    req.body?.type === "text"
      ? createTextStatusSchema.safeParse(req.body)
      : createMediaStatusSchema.safeParse(req.body);

  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const expiresAt = new Date(Date.now() + STATUS_TTL_MS);
    let created: any;

    if (parsed.data.type === "text") {
      created = await prismaStatusItem.create({
        data: {
          authorId: req.authUserId!,
          type: "TEXT",
          text: parsed.data.text,
          backgroundColor: sanitizeHexColor(
            parsed.data.backgroundColor,
            TEXT_STATUS_COLORS.background
          ),
          textColor: sanitizeHexColor(parsed.data.textColor, TEXT_STATUS_COLORS.text),
          expiresAt
        },
        select: {
          id: true,
          type: true,
          text: true,
          backgroundColor: true,
          textColor: true,
          objectKey: true,
          contentType: true,
          fileName: true,
          sizeBytes: true,
          width: true,
          height: true,
          durationSeconds: true,
          createdAt: true,
          expiresAt: true,
          _count: {
            select: {
              views: true
            }
          },
          author: {
            select: {
              id: true,
              displayName: true,
              phone: true,
              avatarUrl: true,
              updatedAt: true
            }
          },
          views: {
            where: {
              viewerUserId: req.authUserId!
            },
            select: {
              viewerUserId: true
            }
          }
        }
      });
    } else {
      if (!isStatusAttachmentKeyOwnedByUser({
        userId: req.authUserId!,
        objectKey: parsed.data.objectKey
      })) {
        res.status(403).json({ error: "invalid_status_media_key" });
        return;
      }

      try {
        await assertObjectExists(parsed.data.objectKey);
      } catch (error) {
        logError("status create missing object", error);
        res.status(404).json({ error: "uploaded_file_not_found" });
        return;
      }

      created = await prismaStatusItem.create({
        data: {
          authorId: req.authUserId!,
          type: parsed.data.type.toUpperCase(),
          objectKey: parsed.data.objectKey,
          contentType: parsed.data.contentType,
          fileName: parsed.data.fileName,
          sizeBytes: parsed.data.sizeBytes ?? null,
          width: parsed.data.width ?? null,
          height: parsed.data.height ?? null,
          durationSeconds:
            parsed.data.type === "video" ? (parsed.data.durationSeconds ?? null) : null,
          expiresAt
        },
        select: {
          id: true,
          type: true,
          text: true,
          backgroundColor: true,
          textColor: true,
          objectKey: true,
          contentType: true,
          fileName: true,
          sizeBytes: true,
          width: true,
          height: true,
          durationSeconds: true,
          createdAt: true,
          expiresAt: true,
          _count: {
            select: {
              views: true
            }
          },
          author: {
            select: {
              id: true,
              displayName: true,
              phone: true,
              avatarUrl: true,
              updatedAt: true
            }
          },
          views: {
            where: {
              viewerUserId: req.authUserId!
            },
            select: {
              viewerUserId: true
            }
          }
        }
      });
    }

    res.status(201).json({
      data: await serializeStatusItem(req, created)
    });
  } catch (error) {
    logError("status create failed", error);
    res.status(500).json({ error: "failed_to_create_status" });
  }
});

statusRouter.get("/users/:userId", requireAuth, async (req, res) => {
  await cleanupExpiredStatuses();

  const parsed = userIdParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const targetUserId = parsed.data.userId;
  const currentUserId = req.authUserId!;

  try {
    if (targetUserId !== currentUserId) {
      const visibilityByAuthor = await buildAuthorVisibilityMap(currentUserId, [targetUserId]);
      if (!visibilityByAuthor.get(targetUserId)) {
        res.status(404).json({ error: "status_feed_not_found" });
        return;
      }
    }

    const rows = await prismaStatusItem.findMany({
      where: {
        authorId: targetUserId,
        expiresAt: { gt: new Date() }
      },
      orderBy: { createdAt: "asc" },
      select: {
        id: true,
        type: true,
        text: true,
        backgroundColor: true,
        textColor: true,
        objectKey: true,
        contentType: true,
        fileName: true,
        sizeBytes: true,
        width: true,
        height: true,
        durationSeconds: true,
        createdAt: true,
        expiresAt: true,
        _count: {
          select: {
            views: true
          }
        },
        author: {
          select: {
            id: true,
            displayName: true,
            phone: true,
            avatarUrl: true,
            updatedAt: true
          }
        },
        views: {
          where: {
            viewerUserId: currentUserId
          },
          select: {
            viewerUserId: true
          }
        }
      }
    });

    if (rows.length === 0) {
      res.status(404).json({ error: "status_feed_not_found" });
      return;
    }

    res.json({
      data: {
        own: targetUserId === currentUserId,
        user: serializeStatusUser(req, rows[0].author),
        items: await Promise.all(rows.map((row: any) => serializeStatusItem(req, row)))
      }
    });
  } catch (error) {
    logError("status user feed failed", error);
    res.status(500).json({ error: "failed_to_load_status_user_feed" });
  }
});

statusRouter.post("/:statusId/view", requireAuth, async (req, res) => {
  await cleanupExpiredStatuses();

  const parsed = statusIdParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const row = await prismaStatusItem.findUnique({
      where: { id: parsed.data.statusId },
      select: {
        id: true,
        authorId: true,
        expiresAt: true
      }
    });

    if (!row || row.expiresAt <= new Date()) {
      res.status(404).json({ error: "status_not_found" });
      return;
    }

    if (row.authorId === req.authUserId!) {
      res.json({ data: { viewed: false } });
      return;
    }

    const visibilityByAuthor = await buildAuthorVisibilityMap(req.authUserId!, [row.authorId]);
    if (!visibilityByAuthor.get(row.authorId)) {
      res.status(404).json({ error: "status_not_found" });
      return;
    }

    await prismaStatusView.upsert({
      where: {
        statusId_viewerUserId: {
          statusId: row.id,
          viewerUserId: req.authUserId!
        }
      },
      create: {
        statusId: row.id,
        viewerUserId: req.authUserId!
      },
      update: {
        viewedAt: new Date()
      }
    });

    res.json({ data: { viewed: true } });
  } catch (error) {
    logError("status view mark failed", error);
    res.status(500).json({ error: "failed_to_mark_status_viewed" });
  }
});

statusRouter.get("/:statusId/viewers", requireAuth, async (req, res) => {
  await cleanupExpiredStatuses();

  const parsed = statusIdParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const row = await prismaStatusItem.findUnique({
      where: { id: parsed.data.statusId },
      select: {
        id: true,
        authorId: true,
        expiresAt: true
      }
    });

    if (!row || row.expiresAt <= new Date()) {
      res.status(404).json({ error: "status_not_found" });
      return;
    }

    if (row.authorId !== req.authUserId!) {
      res.status(403).json({ error: "forbidden_status_viewers_access" });
      return;
    }

    const viewers = await prismaStatusView.findMany({
      where: {
        statusId: row.id
      },
      orderBy: { viewedAt: "desc" },
      select: {
        viewedAt: true,
        viewer: {
          select: {
            id: true,
            displayName: true,
            phone: true,
            avatarUrl: true,
            updatedAt: true
          }
        }
      }
    });

    res.json({
      data: viewers.map((item: any) => ({
        viewedAt: item.viewedAt.toISOString(),
        user: serializeStatusUser(req, item.viewer)
      }))
    });
  } catch (error) {
    logError("status viewers fetch failed", error);
    res.status(500).json({ error: "failed_to_load_status_viewers" });
  }
});

statusRouter.post("/users/:userId/mute", requireAuth, async (req, res) => {
  const parsedParams = userIdParamSchema.safeParse(req.params);
  const parsedBody = setStatusMutedSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  if (parsedParams.data.userId === req.authUserId!) {
    res.status(400).json({ error: "invalid_status_mute_target" });
    return;
  }

  try {
    const existing = await getStatusPreference(req.authUserId!);
    const nextMutedUserIds = new Set(existing.mutedUserIds);
    if (parsedBody.data.muted) {
      nextMutedUserIds.add(parsedParams.data.userId);
    } else {
      nextMutedUserIds.delete(parsedParams.data.userId);
    }

    await prismaStatusPreference.upsert({
      where: { userId: req.authUserId! },
      create: {
        userId: req.authUserId!,
        privacyMode: existing.privacyMode,
        targetUserIds: existing.targetUserIds,
        mutedUserIds: [...nextMutedUserIds]
      },
      update: {
        mutedUserIds: [...nextMutedUserIds]
      }
    });

    res.json({ data: { muted: parsedBody.data.muted } });
  } catch (error) {
    logError("status mute update failed", error);
    res.status(500).json({ error: "failed_to_update_status_mute" });
  }
});
