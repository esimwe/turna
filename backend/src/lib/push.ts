import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { createSign } from "node:crypto";
import * as http2 from "node:http2";
import { env } from "../config/env.js";
import { logError, logInfo } from "./logger.js";
import { prisma } from "./prisma.js";
import { areUsersBlocked } from "./user-relationship.js";
import { summarizeTurnaMessageText } from "../modules/chat/message-text.js";
import type { ChatMessage } from "../modules/chat/chat.types.js";
import type { AppCallType } from "../modules/calls/call.types.js";
const MessageStatus = {
  sent: "sent",
  delivered: "delivered",
  read: "read"
} as const;
const PushPlatform = {
  IOS: "IOS",
  ANDROID: "ANDROID"
} as const;
type PushPlatformValue = typeof PushPlatform[keyof typeof PushPlatform];

interface PushDevice {
  id: string;
  userId: string;
  token: string;
  platform: PushPlatformValue;
  tokenKind: "STANDARD" | "VOIP";
}

interface IncomingCallPushParams {
  callId: string;
  type: AppCallType;
  callerId: string;
  callerDisplayName: string;
  recipientUserIds: string[];
}

interface CallEndedPushParams {
  callId: string;
  reason: string;
  recipientUserIds: string[];
}

let apnsBearerCache: { token: string; expiresAtEpochSeconds: number } | null = null;
let apnsVoipKeyErrorLogged = false;
const prismaDeviceToken = (prisma as unknown as { deviceToken: any }).deviceToken;
const prismaChatMember = (prisma as unknown as { chatMember: any }).chatMember;

function isAudioAttachmentMeta(attachment: {
  kind: "image" | "video" | "file";
  contentType: string;
  fileName: string | null;
}): boolean {
  if (attachment.contentType.toLowerCase().startsWith("audio/")) return true;

  const fileName = attachment.fileName?.toLowerCase() ?? "";
  return (
    fileName.endsWith(".m4a") ||
    fileName.endsWith(".aac") ||
    fileName.endsWith(".mp3") ||
    fileName.endsWith(".wav") ||
    fileName.endsWith(".ogg") ||
    fileName.endsWith(".opus")
  );
}

function hasFirebaseCredentials(): boolean {
  return Boolean(
    env.FIREBASE_SERVICE_ACCOUNT_JSON ||
      (env.FIREBASE_PROJECT_ID && env.FIREBASE_CLIENT_EMAIL && env.FIREBASE_PRIVATE_KEY)
  );
}

function hasApnsVoipCredentials(): boolean {
  return Boolean(
    env.APNS_TEAM_ID &&
      env.APNS_KEY_ID &&
      env.APNS_BUNDLE_ID &&
      (env.APNS_VOIP_PRIVATE_KEY || env.APNS_VOIP_PRIVATE_KEY_BASE64)
  );
}

function getFirebaseServiceAccount():
  | {
      projectId: string;
      clientEmail: string;
      privateKey: string;
    }
  | null {
  if (env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    try {
      const parsed = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON) as {
        project_id?: string;
        client_email?: string;
        private_key?: string;
      };
      if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
        return null;
      }
      return {
        projectId: parsed.project_id,
        clientEmail: parsed.client_email,
        privateKey: parsed.private_key
      };
    } catch (error) {
      logError("firebase service account json parse failed", error);
      return null;
    }
  }

  if (!env.FIREBASE_PROJECT_ID || !env.FIREBASE_CLIENT_EMAIL || !env.FIREBASE_PRIVATE_KEY) {
    return null;
  }

  return {
    projectId: env.FIREBASE_PROJECT_ID,
    clientEmail: env.FIREBASE_CLIENT_EMAIL,
    privateKey: env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n")
  };
}

function getApnsVoipPrivateKey(): string | null {
  if (env.APNS_VOIP_PRIVATE_KEY_BASE64) {
    try {
      return Buffer.from(env.APNS_VOIP_PRIVATE_KEY_BASE64, "base64").toString("utf8");
    } catch (error) {
      logError("apns private key base64 decode failed", error);
      return null;
    }
  }

  if (!env.APNS_VOIP_PRIVATE_KEY) return null;
  return env.APNS_VOIP_PRIVATE_KEY.replace(/\\n/g, "\n");
}

