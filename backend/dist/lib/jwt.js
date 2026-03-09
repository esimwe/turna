import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
export function signAccessToken(userId) {
    const claims = { sub: userId };
    return jwt.sign(claims, env.JWT_SECRET, { expiresIn: "7d" });
}
export function verifyAccessToken(token) {
    const decoded = jwt.verify(token, env.JWT_SECRET);
    if (!decoded || typeof decoded !== "object" || typeof decoded.sub !== "string") {
        throw new Error("invalid_token");
    }
    return { sub: decoded.sub };
}
