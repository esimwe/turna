import { prisma } from "../../lib/prisma.js";

const prismaCommunityMembership = (
  prisma as unknown as { communityMembership: any }
).communityMembership;
const prismaUserReactionPreference = (
  prisma as unknown as { userReactionPreference: any }
).userReactionPreference;
const prismaReactionPackUsageEvent = (
  prisma as unknown as { reactionPackUsageEvent: any }
).reactionPackUsageEvent;

export type ReactionPackStyleValue = "standard" | "premium" | "community";
export type ReactionPackEntitlementValue = "free" | "community_member";
export type ReactionPackSurfaceValue = "chat_reaction" | "profile_mood";

interface ReactionPackCatalogItem {
  id: string;
  title: string;
  subtitle: string;
  style: ReactionPackStyleValue;
  entitlement: ReactionPackEntitlementValue;
  defaultInstalled: boolean;
  emojis: string[];
}

interface ReactionPackPreferenceRecord {
  installedPackIds?: unknown;
  favoriteEmojis?: unknown;
  recentEmojis?: unknown;
}

export interface ReactionPackApiItem {
  id: string;
  title: string;
  subtitle: string;
  style: ReactionPackStyleValue;
  entitlement: ReactionPackEntitlementValue;
  unlocked: boolean;
  installed: boolean;
  usageCount: number;
  emojis: string[];
}

export interface ReactionPackCatalogResponse {
  packs: ReactionPackApiItem[];
  preferences: {
    installedPackIds: string[];
    favoriteEmojis: string[];
    recentEmojis: string[];
  };
}

const reactionPackCatalog: ReactionPackCatalogItem[] = [
  {
    id: "core",
    title: "Temel",
    subtitle: "Her sohbette rahat kullanilan klasik tepkiler.",
    style: "standard",
    entitlement: "free",
    defaultInstalled: true,
    emojis: ["👍", "❤️", "😂", "🔥", "👏", "😮", "😢", "🙏"]
  },
  {
    id: "vibes",
    title: "Vibe",
    subtitle: "Gunluk ruh hali ve akici tepki seti.",
    style: "premium",
    entitlement: "free",
    defaultInstalled: true,
    emojis: ["✨", "🫶", "🥹", "😎", "🫠", "💯", "🌙", "⚡️"]
  },
  {
    id: "moods",
    title: "Mood",
    subtitle: "Profil ruh halini daha belirgin gosteren ikonlar.",
    style: "premium",
    entitlement: "free",
    defaultInstalled: false,
    emojis: ["🌿", "☕️", "🎧", "🌊", "🧠", "📚", "🛫", "🌤️"]
  },
  {
    id: "community",
    title: "Topluluk",
    subtitle: "Topluluk uyelerine acilan ortak ifade paketi.",
    style: "community",
    entitlement: "community_member",
    defaultInstalled: false,
    emojis: ["🚀", "🧩", "🤝", "📣", "🪄", "🎟️", "🫡", "🏁"]
  }
];

function normalizeTrimmedStringList(
  value: unknown,
  maxItems: number,
  maxLength = 64
): string[] {
  if (!Array.isArray(value)) return [];
  const deduped = new Set<string>();
  for (const item of value) {
    const normalized =
      typeof item === "string" ? item.trim() : item?.toString().trim() ?? "";
    if (!normalized || normalized.length > maxLength) continue;
    deduped.add(normalized);
    if (deduped.size >= maxItems) break;
  }
  return [...deduped];
}

function normalizePreferenceRecord(record: ReactionPackPreferenceRecord | null | undefined) {
  return {
    installedPackIds: normalizeTrimmedStringList(record?.installedPackIds, 24),
    favoriteEmojis: normalizeTrimmedStringList(record?.favoriteEmojis, 48, 16),
    recentEmojis: normalizeTrimmedStringList(record?.recentEmojis, 16, 16)
  };
}

async function getUnlockedEntitlementsForUser(
  userId: string
): Promise<Set<ReactionPackEntitlementValue>> {
  const entitlements = new Set<ReactionPackEntitlementValue>(["free"]);
  const communityCount = await prismaCommunityMembership.count({
    where: { userId }
  });
  if (communityCount > 0) {
    entitlements.add("community_member");
  }
  return entitlements;
}