function ensureFirebaseApp() {
  const existing = getApps()[0];
  if (existing) return existing;

  const serviceAccount = getFirebaseServiceAccount();
  if (!serviceAccount) {
    return null;
  }

  return initializeApp({
    credential: cert(serviceAccount)
  });
}

function buildPushBody(message: ChatMessage): string {
  const trimmedText = summarizeTurnaMessageText(message.text);
  if (trimmedText.length > 0) {
    return trimmedText.length > 120 ? `${trimmedText.slice(0, 117)}...` : trimmedText;
  }

  if (message.attachments.length === 0) {
    return "Yeni mesaj";
  }

  if (message.attachments.length > 1) {
    return `${message.attachments.length} ek gönderdi`;
  }

  switch (message.attachments[0].kind) {
    case "image":
      return "Fotoğraf gönderdi";
    case "video":
      return "Video gönderdi";
    default:
      return isAudioAttachmentMeta(message.attachments[0])
        ? "Ses kaydı gönderdi"
        : "Dosya gönderdi";
  }
}

function buildChatPushCollapseId(chatId: string): string {
  const normalized = `chat-${chatId}`.replace(/[^A-Za-z0-9_.-]/g, "_");
  return normalized.length <= 64 ? normalized : normalized.slice(0, 64);
}

function base64UrlEncode(value: string): string {
  return Buffer.from(value)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function createApnsBearerToken(): string | null {
  if (!hasApnsVoipCredentials()) return null;
  const now = Math.floor(Date.now() / 1000);
  if (apnsBearerCache && apnsBearerCache.expiresAtEpochSeconds > now + 60) {
    return apnsBearerCache.token;
  }

  const privateKey = getApnsVoipPrivateKey();
  if (!privateKey || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) {
    return null;
  }

  const header = base64UrlEncode(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const payload = base64UrlEncode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now }));
  const unsignedToken = `${header}.${payload}`;
  const signer = createSign("sha256");
  signer.update(unsignedToken);
  signer.end();
  let signature: string;
  try {
    signature = signer.sign(privateKey, "base64url");
  } catch (error) {
    if (!apnsVoipKeyErrorLogged) {
      logError("apns voip bearer token create failed", {
        error: error instanceof Error ? error.message : String(error),
        hint: "Check APNS_VOIP_PRIVATE_KEY or APNS_VOIP_PRIVATE_KEY_BASE64 format. Apple .p8 key expected."
      });
      apnsVoipKeyErrorLogged = true;
    }
    return null;
  }
  const token = `${unsignedToken}.${signature}`;
  apnsBearerCache = {
    token,
    expiresAtEpochSeconds: now + 50 * 60
  };
  apnsVoipKeyErrorLogged = false;
  return token;
}

async function markInactiveDeviceTokens(deviceIds: string[]): Promise<void> {
  if (deviceIds.length === 0) return;
  await prismaDeviceToken.updateMany({
    where: { id: { in: deviceIds } },
    data: { isActive: false }
  });
}

function getInvalidFcmTokenIds(
  response: {
    responses: Array<{
      success: boolean;
      error?: { code?: string };
    }>;
  },
  devices: PushDevice[]
): string[] {
  return response.responses
    .map((result, index) => ({
      ok: result.success,
      id: devices[index]?.id,
      code: result.error?.code ?? ""
    }))
    .filter(
      (result) =>
        !result.ok &&
        result.id &&
        (result.code === "messaging/registration-token-not-registered" ||
          result.code === "messaging/invalid-registration-token")
    )
    .map((result) => result.id!);
}

function summarizeFcmFailures(
  response: {
    responses: Array<{
      success: boolean;
      error?: { code?: string; message?: string };
    }>;
  },
  devices: PushDevice[]
): Array<{
  deviceId: string;
  platform: string;
  tokenKind: string;
  code: string;
  message: string;
}> {
  return response.responses
    .map((result, index) => {
      if (result.success) return null;
      const device = devices[index];
      if (!device) return null;
      return {
        deviceId: device.id,
        platform: device.platform,
        tokenKind: device.tokenKind,
        code: result.error?.code ?? "unknown",
        message: result.error?.message ?? ""
      };
    })
    .filter((item): item is NonNullable<typeof item> => item != null);
}

async function findActiveDevices(userIds: string[]): Promise<PushDevice[]> {
  if (userIds.length === 0) return [];
  return prismaDeviceToken.findMany({
    where: {
      userId: { in: userIds },
      isActive: true
    },
    select: {
      id: true,
      userId: true,
      token: true,
      platform: true,
      tokenKind: true
    }
  });
}

