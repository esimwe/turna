import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "crypto";
import { env } from "../config/env.js";

const IMAGE_EXTENSION_BY_CONTENT_TYPE: Record<string, string> = {
  "image/gif": "gif",
  "image/heic": "heic",
  "image/heif": "heif",
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
  "image/png": "png",
  "image/webp": "webp"
};

const VIDEO_EXTENSION_BY_CONTENT_TYPE: Record<string, string> = {
  "video/mp4": "mp4",
  "video/quicktime": "mov",
  "video/webm": "webm",
  "video/x-m4v": "m4v"
};

export type ChatUploadKind = "image" | "video" | "file";
export type CommunityUploadKind = ChatUploadKind;
export type StatusUploadKind = "image" | "video";

export type StorageScope = "turna" | "community";

type StorageConfig = {
  bucket: string | undefined;
  endpoint: string | undefined;
  accessKeyId: string | undefined;
  secretAccessKey: string | undefined;
};

const storageClients: Partial<Record<StorageScope, S3Client>> = {};

function getStorageConfig(scope: StorageScope): StorageConfig {
  if (scope === "community") {
    return {
      bucket: env.COMMUNITY_R2_BUCKET,
      endpoint: env.COMMUNITY_R2_ENDPOINT,
      accessKeyId: env.COMMUNITY_R2_ACCESS_KEY_ID,
      secretAccessKey: env.COMMUNITY_R2_SECRET_ACCESS_KEY
    };
  }

  return {
    bucket: env.R2_BUCKET,
    endpoint: env.R2_ENDPOINT,
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY
  };
}

function storageNotConfiguredError(scope: StorageScope): string {
  return scope === "community" ? "community_storage_not_configured" : "storage_not_configured";
}

function getStorageBucket(scope: StorageScope): string {
  const config = getStorageConfig(scope);
  if (!config.bucket) {
    throw new Error(storageNotConfiguredError(scope));
  }
  return config.bucket;
}

function hasStorageConfig(scope: StorageScope = "turna"): boolean {
  const config = getStorageConfig(scope);
  return Boolean(
    config.bucket &&
      config.endpoint &&
      config.accessKeyId &&
      config.secretAccessKey
  );
}

function getStorageClient(scope: StorageScope = "turna"): S3Client {
  const config = getStorageConfig(scope);
  if (!hasStorageConfig(scope)) {
    throw new Error(storageNotConfiguredError(scope));
  }

  if (!storageClients[scope]) {
    storageClients[scope] = new S3Client({
      region: "auto",
      endpoint: config.endpoint!,
      forcePathStyle: true,
      credentials: {
        accessKeyId: config.accessKeyId!,
        secretAccessKey: config.secretAccessKey!
      }
    });
  }

  return storageClients[scope]!;
}

function sanitizeExtension(rawExtension: string | null | undefined): string {
  if (!rawExtension) return "bin";
  const normalized = rawExtension.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (!normalized) return "bin";
  return normalized.slice(0, 10);
}

function extractFileExtension(fileName?: string | null): string | null {
  if (!fileName) return null;
  const cleaned = fileName.trim().split("/").pop() ?? "";
  const parts = cleaned.split(".");
  if (parts.length < 2) return null;
  return sanitizeExtension(parts.pop());
}

function inferExtension(contentType: string, fileName?: string | null): string {
  const fromName = extractFileExtension(fileName);
  if (fromName) return fromName;
  return (
    IMAGE_EXTENSION_BY_CONTENT_TYPE[contentType] ??
    VIDEO_EXTENSION_BY_CONTENT_TYPE[contentType] ??
    "bin"
  );
}

export function isStorageConfigured(scope: StorageScope = "turna"): boolean {
  return hasStorageConfig(scope);
}

export function isCommunityStorageConfigured(): boolean {
  return hasStorageConfig("community");
}

export function buildAvatarObjectKey(
  userId: string,
  contentType: string,
  fileName?: string | null
): string {
  const extension = inferExtension(contentType, fileName);
  return `avatars/${userId}/${Date.now()}-${randomUUID()}.${extension}`;
}

