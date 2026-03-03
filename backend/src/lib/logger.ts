export function logInfo(message: string, meta?: unknown): void {
  if (meta) {
    console.log(`[turna] ${message}`, meta);
    return;
  }
  console.log(`[turna] ${message}`);
}

export function logError(message: string, err: unknown): void {
  console.error(`[turna] ${message}`, err);
}
