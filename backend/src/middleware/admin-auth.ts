import type { NextFunction, Request, Response } from "express";
import { prisma } from "../lib/prisma.js";
import type { AdminRoleValue } from "../lib/admin-types.js";
import { verifyAdminAccessToken } from "../lib/jwt.js";

const prismaAdminUser = (prisma as unknown as { adminUser: any }).adminUser;

declare global {
  namespace Express {
    interface Request {
      adminUserId?: string;
      adminRole?: AdminRoleValue;
    }
  }
}

export async function requireAdminAuth(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authorization = req.header("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    res.status(401).json({ error: "admin_unauthorized" });
    return;
  }

  const token = authorization.replace("Bearer ", "").trim();

  try {
    const claims = verifyAdminAccessToken(token);
    const admin = await prismaAdminUser.findUnique({
      where: { id: claims.sub },
      select: { id: true, role: true, isActive: true }
    });

    if (!admin || !admin.isActive) {
      res.status(401).json({ error: "admin_not_found" });
      return;
    }

    req.adminUserId = admin.id;
    req.adminRole = admin.role;
    next();
  } catch {
    res.status(401).json({ error: "invalid_admin_token" });
  }
}

export function requireAdminRole(...roles: AdminRoleValue[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.adminRole || !roles.includes(req.adminRole)) {
      res.status(403).json({ error: "admin_forbidden" });
      return;
    }
    next();
  };
}
