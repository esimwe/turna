import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { prisma } from "../../lib/prisma.js";

export type ExpressionPackSourceKindValue = "remote_zip";
export type ExpressionPackAssetTypeValue =
  | "static_png"
  | "static_webp"
  | "animated_lottie"
  | "video_webm";

interface ExpressionPackManifestItem {
  id: string;
  title: string;
  subtitle: string;
  iconEmoji: string;
  version: string;
  sourceKind: ExpressionPackSourceKindValue;
  archivePath: string;
  isActive: boolean;
  uploadedAt: string | null;
  items: ExpressionPackManifestStickerItem[];
}

interface ExpressionPackManifestStickerItem {
  id: string;
  emoji: string;
  label: string;
  assetType: ExpressionPackAssetTypeValue;
  relativeAssetPath: string;
  palette: string[];
}

export interface ExpressionPackApiItem {
  id: string;
  title: string;
  subtitle: string;
  iconEmoji: string;
  version: string;
  sourceKind: ExpressionPackSourceKindValue;
  downloadUrl: string;
  items: Array<{
    id: string;
    emoji: string;
    label: string;
    assetType: ExpressionPackAssetTypeValue;
    relativeAssetPath: string;
    palette: string[];
  }>;
}

export interface ExpressionPackCatalogResponse {
  catalogVersion: string;
  packs: ExpressionPackApiItem[];
}

export interface AdminExpressionPackItem {
  id: string;
  title: string;
  subtitle: string;
  iconEmoji: string;
  version: string;
  sourceKind: ExpressionPackSourceKindValue;
  archivePath: string;
  isActive: boolean;
  uploadedAt: string | null;
  archiveExists: boolean;
  archiveSizeBytes: number;
  itemCount: number;
  usageCount: number;
  lastUsedAt: string | null;
  items: Array<{
    id: string;
    emoji: string;
    label: string;
    assetType: ExpressionPackAssetTypeValue;
    relativeAssetPath: string;
    palette: string[];
  }>;
}

const expressionPacksRootDir = fileURLToPath(
  new URL("../../../public/expression-packs", import.meta.url)
);
const prismaExpressionPackUsageEvent = (
  prisma as unknown as { expressionPackUsageEvent: any }
).expressionPackUsageEvent;
const expressionPackManifestPath = path.join(expressionPacksRootDir, "manifest.json");
const maxExpressionPackArchiveBytes = 64 * 1024 * 1024;
const maxExpressionPackEntries = 512;
const maxExpressionPackTotalUncompressedBytes = 96 * 1024 * 1024;

const assetTypeAllowedExtensions: Record<ExpressionPackAssetTypeValue, string[]> = {
  static_png: [".png"],
  static_webp: [".webp"],
  animated_lottie: [".json", ".lottie"],
  video_webm: [".webm"]
};

const assetTypeMaxBytes: Record<ExpressionPackAssetTypeValue, number> = {
  static_png: 6 * 1024 * 1024,
  static_webp: 4 * 1024 * 1024,
  animated_lottie: 2 * 1024 * 1024,
  video_webm: 24 * 1024 * 1024
};

class ExpressionPackValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ExpressionPackValidationError";
  }
}

interface IndexedZipEntry {
  path: string;
  isDirectory: boolean;
  compressedSize: number;
  uncompressedSize: number;
}

function normalizeTrimmedString(value: unknown, maxLength: number): string {
  const normalized = typeof value === "string" ? value.trim() : value?.toString().trim() ?? "";
  if (!normalized) return "";
  return normalized.slice(0, maxLength);
}

