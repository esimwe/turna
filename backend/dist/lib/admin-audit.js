import { prisma } from "./prisma.js";
const prismaAdminAuditLog = prisma.adminAuditLog;
export async function writeAdminAuditLog(input) {
    const metadata = input.metadata === undefined ? undefined : JSON.parse(JSON.stringify(input.metadata));
    await prismaAdminAuditLog.create({
        data: {
            actorAdminId: input.actorAdminId,
            action: input.action,
            targetType: input.targetType,
            targetId: input.targetId ?? null,
            reason: input.reason ?? null,
            metadata
        }
    });
}
