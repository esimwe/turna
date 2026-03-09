import { verifyAccessToken } from "../lib/jwt.js";
export function requireAuth(req, res, next) {
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
    }
    catch {
        res.status(401).json({ error: "invalid_token" });
    }
}