function normalizePalette(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const colors: string[] = [];
  for (const item of value) {
    const normalized = normalizeTrimmedString(item, 16);
    if (!/^#?[A-Fa-f0-9]{6,8}$/.test(normalized)) continue;
    colors.push(normalized.startsWith("#") ? normalized : `#${normalized}`);
    if (colors.length >= 2) break;
  }
  return colors;
}

function normalizeRelativePath(value: unknown): string {
  const normalized = normalizeTrimmedString(value, 512).replaceAll("\\", "/");
  if (
    !normalized ||
    normalized.startsWith("/") ||
    normalized.includes("../") ||
    normalized.includes("..\\")
  ) {
    return "";
  }
  return normalized;
}

function tokenizeVersion(value: string): string[] {
  return String(value || "")
    .trim()
    .split(/[^a-zA-Z0-9]+/)
    .filter(Boolean);
}

function comparePackVersion(left: string, right: string): number {
  const leftTokens = tokenizeVersion(left);
  const rightTokens = tokenizeVersion(right);
  const length = Math.max(leftTokens.length, rightTokens.length);

  for (let index = 0; index < length; index += 1) {
    const leftToken = leftTokens[index] ?? "";
    const rightToken = rightTokens[index] ?? "";
    const leftNumeric = /^\d+$/.test(leftToken);
    const rightNumeric = /^\d+$/.test(rightToken);

    if (leftNumeric && rightNumeric) {
      const leftValue = Number.parseInt(leftToken, 10);
      const rightValue = Number.parseInt(rightToken, 10);
      if (leftValue !== rightValue) {
        return leftValue - rightValue;
      }
      continue;
    }

    const compared = leftToken.localeCompare(rightToken, "tr", { sensitivity: "base" });
    if (compared !== 0) return compared;
  }

  return left.localeCompare(right, "tr", { sensitivity: "base" });
}

function ensureSingleActiveVersion(
  packs: ExpressionPackManifestItem[],
  targetId: string,
  targetVersion: string
): void {
  for (const pack of packs) {
    if (pack.id !== targetId) continue;
    pack.isActive = pack.version === targetVersion;
  }
}

function buildPackVersionKey(packId: string, version: string): string {
  return `${packId.trim()}::${version.trim()}`;
}

function isSupportedAssetType(value: string): value is ExpressionPackAssetTypeValue {
  return (
    value === "static_png" ||
    value === "static_webp" ||
    value === "animated_lottie" ||
    value === "video_webm"
  );
}

function assetTypeForRelativePath(relativePath: string): ExpressionPackAssetTypeValue | null {
  const extension = path.extname(relativePath).toLowerCase();
  for (const [assetType, extensions] of Object.entries(assetTypeAllowedExtensions) as Array<
    [ExpressionPackAssetTypeValue, string[]]
  >) {
    if (extensions.includes(extension)) {
      return assetType;
    }
  }
  return null;
}

function sanitizeGeneratedItemId(value: string): string {
  const normalized = value
    .trim()
    .toLowerCase()
    .replaceAll(/[^a-z0-9]+/g, "-")
    .replaceAll(/^-+|-+$/g, "");
  return normalized.slice(0, 120);
}

function humanizeGeneratedLabel(filePath: string): string {
  const baseName = path.basename(filePath, path.extname(filePath));
  const cleaned = baseName
    .replaceAll(/[_-]?hires/gi, "")
    .replaceAll(/[_-]?icon/gi, "")
    .replaceAll(/[_-]?emoji/gi, "")
    .replaceAll(/[_-]+/g, " ")
    .trim();
  if (!cleaned) return "Sticker";
  return cleaned
    .split(/\s+/)
    .map((part) => (part ? `${part.charAt(0).toUpperCase()}${part.slice(1)}` : part))
    .join(" ")
    .slice(0, 80);
}

function inferEmojiFromRelativePath(filePath: string): string {
  const normalized = path
    .basename(filePath, path.extname(filePath))
    .trim()
    .toLowerCase()
    .replaceAll(/[_\s]+/g, "-");

  const rules: Array<[string, string]> = [
    ["rolling-on-the-floor", "🤣"],
    ["tears-of-joy", "😂"],
    ["big-eyes", "😃"],
    ["smiling-eyes", "😊"],
    ["heart-eyes", "😍"],
    ["in-love", "😍"],
    ["blowing-a-kiss", "😘"],
    ["kissing-face", "😘"],
    ["kiss", "😘"],
    ["squinting", "😆"],
    ["tongue", "😛"],
    ["halo", "😇"],
    ["upside-down", "🙃"],
    ["winking", "😉"],
    ["mask", "😷"],
    ["fearful", "😨"],
    ["nauseated", "🤢"],
    ["poo", "💩"],
    ["relieved", "😌"],
    ["pouting", "😠"],
    ["angry", "😠"],
    ["sad", "😢"],
    ["disappointed", "😞"],
    ["blushing", "😊"],
    ["slightly-smiling", "🙂"],
    ["smiling-face", "😊"],
    ["grinning", "😀"],
    ["grin", "😄"],
    ["lol", "😆"],
    ["zany", "🤪"]
  ];

  for (const [pattern, emoji] of rules) {
    if (normalized.includes(pattern)) {
      return emoji;
    }
  }
  return "🙂";
}

function buildGeneratedItemsFromArchive(
  archiveBytes: Buffer
): ExpressionPackManifestStickerItem[] {
  const entries = listArchiveEntries(archiveBytes);
  const items: ExpressionPackManifestStickerItem[] = [];
  const usedIds = new Set<string>();

  for (const entry of entries) {
    if (!entry.path || entry.isDirectory) continue;
    const assetType = assetTypeForRelativePath(entry.path);
    if (!assetType) continue;

    let itemId = sanitizeGeneratedItemId(
      path.join(path.dirname(entry.path), path.basename(entry.path, path.extname(entry.path)))
    );
    if (!itemId) {
      itemId = `sticker-${items.length + 1}`;
    }
    let uniqueItemId = itemId;
    let suffix = 2;
    while (usedIds.has(uniqueItemId)) {
      uniqueItemId = `${itemId}-${suffix}`;
      suffix += 1;
    }
    usedIds.add(uniqueItemId);

    items.push({
      id: uniqueItemId,
      emoji: inferEmojiFromRelativePath(entry.path),
      label: humanizeGeneratedLabel(entry.path),
      assetType,
      relativeAssetPath: entry.path,
      palette: []
    });
  }

  if (items.length === 0) {
    throw new ExpressionPackValidationError(
      "Zip icinde desteklenen png/webp/lottie/webm dosyasi bulunamadi."
    );
  }

  return items.slice(0, 200);
}

function parseManifestItem(value: unknown): ExpressionPackManifestStickerItem | null {
  if (value == null || typeof value !== "object") return null;
  const map = value as Record<string, unknown>;
  const id = normalizeTrimmedString(map.id, 120);
  const emoji = normalizeTrimmedString(map.emoji, 32);
  const label = normalizeTrimmedString(map.label, 80);
  const relativeAssetPath = normalizeRelativePath(map.relativeAssetPath);
  const rawAssetType = normalizeTrimmedString(map.assetType, 32).toLowerCase();
  const assetType = isSupportedAssetType(rawAssetType) ? rawAssetType : "static_png";
  if (!id || !emoji || !label || !relativeAssetPath) {
    return null;
  }
  return {
    id,
    emoji,
    label,
    assetType,
    relativeAssetPath,
    palette: normalizePalette(map.palette)
  };
}

function parseManifestPack(value: unknown): ExpressionPackManifestItem | null {
  if (value == null || typeof value !== "object") return null;
  const map = value as Record<string, unknown>;
  const id = normalizeTrimmedString(map.id, 120);
  const title = normalizeTrimmedString(map.title, 80);
  const subtitle = normalizeTrimmedString(map.subtitle, 160);
  const iconEmoji = normalizeTrimmedString(map.iconEmoji, 32) || "🙂";
  const version = normalizeTrimmedString(map.version, 60);
  const sourceKind = normalizeTrimmedString(map.sourceKind, 32).toLowerCase();
  const archivePath = normalizeRelativePath(map.archivePath);
  const isActive = map.isActive !== false;
  const uploadedAt = normalizeTrimmedString(map.uploadedAt, 64) || null;
  const items = (Array.isArray(map.items) ? map.items : [])
    .map((item) => parseManifestItem(item))
    .filter((item): item is ExpressionPackManifestStickerItem => item != null);

  if (
    !id ||
    !title ||
    !version ||
    !archivePath ||
    sourceKind !== "remote_zip"
  ) {
    return null;
  }

  return {
    id,
    title,
    subtitle,
    iconEmoji,
    version,
    sourceKind: "remote_zip",
    archivePath,
    isActive,
    uploadedAt,
    items
  };
}

async function loadExpressionPackManifest(): Promise<{
  catalogVersion: string;
  packs: ExpressionPackManifestItem[];
}> {
  try {
    const raw = await fs.readFile(expressionPackManifestPath, "utf8");
    const payload = JSON.parse(raw) as Record<string, unknown>;
    const packs = (Array.isArray(payload.packs) ? payload.packs : [])
      .map((item) => parseManifestPack(item))
      .filter((item): item is ExpressionPackManifestItem => item != null);
    return {
      catalogVersion:
        normalizeTrimmedString(payload.catalogVersion, 80) ||
        new Date().toISOString().slice(0, 10),
      packs
    };
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return { catalogVersion: new Date().toISOString().slice(0, 10), packs: [] };
    }
    throw error;
  }
}

