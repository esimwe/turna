import { Router, type Request, type Response } from "express";
import { randomUUID } from "node:crypto";
import { WebhookReceiver } from "livekit-server-sdk";
import { z } from "zod";
import { env } from "../../config/env.js";
import { logError, logInfo } from "../../lib/logger.js";
import { redis } from "../../lib/redis.js";
import { sendCallEndedPush, sendIncomingCallPush } from "../../lib/push.js";
import { requireAuth, requireCallingAccess } from "../../middleware/auth.js";
import { emitUserEvent } from "../chat/chat.realtime.js";
import { chatService } from "../chat/chat.service.js";
import { buildAvatarUrlFromOrigin, getRequestOrigin } from "../profile/avatar-url.js";
import { callService } from "./call.service.js";
import {
  cancelCallReconnectGrace,
  cancelCallTimeout,
  scheduleCallReconnectGrace,
  scheduleCallTimeout
} from "./call.timeout.js";
import type { CallHistoryItem, CallRecord, CallUser } from "./call.types.js";
import { livekitCallProvider } from "./livekit.provider.js";

export const callRouter = Router();
const liveKitWebhookReceiver =
  env.LIVEKIT_API_KEY && env.LIVEKIT_API_SECRET
    ? new WebhookReceiver(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET)
    : null;

const startCallSchema = z.object({
  calleeId: z.string().trim().min(1),
  type: z.enum(["audio", "video"])
});

const videoUpgradeActionSchema = z.object({
  requestId: z.string().trim().min(1)
});

const listCallsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50)
});

const groupChatCallParamSchema = z.object({
  chatId: z.string().trim().min(1).max(255)
});

const joinGroupCallSchema = z.object({
  type: z.enum(["audio", "video"]).optional()
});

const leaveGroupCallSchema = z.object({
  roomName: z.string().trim().min(1).max(255)
});

const GROUP_CALL_TTL_SECONDS = 60 * 60 * 6;
const GROUP_CALL_EMPTY_TIMEOUT_SECONDS = 60 * 10;
const GROUP_CALL_MAX_PARTICIPANTS = 64;

interface GroupCallStateRecord {
  chatId: string;
  roomName: string;
  sessionId: string;
  type: "audio" | "video";
  startedByUserId: string;
  startedByDisplayName: string | null;
  startedAt: string;
}

function groupCallRedisKey(chatId: string): string {
  return `turna:group-call:${chatId}`;
}

function canUseGroupCallState(): boolean {
  return redis.status === "ready";
}

async function loadGroupCallState(chatId: string): Promise<GroupCallStateRecord | null> {
  if (!canUseGroupCallState()) return null;
  try {
    const raw = await redis.get(groupCallRedisKey(chatId));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<GroupCallStateRecord>;
    if (
      !parsed.chatId ||
      !parsed.roomName ||
      !parsed.sessionId ||
      !parsed.type ||
      !parsed.startedByUserId ||
      !parsed.startedAt
    ) {
      return null;
    }
    return {
      chatId: parsed.chatId,
      roomName: parsed.roomName,
      sessionId: parsed.sessionId,
      type: parsed.type,
      startedByUserId: parsed.startedByUserId,
      startedByDisplayName: parsed.startedByDisplayName ?? null,
      startedAt: parsed.startedAt
    };
  } catch (error) {
    logError("group call state read failed", error);
    return null;
  }
}

async function saveGroupCallState(state: GroupCallStateRecord): Promise<void> {
  if (!canUseGroupCallState()) {
    throw new Error("group_call_state_unavailable");
  }
  await redis.set(
    groupCallRedisKey(state.chatId),
    JSON.stringify(state),
    "EX",
    GROUP_CALL_TTL_SECONDS
  );
}

async function clearGroupCallState(chatId: string): Promise<void> {
  if (!canUseGroupCallState()) return;
  await redis.del(groupCallRedisKey(chatId));
}

function buildGroupCallRoomName(chatId: string): string {
  return `group_call_${chatId.replace(/[^a-zA-Z0-9]/g, "")}_${randomUUID().slice(0, 8)}`;
}

function policyAllows(policy: string, role: string | null | undefined): boolean {
  const normalizedRole = (role ?? "").trim().toUpperCase();
  if (normalizedRole == "OWNER") return true;
  switch (policy.trim().toUpperCase()) {
    case "EVERYONE":
      return true;
    case "EDITOR_ONLY":
      return normalizedRole == "ADMIN" || normalizedRole == "EDITOR";
    case "ADMIN_ONLY":
      return normalizedRole == "ADMIN";
    default:
      return false;
  }
}

