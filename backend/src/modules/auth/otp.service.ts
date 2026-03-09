import { randomBytes, randomInt, createHmac } from "crypto";
import type { Request } from "express";
import { env } from "../../config/env.js";
import { createAuthSessionForRequest, getRequestIp } from "../../lib/auth-sessions.js";
import { signAccessToken } from "../../lib/jwt.js";
import { prisma } from "../../lib/prisma.js";
import { assertUserCanAccessApp, assertUserCanUseOtp } from "../../lib/user-access.js";
import {
  buildDefaultDisplayName,
  formatE164Phone,
  normalizeCountryIso,
  normalizeDialCode,
  normalizeE164Phone,
  normalizeNationalNumber
} from "./phone.js";
import { assertOtpRequestAllowed, getOtpCooldownSeconds, setOtpCooldown } from "./rate-limit.js";

const prismaUser = (prisma as unknown as { user: any }).user;
const prismaOtpCode = (prisma as unknown as { otpCode: any }).otpCode;
const prismaFeatureFlag = (prisma as unknown as { featureFlag: any }).featureFlag;
const prismaCountryPolicy = (prisma as unknown as { countryPolicy: any }).countryPolicy;

type OtpPurpose = "LOGIN" | "PHONE_CHANGE";

interface RequestOtpInput {
  countryIso: string;
  dialCode: string;
  nationalNumber: string;
  ipAddress: string | null;
}

interface VerifyOtpInput {
  phone: string;
  code: string;
}

function hashOtpCode(input: {
  phone: string;
  purpose: OtpPurpose;
  nonce: string;
  code: string;
}): string {
  return createHmac("sha256", env.OTP_SECRET)
    .update(`${input.phone}:${input.purpose}:${input.nonce}:${input.code}`)
    .digest("hex");
}

function normalizeOtpCode(code: string): string {
  const normalized = code.trim();
  if (!/^\d{4,8}$/.test(normalized)) {
    throw new Error("invalid_otp_code");
  }
  return normalized;
}

function nextOtpCode(): string {
  if (env.FIXED_OTP_CODE) {
    return env.FIXED_OTP_CODE;
  }

  throw new Error("otp_provider_not_configured");
}

function secondsBetween(now: Date, later: Date): number {
  return Math.max(0, Math.ceil((later.getTime() - now.getTime()) / 1000));
}

export class OtpService {
  private async getFeatureFlagEnabled(key: string, fallback = true): Promise<boolean> {
    const flag = await prismaFeatureFlag.findUnique({
      where: { key },
      select: { enabled: true }
    });
    return flag?.enabled ?? fallback;
  }

  private async getCountryPolicy(countryIso: string) {
    return prismaCountryPolicy.findUnique({
      where: { countryIso },
      select: {
        countryIso: true,
        countryName: true,
        isServiceEnabled: true,
        isSignupEnabled: true,
        isLoginEnabled: true,
        isOtpEnabled: true,
        isPhoneChangeEnabled: true
      }
    });
  }

  private async ensureLoginOtpAllowed(input: {
    countryIso: string;
    userExists: boolean;
  }): Promise<void> {
    const otpEnabled = await this.getFeatureFlagEnabled("otp_login_enabled", true);
    if (!otpEnabled) {
      throw new Error("otp_temporarily_unavailable");
    }

    const countryPolicy = await this.getCountryPolicy(input.countryIso);
    if (!countryPolicy) {
      return;
    }

    if (!countryPolicy.isServiceEnabled || !countryPolicy.isOtpEnabled) {
      throw new Error("otp_temporarily_unavailable");
    }

    if (input.userExists && !countryPolicy.isLoginEnabled) {
      throw new Error("login_temporarily_unavailable");
    }

    if (!input.userExists && !countryPolicy.isSignupEnabled) {
      throw new Error("signup_temporarily_unavailable");
    }
  }