async function countUnreadMessagesForUser(userId: string): Promise<number> {
  const memberships = await prismaChatMember.findMany({
    where: { userId },
    select: {
      chatId: true,
      hiddenAt: true,
      clearedAt: true
    }
  });

  let total = 0;
  for (const membership of memberships) {
    const cutoff =
      membership.hiddenAt && membership.clearedAt
        ? (membership.hiddenAt > membership.clearedAt
            ? membership.hiddenAt
            : membership.clearedAt)
        : (membership.hiddenAt ?? membership.clearedAt ?? null);

    total += await prisma.message.count({
      where: {
        chatId: membership.chatId,
        senderId: { not: userId },
        status: { not: MessageStatus.read },
        ...(cutoff ? { createdAt: { gt: cutoff } } : {})
      }
    });
  }

  return total;
}

async function getChatPushContext(chatId: string): Promise<{
  chatType: "direct" | "group";
  chatTitle: string | null;
} | null> {
  const chat = await prisma.chat.findUnique({
    where: { id: chatId },
    select: {
      type: true,
      title: true
    }
  });
  if (!chat) return null;
  return {
    chatType: chat.type === "GROUP" ? "group" : "direct",
    chatTitle: chat.title?.trim() || null
  };
}

function buildChatPushNotification(params: {
  message: ChatMessage;
  senderDisplayName: string;
  chatType: "direct" | "group";
  chatTitle: string | null;
  isMention: boolean;
}): { title: string; body: string } {
  const baseBody = buildPushBody(params.message);
  if (params.chatType === "group") {
    const title = params.chatTitle?.trim() || "Grup sohbeti";
    if (params.isMention) {
      return {
        title,
        body: baseBody === "Yeni mesaj"
          ? `${params.senderDisplayName} senden bahsetti`
          : `${params.senderDisplayName}: ${baseBody}`
      };
    }
    return {
      title,
      body: `${params.senderDisplayName}: ${baseBody}`
    };
  }

  return {
    title: params.senderDisplayName,
    body: baseBody
  };
}

async function getEligibleChatPushRecipients(params: {
  chatId: string;
  senderId: string;
  recipientUserIds: string[];
}): Promise<string[]> {
  const membershipRows = await prismaChatMember.findMany({
    where: {
      chatId: params.chatId,
      userId: { in: params.recipientUserIds },
      muted: false
    },
    select: { userId: true }
  });

  const eligibleUserIds: string[] = [];
  for (const row of membershipRows) {
    if (!(await areUsersBlocked(params.senderId, row.userId))) {
      eligibleUserIds.push(row.userId);
    }
  }

  return eligibleUserIds;
}

async function sendApnsVoipPayload(
  devices: PushDevice[],
  payload: Record<string, unknown>
): Promise<void> {
  if (devices.length === 0 || !hasApnsVoipCredentials() || !env.APNS_BUNDLE_ID) {
    return;
  }

  const bearerToken = createApnsBearerToken();
  if (!bearerToken) return;

  const endpoint = env.APNS_USE_SANDBOX
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const client = http2.connect(endpoint);
  const invalidIds: string[] = [];

  try {
    await Promise.all(
      devices.map(
        (device) =>
          new Promise<void>((resolve) => {
            const request = client.request({
              [http2.constants.HTTP2_HEADER_METHOD]: http2.constants.HTTP2_METHOD_POST,
              [http2.constants.HTTP2_HEADER_PATH]: `/3/device/${device.token}`,
              authorization: `bearer ${bearerToken}`,
              "apns-topic": `${env.APNS_BUNDLE_ID}.voip`,
              "apns-push-type": "voip",
              "apns-priority": "10",
              "content-type": "application/json"
            });

            let statusCode = 0;
            let body = "";

            request.setEncoding("utf8");
            request.on("response", (headers) => {
              statusCode = Number(headers[http2.constants.HTTP2_HEADER_STATUS] ?? 0);
            });
            request.on("data", (chunk) => {
              body += chunk;
            });
            request.on("end", () => {
              if (statusCode < 200 || statusCode >= 300) {
                try {
                  const parsed = body ? (JSON.parse(body) as { reason?: string }) : {};
                  if (
                    parsed.reason === "BadDeviceToken" ||
                    parsed.reason === "Unregistered" ||
                    parsed.reason === "DeviceTokenNotForTopic"
                  ) {
                    invalidIds.push(device.id);
                  }
                  logError("apns voip push failed", {
                    statusCode,
                    reason: parsed.reason ?? body,
                    deviceId: device.id
                  });
                } catch {
                  logError("apns voip push failed", { statusCode, body, deviceId: device.id });
                }
              }
              resolve();
            });
            request.on("error", (error) => {
              logError("apns voip request failed", error);
              resolve();
            });

            request.end(JSON.stringify(payload));
          })
      )
    );
  } finally {
    client.close();
  }

  if (invalidIds.length > 0) {
    await markInactiveDeviceTokens(invalidIds);
  }
}

