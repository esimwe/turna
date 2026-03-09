import { env } from "../../config/env.js";
import { redis } from "../../lib/redis.js";

function key(parts: string[]): string {
  return parts.join(":");
}

async function incrementWithinWindow(redisKey: string, windowSeconds: number): Promise<number> {
  const value = await redis.incr(redisKey);
  if (value === 1) {
    await redis.expire(redisKey, windowSeconds);
  }
  return value;
}

async function getSecondsToLive(redisKey: string): Promise<number> {
  const ttl = await redis.ttl(redisKey);
  return ttl > 0 ? ttl : 0;
}

export async function assertOtpRequestAllowed(input: {
  phone: string;
  ipAddress: string | null;
}): Promise<void> {
  const cooldownKey = key(["otp", "cooldown", "phone", input.phone]);
  const cooldownTtl = await getSecondsToLive(cooldownKey);
  if (cooldownTtl > 0) {
    throw new Error(`otp_cooldown:${cooldownTtl}`);
  }

  const phone10m = await incrementWithinWindow(
    key(["otp", "send", "phone", "10m", input.phone]),
    10 * 60
  );
  if (phone10m > env.OTP_PHONE_LIMIT_10M) {
    throw new Error("otp_rate_limited");
  }

  const phone24h = await incrementWithinWindow(
    key(["otp", "send", "phone", "24h", input.phone]),
    24 * 60 * 60
  );
  if (phone24h > env.OTP_PHONE_LIMIT_24H) {
    throw new Error("otp_rate_limited");
  }

  if (input.ipAddress) {
    const ip10m = await incrementWithinWindow(
      key(["otp", "send", "ip", "10m", input.ipAddress]),
      10 * 60
    );
    if (ip10m > env.OTP_IP_LIMIT_10M) {
      throw new Error("otp_rate_limited");
    }

    const ip24h = await incrementWithinWindow(
      key(["otp", "send", "ip", "24h", input.ipAddress]),
      24 * 60 * 60
    );
    if (ip24h > env.OTP_IP_LIMIT_24H) {
      throw new Error("otp_rate_limited");
    }
  }
}

export async function setOtpCooldown(phone: string): Promise<void> {
  await redis.set(
    key(["otp", "cooldown", "phone", phone]),
    "1",
    "EX",
    env.OTP_RESEND_COOLDOWN_SECONDS
  );
}

export async function getOtpCooldownSeconds(phone: string): Promise<number> {
  return getSecondsToLive(key(["otp", "cooldown", "phone", phone]));
}
