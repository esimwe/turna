import path from "node:path";
import cors from "cors";
import express from "express";
import helmet from "helmet";
import { fileURLToPath } from "url";
import { env } from "./config/env.js";
import { adminRouter } from "./modules/admin/routes.js";
import { authRouter } from "./modules/auth/routes.js";
import { chatRouter } from "./modules/chat/routes.js";
import { callRouter } from "./modules/calls/routes.js";
import { communityRouter } from "./modules/community/routes.js";
import { healthRouter } from "./modules/health/routes.js";
import { profileRouter } from "./modules/profile/routes.js";
import { pushRouter } from "./modules/push/routes.js";
import { statusRouter } from "./modules/status/routes.js";

export function createApp() {
  const app = express();
  const adminPublicDir = fileURLToPath(new URL("../public/admin", import.meta.url));
  const webPublicDir = fileURLToPath(new URL("../public/web", import.meta.url));
  const webIndexFile = path.join(webPublicDir, "index.html");

  if (env.TRUST_PROXY) {
    app.set("trust proxy", 1);
  }

  app.disable("x-powered-by");
  app.use(helmet());
  app.use(cors({ origin: env.CORS_ORIGIN === "*" ? true : env.CORS_ORIGIN }));
  if (env.FORCE_HTTPS) {
    app.use((req, res, next) => {
      const forwardedProto = req.header("x-forwarded-proto")?.split(",")[0]?.trim();
      if (req.secure || forwardedProto === "https") {
        next();
        return;
      }

      if (req.method === "GET" || req.method === "HEAD") {
        res.redirect(308, `https://${req.get("host")}${req.originalUrl}`);
        return;
      }

      res.status(426).json({ error: "https_required" });
    });
  }
  app.use("/api/calls/livekit/webhook", express.text({ type: "*/*", limit: "256kb" }));
  app.use(express.json({ limit: "2mb" }));
  app.use("/admin", express.static(adminPublicDir));
  app.use("/web", express.static(webPublicDir, { index: false }));

  app.use("/api", healthRouter);
  app.use("/api/auth", authRouter);
  app.use("/api/admin", adminRouter);
  app.use("/api/profile", profileRouter);
  app.use("/api/chats", chatRouter);
  app.use("/api/calls", callRouter);
  app.use("/api/communities", communityRouter);
  app.use("/api/push", pushRouter);
  app.use("/api/statuses", statusRouter);
  app.get("/web", (_req, res) => {
    res.sendFile(webIndexFile);
  });
  app.get("/web/*", (req, res, next) => {
    if (path.extname(req.path)) {
      next();
      return;
    }
    res.sendFile(webIndexFile);
  });
  app.use((req, res, next) => {
    const host = (req.hostname || req.get("host") || "").split(":")[0].toLowerCase();
    if (!host.startsWith("web.")) {
      next();
      return;
    }
    if (
      req.path.startsWith("/api") ||
      req.path.startsWith("/admin") ||
      req.path.startsWith("/socket.io") ||
      req.path.startsWith("/web")
    ) {
      next();
      return;
    }
    if (req.method !== "GET" && req.method !== "HEAD") {
      next();
      return;
    }
    if (path.extname(req.path)) {
      next();
      return;
    }
    res.sendFile(webIndexFile);
  });

  return app;
}
