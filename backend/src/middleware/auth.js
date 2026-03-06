"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAuth = requireAuth;
var jwt_js_1 = require("../lib/jwt.js");
function requireAuth(req, res, next) {
    var authorization = req.header("authorization");
    if (!(authorization === null || authorization === void 0 ? void 0 : authorization.startsWith("Bearer "))) {
        res.status(401).json({ error: "unauthorized" });
        return;
    }
    var token = authorization.replace("Bearer ", "").trim();
    try {
        var claims = (0, jwt_js_1.verifyAccessToken)(token);
        req.authUserId = claims.sub;
        next();
    }
    catch (_a) {
        res.status(401).json({ error: "invalid_token" });
    }
}
