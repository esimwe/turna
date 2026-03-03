import { config } from "dotenv";
import { z } from "zod";

config();

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().default(4000),
  CORS_ORIGIN: z.string().default("*"),
  REDIS_URL: z.string().default("redis://localhost:6379"),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(12)
});

export const env = envSchema.parse(process.env);
