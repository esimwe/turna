import jwt from "jsonwebtoken";
import { env } from "../config/env.js";

interface Claims {
  sub: string;
}

export function signAccessToken(userId: string): string {
  const claims: Claims = { sub: userId };
  return jwt.sign(claims, env.JWT_SECRET, { expiresIn: "7d" });
}

export function verifyAccessToken(token: string): Claims {
  const decoded = jwt.verify(token, env.JWT_SECRET);
  if (!decoded || typeof decoded !== "object" || typeof decoded.sub !== "string") {
    throw new Error("invalid_token");
  }

  return { sub: decoded.sub };
}
