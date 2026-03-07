import { PushPlatform } from "@prisma/client";
import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { createSign } from "node:crypto";
import * as http2 from "node:http2";
import { env } from "../config/env.js";
import { logError } from "./logger.js";
import { prisma } from "./prisma.js";
import type { ChatMessage } from "../modules/chat/chat.types.js";
import type { AppCallType } from "../modules/calls/call.types.js";

interface PushDevice {
  id: string;
  token: string;
  platform: PushPlatform;
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
const prismaDeviceToken = (prisma as unknown as { deviceToken: any }).deviceToken;

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
  const trimmedText = message.text.trim();
  if (trimmedText.length > 0) {
    return trimmedText.length > 120 ? `${trimmedText.slice(0, 117)}...` : trimmedText;
  }

  if (message.attachments.length === 0) {
    return "Yeni mesaj";
  }

  if (message.attachments.length > 1) {
    return `${message.attachments.length} ek gonderdi`;
  }

  switch (message.attachments[0].kind) {
    case "image":
      return "Fotograf gonderdi";
    case "video":
      return "Video gonderdi";
    default:
      return "Dosya gonderdi";
  }
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
  const signature = signer.sign(privateKey, "base64url");
  const token = `${unsignedToken}.${signature}`;
  apnsBearerCache = {
    token,
    expiresAtEpochSeconds: now + 50 * 60
  };
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

async function findActiveDevices(userIds: string[]): Promise<PushDevice[]> {
  if (userIds.length === 0) return [];
  return prismaDeviceToken.findMany({
    where: {
      userId: { in: userIds },
      isActive: true
    },
    select: {
      id: true,
      token: true,
      platform: true,
      tokenKind: true
    }
  });
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
}): Promise<void> {
  if (!hasFirebaseCredentials() || params.recipientUserIds.length === 0) {
    return;
  }

  const app = ensureFirebaseApp();
  if (!app) return;

  const devices = (await findActiveDevices(params.recipientUserIds)).filter(
    (device) => device.tokenKind === "STANDARD"
  );
  if (devices.length === 0) return;

  try {
    const response = await getMessaging(app).sendEachForMulticast({
      tokens: devices.map((device) => device.token),
      notification: {
        title: params.senderDisplayName,
        body: buildPushBody(params.message)
      },
      data: {
        type: "chat_message",
        chatId: params.message.chatId,
        senderId: params.message.senderId
      }
    });

    const invalidTokenIds = getInvalidFcmTokenIds(response, devices);
    if (invalidTokenIds.length > 0) {
      await markInactiveDeviceTokens(invalidTokenIds);
    }
  } catch (error) {
    logError("send chat push failed", error);
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
