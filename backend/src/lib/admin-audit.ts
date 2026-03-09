import { prisma } from "./prisma.js";

const prismaAdminAuditLog = (prisma as unknown as { adminAuditLog: any }).adminAuditLog;

export async function writeAdminAuditLog(input: {
  actorAdminId: string;
  action: string;
  targetType: string;
  targetId?: string | null;
  reason?: string | null;
  metadata?: unknown;
}): Promise<void> {
  const metadata =
    input.metadata === undefined ? undefined : JSON.parse(JSON.stringify(input.metadata));

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