async function writeExpressionPackManifest(input: {
  catalogVersion: string;
  packs: ExpressionPackManifestItem[];
}): Promise<void> {
  await fs.mkdir(expressionPacksRootDir, { recursive: true });
  const payload = {
    catalogVersion: input.catalogVersion,
    packs: input.packs.map((pack) => ({
      id: pack.id,
      title: pack.title,
      subtitle: pack.subtitle,
      iconEmoji: pack.iconEmoji,
      version: pack.version,
      sourceKind: pack.sourceKind,
      archivePath: pack.archivePath,
      isActive: pack.isActive,
      uploadedAt: pack.uploadedAt,
      items: pack.items.map((item) => ({
        id: item.id,
        emoji: item.emoji,
        label: item.label,
        assetType: item.assetType,
        relativeAssetPath: item.relativeAssetPath,
        palette: item.palette
      }))
    }))
  };
  const tempPath = `${expressionPackManifestPath}.tmp`;
  await fs.writeFile(tempPath, JSON.stringify(payload, null, 2));
  await fs.rename(tempPath, expressionPackManifestPath);
}

function resolveArchiveAbsolutePath(relativePath: string): string | null {
  const normalized = normalizeRelativePath(relativePath);
  if (!normalized) return null;
  const absolutePath = path.resolve(expressionPacksRootDir, normalized);
  if (
    absolutePath !== expressionPacksRootDir &&
    !absolutePath.startsWith(`${expressionPacksRootDir}${path.sep}`)
  ) {
    return null;
  }
  return absolutePath;
}

