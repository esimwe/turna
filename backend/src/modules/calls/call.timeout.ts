export const CALL_RING_TIMEOUT_MS = 30_000;
const scheduledTimeouts = new Map<string, NodeJS.Timeout>();

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

export function clearAllCallTimeouts(): void {
  for (const timeout of scheduledTimeouts.values()) {
    clearTimeout(timeout);
  }
  scheduledTimeouts.clear();
}