async function syncGroupCallState(
  chatId: string
): Promise<{ state: GroupCallStateRecord | null; participantCount: number }> {
  const current = await loadGroupCallState(chatId);
  if (!current) {
    return { state: null, participantCount: 0 };
  }

  const participantCount =
    (await livekitCallProvider.getParticipantCount({
      callId: current.roomName,
      roomName: current.roomName,
      sessionId: current.sessionId
    })) ?? 0;

  if (participantCount <= 0) {
    await clearGroupCallState(chatId);
    return { state: null, participantCount: 0 };
  }

  await saveGroupCallState(current);
  return { state: current, participantCount };
}

async function emitGroupCallStateUpdate(origin: string, chatId: string): Promise<void> {
  const participantIds = await chatService.getChatParticipantIds(chatId);
  const { state, participantCount } = await syncGroupCallState(chatId);
  emitUserEvent(participantIds, "chat:group-call:update", {
    chatId,
    state: state
      ? {
          chatId,
          roomName: state.roomName,
          type: state.type,
          startedByUserId: state.startedByUserId,
          startedByDisplayName: state.startedByDisplayName,
          startedAt: state.startedAt,
          participantCount
        }
      : null,
    origin
  });
}

async function serializeGroupCallStateForViewer(params: {
  chatId: string;
  userId: string;
}): Promise<{
  chatId: string;
  roomName: string;
  type: "audio" | "video";
  startedByUserId: string;
  startedByDisplayName: string | null;
  startedAt: string;
  participantCount: number;
  canStart: boolean;
} | null> {
  const detail = await chatService.getGroupDetail(params.chatId, params.userId);
  if (!detail || detail.chatType !== "group") {
    throw new Error("group_not_found");
  }

  const { state, participantCount } = await syncGroupCallState(params.chatId);
  if (!state) return null;

  return {
    chatId: state.chatId,
    roomName: state.roomName,
    type: state.type,
    startedByUserId: state.startedByUserId,
    startedByDisplayName: state.startedByDisplayName,
    startedAt: state.startedAt,
    participantCount,
    canStart: policyAllows(detail.whoCanStartCalls, detail.myRole)
  };
}

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

function emitVideoUpgradeEvent(
  origin: string,
  call: CallRecord,
  eventName:
    | "call:video-upgrade:requested"
    | "call:video-upgrade:accepted"
    | "call:video-upgrade:declined",
  payload: Record<string, unknown>
): void {
  emitUserEvent([call.callerId], eventName, {
    call: serializeCallForViewer(origin, call, call.callerId),
    ...payload
  });
  emitUserEvent([call.calleeId], eventName, {
    call: serializeCallForViewer(origin, call, call.calleeId),
    ...payload
  });
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
    case "call_not_accepted":
      res.status(409).json({ error: "call_not_accepted" });
      return true;
    case "call_already_video":
      res.status(409).json({ error: "call_already_video" });
      return true;
    case "video_upgrade_request_conflict":
      res.status(409).json({ error: "video_upgrade_request_conflict" });
      return true;
    case "call_no_pending_video_upgrade":
      res.status(409).json({ error: "call_no_pending_video_upgrade" });
      return true;
    case "video_upgrade_invalid_request":
      res.status(409).json({ error: "video_upgrade_invalid_request" });
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
        const groupStates = await redis.keys("turna:group-call:*").catch(() => []);
        if (groupStates.length > 0) {
          for (const key of groupStates) {
            const raw = await redis.get(key).catch(() => null);
            if (!raw) continue;
            const state = JSON.parse(raw) as GroupCallStateRecord;
            if (state.roomName !== roomName) continue;
            await emitGroupCallStateUpdate("participant_joined", state.chatId);
            res.status(204).end();
            return;
          }
        }
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
        const groupStates = await redis.keys("turna:group-call:*").catch(() => []);
        if (groupStates.length > 0) {
          for (const key of groupStates) {
            const raw = await redis.get(key).catch(() => null);
            if (!raw) continue;
            const state = JSON.parse(raw) as GroupCallStateRecord;
            if (state.roomName !== roomName) continue;
            await emitGroupCallStateUpdate("participant_left", state.chatId);
            res.status(204).end();
            return;
          }
        }
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
        const groupStates = await redis.keys("turna:group-call:*").catch(() => []);
        if (groupStates.length > 0) {
          for (const key of groupStates) {
            const raw = await redis.get(key).catch(() => null);
            if (!raw) continue;
            const state = JSON.parse(raw) as GroupCallStateRecord;
            if (state.roomName !== roomName) continue;
            await clearGroupCallState(state.chatId);
            await emitGroupCallStateUpdate("room_finished", state.chatId);
            res.status(204).end();
            return;
          }
        }
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

callRouter.get("/group-chat/:chatId", requireAuth, async (req, res) => {
  const parsed = groupChatCallParamSchema.safeParse(req.params);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const detail = await chatService.getGroupDetail(parsed.data.chatId, req.authUserId!);
    if (!detail || detail.chatType !== "group") {
      res.status(404).json({ error: "group_not_found" });
      return;
    }

    const state = await serializeGroupCallStateForViewer({
      chatId: parsed.data.chatId,
      userId: req.authUserId!
    });

    res.json({
      data: {
        state,
        canStart: policyAllows(detail.whoCanStartCalls, detail.myRole)
      }
    });
  } catch (error) {
    if (error instanceof Error) {
      if (error.message === "forbidden_chat_access") {
        res.status(403).json({ error: error.message });
        return;
      }
      if (error.message === "group_not_found") {
        res.status(404).json({ error: error.message });
        return;
      }
    }
    logError("group call state failed", error);
    res.status(500).json({ error: "failed_to_load_group_call_state" });
  }
});