export function isPushConfigured(): boolean {
  return hasFirebaseCredentials();
}

export async function sendChatMessagePush(params: {
  message: ChatMessage;
  senderDisplayName: string;
  recipientUserIds: string[];
}): Promise<string[]> {
  const eligibleRecipientUserIds = await getEligibleChatPushRecipients({
    chatId: params.message.chatId,
    senderId: params.message.senderId,
    recipientUserIds: params.recipientUserIds
  });

  if (!hasFirebaseCredentials() || eligibleRecipientUserIds.length === 0) {
    logInfo("chat push skipped", {
      reason: !hasFirebaseCredentials() ? "firebase_not_configured" : "no_recipients",
      chatId: params.message.chatId,
      recipientCount: eligibleRecipientUserIds.length
    });
    return [];
  }

  const app = ensureFirebaseApp();
  if (!app) {
    logInfo("chat push skipped", {
      reason: "firebase_app_init_failed",
      chatId: params.message.chatId
    });
    return [];
  }

  const devices = (await findActiveDevices(eligibleRecipientUserIds)).filter(
    (device) => device.tokenKind === "STANDARD"
  );
  if (devices.length === 0) {
    logInfo("chat push skipped", {
      reason: "no_active_standard_devices",
      chatId: params.message.chatId,
      recipientUserIds: eligibleRecipientUserIds
    });
    return [];
  }

  try {
    const chatContext = await getChatPushContext(params.message.chatId);
    const collapseId = buildChatPushCollapseId(params.message.chatId);
    const mentionUserIds = new Set(
      params.message.mentions
        .map((mention) => mention.userId.trim())
        .filter((userId) => userId.length > 0)
    );
    const groupedDevices = new Map<string, PushDevice[]>();
    for (const device of devices) {
      const current = groupedDevices.get(device.userId) ?? [];
      current.push(device);
      groupedDevices.set(device.userId, current);
    }

    let totalSuccessCount = 0;
    let totalFailureCount = 0;
    const allFailures: Array<{
      deviceId: string;
      platform: string;
      tokenKind: string;
      code: string;
      message: string;
    }> = [];
    const invalidTokenIds: string[] = [];
    const deliveredRecipientUserIds = new Set<string>();

    for (const recipientUserId of eligibleRecipientUserIds) {
      const recipientDevices = groupedDevices.get(recipientUserId) ?? [];
      if (recipientDevices.length === 0) continue;

      const unreadTotal = await countUnreadMessagesForUser(recipientUserId);
      const notification = buildChatPushNotification({
        message: params.message,
        senderDisplayName: params.senderDisplayName,
        chatType: chatContext?.chatType ?? "direct",
        chatTitle: chatContext?.chatTitle ?? null,
        isMention: mentionUserIds.has(recipientUserId)
      });
      const response = await getMessaging(app).sendEachForMulticast({
        tokens: recipientDevices.map((device) => device.token),
        notification: {
          title: notification.title,
          body: notification.body
        },
        data: {
          type: "chat_message",
          chatId: params.message.chatId,
          messageId: params.message.id,
          senderId: params.message.senderId,
          senderDisplayName: params.senderDisplayName,
          chatType: chatContext?.chatType ?? "direct",
          chatTitle: chatContext?.chatTitle ?? "",
          body: notification.body,
          isMention: mentionUserIds.has(recipientUserId) ? "true" : "false",
          unreadTotal: unreadTotal.toString()
        },
        android: {
          priority: "high",
          collapseKey: collapseId,
          notification: {
            notificationCount: unreadTotal,
            tag: collapseId
          }
        },
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-collapse-id": collapseId
          },
          payload: {
            aps: {
              sound: "default",
              badge: unreadTotal,
              threadId: collapseId
            }
          }
        }
      });

      if (response.successCount > 0) {
        deliveredRecipientUserIds.add(recipientUserId);
      }
      totalSuccessCount += response.successCount;
      totalFailureCount += response.failureCount;
      invalidTokenIds.push(...getInvalidFcmTokenIds(response, recipientDevices));
      allFailures.push(...summarizeFcmFailures(response, recipientDevices));
    }

    if (invalidTokenIds.length > 0) {
      await markInactiveDeviceTokens([...new Set(invalidTokenIds)]);
    }

    logInfo("chat push sent", {
      chatId: params.message.chatId,
      recipientUserIds: eligibleRecipientUserIds,
      deviceCount: devices.length,
      successCount: totalSuccessCount,
      failureCount: totalFailureCount,
      failures: allFailures
    });
    return [...deliveredRecipientUserIds];
  } catch (error) {
    logError("send chat push failed", error);
    return [];
  }
}

