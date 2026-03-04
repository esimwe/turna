import { config } from "dotenv";
import { z } from "zod";

config();

const resolvedEnv = {
  NODE_ENV: process.env.NODE_ENV,
  PORT: process.env.PORT,
  CORS_ORIGIN: process.env.CORS_ORIGIN,
  REDIS_URL: process.env.REDIS_URL ?? process.env.REDIS_PRIVATE_URL,
  DATABASE_URL:
    process.env.DATABASE_URL ??
    process.env.POSTGRES_URL ??
    process.env.POSTGRES_URL_NON_POOLING ??
    process.env.DATABASE_PUBLIC_URL,
  JWT_SECRET: process.env.JWT_SECRET ?? process.env.AUTH_SECRET
};

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().default(4000),
  CORS_ORIGIN: z.string().default("*"),
  REDIS_URL: z.string().default("redis://localhost:6379"),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(12).default("turna-dev-secret-change-me")
});

export const env = envSchema.parse(resolvedEnv);
