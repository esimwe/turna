const TURNA_REPLY_MARKER_PATTERN = /^\[\[turna-reply:([A-Za-z0-9_-]+)\]\]\n?/;
const TURNA_STATUS_MARKER_PATTERN = /^\[\[turna-status:([A-Za-z0-9_-]+)\]\]\n?/;
const TURNA_LOCATION_MARKER_PATTERN = /^\[\[turna-location:([A-Za-z0-9_-]+)\]\]\n?/;
const TURNA_CONTACT_MARKER_PATTERN = /^\[\[turna-contact:([A-Za-z0-9_-]+)\]\]\n?/;
const TURNA_INLINE_EXPRESSION_MARKER_PATTERN = /\[\[turna-inline-expression:([A-Za-z0-9_-]+)\]\]/g;
export const TURNA_DELETED_EVERYONE_MARKER = "[[turna-deleted-everyone]]";

export interface TurnaLocationPayload {
  latitude: number;
  longitude: number;
  accuracyMeters?: number | null;
  title?: string | null;
  subtitle?: string | null;
  live?: boolean;
  liveId?: string | null;
  startedAt?: string | null;
  expiresAt?: string | null;
  updatedAt?: string | null;
  endedAt?: string | null;
}

export interface ParsedTurnaMessageText {
  text: string;
  status: TurnaStatusPayload | null;
  location: TurnaLocationPayload | null;
  contact: TurnaContactPayload | null;
  deletedForEveryone: boolean;
}

export interface TurnaContactPayload {
  displayName?: string | null;
  phones?: string[];
}

export interface TurnaStatusPayload {
  statusId: string;
  authorUserId: string;
  authorDisplayName?: string | null;
  statusType?: string | null;
  previewText?: string | null;
}

interface TurnaInlineExpressionPayload {
  emoji: string;
}

function nullableString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function normalizeBase64Url(value: string): string {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padding = normalized.length % 4;
  if (padding === 0) return normalized;
  return `${normalized}${"=".repeat(4 - padding)}`;
}

function decodeBase64Url(value: string): string {
  return Buffer.from(normalizeBase64Url(value), "base64").toString("utf8");
}

function parseNumber(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}

function parseLocationPayload(value: unknown): TurnaLocationPayload | null {
  if (!value || typeof value !== "object") return null;
  const map = value as Record<string, unknown>;
  return {
    latitude: parseNumber(map.latitude),
    longitude: parseNumber(map.longitude),
    accuracyMeters:
      typeof map.accuracyMeters === "number" && Number.isFinite(map.accuracyMeters)
        ? map.accuracyMeters
        : null,
    title: nullableString(map.title),
    subtitle: nullableString(map.subtitle),
    live: map.live === true,
    liveId: nullableString(map.liveId),
    startedAt: nullableString(map.startedAt),
    expiresAt: nullableString(map.expiresAt),
    updatedAt: nullableString(map.updatedAt),
    endedAt: nullableString(map.endedAt)
  };
}

function parseContactPayload(value: unknown): TurnaContactPayload | null {
  if (!value || typeof value !== "object") return null;
  const map = value as Record<string, unknown>;
  return {
    displayName: nullableString(map.displayName),
    phones: Array.isArray(map.phones)
      ? map.phones
          .map((item) => (typeof item === "string" ? item.trim() : ""))
          .filter((item) => item.length > 0)
      : []
  };
}

function parseStatusPayload(value: unknown): TurnaStatusPayload | null {
  if (!value || typeof value !== "object") return null;
  const map = value as Record<string, unknown>;
  const statusId = nullableString(map.statusId);
  const authorUserId = nullableString(map.authorUserId);
  if (!statusId || !authorUserId) return null;
  return {
    statusId,
    authorUserId,
    authorDisplayName: nullableString(map.authorDisplayName),
    statusType: nullableString(map.statusType),
    previewText: nullableString(map.previewText)
  };
}

function parseInlineExpressionPayload(value: unknown): TurnaInlineExpressionPayload | null {
  if (!value || typeof value !== "object") return null;
  const map = value as Record<string, unknown>;
  const emoji = nullableString(map.emoji);
  if (!emoji) return null;
  return { emoji };
}

function parseDate(value: string | null | undefined): Date | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isLiveLocationActive(payload: TurnaLocationPayload): boolean {
  if (!payload.live) return false;
  if (payload.endedAt) return false;
  const expiresAt = parseDate(payload.expiresAt);
  if (!expiresAt) return false;
  return Date.now() < expiresAt.getTime();
}

function summarizeLocation(payload: TurnaLocationPayload): string {
  if (payload.live) {
    return isLiveLocationActive(payload)
      ? "Canlı konum"
      : "Canlı konum (sona erdi)";
  }
  return payload.title ?? "Konum";
}

function summarizeContact(payload: TurnaContactPayload): string {
  return payload.displayName ?? "Kişi";
}

