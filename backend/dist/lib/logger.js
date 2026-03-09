export function logInfo(message, meta) {
    if (meta) {
        console.log(`[turna] ${message}`, meta);
        return;
    }
    console.log(`[turna] ${message}`);
}
export function logError(message, err) {
    console.error(`[turna] ${message}`, err);
}
