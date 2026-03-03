import type { NextFunction, Request, Response } from "express";
import { verifyAccessToken } from "../lib/jwt.js";

declare global {
  namespace Express {
    interface Request {
      authUserId?: string;
    }
  }
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const authorization = req.header("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  const token = authorization.replace("Bearer ", "").trim();

  try {
    const claims = verifyAccessToken(token);
    req.authUserId = claims.sub;
    next();
  } catch {
    res.status(401).json({ error: "invalid_token" });
  }
}
