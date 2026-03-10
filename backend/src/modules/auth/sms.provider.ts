import { Buffer } from "buffer";
import { env } from "../../config/env.js";
import { logError, logInfo } from "../../lib/logger.js";

type OtpPurpose = "LOGIN" | "PHONE_CHANGE";
type OtpProviderKind = "MOCK" | "NETGSM_BULK";

interface SendOtpCodeInput {
  phone: string;
  code: string;
  purpose: OtpPurpose;
}

interface SendOtpCodeResult {
  provider: OtpProviderKind;
}

const NETGSM_BULK_URL = "https://api.netgsm.com.tr/sms/rest/v2/send";

function formatNetgsmPhone(phone: string): string {
  const digits = phone.replace(/\D+/g, "");

  if (/^90(5\d{9})$/.test(digits)) {
    return digits.slice(2);
  }

  if (/^0(5\d{9})$/.test(digits)) {
    return digits.slice(1);
  }

  if (/^5\d{9}$/.test(digits)) {
    return digits;
  }

  throw new Error("invalid_phone");
}

function buildOtpMessage(code: string): string {
  const ttlMinutes = Math.max(1, Math.ceil(env.OTP_TTL_SECONDS / 60));
  return `Turna kodunuz: ${code}. Bu kod ${ttlMinutes} dakika gecerlidir.`;
}

function requireNetgsmConfig(): {
  usercode: string;
  password: string;
  msgheader: string;
} {
  if (!env.NETGSM_USERCODE || !env.NETGSM_PASSWORD || !env.NETGSM_HEADER) {
    throw new Error("otp_provider_not_configured");
  }

  return {
    usercode: env.NETGSM_USERCODE,
    password: env.NETGSM_PASSWORD,
    msgheader: env.NETGSM_HEADER
  };
}

function buildBasicAuth(usercode: string, password: string): string {
  return `Basic ${Buffer.from(`${usercode}:${password}`, "utf8").toString("base64")}`;
}

function parseJson(text: string): Record<string, unknown> | null {
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function sendNetgsmBulkOtp(input: SendOtpCodeInput): Promise<SendOtpCodeResult> {
  const config = requireNetgsmConfig();
  const no = formatNetgsmPhone(input.phone);
  const body = {
    msgheader: config.msgheader,
    messages: [
      {
        msg: buildOtpMessage(input.code),
        no
      }
    ],
    encoding: "TR"
  };

  const requestId = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;

  try {
    const response = await fetch(NETGSM_BULK_URL, {
      method: "POST",
      headers: {
        Authorization: buildBasicAuth(config.usercode, config.password),
        "Content-Type": "application/json",
        Accept: "application/json"
      },
      body: JSON.stringify(body)
    });

    const raw = await response.text();
    const parsed = parseJson(raw);
    const code = typeof parsed?.code === "string" ? parsed.code : null;

    if (!response.ok || code !== "00") {
      logError("netgsm bulk otp send failed", {
        requestId,
        status: response.status,
        response: parsed ?? raw
      });
      throw new Error("otp_provider_request_failed");
    }

    logInfo("netgsm bulk otp queued", {
      requestId,
      jobId: parsed?.jobid,
      phoneSuffix: no.slice(-4),
      purpose: input.purpose
    });

    return { provider: "NETGSM_BULK" };
  } catch (error) {
    if (error instanceof Error && error.message === "otp_provider_request_failed") {
      throw error;
    }

    logError("netgsm bulk otp request error", {
      requestId,
      error
    });
    throw new Error("otp_provider_request_failed");
  }
}

export async function sendOtpCode(input: SendOtpCodeInput): Promise<SendOtpCodeResult> {
  if (env.FIXED_OTP_CODE) {
    return { provider: "MOCK" };
  }

  if (env.SMS_PROVIDER !== "netgsm_bulk") {
    throw new Error("otp_provider_not_configured");
  }

  return sendNetgsmBulkOtp(input);
}
