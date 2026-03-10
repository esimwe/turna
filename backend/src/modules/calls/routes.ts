import { Router, type Request, type Response } from "express";
import { WebhookReceiver } from "livekit-server-sdk";
import { z } from "zod";
import { env } from "../../config/env.js";
import { logError, logInfo } from "../../lib/logger.js";
import { sendCallEndedPush, sendIncomingCallPush } from "../../lib/push.js";
import { requireAuth, requireCallingAccess } from "../../middleware/auth.js";
import { emitUserEvent } from "../chat/chat.realtime.js";
import { buildAvatarUrlFromOrigin, getRequestOrigin } from "../profile/avatar-url.js";
import { callService } from "./call.service.js";
import {
  cancelCallReconnectGrace,
  cancelCallTimeout,
  scheduleCallReconnectGrace,
  scheduleCallTimeout
} from "./call.timeout.js";
import type { CallHistoryItem, CallRecord, CallUser } from "./call.types.js";

export const callRouter = Router();
const liveKitWebhookReceiver =
  env.LIVEKIT_API_KEY && env.LIVEKIT_API_SECRET
    ? new WebhookReceiver(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET)
    : null;

const startCallSchema = z.object({
  calleeId: z.string().trim().min(1),
  type: z.enum(["audio", "video"])
});

const listCallsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50)
});

