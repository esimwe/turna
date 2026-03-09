import { prisma } from "./prisma.js";
const prismaUserBlock = prisma.userBlock;
export async function areUsersBlocked(userAId, userBId) {
    if (!userAId || !userBId || userAId === userBId) {
        return false;
    }
    const match = await prismaUserBlock.findFirst({
        where: {
            OR: [
                { blockerId: userAId, blockedUserId: userBId },
                { blockerId: userBId, blockedUserId: userAId }
            ]
        },
        select: { blockerId: true }
    });
    return Boolean(match);
}
export async function isUserBlockedBy(blockerId, blockedUserId) {
    if (!blockerId || !blockedUserId || blockerId === blockedUserId) {
        return false;
    }
    const match = await prismaUserBlock.findUnique({
        where: {
            blockerId_blockedUserId: {
                blockerId,
                blockedUserId
            }
        },
        select: { blockerId: true }
    });
    return Boolean(match);
}
export async function setUserBlocked(blockerId, blockedUserId, blocked) {
    if (!blockerId || !blockedUserId || blockerId === blockedUserId) {
        throw new Error("invalid_block_target");
    }
    if (blocked) {
        await prismaUserBlock.upsert({
            where: {
                blockerId_blockedUserId: {
                    blockerId,
                    blockedUserId
                }
            },
            create: {
                blockerId,
                blockedUserId
            },
            update: {}
        });
        return true;
    }
    await prismaUserBlock.deleteMany({
        where: {
            blockerId,
            blockedUserId
        }
    });
    return false;
}
export async function getBlockedUserIdsByUser(blockerId, candidateUserIds) {
    if (!blockerId || candidateUserIds.length === 0) {
        return new Set();
    }
    const rows = await prismaUserBlock.findMany({
        where: {
            blockerId,
            blockedUserId: { in: candidateUserIds }
        },
        select: { blockedUserId: true }
    });
    return new Set(rows.map((row) => row.blockedUserId));
}