function buildDownloadPath(packId: string, version: string): string {
  return `/api/chats/expression-packs/${encodeURIComponent(packId)}/${encodeURIComponent(version)}/archive`;
}

function listArchiveEntries(archiveBytes: Buffer): IndexedZipEntry[] {
  if (archiveBytes.length < 22) {
    throw new ExpressionPackValidationError("Zip arsivi gecersiz veya eksik.");
  }

  let eocdOffset = -1;
  const minOffset = Math.max(0, archiveBytes.length - (0xffff + 22));
  for (let offset = archiveBytes.length - 22; offset >= minOffset; offset -= 1) {
    if (archiveBytes.readUInt32LE(offset) === 0x06054b50) {
      eocdOffset = offset;
      break;
    }
  }
  if (eocdOffset < 0) {
    throw new ExpressionPackValidationError("Zip arsivinin merkezi dizini bulunamadi.");
  }

  const totalEntries = archiveBytes.readUInt16LE(eocdOffset + 10);
  const centralDirectorySize = archiveBytes.readUInt32LE(eocdOffset + 12);
  const centralDirectoryOffset = archiveBytes.readUInt32LE(eocdOffset + 16);
  if (
    centralDirectoryOffset < 0 ||
    centralDirectorySize <= 0 ||
    centralDirectoryOffset + centralDirectorySize > archiveBytes.length
  ) {
    throw new ExpressionPackValidationError("Zip arsivinin merkezi dizin bilgisi bozuk.");
  }

  const entries: IndexedZipEntry[] = [];
  let cursor = centralDirectoryOffset;
  const endOffset = centralDirectoryOffset + centralDirectorySize;
  while (cursor < endOffset) {
    if (cursor + 46 > archiveBytes.length || archiveBytes.readUInt32LE(cursor) !== 0x02014b50) {
      throw new ExpressionPackValidationError("Zip arsivi okunurken gecersiz entry bulundu.");
    }
    const compressedSize = archiveBytes.readUInt32LE(cursor + 20);
    const uncompressedSize = archiveBytes.readUInt32LE(cursor + 24);
    const fileNameLength = archiveBytes.readUInt16LE(cursor + 28);
    const extraLength = archiveBytes.readUInt16LE(cursor + 30);
    const commentLength = archiveBytes.readUInt16LE(cursor + 32);
    const dataStart = cursor + 46;
    const dataEnd = dataStart + fileNameLength;
    if (dataEnd > archiveBytes.length) {
      throw new ExpressionPackValidationError("Zip arsivindeki dosya isimleri okunamadi.");
    }
    const rawPath = archiveBytes.subarray(dataStart, dataEnd).toString("utf8");
    const normalizedPath = normalizeRelativePath(rawPath);
    if (!normalizedPath && rawPath.trim()) {
      throw new ExpressionPackValidationError("Zip icinde gecersiz dosya yolu bulundu.");
    }
    entries.push({
      path: normalizedPath,
      isDirectory: rawPath.endsWith("/"),
      compressedSize,
      uncompressedSize
    });
    if (entries.length > maxExpressionPackEntries) {
      throw new ExpressionPackValidationError("Zip icindeki dosya sayisi siniri asti.");
    }
    cursor = dataEnd + extraLength + commentLength;
  }

  if (totalEntries > 0 && entries.length !== totalEntries) {
    throw new ExpressionPackValidationError("Zip arsivindeki entry sayisi tutarsiz.");
  }

  return entries;
}