function summarizeStatus(payload: TurnaStatusPayload): string {
  const preview = payload.previewText?.trim();
  if (preview) return preview;
  switch ((payload.statusType ?? "").trim().toLowerCase()) {
    case "video":
      return "Video durumu";
    case "image":
      return "Fotograf durumu";
    default:
      return "Durum";
  }
}

function replaceInlineExpressionsWithEmoji(raw: string): string {
  return raw.replace(TURNA_INLINE_EXPRESSION_MARKER_PATTERN, (_, encoded: string) => {
    try {
      const decoded = JSON.parse(decodeBase64Url(encoded)) as Record<string, unknown>;
      return parseInlineExpressionPayload(decoded)?.emoji ?? "";
    } catch {
      return "";
    }
  });
}

export function parseTurnaMessageText(rawText: string | null | undefined): ParsedTurnaMessageText {
  const raw = (rawText ?? "").toString();
  if (raw.trim() === TURNA_DELETED_EVERYONE_MARKER) {
      return {
        text: "Silindi.",
        status: null,
        location: null,
        contact: null,
        deletedForEveryone: true
      };
  }

  let working = raw;
  const replyMatch = TURNA_REPLY_MARKER_PATTERN.exec(working);
  if (replyMatch) {
    try {
      JSON.parse(decodeBase64Url(replyMatch[1]!)) as Record<string, unknown>;
      working = working.slice(replyMatch[0].length);
    } catch {
      return {
        text: raw,
        status: null,
        location: null,
        contact: null,
        deletedForEveryone: false
      };
    }
  }

  let status: TurnaStatusPayload | null = null;
  const statusMatch = TURNA_STATUS_MARKER_PATTERN.exec(working);
  if (statusMatch) {
    try {
      const decoded = JSON.parse(decodeBase64Url(statusMatch[1]!)) as Record<string, unknown>;
      status = parseStatusPayload(decoded);
      if (!status) {
        return {
          text: raw,
          status: null,
          location: null,
          contact: null,
          deletedForEveryone: false
        };
      }
      working = working.slice(statusMatch[0].length);
    } catch {
      return {
        text: raw,
        status: null,
        location: null,
        contact: null,
        deletedForEveryone: false
      };
    }
  }

  const locationMatch = TURNA_LOCATION_MARKER_PATTERN.exec(working);
  if (locationMatch) {
    try {
      const decoded = JSON.parse(decodeBase64Url(locationMatch[1]!)) as Record<string, unknown>;
      const payload = parseLocationPayload(decoded);
      if (!payload) {
        return {
          text: raw,
          status: null,
          location: null,
          contact: null,
          deletedForEveryone: false
        };
      }
      return {
        text: working.slice(locationMatch[0].length).trimStart(),
        status,
        location: payload,
        contact: null,
        deletedForEveryone: false
      };
    } catch {
      return {
        text: raw,
        status: null,
        location: null,
        contact: null,
        deletedForEveryone: false
      };
    }
  }

  const contactMatch = TURNA_CONTACT_MARKER_PATTERN.exec(working);
  if (contactMatch) {
    try {
      const decoded = JSON.parse(decodeBase64Url(contactMatch[1]!)) as Record<string, unknown>;
      const payload = parseContactPayload(decoded);
      if (!payload) {
        return {
          text: raw,
          status: null,
          location: null,
          contact: null,
          deletedForEveryone: false
        };
      }
      return {
        text: working.slice(contactMatch[0].length).trimStart(),
        status,
        location: null,
        contact: payload,
        deletedForEveryone: false
      };
    } catch {
      return {
        text: raw,
        status: null,
        location: null,
        contact: null,
        deletedForEveryone: false
      };
    }
  }

  return {
    text: working,
    status,
    location: null,
    contact: null,
    deletedForEveryone: false
  };
}

export function summarizeTurnaMessageText(rawText: string | null | undefined): string {
  const parsed = parseTurnaMessageText(rawText);
  if (parsed.deletedForEveryone) return parsed.text;
  if (parsed.location) return summarizeLocation(parsed.location);
  if (parsed.contact) return summarizeContact(parsed.contact);
  const cleaned = replaceInlineExpressionsWithEmoji(parsed.text).trim();
  if (cleaned) return cleaned;
  if (parsed.status) return summarizeStatus(parsed.status);
  return cleaned;
}

export function canExtendLiveLocationEditWindow(
  existingText: string | null | undefined,
  nextText: string,
  now = new Date()
): boolean {
  const existing = parseTurnaMessageText(existingText);
  const next = parseTurnaMessageText(nextText);
  if (!existing.location?.live) return false;
  if (!existing.location.liveId || !next.location?.liveId) return false;
  if (existing.location.liveId !== next.location.liveId) return false;
  const expiresAt = parseDate(existing.location.expiresAt ?? next.location.expiresAt);
  if (!expiresAt) return false;
  const endedAt = parseDate(next.location.endedAt);
  if (endedAt && endedAt.getTime() <= expiresAt.getTime()) return true;
  return now.getTime() <= expiresAt.getTime();
}
