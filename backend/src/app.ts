import cors from "cors";
import express from "express";
import helmet from "helmet";
import { fileURLToPath } from "url";
import { env } from "./config/env.js";
import { adminRouter } from "./modules/admin/routes.js";
import { authRouter } from "./modules/auth/routes.js";
import { chatRouter } from "./modules/chat/routes.js";
import { callRouter } from "./modules/calls/routes.js";
import { healthRouter } from "./modules/health/routes.js";
import { profileRouter } from "./modules/profile/routes.js";
import { pushRouter } from "./modules/push/routes.js";

export function createApp() {
  const app = express();
  const adminPublicDir = fileURLToPath(new URL("../public/admin", import.meta.url));

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

  app.use("/api", healthRouter);
  app.use("/api/auth", authRouter);
  app.use("/api/admin", adminRouter);
  app.use("/api/profile", profileRouter);
  app.use("/api/chats", chatRouter);
  app.use("/api/calls", callRouter);
  app.use("/api/push", pushRouter);

  return app;
}
