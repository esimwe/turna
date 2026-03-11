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
export type StatusUploadKind = "image" | "video";

let storageClient: S3Client | null = null;

function hasStorageConfig(): boolean {
  return Boolean(
    env.R2_BUCKET &&
      env.R2_ENDPOINT &&
      env.R2_ACCESS_KEY_ID &&
      env.R2_SECRET_ACCESS_KEY
  );
}

function getStorageClient(): S3Client {
  if (!hasStorageConfig()) {
    throw new Error("storage_not_configured");
  }

  if (!storageClient) {
    storageClient = new S3Client({
      region: "auto",
      endpoint: env.R2_ENDPOINT,
      forcePathStyle: true,
      credentials: {
        accessKeyId: env.R2_ACCESS_KEY_ID!,
        secretAccessKey: env.R2_SECRET_ACCESS_KEY!
      }
    });
  }

  return storageClient;
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

export function isStorageConfigured(): boolean {
  return hasStorageConfig();
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

export async function createAvatarUploadUrl(params: {
  userId: string;
  contentType: string;
  fileName?: string | null;
}): Promise<{
  objectKey: string;
  uploadUrl: string;
  headers: Record<string, string>;
}> {
  const client = getStorageClient();
  const objectKey = buildAvatarObjectKey(params.userId, params.contentType, params.fileName);
  const command = new PutObjectCommand({
    Bucket: env.R2_BUCKET!,
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
  const client = getStorageClient();
  const objectKey = buildChatAttachmentObjectKey(params);
  const command = new PutObjectCommand({
    Bucket: env.R2_BUCKET!,
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
  const client = getStorageClient();
  const objectKey = buildStatusAttachmentObjectKey(params);
  const command = new PutObjectCommand({
    Bucket: env.R2_BUCKET!,
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

export async function assertObjectExists(objectKey: string): Promise<void> {
  const client = getStorageClient();
  await client.send(
    new HeadObjectCommand({
      Bucket: env.R2_BUCKET!,
      Key: objectKey
    })
  );
}

export async function getObjectHead(objectKey: string): Promise<{
  contentType: string | null;
  contentLength: number | null;
}> {
  const client = getStorageClient();
  const response = await client.send(
    new HeadObjectCommand({
      Bucket: env.R2_BUCKET!,
      Key: objectKey
    })
  );

  return {
    contentType: response.ContentType ?? null,
    contentLength: response.ContentLength ?? null
  };
}

export async function getObjectBytes(objectKey: string): Promise<{
  bytes: Uint8Array;
  contentType: string;
  contentLength: number | null;
}> {
  const client = getStorageClient();
  const response = await client.send(
    new GetObjectCommand({
      Bucket: env.R2_BUCKET!,
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

export async function deleteObject(objectKey: string): Promise<void> {
  const client = getStorageClient();
  await client.send(
    new DeleteObjectCommand({
      Bucket: env.R2_BUCKET!,
      Key: objectKey
    })
  );
}

export async function createObjectReadUrl(objectKey: string): Promise<string> {
  const client = getStorageClient();
  return getSignedUrl(
    client,
    new GetObjectCommand({
      Bucket: env.R2_BUCKET!,
      Key: objectKey
    }),
    { expiresIn: 60 * 60 * 12 }
  );
}
