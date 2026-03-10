const TURNA_REPLY_MARKER_PATTERN = /^\[\[turna-reply:([A-Za-z0-9_-]+)\]\]\n?/;
const TURNA_LOCATION_MARKER_PATTERN = /^\[\[turna-location:([A-Za-z0-9_-]+)\]\]\n?/;
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
  location: TurnaLocationPayload | null;
  deletedForEveryone: boolean;
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
    return isLiveLocationActive(payload) ? "Canli konum" : "Canli konum (sona erdi)";
  }
  return payload.title ?? "Konum";
}

export function parseTurnaMessageText(rawText: string | null | undefined): ParsedTurnaMessageText {
  const raw = (rawText ?? "").toString();
  if (raw.trim() === TURNA_DELETED_EVERYONE_MARKER) {
    return {
      text: "Silindi.",
      location: null,
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
        location: null,
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
          location: null,
          deletedForEveryone: false
        };
      }
      return {
        text: working.slice(locationMatch[0].length).trimStart(),
        location: payload,
        deletedForEveryone: false
      };
    } catch {
      return {
        text: raw,
        location: null,
        deletedForEveryone: false
      };
    }
  }

  return {
    text: working,
    location: null,
    deletedForEveryone: false
  };
}

export function summarizeTurnaMessageText(rawText: string | null | undefined): string {
  const parsed = parseTurnaMessageText(rawText);
  if (parsed.deletedForEveryone) return parsed.text;
  if (parsed.location) return summarizeLocation(parsed.location);
  return parsed.text.trim();
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
