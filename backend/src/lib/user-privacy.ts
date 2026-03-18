import { buildPhoneLookupKeys } from "../modules/profile/contact-lookup.js";
import { prisma } from "./prisma.js";

const prismaUser = (prisma as unknown as { user: any }).user;
const prismaUserContact = (prisma as unknown as { userContact: any }).userContact;
const prismaUserPrivacyPreference =
  (prisma as unknown as { userPrivacyPreference: any }).userPrivacyPreference;

export const userPrivacyAudienceValues = [
  "EVERYONE",
  "MY_CONTACTS",
  "EXCLUDED_CONTACTS",
  "NOBODY",
  "ONLY_SHARED_WITH"
] as const;

export const userOnlineVisibilityValues = ["EVERYONE", "SAME_AS_LAST_SEEN"] as const;
export const allowedMessageExpirationSeconds = [
  24 * 60 * 60,
  7 * 24 * 60 * 60,
  90 * 24 * 60 * 60
] as const;

export type UserPrivacyAudienceValue = (typeof userPrivacyAudienceValues)[number];
export type UserOnlineVisibilityValue = (typeof userOnlineVisibilityValues)[number];
export type AllowedMessageExpirationSeconds =
  (typeof allowedMessageExpirationSeconds)[number];

export interface UserPrivacyPreferenceRecord {
  lastSeenMode: UserPrivacyAudienceValue;
  lastSeenTargetUserIds: string[];
  onlineMode: UserOnlineVisibilityValue;
  profilePhotoMode: UserPrivacyAudienceValue;
  profilePhotoTargetUserIds: string[];
  aboutMode: UserPrivacyAudienceValue;
  aboutTargetUserIds: string[];
  linksMode: UserPrivacyAudienceValue;
  linksTargetUserIds: string[];
  groupsMode: Extract<
    UserPrivacyAudienceValue,
    "EVERYONE" | "MY_CONTACTS" | "EXCLUDED_CONTACTS"
  >;
  groupsTargetUserIds: string[];
  defaultMessageExpirationSeconds: AllowedMessageExpirationSeconds | null;
  statusAllowReshare: boolean;
}

export const DEFAULT_USER_PRIVACY_PREFERENCE: UserPrivacyPreferenceRecord = {
  lastSeenMode: "EVERYONE",
  lastSeenTargetUserIds: [],
  onlineMode: "EVERYONE",
  profilePhotoMode: "EVERYONE",
  profilePhotoTargetUserIds: [],
  aboutMode: "MY_CONTACTS",
  aboutTargetUserIds: [],
  linksMode: "MY_CONTACTS",
  linksTargetUserIds: [],
  groupsMode: "EVERYONE",
  groupsTargetUserIds: [],
  defaultMessageExpirationSeconds: null,
  statusAllowReshare: false
};

export function parsePrivacyStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];

  const unique = new Set<string>();
  for (const item of value) {
    const normalized = item?.toString().trim();
    if (!normalized) continue;
    unique.add(normalized);
  }
  return [...unique];
}

