import { config } from "dotenv";
import { z } from "zod";

config();

const resolvedEnv = {
  NODE_ENV: process.env.NODE_ENV,
  PORT: process.env.PORT,
  CORS_ORIGIN: process.env.CORS_ORIGIN,
  TRUST_PROXY: process.env.TRUST_PROXY,
  FORCE_HTTPS: process.env.FORCE_HTTPS,
  REDIS_URL: process.env.REDIS_URL ?? process.env.REDIS_PRIVATE_URL,
  DATABASE_URL:
    process.env.DATABASE_URL ??
    process.env.POSTGRES_URL ??
    process.env.POSTGRES_URL_NON_POOLING ??
    process.env.DATABASE_PUBLIC_URL,
  JWT_SECRET: process.env.JWT_SECRET ?? process.env.AUTH_SECRET,
  R2_ACCOUNT_ID: process.env.R2_ACCOUNT_ID,
  R2_BUCKET: process.env.R2_BUCKET,
  R2_ENDPOINT: process.env.R2_ENDPOINT,
  R2_ACCESS_KEY_ID: process.env.R2_ACCESS_KEY_ID,
  R2_SECRET_ACCESS_KEY: process.env.R2_SECRET_ACCESS_KEY,
  FIREBASE_PROJECT_ID: process.env.FIREBASE_PROJECT_ID,
  FIREBASE_CLIENT_EMAIL: process.env.FIREBASE_CLIENT_EMAIL,
  FIREBASE_PRIVATE_KEY: process.env.FIREBASE_PRIVATE_KEY,
  FIREBASE_SERVICE_ACCOUNT_JSON: process.env.FIREBASE_SERVICE_ACCOUNT_JSON,
  APNS_TEAM_ID: process.env.APNS_TEAM_ID,
  APNS_KEY_ID: process.env.APNS_KEY_ID,
  APNS_BUNDLE_ID: process.env.APNS_BUNDLE_ID,
  APNS_USE_SANDBOX: process.env.APNS_USE_SANDBOX,
  APNS_VOIP_PRIVATE_KEY: process.env.APNS_VOIP_PRIVATE_KEY,
  APNS_VOIP_PRIVATE_KEY_BASE64: process.env.APNS_VOIP_PRIVATE_KEY_BASE64,
  LIVEKIT_HOST: process.env.LIVEKIT_HOST,
  LIVEKIT_WS_URL: process.env.LIVEKIT_WS_URL,
  LIVEKIT_API_KEY: process.env.LIVEKIT_API_KEY,
  LIVEKIT_API_SECRET: process.env.LIVEKIT_API_SECRET
};

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().default(4000),
  CORS_ORIGIN: z.string().default("*"),
  TRUST_PROXY: z
    .string()
    .optional()
    .transform((value) => (value == null ? false : value === "true")),
  FORCE_HTTPS: z
    .string()
    .optional()
    .transform((value) => (value == null ? false : value === "true")),
  REDIS_URL: z.string().default("redis://localhost:6379"),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(12).default("turna-dev-secret-change-me"),
  R2_ACCOUNT_ID: z.string().min(1).optional(),
  R2_BUCKET: z.string().min(1).optional(),
  R2_ENDPOINT: z.string().url().optional(),
  R2_ACCESS_KEY_ID: z.string().min(1).optional(),
  R2_SECRET_ACCESS_KEY: z.string().min(1).optional(),
  FIREBASE_PROJECT_ID: z.string().min(1).optional(),
  FIREBASE_CLIENT_EMAIL: z.string().min(1).optional(),
  FIREBASE_PRIVATE_KEY: z.string().min(1).optional(),
  FIREBASE_SERVICE_ACCOUNT_JSON: z.string().min(1).optional(),
  APNS_TEAM_ID: z.string().min(1).optional(),
  APNS_KEY_ID: z.string().min(1).optional(),
  APNS_BUNDLE_ID: z.string().min(1).optional(),
  APNS_USE_SANDBOX: z
    .string()
    .optional()
    .transform((value) => (value == null ? undefined : value === "true")),
  APNS_VOIP_PRIVATE_KEY: z.string().min(1).optional(),
  APNS_VOIP_PRIVATE_KEY_BASE64: z.string().min(1).optional(),
  LIVEKIT_HOST: z.string().url().optional(),
  LIVEKIT_WS_URL: z.string().url().optional(),
  LIVEKIT_API_KEY: z.string().min(1).optional(),
  LIVEKIT_API_SECRET: z.string().min(1).optional()
});

export const env = envSchema.parse(resolvedEnv);
