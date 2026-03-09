import jwt from "jsonwebtoken";
import type { AdminRoleValue } from "./admin-types.js";
import { env } from "../config/env.js";

interface UserClaims {
  sub: string;
  sid?: string;
  typ?: "user";
}

interface AdminClaims {
  sub: string;
  role: AdminRoleValue;
  typ: "admin";
}

export function signAccessToken(userId: string, sessionId?: string): string {
  const claims: UserClaims = { sub: userId, typ: "user" };
  if (sessionId) {
    claims.sid = sessionId;
  }
  return jwt.sign(claims, env.JWT_SECRET, { expiresIn: "7d" });
}

export function signAdminAccessToken(adminId: string, role: AdminRoleValue): string {
  const claims: AdminClaims = { sub: adminId, role, typ: "admin" };
  return jwt.sign(claims, env.ADMIN_JWT_SECRET, { expiresIn: "7d" });
}

export function verifyAccessToken(token: string): { sub: string; sessionId: string | null } {
  const decoded = jwt.verify(token, env.JWT_SECRET);
  if (
    !decoded ||
    typeof decoded !== "object" ||
    typeof decoded.sub !== "string" ||
    ("typ" in decoded && decoded.typ !== undefined && decoded.typ !== "user") ||
    ("sid" in decoded && decoded.sid !== undefined && typeof decoded.sid !== "string")
  ) {
    throw new Error("invalid_token");
  }

  return {
    sub: decoded.sub,
    sessionId: typeof decoded.sid === "string" ? decoded.sid : null
  };
}

export function verifyAdminAccessToken(token: string): { sub: string; role: AdminRoleValue } {
  const decoded = jwt.verify(token, env.ADMIN_JWT_SECRET);
  if (
    !decoded ||
    typeof decoded !== "object" ||
    typeof decoded.sub !== "string" ||
    decoded.typ !== "admin" ||
    typeof decoded.role !== "string"
  ) {
    throw new Error("invalid_admin_token");
  }

  return {
    sub: decoded.sub,
    role: decoded.role as AdminRoleValue
  };
}
