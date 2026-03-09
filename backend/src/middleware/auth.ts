import type { NextFunction, Request, Response } from "express";
import {
  assertUserCanSendMessages,
  assertUserCanStartOrAcceptCalls,
  getAccountAccessError,
  requireUserAccessState,
  type UserAccessState
} from "../lib/user-access.js";
import { findActiveAuthSession } from "../lib/auth-sessions.js";
import { verifyAccessToken } from "../lib/jwt.js";

declare global {
  namespace Express {
    interface Request {
      authUserId?: string;
      authSessionId?: string | null;
      authUserAccess?: UserAccessState;
    }
  }
}

function respondForbidden(res: Response, error: string): void {
  res.status(403).json({ error });
}

export async function requireAuth(req: Request, res: Response, next: NextFunction): Promise<void> {
  const authorization = req.header("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  const token = authorization.replace("Bearer ", "").trim();

  try {
    const claims = verifyAccessToken(token);
    const access = await requireUserAccessState(claims.sub);
    const accountError = getAccountAccessError(access);
    if (accountError) {
      respondForbidden(res, accountError);
      return;
    }

    if (claims.sessionId) {
      const session = await findActiveAuthSession(claims.sessionId);
      if (!session || session.userId !== claims.sub) {
        res.status(401).json({ error: "session_revoked" });
        return;
      }
    }

    req.authUserId = claims.sub;
    req.authSessionId = claims.sessionId;
    req.authUserAccess = access;
    next();
  } catch (error) {
    if (error instanceof Error && error.message === "user_not_found") {
      res.status(401).json({ error: "user_not_found" });
      return;
    }
    res.status(401).json({ error: "invalid_token" });
  }
}

export function requireMessagingAccess(req: Request, res: Response, next: NextFunction): void {
  const access = req.authUserAccess;
  if (!access) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  try {
    assertUserCanSendMessages(access);
    next();
  } catch (error) {
    respondForbidden(res, error instanceof Error ? error.message : "message_sending_restricted");
  }
}

export function requireCallingAccess(req: Request, res: Response, next: NextFunction): void {
  const access = req.authUserAccess;
  if (!access) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  try {
    assertUserCanStartOrAcceptCalls(access);
    next();
  } catch (error) {
    respondForbidden(res, error instanceof Error ? error.message : "calling_restricted");
  }
}
