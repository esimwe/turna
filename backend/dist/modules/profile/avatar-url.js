function getRequestOrigin(req) {
    const forwardedProto = req.header("x-forwarded-proto");
    const proto = forwardedProto?.split(",")[0]?.trim() || req.protocol;
    return `${proto}://${req.get("host")}`;
}
export function buildAvatarUrlFromOrigin(origin, userId, updatedAt) {
    const version = encodeURIComponent(updatedAt.toISOString());
    return `${origin}/api/profile/avatar/${userId}?v=${version}`;
}
export function buildAvatarUrl(req, userId, updatedAt) {
    return buildAvatarUrlFromOrigin(getRequestOrigin(req), userId, updatedAt);
}
