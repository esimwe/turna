import { assertUserCanSendMessages, assertUserCanStartOrAcceptCalls, getAccountAccessError, requireUserAccessState } from "../lib/user-access.js";
import { findActiveAuthSession } from "../lib/auth-sessions.js";
import { verifyAccessToken } from "../lib/jwt.js";
import { logInfo } from "../lib/logger.js";
function logAuthFailure(req, reason, meta) {
    logInfo("requireAuth failed", {
        method: req.method,
        path: req.originalUrl || req.path,
        ip: req.ip,
        reason,
        hasAuthorizationHeader: Boolean(req.header("authorization")),
        ...meta
    });
}
function respondForbidden(req, res, error) {
    logAuthFailure(req, error);
    res.status(403).json({ error });
}
export async function requireAuth(req, res, next) {
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
        }
        req.authUserId = claims.sub;
        req.authSessionId = claims.sessionId;
        req.authUserAccess = access;
        next();
    }
    catch (error) {
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
export function requireMessagingAccess(req, res, next) {
    const access = req.authUserAccess;
    if (!access) {
        logAuthFailure(req, "unauthorized");
        res.status(401).json({ error: "unauthorized" });
        return;
    }
    try {
        assertUserCanSendMessages(access);
        next();
    }
    catch (error) {
        respondForbidden(req, res, error instanceof Error ? error.message : "message_sending_restricted");
    }
}
export function requireCallingAccess(req, res, next) {
    const access = req.authUserAccess;
    if (!access) {
        logAuthFailure(req, "unauthorized");
        res.status(401).json({ error: "unauthorized" });
        return;
    }
    try {
        assertUserCanStartOrAcceptCalls(access);
        next();
    }
    catch (error) {
        respondForbidden(req, res, error instanceof Error ? error.message : "calling_restricted");
    }
}