function getRouteParam(req: Request, key: string): string {
  const value = req.params[key];
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

function withAvatarUrl(origin: string, user: CallUser) {
  return {
    id: user.id,
    displayName: user.displayName,
    avatarUrl: user.avatarKey
      ? buildAvatarUrlFromOrigin(origin, user.id, new Date(user.updatedAt))
      : null
  };
}

function serializeCallForViewer(origin: string, call: CallRecord, viewerId: string) {
  const outgoing = call.callerId === viewerId;
  const peer = outgoing ? call.callee : call.caller;
  return {
    id: call.id,
    callerId: call.callerId,
    calleeId: call.calleeId,
    type: call.type,
    status: call.status,
    provider: call.provider,
    roomName: call.roomName,
    createdAt: call.createdAt,
    acceptedAt: call.acceptedAt,
    endedAt: call.endedAt,
    direction: outgoing ? "outgoing" : "incoming",
    peer: withAvatarUrl(origin, peer),
    caller: withAvatarUrl(origin, call.caller),
    callee: withAvatarUrl(origin, call.callee)
  };
}

function serializeHistoryItem(origin: string, item: CallHistoryItem) {
  return {
    id: item.id,
    type: item.type,
    status: item.status,
    direction: item.direction,
    createdAt: item.createdAt,
    acceptedAt: item.acceptedAt,
    endedAt: item.endedAt,
    durationSeconds: item.durationSeconds,
    peer: withAvatarUrl(origin, item.peer)
  };
}

async function emitResolvedCall(
  origin: string,
  call: CallRecord,
  eventName: "call:missed" | "call:declined" | "call:ended",
  pushReason = call.status
): Promise<void> {
  emitUserEvent([call.callerId], eventName, {
    call: serializeCallForViewer(origin, call, call.callerId)
  });
  emitUserEvent([call.calleeId], eventName, {
    call: serializeCallForViewer(origin, call, call.calleeId)
  });
  try {
    await sendCallEndedPush({
      callId: call.id,
      reason: pushReason,
      recipientUserIds: [call.callerId, call.calleeId]
    });
  } catch (error) {
    logError("call ended push failed", error);
  }
}

function getWebhookAuthToken(req: Request): string | undefined {
  const rawHeader = req.get("authorization") ?? req.get("authorize") ?? undefined;
  if (!rawHeader) return undefined;
  return rawHeader.startsWith("Bearer ") ? rawHeader.slice(7) : rawHeader;
}

function respondCallError(res: Response, error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  switch (error.message) {
    case "call_provider_not_configured":
      res.status(503).json({ error: "call_provider_not_configured" });
      return true;
    case "invalid_call_target":
      res.status(400).json({ error: "invalid_call_target" });
      return true;
    case "user_not_found":
      res.status(404).json({ error: "user_not_found" });
      return true;
    case "call_conflict":
      res.status(409).json({ error: "call_conflict" });
      return true;
    case "call_blocked":
      res.status(403).json({ error: "call_blocked" });
      return true;
    case "call_not_found":
      res.status(404).json({ error: "call_not_found" });
      return true;
    case "forbidden_call_access":
      res.status(403).json({ error: "forbidden_call_access" });
      return true;
    case "call_not_ringing":
      res.status(409).json({ error: "call_not_ringing" });
      return true;
    case "call_room_missing":
      res.status(500).json({ error: "call_room_missing" });
      return true;
    case "call_not_active":
      res.status(409).json({ error: "call_not_active" });
      return true;
    default:
      return false;
  }
}

callRouter.get("/", requireAuth, async (req, res) => {
  const origin = getRequestOrigin(req);
  const parsed = listCallsQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const calls = await callService.listCalls(req.authUserId!, parsed.data.limit);
  res.json({
    data: calls.map((item) => serializeHistoryItem(origin, item))
  });
});

callRouter.post("/livekit/webhook", async (req, res) => {
  if (!liveKitWebhookReceiver) {
    res.status(503).json({ error: "call_provider_not_configured" });
    return;
  }

  const origin = getRequestOrigin(req);
  const rawBody =
    typeof req.body === "string" ? req.body : JSON.stringify(req.body ?? {});

  try {
    const event = await liveKitWebhookReceiver.receive(rawBody, getWebhookAuthToken(req));
    const roomName = event.room?.name?.trim() ?? "";

    if (!roomName) {
      res.status(204).end();
      return;
    }

    switch (event.event) {
      case "participant_joined": {
        const call = await callService.findActiveCallByRoomName(roomName);
        if (call) {
          cancelCallReconnectGrace(call.id);
          logInfo("call reconnect grace cleared", {
            callId: call.id,
            event: event.event,
            participantIdentity: event.participant?.identity || null,
            roomName
          });
        }
        break;
      }
      case "participant_left":
      case "participant_connection_aborted": {
        const call = await callService.findActiveCallByRoomName(roomName);
        if (call?.status === "accepted") {
          scheduleCallReconnectGrace(call.id, async () => {
            const endedCall = await callService.endAcceptedCallByRoomName({
              roomName,
              reason: "reconnect_grace_expired",
              minParticipantCount: 2
            });
            if (!endedCall) return;
            await emitResolvedCall(origin, endedCall, "call:ended", "ended");
          });
          logInfo("call reconnect grace scheduled", {
            callId: call.id,
            event: event.event,
            participantIdentity: event.participant?.identity || null,
            roomName
          });
        }
        break;
      }
      case "room_finished": {
        const call = await callService.endAcceptedCallByRoomName({
          roomName,
          reason: "room_finished_webhook"
        });
        if (call) {
          await emitResolvedCall(origin, call, "call:ended", "ended");
          logInfo("call ended from room_finished webhook", { callId: call.id, roomName });
        }
        break;
      }
      default:
        break;
    }

    res.status(204).end();
  } catch (error) {
    logError("livekit webhook failed", error);
    const message = error instanceof Error ? error.message : "";
    const status = /authorization|checksum|jwt/i.test(message) ? 401 : 500;
    res.status(status).json({ error: "failed_to_process_livekit_webhook" });
  }
});

callRouter.post("/reconcile", requireAuth, async (req, res) => {
  const origin = getRequestOrigin(req);
  try {
    const calls = await callService.reconcileActiveCallsForUsers([req.authUserId!]);

    for (const call of calls) {
      const eventName = call.status === "missed" ? "call:missed" : "call:ended";
      await emitResolvedCall(origin, call, eventName, call.status);
    }

    res.json({
      data: {
        calls: calls.map((call) => serializeCallForViewer(origin, call, req.authUserId!))
      }
    });
  } catch (error) {
    logError("call reconcile failed", error);
    res.status(500).json({ error: "failed_to_reconcile_calls" });
  }
});

callRouter.post("/start", requireAuth, requireCallingAccess, async (req, res) => {
  const origin = getRequestOrigin(req);
  const parsed = startCallSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const callerId = req.authUserId!;
    const call = await callService.startCall({
      callerId,
      calleeId: parsed.data.calleeId,
      type: parsed.data.type
    });

    const callerPayload = serializeCallForViewer(origin, call, call.callerId);
    const calleePayload = serializeCallForViewer(origin, call, call.calleeId);

    res.status(201).json({ data: { call: callerPayload } });

    emitUserEvent([call.callerId], "call:ringing", { call: callerPayload });
    emitUserEvent([call.calleeId], "call:incoming", { call: calleePayload });

    scheduleCallTimeout(call.id, async () => {
      try {
        const missedCall = await callService.timeoutCall(call.id);
        await emitResolvedCall(origin, missedCall, "call:missed", "missed");
      } catch (error) {
        if (error instanceof Error && error.message === "call_not_ringing") {
          return;
        }
        logError("call timeout failed", error);
      }
    });

    void sendIncomingCallPush({
      callId: call.id,
      type: call.type,
      callerId: call.callerId,
      callerDisplayName: call.caller.displayName,
      recipientUserIds: [call.calleeId]
    }).catch((error: unknown) => {
      logError("incoming call push failed", error);
    });
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call start failed", error);
    res.status(500).json({ error: "failed_to_start_call" });
  }
});

