import { config } from "dotenv";
import { z } from "zod";

config();

function emptyStringToUndefined(value: unknown): unknown {
  if (typeof value !== "string") {
    return value;
  }

  const trimmed = value.trim();
  return trimmed === "" ? undefined : trimmed;
}

const optionalNonEmptyString = z.preprocess(emptyStringToUndefined, z.string().min(1).optional());
const optionalFixedOtpCode = z.preprocess(
  emptyStringToUndefined,
  z
    .string()
    .regex(/^\d{4,8}$/)
    .optional()
);

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
  ADMIN_JWT_SECRET: process.env.ADMIN_JWT_SECRET ?? process.env.JWT_SECRET ?? process.env.AUTH_SECRET,
  ADMIN_BOOTSTRAP_USERNAME: process.env.ADMIN_BOOTSTRAP_USERNAME,
  ADMIN_BOOTSTRAP_PASSWORD: process.env.ADMIN_BOOTSTRAP_PASSWORD,
  ADMIN_BOOTSTRAP_DISPLAY_NAME: process.env.ADMIN_BOOTSTRAP_DISPLAY_NAME,
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
  LIVEKIT_API_SECRET: process.env.LIVEKIT_API_SECRET,
  SMS_PROVIDER: process.env.SMS_PROVIDER,
  NETGSM_USERCODE: process.env.NETGSM_USERCODE,
  NETGSM_PASSWORD: process.env.NETGSM_PASSWORD,
  NETGSM_HEADER: process.env.NETGSM_HEADER,
  OTP_SECRET: process.env.OTP_SECRET,
  FIXED_OTP_CODE:
    process.env.FIXED_OTP_CODE ?? process.env.OTP_FIXED_CODE ?? process.env.fixed_otp_code,
  OTP_TTL_SECONDS: process.env.OTP_TTL_SECONDS,
  OTP_RESEND_COOLDOWN_SECONDS: process.env.OTP_RESEND_COOLDOWN_SECONDS,
  OTP_MAX_ATTEMPTS: process.env.OTP_MAX_ATTEMPTS,
  OTP_PHONE_LIMIT_10M: process.env.OTP_PHONE_LIMIT_10M,
  OTP_PHONE_LIMIT_24H: process.env.OTP_PHONE_LIMIT_24H,
  OTP_IP_LIMIT_10M: process.env.OTP_IP_LIMIT_10M,
  OTP_IP_LIMIT_24H: process.env.OTP_IP_LIMIT_24H
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
  ADMIN_JWT_SECRET: z.string().min(12).default("turna-admin-dev-secret-change-me"),
  ADMIN_BOOTSTRAP_USERNAME: z.string().min(3).max(64).optional(),
  ADMIN_BOOTSTRAP_PASSWORD: z.string().min(8).max(255).optional(),
  ADMIN_BOOTSTRAP_DISPLAY_NAME: z.string().min(1).max(120).optional(),
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
  LIVEKIT_API_SECRET: z.string().min(1).optional(),
  SMS_PROVIDER: z.enum(["netgsm_bulk", "netgsm_otp", "mock"]).default("mock"),
  NETGSM_USERCODE: optionalNonEmptyString,
  NETGSM_PASSWORD: optionalNonEmptyString,
  NETGSM_HEADER: optionalNonEmptyString,
  OTP_SECRET: z.string().min(12).default("turna-otp-dev-secret-change-me"),
  FIXED_OTP_CODE: optionalFixedOtpCode,
  OTP_TTL_SECONDS: z.coerce.number().int().min(30).max(900).default(180),
  OTP_RESEND_COOLDOWN_SECONDS: z.coerce.number().int().min(15).max(300).default(60),
  OTP_MAX_ATTEMPTS: z.coerce.number().int().min(1).max(10).default(5),
  OTP_PHONE_LIMIT_10M: z.coerce.number().int().min(1).max(50).default(3),
  OTP_PHONE_LIMIT_24H: z.coerce.number().int().min(1).max(200).default(10),
  OTP_IP_LIMIT_10M: z.coerce.number().int().min(1).max(100).default(5),
  OTP_IP_LIMIT_24H: z.coerce.number().int().min(1).max(500).default(20)
});

export const env = envSchema.parse(resolvedEnv);