function assertValidPackDefinition(pack: ExpressionPackManifestItem): void {
  if (!pack.id || !pack.title || !pack.version) {
    throw new ExpressionPackValidationError("Pack bilgileri eksik.");
  }
  if (pack.items.length === 0) {
    throw new ExpressionPackValidationError("Pack icin en az bir item gerekli.");
  }

  const itemIds = new Set<string>();
  const relativePaths = new Set<string>();
  for (const item of pack.items) {
    if (!item.id || !item.emoji || !item.label || !item.relativeAssetPath) {
      throw new ExpressionPackValidationError("Pack item alanlari eksik.");
    }
    if (itemIds.has(item.id)) {
      throw new ExpressionPackValidationError(`Ayni item id iki kez kullanildi: ${item.id}`);
    }
    itemIds.add(item.id);

    if (relativePaths.has(item.relativeAssetPath)) {
      throw new ExpressionPackValidationError(
        `Ayni relativeAssetPath iki kez kullanildi: ${item.relativeAssetPath}`
      );
    }
    relativePaths.add(item.relativeAssetPath);

    const extension = path.extname(item.relativeAssetPath).toLowerCase();
    const allowedExtensions = assetTypeAllowedExtensions[item.assetType];
    if (!allowedExtensions.includes(extension)) {
      throw new ExpressionPackValidationError(
        `${item.relativeAssetPath} yolu ${item.assetType} icin uygun uzantida degil.`
      );
    }
  }
}

function assertArchiveMatchesPack(
  pack: ExpressionPackManifestItem,
  archiveBytes: Buffer
): void {
  assertValidPackDefinition(pack);

  if (archiveBytes.length <= 0) {
    throw new ExpressionPackValidationError("Zip arsivi bos olamaz.");
  }
  if (archiveBytes.length > maxExpressionPackArchiveBytes) {
    throw new ExpressionPackValidationError("Zip arsivi 64 MB sinirini asti.");
  }

  const entries = listArchiveEntries(archiveBytes);
  const files = new Map<string, IndexedZipEntry>();
  let totalUncompressedBytes = 0;
  for (const entry of entries) {
    if (!entry.path || entry.isDirectory) continue;
    if (files.has(entry.path)) {
      throw new ExpressionPackValidationError(`Zip icinde ayni dosya iki kez bulundu: ${entry.path}`);
    }
    files.set(entry.path, entry);
    totalUncompressedBytes += entry.uncompressedSize;
  }

  if (files.size === 0) {
    throw new ExpressionPackValidationError("Zip arsivinde kullanilabilir dosya bulunamadi.");
  }
  if (totalUncompressedBytes > maxExpressionPackTotalUncompressedBytes) {
    throw new ExpressionPackValidationError("Zip arsivinin acilmis boyutu izin verilen siniri asti.");
  }

  const missingPaths: string[] = [];
  for (const item of pack.items) {
    const file = files.get(item.relativeAssetPath);
    if (!file) {
      missingPaths.push(item.relativeAssetPath);
      continue;
    }
    if (file.uncompressedSize <= 0) {
      throw new ExpressionPackValidationError(`Bos dosya kabul edilmiyor: ${item.relativeAssetPath}`);
    }
    if (file.uncompressedSize > assetTypeMaxBytes[item.assetType]) {
      throw new ExpressionPackValidationError(
        `${item.relativeAssetPath} dosyasi izin verilen boyutu asiyor.`
      );
    }
  }

  if (missingPaths.length > 0) {
    const preview = missingPaths.slice(0, 4).join(", ");
    throw new ExpressionPackValidationError(
      `Zip icinde beklenen dosyalar bulunamadi: ${preview}${
        missingPaths.length > 4 ? " ..." : ""
      }`
    );
  }
}

