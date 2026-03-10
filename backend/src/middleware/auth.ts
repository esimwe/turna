import type { NextFunction, Request, Response } from "express";
import {
  assertUserCanSendMessages,
  assertUserCanStartOrAcceptCalls,
  getAccountAccessError,
  requireUserAccessState,
  type UserAccessState
} from "../lib/user-access.js";
import {
  findActiveAuthSession,
  touchActiveAuthSessionForRequest
} from "../lib/auth-sessions.js";
import { verifyAccessToken } from "../lib/jwt.js";
import { logInfo } from "../lib/logger.js";

declare global {
  namespace Express {
    interface Request {
      authUserId?: string;
      authSessionId?: string | null;
      authUserAccess?: UserAccessState;
    }
  }
}

function logAuthFailure(req: Request, reason: string, meta?: Record<string, unknown>): void {
  logInfo("requireAuth failed", {
    method: req.method,
    path: req.originalUrl || req.path,
    ip: req.ip,
    reason,
    hasAuthorizationHeader: Boolean(req.header("authorization")),
    ...meta
  });
}

function respondForbidden(req: Request, res: Response, error: string): void {
  logAuthFailure(req, error);
  res.status(403).json({ error });
}

export async function requireAuth(req: Request, res: Response, next: NextFunction): Promise<void> {
  const authorization = req.header("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    logAuthFailure(req, "unauthorized");
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  const token = authorization.replace("Bearer ", "").trim();

  try {
    const claims = verifyAccessToken(token);
    const access = await requireUserAccessState(claims.sub);
    const accountError = getAccountAccessError(access);
    if (accountError) {
      respondForbidden(req, res, accountError);
      return;
    }

    if (claims.sessionId) {
      const session = await findActiveAuthSession(claims.sessionId);
      if (!session || session.userId !== claims.sub) {
        logAuthFailure(req, "session_revoked", {
          userId: claims.sub,
          hasSessionId: true
        });
        res.status(401).json({ error: "session_revoked" });
        return;
      }
      await touchActiveAuthSessionForRequest(claims.sessionId, req);
    }

    req.authUserId = claims.sub;
    req.authSessionId = claims.sessionId;
    req.authUserAccess = access;
    next();
  } catch (error) {
    if (error instanceof Error && error.message === "user_not_found") {
      logAuthFailure(req, "user_not_found");
      res.status(401).json({ error: "user_not_found" });
      return;
    }
    logAuthFailure(req, "invalid_token", {
      message: error instanceof Error ? error.message : String(error)
    });
    res.status(401).json({ error: "invalid_token" });
  }
}

export function requireMessagingAccess(req: Request, res: Response, next: NextFunction): void {
  const access = req.authUserAccess;
  if (!access) {
    logAuthFailure(req, "unauthorized");
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  try {
    assertUserCanSendMessages(access);
    next();
  } catch (error) {
    respondForbidden(
      req,
      res,
      error instanceof Error ? error.message : "message_sending_restricted"
    );
  }
}

export function requireCallingAccess(req: Request, res: Response, next: NextFunction): void {
  const access = req.authUserAccess;
  if (!access) {
    logAuthFailure(req, "unauthorized");
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  try {
    assertUserCanStartOrAcceptCalls(access);
    next();
  } catch (error) {
    respondForbidden(
      req,
      res,
      error instanceof Error ? error.message : "calling_restricted"
    );
  }
}