export function isAvatarKeyOwnedByUser(userId: string, objectKey: string): boolean {
  return objectKey.startsWith(`avatars/${userId}/`);
}

export function buildChatAttachmentObjectKey(params: {
  chatId: string;
  userId: string;
  kind: ChatUploadKind;
  contentType: string;
  fileName?: string | null;
}): string {
  const extension = inferExtension(params.contentType, params.fileName);
  return `chat-media/${params.chatId}/${params.userId}/${params.kind}/${Date.now()}-${randomUUID()}.${extension}`;
}

export function isChatAttachmentKeyOwnedByUser(params: {
  chatId: string;
  userId: string;
  objectKey: string;
}): boolean {
  return params.objectKey.startsWith(`chat-media/${params.chatId}/${params.userId}/`);
}

export function buildStatusAttachmentObjectKey(params: {
  userId: string;
  kind: StatusUploadKind;
  contentType: string;
  fileName?: string | null;
}): string {
  const extension = inferExtension(params.contentType, params.fileName);
  return `statuses/${params.userId}/${params.kind}/${Date.now()}-${randomUUID()}.${extension}`;
}

export function isStatusAttachmentKeyOwnedByUser(params: {
  userId: string;
  objectKey: string;
}): boolean {
  return params.objectKey.startsWith(`statuses/${params.userId}/`);
}

export function buildCommunityAttachmentObjectKey(params: {
  communityId: string;
  userId: string;
  kind: CommunityUploadKind;
  contentType: string;
  fileName?: string | null;
}): string {
  const extension = inferExtension(params.contentType, params.fileName);
  return `community-media/${params.communityId}/${params.userId}/${params.kind}/${Date.now()}-${randomUUID()}.${extension}`;
}

export function isCommunityAttachmentKeyOwnedByUser(params: {
  communityId: string;
  userId: string;
  objectKey: string;
}): boolean {
  return params.objectKey.startsWith(`community-media/${params.communityId}/${params.userId}/`);
}

export async function createAvatarUploadUrl(params: {
  userId: string;
  contentType: string;
  fileName?: string | null;
}): Promise<{
  objectKey: string;
  uploadUrl: string;
  headers: Record<string, string>;
}> {
  const scope: StorageScope = "turna";
  const client = getStorageClient(scope);
  const objectKey = buildAvatarObjectKey(params.userId, params.contentType, params.fileName);
  const command = new PutObjectCommand({
    Bucket: getStorageBucket(scope),
    Key: objectKey,
    ContentType: params.contentType,
    CacheControl: "private, max-age=31536000"
  });

  const uploadUrl = await getSignedUrl(client, command, { expiresIn: 60 * 5 });

  return {
    objectKey,
    uploadUrl,
    headers: {
      "Content-Type": params.contentType
    }
  };
}

export async function createChatAttachmentUploadUrl(params: {
  chatId: string;
  userId: string;
  kind: ChatUploadKind;
  contentType: string;
  fileName?: string | null;
}): Promise<{
  objectKey: string;
  uploadUrl: string;
  headers: Record<string, string>;
}> {
  const scope: StorageScope = "turna";
  const client = getStorageClient(scope);
  const objectKey = buildChatAttachmentObjectKey(params);
  const command = new PutObjectCommand({
    Bucket: getStorageBucket(scope),
    Key: objectKey,
    ContentType: params.contentType,
    CacheControl: "private, max-age=31536000"
  });

  const uploadUrl = await getSignedUrl(client, command, { expiresIn: 60 * 5 });

  return {
    objectKey,
    uploadUrl,
    headers: {
      "Content-Type": params.contentType
    }
  };
}