export function isExpressionPackValidationError(
  error: unknown
): error is ExpressionPackValidationError {
  return error instanceof ExpressionPackValidationError;
}

export async function listExpressionPacks(baseUrl: string): Promise<ExpressionPackCatalogResponse> {
  const manifest = await loadExpressionPackManifest();
  const latestActivePacks = new Map<string, ExpressionPackManifestItem>();

  for (const pack of manifest.packs) {
    if (!pack.isActive) continue;
    if (pack.items.length === 0) continue;
    const absoluteArchivePath = resolveArchiveAbsolutePath(pack.archivePath);
    if (!absoluteArchivePath) continue;
    try {
      const stat = await fs.stat(absoluteArchivePath);
      if (!stat.isFile() || stat.size <= 0) continue;
    } catch {
      continue;
    }

    const current = latestActivePacks.get(pack.id);
    if (!current || comparePackVersion(pack.version, current.version) > 0) {
      latestActivePacks.set(pack.id, pack);
    }
  }

  const packs = Array.from(latestActivePacks.values())
    .sort((left, right) => {
      const titleCompare = left.title.localeCompare(right.title, "tr", { sensitivity: "base" });
      if (titleCompare !== 0) return titleCompare;
      return comparePackVersion(right.version, left.version);
    })
    .map((pack) => ({
      id: pack.id,
      title: pack.title,
      subtitle: pack.subtitle,
      iconEmoji: pack.iconEmoji,
      version: pack.version,
      sourceKind: pack.sourceKind,
      downloadUrl: `${baseUrl}${buildDownloadPath(pack.id, pack.version)}`,
      items: pack.items.map((item) => ({
        id: item.id,
        emoji: item.emoji,
        label: item.label,
        assetType: item.assetType,
        relativeAssetPath: item.relativeAssetPath,
        palette: item.palette
      }))
    }));

  return {
    catalogVersion: manifest.catalogVersion,
    packs
  };
}

async function getUsageSummaryByPackVersion(): Promise<
  Map<string, { usageCount: number; lastUsedAt: string | null }>
> {
  const rows = await prismaExpressionPackUsageEvent.groupBy({
    by: ["packId", "packVersion"],
    _count: {
      packId: true
    },
    _max: {
      createdAt: true
    }
  });

  const map = new Map<string, { usageCount: number; lastUsedAt: string | null }>();
  for (const row of rows as Array<{
    packId: string;
    packVersion: string;
    _count?: { packId?: number | null };
    _max?: { createdAt?: Date | string | null };
  }>) {
    const lastUsedAtValue = row._max?.createdAt;
    map.set(buildPackVersionKey(row.packId, row.packVersion), {
      usageCount: row._count?.packId ?? 0,
      lastUsedAt:
        lastUsedAtValue instanceof Date
          ? lastUsedAtValue.toISOString()
          : lastUsedAtValue?.toString() ?? null
    });
  }
  return map;
}

export async function resolveExpressionPackArchivePath(
  packId: string,
  version: string
): Promise<string | null> {
  const manifest = await loadExpressionPackManifest();
  const pack = manifest.packs.find(
    (item) => item.id === packId.trim() && item.version === version.trim()
  );
  if (!pack) return null;
  const absoluteArchivePath = resolveArchiveAbsolutePath(pack.archivePath);
  if (!absoluteArchivePath) return null;
  try {
    const stat = await fs.stat(absoluteArchivePath);
    if (!pack.isActive || !stat.isFile() || stat.size <= 0) return null;
    return absoluteArchivePath;
  } catch {
    return null;
  }
}

