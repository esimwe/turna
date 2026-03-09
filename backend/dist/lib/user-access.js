import { prisma } from "./prisma.js";
const prismaUser = prisma.user;
export async function getUserAccessState(userId) {
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
export async function requireUserAccessState(userId) {
    const state = await getUserAccessState(userId);
    if (!state) {
        throw new Error("user_not_found");
    }
    return state;
}
export function getAccountAccessError(state) {
    switch (state.accountStatus) {
        case "SUSPENDED":
            return "account_suspended";
        case "BANNED":
            return "account_banned";
        default:
            return null;
    }
}
export function assertUserCanAccessApp(state) {
    const error = getAccountAccessError(state);
    if (error) {
        throw new Error(error);
    }
}
export function assertUserCanUseOtp(state) {
    assertUserCanAccessApp(state);
    if (state.otpBlocked) {
        throw new Error("otp_blocked");
    }
}
export function assertUserCanSendMessages(state) {
    assertUserCanAccessApp(state);
    if (state.sendRestricted) {
        throw new Error("message_sending_restricted");
    }
}
export function assertUserCanStartOrAcceptCalls(state) {
    assertUserCanAccessApp(state);
    if (state.callRestricted) {
        throw new Error("calling_restricted");
    }
}
export async function assertUserCanAccessAppById(userId) {
    const state = await requireUserAccessState(userId);
    assertUserCanAccessApp(state);
    return state;
}
export async function assertUserCanSendMessagesById(userId) {
    const state = await requireUserAccessState(userId);
    assertUserCanSendMessages(state);
    return state;
}
export async function assertUserCanStartOrAcceptCallsById(userId) {
    const state = await requireUserAccessState(userId);
    assertUserCanStartOrAcceptCalls(state);
    return state;
}