callRouter.post("/:callId/accept", requireAuth, requireCallingAccess, async (req, res) => {
  const origin = getRequestOrigin(req);
  try {
    cancelCallTimeout(getRouteParam(req, "callId"));
    const result = await callService.acceptCall({
      callId: getRouteParam(req, "callId"),
      userId: req.authUserId!
    });

    const callerPayload = serializeCallForViewer(origin, result.call, result.call.callerId);
    const calleePayload = serializeCallForViewer(origin, result.call, result.call.calleeId);

    res.json({
      data: {
        call: calleePayload,
        connect: result.joinByUserId[result.call.calleeId]
      }
    });

    emitUserEvent([result.call.callerId], "call:accepted", {
      call: callerPayload,
      connect: result.joinByUserId[result.call.callerId]
    });
    emitUserEvent([result.call.calleeId], "call:accepted", {
      call: calleePayload,
      connect: result.joinByUserId[result.call.calleeId]
    });
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call accept failed", error);
    res.status(500).json({ error: "failed_to_accept_call" });
  }
});

callRouter.post("/:callId/decline", requireAuth, async (req, res) => {
  const origin = getRequestOrigin(req);
  try {
    cancelCallTimeout(getRouteParam(req, "callId"));
    const call = await callService.declineCall({
      callId: getRouteParam(req, "callId"),
      userId: req.authUserId!
    });

    res.json({
      data: {
        call: serializeCallForViewer(origin, call, req.authUserId!)
      }
    });

    void emitResolvedCall(origin, call, "call:declined", "declined").catch(
      (error: unknown) => {
        logError("call decline side effects failed", error);
      }
    );
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call decline failed", error);
    res.status(500).json({ error: "failed_to_decline_call" });
  }
});

callRouter.post("/:callId/end", requireAuth, async (req, res) => {
  const origin = getRequestOrigin(req);
  try {
    cancelCallTimeout(getRouteParam(req, "callId"));
    const call = await callService.endCall({
      callId: getRouteParam(req, "callId"),
      userId: req.authUserId!
    });

    res.json({
      data: {
        call: serializeCallForViewer(origin, call, req.authUserId!)
      }
    });

    void emitResolvedCall(origin, call, "call:ended", call.status).catch(
      (error: unknown) => {
        logError("call end side effects failed", error);
      }
    );
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call end failed", error);
    res.status(500).json({ error: "failed_to_end_call" });
  }
});
