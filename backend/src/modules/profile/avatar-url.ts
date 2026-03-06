import type { Request } from "express";

function getRequestOrigin(req: Request): string {
  const forwardedProto = req.header("x-forwarded-proto");
  const proto = forwardedProto?.split(",")[0]?.trim() || req.protocol;
  return `${proto}://${req.get("host")}`;
}

export function buildAvatarUrl(req: Request, userId: string, updatedAt: Date): string {
  const version = encodeURIComponent(updatedAt.toISOString());
  return `${getRequestOrigin(req)}/api/profile/avatar/${userId}?v=${version}`;
}
