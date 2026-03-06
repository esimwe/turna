"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.profileRouter = void 0;
var express_1 = require("express");
var zod_1 = require("zod");
var prisma_js_1 = require("../../lib/prisma.js");
var auth_js_1 = require("../../middleware/auth.js");
exports.profileRouter = (0, express_1.Router)();
var nullableTrimmedString = function (maxLength) {
    return zod_1.z.preprocess(function (value) {
        if (typeof value !== "string")
            return value;
        var trimmed = value.trim();
        return trimmed.length === 0 ? null : trimmed;
    }, zod_1.z.string().max(maxLength).nullable());
};
var nullableTrimmedPhone = zod_1.z.preprocess(function (value) {
    if (typeof value !== "string")
        return value;
    var trimmed = value.trim();
    return trimmed.length === 0 ? null : trimmed;
}, zod_1.z.string().min(5).max(20).nullable());
var nullableEmail = zod_1.z.preprocess(function (value) {
    if (typeof value !== "string")
        return value;
    var trimmed = value.trim().toLowerCase();
    return trimmed.length === 0 ? null : trimmed;
}, zod_1.z.string().email().max(255).nullable());
var nullableAvatarUrl = zod_1.z.preprocess(function (value) {
    if (typeof value !== "string")
        return value;
    var trimmed = value.trim();
    return trimmed.length === 0 ? null : trimmed;
}, zod_1.z.string().url().max(2048).nullable());
var updateProfileSchema = zod_1.z.object({
    displayName: zod_1.z.string().trim().min(2).max(80),
    about: nullableTrimmedString(160),
    phone: nullableTrimmedPhone,
    email: nullableEmail,
    avatarUrl: nullableAvatarUrl
});
function toProfileDto(user) {
    return {
        id: user.id,
        displayName: user.displayName,
        phone: user.phone,
        email: user.email,
        about: user.about,
        avatarUrl: user.avatarUrl,
        createdAt: user.createdAt.toISOString()
    };
}
exports.profileRouter.get("/me", auth_js_1.requireAuth, function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var user;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0: return [4 /*yield*/, prisma_js_1.prisma.user.findUnique({
                    where: { id: req.authUserId },
                    select: {
                        id: true,
                        displayName: true,
                        phone: true,
                        email: true,
                        about: true,
                        avatarUrl: true,
                        createdAt: true
                    }
                })];
            case 1:
                user = _a.sent();
                if (!user) {
                    res.status(404).json({ error: "user_not_found" });
                    return [2 /*return*/];
                }
                res.json({ data: toProfileDto(user) });
                return [2 /*return*/];
        }
    });
}); });
exports.profileRouter.put("/me", auth_js_1.requireAuth, function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var parsed, userId, phoneOwner, emailOwner, user;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                parsed = updateProfileSchema.safeParse(req.body);
                if (!parsed.success) {
                    res.status(400).json({ error: "validation_error", details: parsed.error.flatten() });
                    return [2 /*return*/];
                }
                userId = req.authUserId;
                if (!parsed.data.phone) return [3 /*break*/, 2];
                return [4 /*yield*/, prisma_js_1.prisma.user.findFirst({
                        where: {
                            phone: parsed.data.phone,
                            id: { not: userId }
                        },
                        select: { id: true }
                    })];
            case 1:
                phoneOwner = _a.sent();
                if (phoneOwner) {
                    res.status(409).json({ error: "phone_already_in_use" });
                    return [2 /*return*/];
                }
                _a.label = 2;
            case 2:
                if (!parsed.data.email) return [3 /*break*/, 4];
                return [4 /*yield*/, prisma_js_1.prisma.user.findFirst({
                        where: {
                            email: parsed.data.email,
                            id: { not: userId }
                        },
                        select: { id: true }
                    })];
            case 3:
                emailOwner = _a.sent();
                if (emailOwner) {
                    res.status(409).json({ error: "email_already_in_use" });
                    return [2 /*return*/];
                }
                _a.label = 4;
            case 4: return [4 /*yield*/, prisma_js_1.prisma.user.update({
                    where: { id: userId },
                    data: {
                        displayName: parsed.data.displayName,
                        about: parsed.data.about,
                        phone: parsed.data.phone,
                        email: parsed.data.email,
                        avatarUrl: parsed.data.avatarUrl
                    },
                    select: {
                        id: true,
                        displayName: true,
                        phone: true,
                        email: true,
                        about: true,
                        avatarUrl: true,
                        createdAt: true
                    }
                })];
            case 5:
                user = _a.sent();
                res.json({ data: toProfileDto(user) });
                return [2 /*return*/];
        }
    });
}); });
