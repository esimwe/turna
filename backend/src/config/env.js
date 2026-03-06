"use strict";
var _a, _b, _c, _d, _e;
Object.defineProperty(exports, "__esModule", { value: true });
exports.env = void 0;
var dotenv_1 = require("dotenv");
var zod_1 = require("zod");
(0, dotenv_1.config)();
var resolvedEnv = {
    NODE_ENV: process.env.NODE_ENV,
    PORT: process.env.PORT,
    CORS_ORIGIN: process.env.CORS_ORIGIN,
    REDIS_URL: (_a = process.env.REDIS_URL) !== null && _a !== void 0 ? _a : process.env.REDIS_PRIVATE_URL,
    DATABASE_URL: (_d = (_c = (_b = process.env.DATABASE_URL) !== null && _b !== void 0 ? _b : process.env.POSTGRES_URL) !== null && _c !== void 0 ? _c : process.env.POSTGRES_URL_NON_POOLING) !== null && _d !== void 0 ? _d : process.env.DATABASE_PUBLIC_URL,
    JWT_SECRET: (_e = process.env.JWT_SECRET) !== null && _e !== void 0 ? _e : process.env.AUTH_SECRET
};
var envSchema = zod_1.z.object({
    NODE_ENV: zod_1.z.enum(["development", "test", "production"]).default("development"),
    PORT: zod_1.z.coerce.number().default(4000),
    CORS_ORIGIN: zod_1.z.string().default("*"),
    REDIS_URL: zod_1.z.string().default("redis://localhost:6379"),
    DATABASE_URL: zod_1.z.string().url(),
    JWT_SECRET: zod_1.z.string().min(12).default("turna-dev-secret-change-me")
});
exports.env = envSchema.parse(resolvedEnv);