export async function sendIncomingCallPush(params: IncomingCallPushParams): Promise<void> {
  if (params.recipientUserIds.length === 0) {
    return;
  }

  const devices = await findActiveDevices(params.recipientUserIds);
  if (devices.length === 0) return;

  const androidStandardDevices = devices.filter(
    (device) =>
      device.platform === PushPlatform.ANDROID && device.tokenKind === "STANDARD"
  );
  const iosVoipDevices = devices.filter(
    (device) => device.platform === PushPlatform.IOS && device.tokenKind === "VOIP"
  );

  if (androidStandardDevices.length > 0 && hasFirebaseCredentials()) {
    const app = ensureFirebaseApp();
    if (app) {
      try {
        const response = await getMessaging(app).sendEachForMulticast({
          tokens: androidStandardDevices.map((device) => device.token),
          data: {
            type: "incoming_call",
            callId: params.callId,
            callType: params.type,
            callerId: params.callerId,
            callerDisplayName: params.callerDisplayName,
            isVideo: params.type === "video" ? "true" : "false"
          },
          android: {
            priority: "high"
          }
        });

        const invalidTokenIds = getInvalidFcmTokenIds(response, androidStandardDevices);
        if (invalidTokenIds.length > 0) {
          await markInactiveDeviceTokens(invalidTokenIds);
        }
      } catch (error) {
        logError("send incoming call fcm push failed", error);
      }
    }
  }

  if (iosVoipDevices.length > 0) {
    await sendApnsVoipPayload(iosVoipDevices, {
      aps: { "content-available": 1 },
      type: "incoming_call",
      id: params.callId,
      callId: params.callId,
      callerId: params.callerId,
      nameCaller: params.callerDisplayName,
      callerDisplayName: params.callerDisplayName,
      handle: params.callerDisplayName,
      isVideo: params.type === "video"
    });
  }
}

export async function sendCallEndedPush(params: CallEndedPushParams): Promise<void> {
  if (params.recipientUserIds.length === 0) {
    return;
  }

  const devices = await findActiveDevices(params.recipientUserIds);
  if (devices.length === 0) return;

  const androidStandardDevices = devices.filter(
    (device) =>
      device.platform === PushPlatform.ANDROID && device.tokenKind === "STANDARD"
  );
  const iosVoipDevices = devices.filter(
    (device) => device.platform === PushPlatform.IOS && device.tokenKind === "VOIP"
  );

  if (androidStandardDevices.length > 0 && hasFirebaseCredentials()) {
    const app = ensureFirebaseApp();
    if (app) {
      try {
        const response = await getMessaging(app).sendEachForMulticast({
          tokens: androidStandardDevices.map((device) => device.token),
          data: {
            type: "call_ended",
            callId: params.callId,
            reason: params.reason
          },
          android: {
            priority: "high"
          }
        });

        const invalidTokenIds = getInvalidFcmTokenIds(response, androidStandardDevices);
        if (invalidTokenIds.length > 0) {
          await markInactiveDeviceTokens(invalidTokenIds);
        }
      } catch (error) {
        logError("send call ended fcm push failed", error);
      }
    }
  }

  if (iosVoipDevices.length > 0) {
    await sendApnsVoipPayload(iosVoipDevices, {
      aps: { "content-available": 1 },
      type: "call_ended",
      id: params.callId,
      callId: params.callId,
      reason: params.reason
    });
  }
}