function buildDefaultArchivePath(packId: string, version: string): string {
  const normalizedId = packId.replaceAll(/[^a-zA-Z0-9._-]/g, "_");
  const normalizedVersion = version.replaceAll(/[^a-zA-Z0-9._-]/g, "_");
  return `archives/${normalizedId}-${normalizedVersion}.zip`;
}

export async function listAdminExpressionPacks(): Promise<{
  catalogVersion: string;
  packs: AdminExpressionPackItem[];
}> {
  const manifest = await loadExpressionPackManifest();
  const usageSummaryByKey = await getUsageSummaryByPackVersion();
  const packs = await Promise.all(
    manifest.packs.map(async (pack) => {
      const absoluteArchivePath = resolveArchiveAbsolutePath(pack.archivePath);
      let archiveExists = false;
      let archiveSizeBytes = 0;
      if (absoluteArchivePath) {
        try {
          const stat = await fs.stat(absoluteArchivePath);
          archiveExists = stat.isFile() && stat.size > 0;
          archiveSizeBytes = archiveExists ? stat.size : 0;
        } catch {
          archiveExists = false;
          archiveSizeBytes = 0;
        }
      }
      const usageSummary =
        usageSummaryByKey.get(buildPackVersionKey(pack.id, pack.version)) ?? null;
      return {
        id: pack.id,
        title: pack.title,
        subtitle: pack.subtitle,
        iconEmoji: pack.iconEmoji,
        version: pack.version,
        sourceKind: pack.sourceKind,
        archivePath: pack.archivePath,
        isActive: pack.isActive,
        uploadedAt: pack.uploadedAt,
        archiveExists,
        archiveSizeBytes,
        itemCount: pack.items.length,
        usageCount: usageSummary?.usageCount ?? 0,
        lastUsedAt: usageSummary?.lastUsedAt ?? null,
        items: pack.items.map((item) => ({
          id: item.id,
          emoji: item.emoji,
          label: item.label,
          assetType: item.assetType,
          relativeAssetPath: item.relativeAssetPath,
          palette: item.palette
        }))
      } satisfies AdminExpressionPackItem;
    })
  );
  return {
    catalogVersion: manifest.catalogVersion,
    packs: packs.sort((left, right) => {
      const titleCompare = left.title.localeCompare(right.title, "tr", { sensitivity: "base" });
      if (titleCompare !== 0) return titleCompare;
      return comparePackVersion(right.version, left.version);
    })
  };
}

export async function trackExpressionPackUsage(
  userId: string,
  input: {
    packId: string;
    version: string;
    itemId: string;
    surface?: string;
  }
): Promise<void> {
  const manifest = await loadExpressionPackManifest();
  const pack = manifest.packs.find(
    (item) =>
      item.id === input.packId.trim() &&
      item.version === input.version.trim() &&
      item.isActive
  );
  if (!pack) {
    throw new Error("expression_pack_not_found");
  }
  const sticker = pack.items.find((item) => item.id === input.itemId.trim());
  if (!sticker) {
    throw new Error("expression_pack_item_not_found");
  }

  await prismaExpressionPackUsageEvent.create({
    data: {
      userId,
      packId: pack.id,
      packVersion: pack.version,
      itemId: sticker.id,
      assetType: sticker.assetType,
      surface: normalizeTrimmedString(input.surface, 32) || "composer_sticker"
    }
  });
}

