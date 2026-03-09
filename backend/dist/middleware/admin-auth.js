import { prisma } from "../lib/prisma.js";
import { verifyAdminAccessToken } from "../lib/jwt.js";
const prismaAdminUser = prisma.adminUser;
export async function requireAdminAuth(req, res, next) {
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
    }
    catch {
        res.status(401).json({ error: "invalid_admin_token" });
    }
}
export function requireAdminRole(...roles) {
    return (req, res, next) => {
        if (!req.adminRole || !roles.includes(req.adminRole)) {
            res.status(403).json({ error: "admin_forbidden" });
            return;
        }
        next();
    };
}
