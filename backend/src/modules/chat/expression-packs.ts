import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

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
  version: string;
  sourceKind: ExpressionPackSourceKindValue;
  archivePath: string;
  isActive: boolean;
  uploadedAt: string | null;
  archiveExists: boolean;
  archiveSizeBytes: number;
  itemCount: number;
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
const expressionPackManifestPath = path.join(expressionPacksRootDir, "manifest.json");

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

function isSupportedAssetType(value: string): value is ExpressionPackAssetTypeValue {
  return (
    value === "static_png" ||
    value === "static_webp" ||
    value === "animated_lottie" ||
    value === "video_webm"
  );
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
    sourceKind !== "remote_zip" ||
    items.length === 0
  ) {
    return null;
  }

  return {
    id,
    title,
    subtitle,
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

export async function listExpressionPacks(baseUrl: string): Promise<ExpressionPackCatalogResponse> {
  const manifest = await loadExpressionPackManifest();
  const packs: ExpressionPackApiItem[] = [];

  for (const pack of manifest.packs) {
    if (!pack.isActive) continue;
    const absoluteArchivePath = resolveArchiveAbsolutePath(pack.archivePath);
    if (!absoluteArchivePath) continue;
    try {
      const stat = await fs.stat(absoluteArchivePath);
      if (!stat.isFile() || stat.size <= 0) continue;
    } catch {
      continue;
    }

    packs.push({
      id: pack.id,
      title: pack.title,
      subtitle: pack.subtitle,
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
    });
  }

  return {
    catalogVersion: manifest.catalogVersion,
    packs
  };
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
      return {
        id: pack.id,
        title: pack.title,
        subtitle: pack.subtitle,
        version: pack.version,
        sourceKind: pack.sourceKind,
        archivePath: pack.archivePath,
        isActive: pack.isActive,
        uploadedAt: pack.uploadedAt,
        archiveExists,
        archiveSizeBytes,
        itemCount: pack.items.length,
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
      const titleCompare = left.title.localeCompare(right.title, "tr");
      if (titleCompare !== 0) return titleCompare;
      return right.version.localeCompare(left.version, "tr");
    })
  };
}

export async function upsertAdminExpressionPack(input: {
  id: string;
  title: string;
  subtitle?: string | null;
  version: string;
  isActive?: boolean;
  items: Array<{
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
    version: normalizeTrimmedString(input.version, 60),
    sourceKind: "remote_zip",
    archivePath: buildDefaultArchivePath(input.id, input.version),
    isActive: input.isActive !== false,
    uploadedAt: null,
    items: input.items.map((item) => ({
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
    manifest.packs[existingIndex] = nextPack;
  } else {
    manifest.packs.push(nextPack);
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
  target.isActive = input.isActive;
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