function packUnlocked(
  pack: ReactionPackCatalogItem,
  entitlements: Set<ReactionPackEntitlementValue>
): boolean {
  return entitlements.has(pack.entitlement);
}

function buildReactionPackResponse(
  entitlements: Set<ReactionPackEntitlementValue>,
  preference: ReactionPackPreferenceRecord | null | undefined,
  usageCountByPackId: Map<string, number>
): ReactionPackCatalogResponse {
  const normalizedPreference = normalizePreferenceRecord(preference);
  const unlockedEmojiSet = new Set<string>();
  for (const pack of reactionPackCatalog) {
    if (!packUnlocked(pack, entitlements)) continue;
    for (const emoji of pack.emojis) {
      unlockedEmojiSet.add(emoji);
    }
  }

  const defaultInstalledPackIds = reactionPackCatalog
    .filter((item) => item.defaultInstalled && packUnlocked(item, entitlements))
    .map((item) => item.id);
  const installedPackIds = (
    normalizedPreference.installedPackIds.length > 0
      ? normalizedPreference.installedPackIds
      : defaultInstalledPackIds
  ).filter((id) => {
    const pack = reactionPackCatalog.find((item) => item.id === id);
    return pack != null && packUnlocked(pack, entitlements);
  });

  const favoriteEmojis = normalizedPreference.favoriteEmojis.filter((emoji) =>
    unlockedEmojiSet.has(emoji)
  );
  const recentEmojis = normalizedPreference.recentEmojis.filter((emoji) =>
    unlockedEmojiSet.has(emoji)
  );

  return {
    packs: reactionPackCatalog.map((pack) => ({
      id: pack.id,
      title: pack.title,
      subtitle: pack.subtitle,
      style: pack.style,
      entitlement: pack.entitlement,
      unlocked: packUnlocked(pack, entitlements),
      installed: installedPackIds.includes(pack.id),
      usageCount: usageCountByPackId.get(pack.id) ?? 0,
      emojis: pack.emojis
    })),
    preferences: {
      installedPackIds,
      favoriteEmojis,
      recentEmojis
    }
  };
}

async function getUsageCountByPackId(): Promise<Map<string, number>> {
  const rows = await prismaReactionPackUsageEvent.groupBy({
    by: ["packId"],
    _count: {
      packId: true
    }
  });
  const map = new Map<string, number>();
  for (const row of rows as Array<{ packId: string; _count: { packId?: number } }>) {
    map.set(row.packId, row._count?.packId ?? 0);
  }
  return map;
}

export async function listReactionPacksForUser(
  userId: string
): Promise<ReactionPackCatalogResponse> {
  const [entitlements, preference, usageCountByPackId] = await Promise.all([
    getUnlockedEntitlementsForUser(userId),
    prismaUserReactionPreference.findUnique({
      where: { userId },
      select: {
        installedPackIds: true,
        favoriteEmojis: true,
        recentEmojis: true
      }
    }),
    getUsageCountByPackId()
  ]);
  return buildReactionPackResponse(entitlements, preference, usageCountByPackId);
}

