import { Redis } from "ioredis";
import { env } from "../config/env.js";

function buildRedisOptions() {
  return {
    lazyConnect: true,
    maxRetriesPerRequest: 1
  } as const;
}

export const redis = new Redis(env.REDIS_URL, buildRedisOptions());

export function createRedisConnection(): Redis {
  return new Redis(env.REDIS_URL, buildRedisOptions());
}
