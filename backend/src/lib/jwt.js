"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.signAccessToken = signAccessToken;
exports.verifyAccessToken = verifyAccessToken;
var jsonwebtoken_1 = require("jsonwebtoken");
var env_js_1 = require("../config/env.js");
function signAccessToken(userId) {
    var claims = { sub: userId };
    return jsonwebtoken_1.default.sign(claims, env_js_1.env.JWT_SECRET, { expiresIn: "7d" });
}
function verifyAccessToken(token) {
    var decoded = jsonwebtoken_1.default.verify(token, env_js_1.env.JWT_SECRET);
    if (!decoded || typeof decoded !== "object" || typeof decoded.sub !== "string") {
        throw new Error("invalid_token");
    }
    return { sub: decoded.sub };
}