export async function updateReactionPackPreferences(
  userId: string,
  input: {
    installedPackIds?: string[];
    favoriteEmojis?: string[];
    recentEmojis?: string[];
  }
): Promise<ReactionPackCatalogResponse> {
  const [entitlements, existing] = await Promise.all([
    getUnlockedEntitlementsForUser(userId),
    prismaUserReactionPreference.findUnique({
      where: { userId },
      select: {
        installedPackIds: true,
        favoriteEmojis: true,
        recentEmojis: true
      }
    })
  ]);

  const current = buildReactionPackResponse(entitlements, existing, new Map());
  const unlockedPackIds = new Set(
    current.packs.filter((item) => item.unlocked).map((item) => item.id)
  );
  const unlockedEmojis = new Set(
    current.packs
      .filter((item) => item.unlocked)
      .flatMap((item) => item.emojis)
  );

  const nextInstalledPackIds = (
    input.installedPackIds != null
      ? normalizeTrimmedStringList(input.installedPackIds, 24)
      : current.preferences.installedPackIds
  ).filter((item) => unlockedPackIds.has(item));
  const nextFavoriteEmojis = (
    input.favoriteEmojis != null
      ? normalizeTrimmedStringList(input.favoriteEmojis, 48, 16)
      : current.preferences.favoriteEmojis
  ).filter((item) => unlockedEmojis.has(item));
  const nextRecentEmojis = (
    input.recentEmojis != null
      ? normalizeTrimmedStringList(input.recentEmojis, 16, 16)
      : current.preferences.recentEmojis
  ).filter((item) => unlockedEmojis.has(item));

  await prismaUserReactionPreference.upsert({
    where: { userId },
    create: {
      userId,
      installedPackIds: nextInstalledPackIds,
      favoriteEmojis: nextFavoriteEmojis,
      recentEmojis: nextRecentEmojis
    },
    update: {
      installedPackIds: nextInstalledPackIds,
      favoriteEmojis: nextFavoriteEmojis,
      recentEmojis: nextRecentEmojis
    }
  });

  return listReactionPacksForUser(userId);
}

export async function assertReactionPackEmojiAllowed(
  userId: string,
  emoji: string,
  packId?: string | null
): Promise<ReactionPackCatalogItem> {
  const trimmedEmoji = emoji.trim();
  if (!trimmedEmoji) {
    throw new Error("reaction_emoji_required");
  }

  const entitlements = await getUnlockedEntitlementsForUser(userId);
  if (packId?.trim()) {
    const pack = reactionPackCatalog.find((item) => item.id === packId.trim());
    if (!pack) {
      throw new Error("reaction_pack_not_found");
    }
    if (!packUnlocked(pack, entitlements)) {
      throw new Error("reaction_pack_locked");
    }
    if (!pack.emojis.includes(trimmedEmoji)) {
      throw new Error("reaction_pack_emoji_invalid");
    }
    return pack;
  }

  const matchedPack = reactionPackCatalog.find(
    (pack) => packUnlocked(pack, entitlements) && pack.emojis.includes(trimmedEmoji)
  );
  if (!matchedPack) {
    throw new Error("reaction_pack_emoji_invalid");
  }
  return matchedPack;
}

export async function trackReactionPackUsage(
  userId: string,
  input: {
    packId: string;
    emoji: string;
    surface: ReactionPackSurfaceValue;
  }
): Promise<void> {
  const trimmedEmoji = input.emoji.trim();
  const [entitlements, existingPreference] = await Promise.all([
    getUnlockedEntitlementsForUser(userId),
    prismaUserReactionPreference.findUnique({
      where: { userId },
      select: {
        installedPackIds: true,
        favoriteEmojis: true,
        recentEmojis: true
      }
    })
  ]);
  const unlockedPacks = reactionPackCatalog.filter((pack) =>
    packUnlocked(pack, entitlements)
  );
  const unlockedPackIds = new Set(unlockedPacks.map((item) => item.id));
  const unlockedEmojis = new Set(unlockedPacks.flatMap((item) => item.emojis));
  if (!unlockedPackIds.has(input.packId) || !unlockedEmojis.has(trimmedEmoji)) {
    return;
  }

  const normalizedPreference = normalizePreferenceRecord(existingPreference);
  const nextRecentEmojis = [
    trimmedEmoji,
    ...normalizedPreference.recentEmojis.filter((item) => item != trimmedEmoji)
  ].slice(0, 16);

  await prisma.$transaction([
    prismaReactionPackUsageEvent.create({
      data: {
        userId,
        packId: input.packId,
        emoji: trimmedEmoji,
        surface: input.surface
      }
    }),
    prismaUserReactionPreference.upsert({
      where: { userId },
      create: {
        userId,
        installedPackIds: normalizedPreference.installedPackIds,
        favoriteEmojis: normalizedPreference.favoriteEmojis,
        recentEmojis: nextRecentEmojis
      },
      update: {
        recentEmojis: nextRecentEmojis
      }
    })
  ]);
}