callRouter.post(
  "/group-chat/:chatId/join",
  requireAuth,
  requireCallingAccess,
  async (req, res) => {
    const parsedParams = groupChatCallParamSchema.safeParse(req.params);
    const parsedBody = joinGroupCallSchema.safeParse(req.body ?? {});
    if (!parsedParams.success) {
      res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
      return;
    }
    if (!parsedBody.success) {
      res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
      return;
    }
    if (!canUseGroupCallState()) {
      res.status(503).json({ error: "group_call_state_unavailable" });
      return;
    }
    if (!livekitCallProvider.isConfigured()) {
      res.status(503).json({ error: "call_provider_not_configured" });
      return;
    }

    try {
      const chatId = parsedParams.data.chatId;
      const userId = req.authUserId!;
      const detail = await chatService.getGroupDetail(chatId, userId);
      if (!detail || detail.chatType !== "group") {
        res.status(404).json({ error: "group_not_found" });
        return;
      }

      let activeState = (await syncGroupCallState(chatId)).state;
      if (!activeState) {
        const requestedType = parsedBody.data.type;
        if (!requestedType) {
          res.status(400).json({ error: "group_call_type_required" });
          return;
        }
        if (!policyAllows(detail.whoCanStartCalls, detail.myRole)) {
          res.status(403).json({ error: "group_call_not_allowed" });
          return;
        }

        const startedByDisplayName = await chatService.getUserDisplayName(userId);
        const createdRoom = await livekitCallProvider.createRoom({
          roomName: buildGroupCallRoomName(chatId),
          maxParticipants: GROUP_CALL_MAX_PARTICIPANTS,
          emptyTimeoutSeconds: GROUP_CALL_EMPTY_TIMEOUT_SECONDS,
          metadata: {
            scope: "group_chat",
            chatId,
            type: requestedType,
            startedByUserId: userId,
            startedByDisplayName
          }
        });

        activeState = {
          chatId,
          roomName: createdRoom.roomName,
          sessionId: createdRoom.sessionId,
          type: requestedType,
          startedByUserId: userId,
          startedByDisplayName,
          startedAt: new Date().toISOString()
        };
        await saveGroupCallState(activeState);
      }

      const connect = await livekitCallProvider.createParticipantToken({
        callId: activeState.roomName,
        roomName: activeState.roomName,
        type: activeState.type,
        userId,
        participantName: await chatService.getUserDisplayName(userId)
      });

      await emitGroupCallStateUpdate("join", chatId);
      const state = await serializeGroupCallStateForViewer({ chatId, userId });
      res.json({
        data: {
          state,
          connect
        }
      });
    } catch (error) {
      if (error instanceof Error) {
        if (error.message === "forbidden_chat_access") {
          res.status(403).json({ error: error.message });
          return;
        }
        if (error.message === "group_not_found") {
          res.status(404).json({ error: error.message });
          return;
        }
      }
      logError("group call join failed", error);
      res.status(500).json({ error: "failed_to_join_group_call" });
    }
  }
);