  private async ensurePhoneChangeOtpAllowed(countryIso: string): Promise<void> {
    const phoneChangeEnabled = await this.getFeatureFlagEnabled("phone_change_enabled", true);
    if (!phoneChangeEnabled) {
      throw new Error("phone_change_temporarily_unavailable");
    }

    const countryPolicy = await this.getCountryPolicy(countryIso);
    if (!countryPolicy) {
      return;
    }

    if (
      !countryPolicy.isServiceEnabled ||
      !countryPolicy.isOtpEnabled ||
      !countryPolicy.isPhoneChangeEnabled
    ) {
      throw new Error("phone_change_temporarily_unavailable");
    }
  }

  private async consumeExistingOtps(phone: string, purpose: OtpPurpose): Promise<void> {
    await prismaOtpCode.updateMany({
      where: {
        phone,
        purpose,
        consumedAt: null
      },
      data: {
        consumedAt: new Date()
      }
    });
  }

  private async createOtpRecord(input: {
    phone: string;
    purpose: OtpPurpose;
    ipAddress: string | null;
  }): Promise<void> {
    const code = nextOtpCode();
    const nonce = randomBytes(12).toString("hex");
    await prismaOtpCode.create({
      data: {
        phone: input.phone,
        codeHash: hashOtpCode({
          phone: input.phone,
          purpose: input.purpose,
          nonce,
          code
        }),
        nonce,
        purpose: input.purpose,
        provider: env.FIXED_OTP_CODE ? "MOCK" : "NETGSM_BULK",
        expiresAt: new Date(Date.now() + env.OTP_TTL_SECONDS * 1000),
        requestIp: input.ipAddress,
        lastSentAt: new Date()
      }
    });
  }

  private async getLatestOtp(phone: string, purpose: OtpPurpose) {
    return prismaOtpCode.findFirst({
      where: {
        phone,
        purpose,
        consumedAt: null
      },
      orderBy: { createdAt: "desc" }
    });
  }

  private async verifyOtpRecord(input: {
    phone: string;
    purpose: OtpPurpose;
    code: string;
  }) {
    const otp = await this.getLatestOtp(input.phone, input.purpose);
    if (!otp) {
      throw new Error("otp_not_found");
    }

    const now = new Date();
    if (otp.expiresAt.getTime() <= now.getTime()) {
      await prismaOtpCode.update({
        where: { id: otp.id },
        data: { consumedAt: now }
      });
      throw new Error("otp_expired");
    }

    if (otp.attemptCount >= env.OTP_MAX_ATTEMPTS) {
      await prismaOtpCode.update({
        where: { id: otp.id },
        data: { consumedAt: now }
      });
      throw new Error("otp_attempts_exceeded");
    }

    const incomingHash = hashOtpCode({
      phone: input.phone,
      purpose: input.purpose,
      nonce: otp.nonce,
      code: input.code
    });

    if (incomingHash !== otp.codeHash) {
      const nextAttempts = otp.attemptCount + 1;
      await prismaOtpCode.update({
        where: { id: otp.id },
        data: {
          attemptCount: nextAttempts,
          consumedAt: nextAttempts >= env.OTP_MAX_ATTEMPTS ? now : undefined
        }
      });

      if (nextAttempts >= env.OTP_MAX_ATTEMPTS) {
        throw new Error("otp_attempts_exceeded");
      }
      throw new Error("otp_invalid");
    }

    await prismaOtpCode.update({
      where: { id: otp.id },
      data: {
        consumedAt: now
      }
    });

    return otp;
  }

  private normalizePhoneRequest(input: {
    countryIso: string;
    dialCode: string;
    nationalNumber: string;
  }): {
    countryIso: string;
    dialCode: string;
    nationalNumber: string;
    phone: string;
  } {
    const countryIso = normalizeCountryIso(input.countryIso);
    const dialCode = normalizeDialCode(input.dialCode);
    const nationalNumber = normalizeNationalNumber(input.nationalNumber);
    const phone = formatE164Phone({ dialCode, nationalNumber });
    return {
      countryIso,
      dialCode,
      nationalNumber,
      phone
    };
  }

