import { Router, type Request, type Response } from "express";
import { z } from "zod";
import { logError } from "../../lib/logger.js";
import { sendCallEndedPush, sendIncomingCallPush } from "../../lib/push.js";
import { requireAuth } from "../../middleware/auth.js";
import { emitUserEvent } from "../chat/chat.realtime.js";
import { buildAvatarUrl } from "../profile/avatar-url.js";
import { callService } from "./call.service.js";
import { cancelCallTimeout, scheduleCallTimeout } from "./call.timeout.js";
import type { CallHistoryItem, CallRecord, CallUser } from "./call.types.js";

export const callRouter = Router();

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

function withAvatarUrl(req: Request, user: CallUser) {
  return {
    id: user.id,
    displayName: user.displayName,
    avatarUrl: user.avatarKey ? buildAvatarUrl(req, user.id, new Date(user.updatedAt)) : null
  };
}

function serializeCallForViewer(req: Request, call: CallRecord, viewerId: string) {
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
    peer: withAvatarUrl(req, peer),
    caller: withAvatarUrl(req, call.caller),
    callee: withAvatarUrl(req, call.callee)
  };
}

function serializeHistoryItem(req: Request, item: CallHistoryItem) {
  return {
    id: item.id,
    type: item.type,
    status: item.status,
    direction: item.direction,
    createdAt: item.createdAt,
    acceptedAt: item.acceptedAt,
    endedAt: item.endedAt,
    durationSeconds: item.durationSeconds,
    peer: withAvatarUrl(req, item.peer)
  };
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
  const parsed = listCallsQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  const calls = await callService.listCalls(req.authUserId!, parsed.data.limit);
  res.json({
    data: calls.map((item) => serializeHistoryItem(req, item))
  });
});

callRouter.post("/reconcile", requireAuth, async (req, res) => {
  try {
    const calls = await callService.reconcileActiveCallsForUsers([req.authUserId!]);

    for (const call of calls) {
      const callerPayload = serializeCallForViewer(req, call, call.callerId);
      const calleePayload = serializeCallForViewer(req, call, call.calleeId);
      const eventName = call.status === "missed" ? "call:missed" : "call:ended";

      emitUserEvent([call.callerId], eventName, { call: callerPayload });
      emitUserEvent([call.calleeId], eventName, { call: calleePayload });

      await sendCallEndedPush({
        callId: call.id,
        reason: call.status,
        recipientUserIds: [call.callerId, call.calleeId]
      });
    }

    res.json({
      data: {
        calls: calls.map((call) => serializeCallForViewer(req, call, req.authUserId!))
      }
    });
  } catch (error) {
    logError("call reconcile failed", error);
    res.status(500).json({ error: "failed_to_reconcile_calls" });
  }
});

callRouter.post("/start", requireAuth, async (req, res) => {
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

    const callerPayload = serializeCallForViewer(req, call, call.callerId);
    const calleePayload = serializeCallForViewer(req, call, call.calleeId);

    emitUserEvent([call.callerId], "call:ringing", { call: callerPayload });
    emitUserEvent([call.calleeId], "call:incoming", { call: calleePayload });

    await sendIncomingCallPush({
      callId: call.id,
      type: call.type,
      callerId: call.callerId,
      callerDisplayName: call.caller.displayName,
      recipientUserIds: [call.calleeId]
    });

    scheduleCallTimeout(call.id, async () => {
      try {
        const missedCall = await callService.timeoutCall(call.id);
        emitUserEvent([missedCall.callerId], "call:missed", {
          call: serializeCallForViewer(req, missedCall, missedCall.callerId)
        });
        emitUserEvent([missedCall.calleeId], "call:missed", {
          call: serializeCallForViewer(req, missedCall, missedCall.calleeId)
        });
        await sendCallEndedPush({
          callId: missedCall.id,
          reason: "missed",
          recipientUserIds: [missedCall.callerId, missedCall.calleeId]
        });
      } catch (error) {
        if (error instanceof Error && error.message === "call_not_ringing") {
          return;
        }
        logError("call timeout failed", error);
      }
    });

    res.status(201).json({ data: { call: callerPayload } });
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call start failed", error);
    res.status(500).json({ error: "failed_to_start_call" });
  }
});

callRouter.post("/:callId/accept", requireAuth, async (req, res) => {
  try {
    cancelCallTimeout(getRouteParam(req, "callId"));
    const result = await callService.acceptCall({
      callId: getRouteParam(req, "callId"),
      userId: req.authUserId!
    });

    const callerPayload = serializeCallForViewer(req, result.call, result.call.callerId);
    const calleePayload = serializeCallForViewer(req, result.call, result.call.calleeId);

    emitUserEvent([result.call.callerId], "call:accepted", {
      call: callerPayload,
      connect: result.joinByUserId[result.call.callerId]
    });
    emitUserEvent([result.call.calleeId], "call:accepted", {
      call: calleePayload,
      connect: result.joinByUserId[result.call.calleeId]
    });

    res.json({
      data: {
        call: calleePayload,
        connect: result.joinByUserId[result.call.calleeId]
      }
    });
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call accept failed", error);
    res.status(500).json({ error: "failed_to_accept_call" });
  }
});

callRouter.post("/:callId/decline", requireAuth, async (req, res) => {
  try {
    cancelCallTimeout(getRouteParam(req, "callId"));
    const call = await callService.declineCall({
      callId: getRouteParam(req, "callId"),
      userId: req.authUserId!
    });

    emitUserEvent([call.callerId], "call:declined", {
      call: serializeCallForViewer(req, call, call.callerId)
    });
    emitUserEvent([call.calleeId], "call:declined", {
      call: serializeCallForViewer(req, call, call.calleeId)
    });
    await sendCallEndedPush({
      callId: call.id,
      reason: "declined",
      recipientUserIds: [call.callerId, call.calleeId]
    });

    res.json({
      data: {
        call: serializeCallForViewer(req, call, req.authUserId!)
      }
    });
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call decline failed", error);
    res.status(500).json({ error: "failed_to_decline_call" });
  }
});

callRouter.post("/:callId/end", requireAuth, async (req, res) => {
  try {
    cancelCallTimeout(getRouteParam(req, "callId"));
    const call = await callService.endCall({
      callId: getRouteParam(req, "callId"),
      userId: req.authUserId!
    });

    emitUserEvent([call.callerId], "call:ended", {
      call: serializeCallForViewer(req, call, call.callerId)
    });
    emitUserEvent([call.calleeId], "call:ended", {
      call: serializeCallForViewer(req, call, call.calleeId)
    });
    await sendCallEndedPush({
      callId: call.id,
      reason: call.status,
      recipientUserIds: [call.callerId, call.calleeId]
    });

    res.json({
      data: {
        call: serializeCallForViewer(req, call, req.authUserId!)
      }
    });
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call end failed", error);
    res.status(500).json({ error: "failed_to_end_call" });
  }
});