callRouter.post("/group-chat/:chatId/leave", requireAuth, async (req, res) => {
  const parsedParams = groupChatCallParamSchema.safeParse(req.params);
  const parsedBody = leaveGroupCallSchema.safeParse(req.body);
  if (!parsedParams.success) {
    res.status(400).json({ error: "validation_error", details: parsedParams.error.flatten() });
    return;
  }
  if (!parsedBody.success) {
    res.status(400).json({ error: "validation_error", details: parsedBody.error.flatten() });
    return;
  }

  try {
    const detail = await chatService.getGroupDetail(parsedParams.data.chatId, req.authUserId!);
    if (!detail || detail.chatType !== "group") {
      res.status(404).json({ error: "group_not_found" });
      return;
    }

    const active = await loadGroupCallState(parsedParams.data.chatId);
    if (!active || active.roomName !== parsedBody.data.roomName) {
      res.json({ data: { state: null } });
      return;
    }

    const participantCount =
      (await livekitCallProvider.getParticipantCount({
        callId: active.roomName,
        roomName: active.roomName,
        sessionId: active.sessionId
      })) ?? 0;

    if (participantCount <= 0) {
      await clearGroupCallState(parsedParams.data.chatId);
    } else {
      await saveGroupCallState(active);
    }

    await emitGroupCallStateUpdate("leave", parsedParams.data.chatId);
    const state = await serializeGroupCallStateForViewer({
      chatId: parsedParams.data.chatId,
      userId: req.authUserId!
    });
    res.json({ data: { state } });
  } catch (error) {
    if (error instanceof Error) {
      if (error.message === "forbidden_chat_access") {
        res.status(403).json({ error: error.message });
        return;
      }
      if (error.message === "group_not_found") {
        res.status(404).json({ error: error.message });
        return;
      }
    }
    logError("group call leave failed", error);
    res.status(500).json({ error: "failed_to_leave_group_call" });
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

callRouter.post("/:callId/video-upgrade/request", requireAuth, async (req, res) => {
  const origin = getRequestOrigin(req);
  try {
    const result = await callService.requestVideoUpgrade({
      callId: getRouteParam(req, "callId"),
      userId: req.authUserId!
    });

    res.json({
      data: {
        call: serializeCallForViewer(origin, result.call, req.authUserId!),
        requestId: result.requestId,
        requestedByUserId: req.authUserId!
      }
    });

    emitVideoUpgradeEvent(origin, result.call, "call:video-upgrade:requested", {
      requestId: result.requestId,
      requestedByUserId: req.authUserId!
    });
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call video upgrade request failed", error);
    res.status(500).json({ error: "failed_to_request_video_upgrade" });
  }
});

callRouter.post("/:callId/video-upgrade/accept", requireAuth, async (req, res) => {
  const origin = getRequestOrigin(req);
  const parsed = videoUpgradeActionSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const call = await callService.acceptVideoUpgrade({
      callId: getRouteParam(req, "callId"),
      userId: req.authUserId!,
      requestId: parsed.data.requestId
    });

    res.json({
      data: {
        call: serializeCallForViewer(origin, call, req.authUserId!),
        requestId: parsed.data.requestId,
        actedByUserId: req.authUserId!
      }
    });

    emitVideoUpgradeEvent(origin, call, "call:video-upgrade:accepted", {
      requestId: parsed.data.requestId,
      actedByUserId: req.authUserId!
    });
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call video upgrade accept failed", error);
    res.status(500).json({ error: "failed_to_accept_video_upgrade" });
  }
});

callRouter.post("/:callId/video-upgrade/decline", requireAuth, async (req, res) => {
  const origin = getRequestOrigin(req);
  const parsed = videoUpgradeActionSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
    return;
  }

  try {
    const call = await callService.declineVideoUpgrade({
      callId: getRouteParam(req, "callId"),
      userId: req.authUserId!,
      requestId: parsed.data.requestId
    });

    res.json({
      data: {
        call: serializeCallForViewer(origin, call, req.authUserId!),
        requestId: parsed.data.requestId,
        actedByUserId: req.authUserId!
      }
    });

    emitVideoUpgradeEvent(origin, call, "call:video-upgrade:declined", {
      requestId: parsed.data.requestId,
      actedByUserId: req.authUserId!
    });
  } catch (error) {
    if (respondCallError(res, error)) return;
    logError("call video upgrade decline failed", error);
    res.status(500).json({ error: "failed_to_decline_video_upgrade" });
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