  async requestLoginOtp(input: RequestOtpInput): Promise<{
    phone: string;
    expiresInSeconds: number;
    retryAfterSeconds: number;
  }> {
    const normalized = this.normalizePhoneRequest(input);
    const existingUser = await prismaUser.findUnique({
      where: { phone: normalized.phone },
      select: {
        id: true,
        accountStatus: true,
        otpBlocked: true,
        sendRestricted: true,
        callRestricted: true
      }
    });

    if (existingUser) {
      assertUserCanUseOtp(existingUser);
    }

    await this.ensureLoginOtpAllowed({
      countryIso: normalized.countryIso,
      userExists: !!existingUser
    });

    await assertOtpRequestAllowed({
      phone: normalized.phone,
      ipAddress: input.ipAddress
    });

    await this.consumeExistingOtps(normalized.phone, "LOGIN");
    await this.createOtpRecord({
      phone: normalized.phone,
      purpose: "LOGIN",
      ipAddress: input.ipAddress
    });
    await setOtpCooldown(normalized.phone);

    return {
      phone: normalized.phone,
      expiresInSeconds: env.OTP_TTL_SECONDS,
      retryAfterSeconds: await getOtpCooldownSeconds(normalized.phone)
    };
  }

  async verifyLoginOtp(input: VerifyOtpInput, req: Request): Promise<{
    accessToken: string;
    user: {
      id: string;
      displayName: string;
      phone: string | null;
      username: string | null;
      avatarUrl: string | null;
    };
    isNewUser: boolean;
    needsOnboarding: boolean;
  }> {
    const phone = normalizeE164Phone(input.phone);
    const code = normalizeOtpCode(input.code);
    await this.verifyOtpRecord({
      phone,
      purpose: "LOGIN",
      code
    });

    let user = await prismaUser.findUnique({
      where: { phone },
      select: {
        id: true,
        username: true,
        displayName: true,
        phone: true,
        avatarUrl: true,
        onboardingCompletedAt: true,
        accountStatus: true,
        otpBlocked: true,
        sendRestricted: true,
        callRestricted: true
      }
    });

    let isNewUser = false;
    if (!user) {
      isNewUser = true;
      user = await prismaUser.create({
        data: {
          phone,
          displayName: buildDefaultDisplayName(phone)
        },
        select: {
          id: true,
          username: true,
          displayName: true,
          phone: true,
          avatarUrl: true,
          onboardingCompletedAt: true,
          accountStatus: true,
          otpBlocked: true,
          sendRestricted: true,
          callRestricted: true
        }
      });
    }

    assertUserCanAccessApp(user);
    const needsOnboarding =
      isNewUser ||
      (!user.onboardingCompletedAt &&
        user.displayName === buildDefaultDisplayName(user.phone ?? phone));

    const session = await createAuthSessionForRequest(user.id, req, {
      revokeExisting: true,
      revokeReason: "new_login"
    });
    const accessToken = signAccessToken(user.id, session.id);

    return {
      accessToken,
      user: {
        id: user.id,
        displayName: user.displayName,
        phone: user.phone ?? null,
        username: user.username ?? null,
        avatarUrl: user.avatarUrl ?? null
      },
      isNewUser,
      needsOnboarding
    };
  }

  async requestPhoneChangeOtp(input: RequestOtpInput & { userId: string }): Promise<{
    phone: string;
    expiresInSeconds: number;
    retryAfterSeconds: number;
  }> {
    const normalized = this.normalizePhoneRequest(input);
    const currentUser = await prismaUser.findUnique({
      where: { id: input.userId },
      select: {
        id: true,
        phone: true,
        accountStatus: true,
        otpBlocked: true,
        sendRestricted: true,
        callRestricted: true
      }
    });
    if (!currentUser) {
      throw new Error("user_not_found");
    }

    assertUserCanUseOtp(currentUser);
    await this.ensurePhoneChangeOtpAllowed(normalized.countryIso);

    if (currentUser.phone === normalized.phone) {
      throw new Error("phone_unchanged");
    }

    const owner = await prismaUser.findFirst({
      where: {
        phone: normalized.phone,
        id: { not: input.userId }
      },
      select: { id: true }
    });
    if (owner) {
      throw new Error("phone_already_in_use");
    }

    await assertOtpRequestAllowed({
      phone: normalized.phone,
      ipAddress: input.ipAddress
    });

    await this.consumeExistingOtps(normalized.phone, "PHONE_CHANGE");
    await this.createOtpRecord({
      phone: normalized.phone,
      purpose: "PHONE_CHANGE",
      ipAddress: input.ipAddress
    });
    await setOtpCooldown(normalized.phone);

    return {
      phone: normalized.phone,
      expiresInSeconds: env.OTP_TTL_SECONDS,
      retryAfterSeconds: await getOtpCooldownSeconds(normalized.phone)
    };
  }

