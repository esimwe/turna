export const CALL_RING_TIMEOUT_MS = 30_000;
export const CALL_RECONNECT_GRACE_MS = 15_000;
const scheduledTimeouts = new Map<string, NodeJS.Timeout>();
const scheduledReconnectGraceTimeouts = new Map<string, NodeJS.Timeout>();

export function scheduleCallTimeout(
  callId: string,
  handler: () => Promise<void>,
  delayMs = CALL_RING_TIMEOUT_MS
): void {
  cancelCallTimeout(callId);
  const timeout = setTimeout(async () => {
    scheduledTimeouts.delete(callId);
    await handler().catch(() => undefined);
  }, delayMs);
  timeout.unref?.();
  scheduledTimeouts.set(callId, timeout);
}

export function cancelCallTimeout(callId: string): void {
  const existing = scheduledTimeouts.get(callId);
  if (!existing) return;
  clearTimeout(existing);
  scheduledTimeouts.delete(callId);
}

export function scheduleCallReconnectGrace(
  callId: string,
  handler: () => Promise<void>,
  delayMs = CALL_RECONNECT_GRACE_MS
): void {
  cancelCallReconnectGrace(callId);
  const timeout = setTimeout(async () => {
    scheduledReconnectGraceTimeouts.delete(callId);
    await handler().catch(() => undefined);
  }, delayMs);
  timeout.unref?.();
  scheduledReconnectGraceTimeouts.set(callId, timeout);
}

export function cancelCallReconnectGrace(callId: string): void {
  const existing = scheduledReconnectGraceTimeouts.get(callId);
  if (!existing) return;
  clearTimeout(existing);
  scheduledReconnectGraceTimeouts.delete(callId);
}

export function clearAllCallTimeouts(): void {
  for (const timeout of scheduledTimeouts.values()) {
    clearTimeout(timeout);
  }
  scheduledTimeouts.clear();

  for (const timeout of scheduledReconnectGraceTimeouts.values()) {
    clearTimeout(timeout);
  }
  scheduledReconnectGraceTimeouts.clear();
}
