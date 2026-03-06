import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { env } from "../config/env.js";
import { logError } from "./logger.js";
import { prisma } from "./prisma.js";
import type { ChatMessage } from "../modules/chat/chat.types.js";

function hasFirebaseCredentials(): boolean {
  return Boolean(
    env.FIREBASE_SERVICE_ACCOUNT_JSON ||
      (env.FIREBASE_PROJECT_ID && env.FIREBASE_CLIENT_EMAIL && env.FIREBASE_PRIVATE_KEY)
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

  const devices = await prisma.deviceToken.findMany({
    where: {
      userId: { in: params.recipientUserIds },
      isActive: true
    },
    select: {
      id: true,
      token: true
    }
  });
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

    const invalidTokenIds = response.responses
      .map((result, index) => ({
        ok: result.success,
        id: devices[index]?.id,
        code: result.error?.code ?? ""
      }))
      .filter((result) =>
        !result.ok &&
        result.id &&
        (result.code === "messaging/registration-token-not-registered" ||
            result.code === "messaging/invalid-registration-token")
      )
      .map((result) => result.id!);

    if (invalidTokenIds.length > 0) {
      await prisma.deviceToken.updateMany({
        where: { id: { in: invalidTokenIds } },
        data: { isActive: false }
      });
    }
  } catch (error) {
    logError("send chat push failed", error);
  }
}
