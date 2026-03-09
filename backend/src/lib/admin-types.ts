export const ADMIN_ROLES = [
  "SUPER_ADMIN",
  "OPS_ADMIN",
  "SUPPORT_ADMIN",
  "MODERATOR",
  "ANALYST"
] as const;

export type AdminRoleValue = (typeof ADMIN_ROLES)[number];

export const USER_ACCOUNT_STATUSES = ["ACTIVE", "SUSPENDED", "BANNED"] as const;

export type UserAccountStatusValue = (typeof USER_ACCOUNT_STATUSES)[number];

export const REPORT_TARGET_TYPES = ["USER", "MESSAGE"] as const;

export type ReportTargetTypeValue = (typeof REPORT_TARGET_TYPES)[number];

export const REPORT_STATUSES = [
  "OPEN",
  "UNDER_REVIEW",
  "ACTIONED",
  "REJECTED",
  "RESOLVED"
] as const;

export type ReportStatusValue = (typeof REPORT_STATUSES)[number];

export const SMS_PROVIDERS = ["NETGSM_BULK", "NETGSM_OTP", "MOCK"] as const;

export type SmsProviderValue = (typeof SMS_PROVIDERS)[number];
