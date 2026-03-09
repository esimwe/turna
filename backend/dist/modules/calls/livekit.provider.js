import { AccessToken, RoomServiceClient } from "livekit-server-sdk";
import { env } from "../../config/env.js";
import { logError } from "../../lib/logger.js";
export class LiveKitCallProvider {
    name = "livekit";
    get roomService() {
        if (!this.isConfigured()) {
            throw new Error("call_provider_not_configured");
        }
        return new RoomServiceClient(env.LIVEKIT_HOST, env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET);
    }
    isConfigured() {
        return Boolean(env.LIVEKIT_HOST &&
            env.LIVEKIT_WS_URL &&
            env.LIVEKIT_API_KEY &&
            env.LIVEKIT_API_SECRET);
    }
    async createSession(input) {
        const roomName = `call_${input.callId}`;
        await this.roomService.createRoom({
            name: roomName,
            maxParticipants: 2,
            emptyTimeout: 60 * 5,
            metadata: JSON.stringify({
                callId: input.callId,
                type: input.type,
                callerId: input.callerId,
                calleeId: input.calleeId
            })
        });
        return {
            provider: this.name,
            sessionId: roomName,
            roomName
        };
    }
    async createParticipantToken(input) {
        if (!this.isConfigured()) {
            throw new Error("call_provider_not_configured");
        }
        const token = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
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
            url: env.LIVEKIT_WS_URL,
            roomName: input.roomName,
            token: await token.toJwt(),
            callId: input.callId,
            type: input.type
        };
    }
    async closeSession(input) {
        if (!this.isConfigured() || !input.roomName) {
            return;
        }
        try {
            await this.roomService.deleteRoom(input.roomName);
        }
        catch (error) {
            logError("livekit room delete failed", error);
        }
    }
    async getParticipantCount(input) {
        if (!this.isConfigured() || !input.roomName) {
            return null;
        }
        try {
            const participants = await this.roomService.listParticipants(input.roomName);
            return participants.length;
        }
        catch (error) {
            logError("livekit participant list failed", error);
            return 0;
        }
    }
}
export const livekitCallProvider = new LiveKitCallProvider();
