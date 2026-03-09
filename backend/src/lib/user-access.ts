import type { UserAccountStatusValue } from "./admin-types.js";
import { prisma } from "./prisma.js";

const prismaUser = (prisma as unknown as { user: any }).user;

export interface UserAccessState {
  id: string;
  accountStatus: UserAccountStatusValue;
  otpBlocked: boolean;
  sendRestricted: boolean;
  callRestricted: boolean;
}

export async function getUserAccessState(userId: string): Promise<UserAccessState | null> {
  return prismaUser.findUnique({
    where: { id: userId },
    select: {
      id: true,
      accountStatus: true,
      otpBlocked: true,
      sendRestricted: true,
      callRestricted: true
    }
  });
}

export async function requireUserAccessState(userId: string): Promise<UserAccessState> {
  const state = await getUserAccessState(userId);
  if (!state) {
    throw new Error("user_not_found");
  }
  return state;
}

export function getAccountAccessError(
  state: Pick<UserAccessState, "accountStatus">
): "account_suspended" | "account_banned" | null {
  switch (state.accountStatus) {
    case "SUSPENDED":
      return "account_suspended";
    case "BANNED":
      return "account_banned";
    default:
      return null;
  }
}

export function assertUserCanAccessApp(state: UserAccessState): void {
  const error = getAccountAccessError(state);
  if (error) {
    throw new Error(error);
  }
}

export function assertUserCanUseOtp(state: UserAccessState): void {
  assertUserCanAccessApp(state);
  if (state.otpBlocked) {
    throw new Error("otp_blocked");
  }
}

export function assertUserCanSendMessages(state: UserAccessState): void {
  assertUserCanAccessApp(state);
  if (state.sendRestricted) {
    throw new Error("message_sending_restricted");
  }
}

export function assertUserCanStartOrAcceptCalls(state: UserAccessState): void {
  assertUserCanAccessApp(state);
  if (state.callRestricted) {
    throw new Error("calling_restricted");
  }
}

export async function assertUserCanAccessAppById(userId: string): Promise<UserAccessState> {
  const state = await requireUserAccessState(userId);
  assertUserCanAccessApp(state);
  return state;
}

export async function assertUserCanSendMessagesById(userId: string): Promise<UserAccessState> {
  const state = await requireUserAccessState(userId);
  assertUserCanSendMessages(state);
  return state;
}

export async function assertUserCanStartOrAcceptCallsById(userId: string): Promise<UserAccessState> {
  const state = await requireUserAccessState(userId);
  assertUserCanStartOrAcceptCalls(state);
  return state;
}