export async function upsertAdminExpressionPack(input: {
  id: string;
  title: string;
  subtitle?: string | null;
  iconEmoji?: string | null;
  version: string;
  isActive?: boolean;
  autoImportFromArchive?: boolean;
  items?: Array<{
    id: string;
    emoji: string;
    label: string;
    assetType: ExpressionPackAssetTypeValue;
    relativeAssetPath: string;
    palette?: string[];
  }>;
}): Promise<AdminExpressionPackItem> {
  const manifest = await loadExpressionPackManifest();
  const nextPack: ExpressionPackManifestItem = {
    id: normalizeTrimmedString(input.id, 120),
    title: normalizeTrimmedString(input.title, 80),
    subtitle: normalizeTrimmedString(input.subtitle, 160),
    iconEmoji: normalizeTrimmedString(input.iconEmoji, 32) || "🙂",
    version: normalizeTrimmedString(input.version, 60),
    sourceKind: "remote_zip",
    archivePath: buildDefaultArchivePath(input.id, input.version),
    isActive: input.isActive !== false,
    uploadedAt: null,
    items: (input.items ?? []).map((item) => ({
      id: normalizeTrimmedString(item.id, 120),
      emoji: normalizeTrimmedString(item.emoji, 32),
      label: normalizeTrimmedString(item.label, 80),
      assetType: item.assetType,
      relativeAssetPath: normalizeRelativePath(item.relativeAssetPath),
      palette: normalizePalette(item.palette)
    }))
  };

  const existingIndex = manifest.packs.findIndex(
    (item) => item.id === nextPack.id && item.version === nextPack.version
  );
  if (existingIndex >= 0) {
    const existing = manifest.packs[existingIndex];
    nextPack.archivePath = existing.archivePath;
    nextPack.uploadedAt = existing.uploadedAt;
    if (nextPack.items.length === 0 && input.autoImportFromArchive !== true) {
      nextPack.items = existing.items;
    }
    if (!nextPack.iconEmoji && input.autoImportFromArchive !== true) {
      nextPack.iconEmoji = existing.iconEmoji || "🙂";
    }
    manifest.packs[existingIndex] = nextPack;
  } else {
    manifest.packs.push(nextPack);
  }

  if (nextPack.items.length > 0) {
    assertValidPackDefinition(nextPack);
  }

  if (nextPack.isActive) {
    ensureSingleActiveVersion(manifest.packs, nextPack.id, nextPack.version);
  }

  manifest.catalogVersion = new Date().toISOString();
  await writeExpressionPackManifest(manifest);
  const listed = await listAdminExpressionPacks();
  const matched = listed.packs.find(
    (item) => item.id === nextPack.id && item.version === nextPack.version
  );
  if (!matched) {
    throw new Error("expression_pack_persist_failed");
  }
  return matched;
}

export async function updateAdminExpressionPackStatus(input: {
  id: string;
  version: string;
  isActive: boolean;
}): Promise<AdminExpressionPackItem> {
  const manifest = await loadExpressionPackManifest();
  const target = manifest.packs.find(
    (item) => item.id === input.id.trim() && item.version === input.version.trim()
  );
  if (!target) {
    throw new Error("expression_pack_not_found");
  }
  if (input.isActive) {
    ensureSingleActiveVersion(manifest.packs, target.id, target.version);
  } else {
    target.isActive = false;
  }
  manifest.catalogVersion = new Date().toISOString();
  await writeExpressionPackManifest(manifest);
  const listed = await listAdminExpressionPacks();
  const matched = listed.packs.find(
    (item) => item.id === target.id && item.version === target.version
  );
  if (!matched) {
    throw new Error("expression_pack_not_found");
  }
  return matched;
}

export async function writeAdminExpressionPackArchive(input: {
  id: string;
  version: string;
  archiveBytes: Buffer;
}): Promise<AdminExpressionPackItem> {
  const manifest = await loadExpressionPackManifest();
  const target = manifest.packs.find(
    (item) => item.id === input.id.trim() && item.version === input.version.trim()
  );
  if (!target) {
    throw new Error("expression_pack_not_found");
  }
  if (target.items.length === 0) {
    target.items = buildGeneratedItemsFromArchive(input.archiveBytes);
  }
  if (!target.iconEmoji.trim()) {
    target.iconEmoji = target.items[0]?.emoji || "🙂";
  }
  assertArchiveMatchesPack(target, input.archiveBytes);
  const absoluteArchivePath = resolveArchiveAbsolutePath(target.archivePath);
  if (!absoluteArchivePath) {
    throw new Error("expression_pack_archive_path_invalid");
  }
  await fs.mkdir(path.dirname(absoluteArchivePath), { recursive: true });
  await fs.writeFile(absoluteArchivePath, input.archiveBytes);
  target.uploadedAt = new Date().toISOString();
  manifest.catalogVersion = new Date().toISOString();
  await writeExpressionPackManifest(manifest);
  const listed = await listAdminExpressionPacks();
  const matched = listed.packs.find(
    (item) => item.id === target.id && item.version === target.version
  );
  if (!matched) {
    throw new Error("expression_pack_not_found");
  }
  return matched;
}