  async confirmPhoneChange(input: VerifyOtpInput & { userId: string }) {
    const phone = normalizeE164Phone(input.phone);
    const code = normalizeOtpCode(input.code);
    await this.verifyOtpRecord({
      phone,
      purpose: "PHONE_CHANGE",
      code
    });

    const owner = await prismaUser.findFirst({
      where: {
        phone,
        id: { not: input.userId }
      },
      select: { id: true }
    });
    if (owner) {
      throw new Error("phone_already_in_use");
    }

    const user = await prismaUser.update({
      where: { id: input.userId },
      data: {
        phone
      },
      select: {
        id: true,
        displayName: true,
        username: true,
        phone: true,
        email: true,
        about: true,
        avatarUrl: true,
        createdAt: true,
        updatedAt: true
      }
    });

    return user;
  }

  extractRequestOtpError(error: unknown): { status: number; error: string; retryAfterSeconds?: number } {
    if (!(error instanceof Error)) {
      return { status: 500, error: "failed_to_request_otp" };
    }

    if (error.message.startsWith("otp_cooldown:")) {
      const retryAfterSeconds = Number(error.message.split(":")[1] || env.OTP_RESEND_COOLDOWN_SECONDS);
      return {
        status: 429,
        error: "otp_cooldown",
        retryAfterSeconds
      };
    }

    switch (error.message) {
      case "invalid_country_iso":
      case "invalid_dial_code":
      case "invalid_national_number":
      case "invalid_phone":
        return { status: 400, error: "invalid_phone" };
      case "otp_rate_limited":
        return { status: 429, error: "otp_rate_limited" };
      case "otp_temporarily_unavailable":
      case "login_temporarily_unavailable":
      case "signup_temporarily_unavailable":
      case "phone_change_temporarily_unavailable":
      case "otp_provider_not_configured":
        return { status: 503, error: error.message };
      case "user_not_found":
        return { status: 404, error: "user_not_found" };
      case "phone_already_in_use":
        return { status: 409, error: error.message };
      case "phone_unchanged":
        return { status: 409, error: error.message };
      case "otp_blocked":
      case "account_suspended":
      case "account_banned":
        return { status: 403, error: error.message };
      default:
        return { status: 500, error: "failed_to_request_otp" };
    }
  }

  extractVerifyOtpError(error: unknown): { status: number; error: string } {
    if (!(error instanceof Error)) {
      return { status: 500, error: "failed_to_verify_otp" };
    }

    switch (error.message) {
      case "invalid_phone":
      case "invalid_otp_code":
        return { status: 400, error: error.message === "invalid_otp_code" ? "invalid_otp_code" : "invalid_phone" };
      case "otp_not_found":
      case "otp_invalid":
      case "otp_expired":
      case "otp_attempts_exceeded":
        return { status: 400, error: error.message };
      case "phone_already_in_use":
      case "phone_unchanged":
        return { status: 409, error: error.message };
      case "user_not_found":
        return { status: 404, error: error.message };
      case "account_suspended":
      case "account_banned":
      case "otp_blocked":
        return { status: 403, error: error.message };
      default:
        return { status: 500, error: "failed_to_verify_otp" };
    }
  }

  buildRequestContext(req: Request): { ipAddress: string | null } {
    return {
      ipAddress: getRequestIp(req)
    };
  }
}

export const otpService = new OtpService();
