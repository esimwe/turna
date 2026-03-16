import { AccessToken, RoomServiceClient } from "livekit-server-sdk";
import { env } from "../../config/env.js";
import { logError } from "../../lib/logger.js";
import type {
  CallProvider,
  CloseCallSessionInput,
  CreateCallParticipantTokenInput,
  CreateCallSessionInput,
  CreateCallSessionResult
} from "./call.provider.js";
import type { CallJoinPayload } from "./call.types.js";

export class LiveKitCallProvider implements CallProvider {
  readonly name = "livekit" as const;

  private get roomService(): RoomServiceClient {
    if (!this.isConfigured()) {
      throw new Error("call_provider_not_configured");
    }

    return new RoomServiceClient(
      env.LIVEKIT_HOST!,
      env.LIVEKIT_API_KEY!,
      env.LIVEKIT_API_SECRET!
    );
  }

  isConfigured(): boolean {
    return Boolean(
      env.LIVEKIT_HOST &&
        env.LIVEKIT_WS_URL &&
        env.LIVEKIT_API_KEY &&
        env.LIVEKIT_API_SECRET
    );
  }

  async createRoom(input: {
    roomName: string;
    metadata?: Record<string, unknown>;
    maxParticipants?: number;
    emptyTimeoutSeconds?: number;
  }): Promise<CreateCallSessionResult> {
    await this.roomService.createRoom({
      name: input.roomName,
      maxParticipants: input.maxParticipants ?? 2,
      emptyTimeout: input.emptyTimeoutSeconds ?? 60 * 5,
      metadata: JSON.stringify(input.metadata ?? {})
    });

    return {
      provider: this.name,
      sessionId: input.roomName,
      roomName: input.roomName
    };
  }

  async createSession(input: CreateCallSessionInput): Promise<CreateCallSessionResult> {
    const roomName = `call_${input.callId}`;
    return this.createRoom({
      roomName,
      maxParticipants: 2,
      emptyTimeoutSeconds: 60 * 5,
      metadata: {
        callId: input.callId,
        type: input.type,
        callerId: input.callerId,
        calleeId: input.calleeId
      }
    });
  }

  async createParticipantToken(input: CreateCallParticipantTokenInput): Promise<CallJoinPayload> {
    if (!this.isConfigured()) {
      throw new Error("call_provider_not_configured");
    }

    const token = new AccessToken(env.LIVEKIT_API_KEY!, env.LIVEKIT_API_SECRET!, {
      identity: input.userId,
      name: input.participantName
    });

    token.addGrant({
      roomJoin: true,
      room: input.roomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true
    });

    return {
      provider: this.name,
      url: env.LIVEKIT_WS_URL!,
      roomName: input.roomName,
      token: await token.toJwt(),
      callId: input.callId,
      type: input.type
    };
  }

  async closeSession(input: CloseCallSessionInput): Promise<void> {
    if (!this.isConfigured() || !input.roomName) {
      return;
    }

    try {
      await this.roomService.deleteRoom(input.roomName);
    } catch (error) {
      logError("livekit room delete failed", error);
    }
  }

  async getParticipantCount(input: CloseCallSessionInput): Promise<number | null> {
    if (!this.isConfigured() || !input.roomName) {
      return null;
    }

    try {
      const participants = await this.roomService.listParticipants(input.roomName);
      return participants.length;
    } catch (error) {
      logError("livekit participant list failed", error);
      return 0;
    }
  }
}

export const livekitCallProvider = new LiveKitCallProvider();