export async function filterPrivacyTargetUserIdsToContacts(
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

export async function getUserPrivacyPreference(
  userId: string
): Promise<UserPrivacyPreferenceRecord> {
  const existing = await prismaUserPrivacyPreference.findUnique({
    where: { userId },
    select: {
      lastSeenMode: true,
      lastSeenTargetUserIds: true,
      onlineMode: true,
      profilePhotoMode: true,
      profilePhotoTargetUserIds: true,
      aboutMode: true,
      aboutTargetUserIds: true,
      linksMode: true,
      linksTargetUserIds: true,
      groupsMode: true,
      groupsTargetUserIds: true,
      defaultMessageExpirationSeconds: true,
      statusAllowReshare: true
    }
  });

  if (!existing) {
    return { ...DEFAULT_USER_PRIVACY_PREFERENCE };
  }

  return {
    lastSeenMode: existing.lastSeenMode ?? DEFAULT_USER_PRIVACY_PREFERENCE.lastSeenMode,
    lastSeenTargetUserIds: parsePrivacyStringArray(existing.lastSeenTargetUserIds),
    onlineMode: existing.onlineMode ?? DEFAULT_USER_PRIVACY_PREFERENCE.onlineMode,
    profilePhotoMode:
      existing.profilePhotoMode ?? DEFAULT_USER_PRIVACY_PREFERENCE.profilePhotoMode,
    profilePhotoTargetUserIds: parsePrivacyStringArray(
      existing.profilePhotoTargetUserIds
    ),
    aboutMode: existing.aboutMode ?? DEFAULT_USER_PRIVACY_PREFERENCE.aboutMode,
    aboutTargetUserIds: parsePrivacyStringArray(existing.aboutTargetUserIds),
    linksMode: existing.linksMode ?? DEFAULT_USER_PRIVACY_PREFERENCE.linksMode,
    linksTargetUserIds: parsePrivacyStringArray(existing.linksTargetUserIds),
    groupsMode: existing.groupsMode ?? DEFAULT_USER_PRIVACY_PREFERENCE.groupsMode,
    groupsTargetUserIds: parsePrivacyStringArray(existing.groupsTargetUserIds),
    defaultMessageExpirationSeconds:
      allowedMessageExpirationSeconds.includes(existing.defaultMessageExpirationSeconds)
        ? existing.defaultMessageExpirationSeconds
        : DEFAULT_USER_PRIVACY_PREFERENCE.defaultMessageExpirationSeconds,
    statusAllowReshare:
      existing.statusAllowReshare ?? DEFAULT_USER_PRIVACY_PREFERENCE.statusAllowReshare
  };
}

async function isViewerInOwnerContacts(
  ownerUserId: string,
  viewerUserId: string
): Promise<boolean> {
  if (!ownerUserId || !viewerUserId || ownerUserId === viewerUserId) {
    return true;
  }

  const viewer = await prismaUser.findUnique({
    where: { id: viewerUserId },
    select: { phone: true }
  });
  if (!viewer?.phone) {
    return false;
  }

  const lookupKeys = buildPhoneLookupKeys(viewer.phone);
  if (lookupKeys.length === 0) {
    return false;
  }

  const row = await prismaUserContact.findFirst({
    where: {
      ownerId: ownerUserId,
      lookupKey: { in: lookupKeys }
    },
    select: { ownerId: true }
  });

  return Boolean(row);
}

export async function canViewerAccessPrivacyAudience(params: {
  ownerUserId: string;
  viewerUserId: string;
  mode: UserPrivacyAudienceValue;
  targetUserIds?: string[];
}): Promise<boolean> {
  const { ownerUserId, viewerUserId, mode } = params;
  if (!ownerUserId || !viewerUserId || ownerUserId === viewerUserId) {
    return true;
  }

  const selectedUserIds = new Set(params.targetUserIds ?? []);

  switch (mode) {
    case "EVERYONE":
      return true;
    case "NOBODY":
      return false;
    case "ONLY_SHARED_WITH":
      return selectedUserIds.has(viewerUserId);
    case "MY_CONTACTS":
      return isViewerInOwnerContacts(ownerUserId, viewerUserId);
    case "EXCLUDED_CONTACTS":
      if (!(await isViewerInOwnerContacts(ownerUserId, viewerUserId))) {
        return false;
      }
      return !selectedUserIds.has(viewerUserId);
  }
}

async function canViewerSeeOwnerLastSeen(params: {
  ownerUserId: string;
  viewerUserId: string;
  ownerPreference?: UserPrivacyPreferenceRecord;
  viewerPreference?: UserPrivacyPreferenceRecord;
}): Promise<boolean> {
  const { ownerUserId, viewerUserId } = params;
  if (!ownerUserId || !viewerUserId || ownerUserId === viewerUserId) {
    return true;
  }

  const ownerPreference =
    params.ownerPreference ?? (await getUserPrivacyPreference(ownerUserId));
  const viewerPreference =
    params.viewerPreference ?? (await getUserPrivacyPreference(viewerUserId));

  const ownerAllowsViewer = await canViewerAccessPrivacyAudience({
    ownerUserId,
    viewerUserId,
    mode: ownerPreference.lastSeenMode,
    targetUserIds: ownerPreference.lastSeenTargetUserIds
  });
  if (!ownerAllowsViewer) {
    return false;
  }

  return canViewerAccessPrivacyAudience({
    ownerUserId: viewerUserId,
    viewerUserId: ownerUserId,
    mode: viewerPreference.lastSeenMode,
    targetUserIds: viewerPreference.lastSeenTargetUserIds
  });
}

export async function buildPresencePayloadForViewer(params: {
  ownerUserId: string;
  viewerUserId: string;
  online: boolean;
  lastSeenAt: string | null;
}): Promise<{
  userId: string;
  online: boolean;
  lastSeenAt: string | null;
}> {
  const { ownerUserId, viewerUserId } = params;
  if (!ownerUserId || !viewerUserId || ownerUserId === viewerUserId) {
    return {
      userId: ownerUserId,
      online: params.online,
      lastSeenAt: params.lastSeenAt
    };
  }

  const [ownerPreference, viewerPreference] = await Promise.all([
    getUserPrivacyPreference(ownerUserId),
    getUserPrivacyPreference(viewerUserId)
  ]);

  const canSeeLastSeen = await canViewerSeeOwnerLastSeen({
    ownerUserId,
    viewerUserId,
    ownerPreference,
    viewerPreference
  });

  const ownerAllowsOnline =
    ownerPreference.onlineMode === "EVERYONE"
      ? true
      : await canViewerAccessPrivacyAudience({
          ownerUserId,
          viewerUserId,
          mode: ownerPreference.lastSeenMode,
          targetUserIds: ownerPreference.lastSeenTargetUserIds
        });
  const viewerSharesBack = await canViewerAccessPrivacyAudience({
    ownerUserId: viewerUserId,
    viewerUserId: ownerUserId,
    mode: viewerPreference.lastSeenMode,
    targetUserIds: viewerPreference.lastSeenTargetUserIds
  });
  const canSeeOnline = ownerAllowsOnline && viewerSharesBack;

  return {
    userId: ownerUserId,
    online: canSeeOnline ? params.online : false,
    lastSeenAt: canSeeLastSeen ? params.lastSeenAt : null
  };
}

export async function buildViewerScopedProfilePrivacy(params: {
  ownerUserId: string;
  viewerUserId: string;
  about: string | null;
  avatarUrl: string | null;
  socialLinks: string[];
}): Promise<{
  about: string | null;
  avatarUrl: string | null;
  socialLinks: string[];
}> {
  const { ownerUserId, viewerUserId } = params;
  if (!ownerUserId || !viewerUserId || ownerUserId === viewerUserId) {
    return {
      about: params.about,
      avatarUrl: params.avatarUrl,
      socialLinks: params.socialLinks
    };
  }

  const preference = await getUserPrivacyPreference(ownerUserId);
  const [canSeeAbout, canSeeAvatar, canSeeLinks] = await Promise.all([
    canViewerAccessPrivacyAudience({
      ownerUserId,
      viewerUserId,
      mode: preference.aboutMode,
      targetUserIds: preference.aboutTargetUserIds
    }),
    canViewerAccessPrivacyAudience({
      ownerUserId,
      viewerUserId,
      mode: preference.profilePhotoMode,
      targetUserIds: preference.profilePhotoTargetUserIds
    }),
    canViewerAccessPrivacyAudience({
      ownerUserId,
      viewerUserId,
      mode: preference.linksMode,
      targetUserIds: preference.linksTargetUserIds
    })
  ]);

  return {
    about: canSeeAbout ? params.about : null,
    avatarUrl: canSeeAvatar ? params.avatarUrl : null,
    socialLinks: canSeeLinks ? params.socialLinks : []
  };
}

export async function canRequesterAddUserToGroup(
  requesterUserId: string,
  targetUserId: string
): Promise<boolean> {
  if (!requesterUserId || !targetUserId || requesterUserId === targetUserId) {
    return true;
  }

  const preference = await getUserPrivacyPreference(targetUserId);
  return canViewerAccessPrivacyAudience({
    ownerUserId: targetUserId,
    viewerUserId: requesterUserId,
    mode: preference.groupsMode,
    targetUserIds: preference.groupsTargetUserIds
  });
}