export async function createStatusAttachmentUploadUrl(params: {
  userId: string;
  kind: StatusUploadKind;
  contentType: string;
  fileName?: string | null;
}): Promise<{
  objectKey: string;
  uploadUrl: string;
  headers: Record<string, string>;
}> {
  const scope: StorageScope = "turna";
  const client = getStorageClient(scope);
  const objectKey = buildStatusAttachmentObjectKey(params);
  const command = new PutObjectCommand({
    Bucket: getStorageBucket(scope),
    Key: objectKey,
    ContentType: params.contentType,
    CacheControl: "private, max-age=31536000"
  });

  const uploadUrl = await getSignedUrl(client, command, { expiresIn: 60 * 5 });

  return {
    objectKey,
    uploadUrl,
    headers: {
      "Content-Type": params.contentType
    }
  };
}

export async function createCommunityAttachmentUploadUrl(params: {
  communityId: string;
  userId: string;
  kind: CommunityUploadKind;
  contentType: string;
  fileName?: string | null;
}): Promise<{
  objectKey: string;
  uploadUrl: string;
  headers: Record<string, string>;
}> {
  const scope: StorageScope = "community";
  const client = getStorageClient(scope);
  const objectKey = buildCommunityAttachmentObjectKey(params);
  const command = new PutObjectCommand({
    Bucket: getStorageBucket(scope),
    Key: objectKey,
    ContentType: params.contentType,
    CacheControl: "private, max-age=31536000"
  });

  const uploadUrl = await getSignedUrl(client, command, { expiresIn: 60 * 5 });

  return {
    objectKey,
    uploadUrl,
    headers: {
      "Content-Type": params.contentType
    }
  };
}

export async function assertObjectExists(
  objectKey: string,
  scope: StorageScope = "turna"
): Promise<void> {
  const client = getStorageClient(scope);
  await client.send(
    new HeadObjectCommand({
      Bucket: getStorageBucket(scope),
      Key: objectKey
    })
  );
}

export async function getObjectHead(
  objectKey: string,
  scope: StorageScope = "turna"
): Promise<{
  contentType: string | null;
  contentLength: number | null;
}> {
  const client = getStorageClient(scope);
  const response = await client.send(
    new HeadObjectCommand({
      Bucket: getStorageBucket(scope),
      Key: objectKey
    })
  );

  return {
    contentType: response.ContentType ?? null,
    contentLength: response.ContentLength ?? null
  };
}

export async function getObjectBytes(
  objectKey: string,
  scope: StorageScope = "turna"
): Promise<{
  bytes: Uint8Array;
  contentType: string;
  contentLength: number | null;
}> {
  const client = getStorageClient(scope);
  const response = await client.send(
    new GetObjectCommand({
      Bucket: getStorageBucket(scope),
      Key: objectKey
    })
  );

  const bytes = response.Body ? await response.Body.transformToByteArray() : new Uint8Array();

  return {
    bytes,
    contentType: response.ContentType ?? "application/octet-stream",
    contentLength: response.ContentLength ?? null
  };
}

export async function deleteObject(
  objectKey: string,
  scope: StorageScope = "turna"
): Promise<void> {
  const client = getStorageClient(scope);
  await client.send(
    new DeleteObjectCommand({
      Bucket: getStorageBucket(scope),
      Key: objectKey
    })
  );
}

export async function createObjectReadUrl(
  objectKey: string,
  scope: StorageScope = "turna"
): Promise<string> {
  const client = getStorageClient(scope);
  return getSignedUrl(
    client,
    new GetObjectCommand({
      Bucket: getStorageBucket(scope),
      Key: objectKey
    }),
    { expiresIn: 60 * 60 * 12 }
  );
}

export async function assertCommunityObjectExists(objectKey: string): Promise<void> {
  await assertObjectExists(objectKey, "community");
}

export async function getCommunityObjectHead(objectKey: string): Promise<{
  contentType: string | null;
  contentLength: number | null;
}> {
  return getObjectHead(objectKey, "community");
}

export async function getCommunityObjectBytes(objectKey: string): Promise<{
  bytes: Uint8Array;
  contentType: string;
  contentLength: number | null;
}> {
  return getObjectBytes(objectKey, "community");
}

export async function deleteCommunityObject(objectKey: string): Promise<void> {
  await deleteObject(objectKey, "community");
}

export async function createCommunityObjectReadUrl(objectKey: string): Promise<string> {
  return createObjectReadUrl(objectKey, "community");
}
