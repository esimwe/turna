import { createServer } from "http";
import { Server } from "socket.io";
import { createApp } from "./app.js";
import { env } from "./config/env.js";
import { logError, logInfo } from "./lib/logger.js";
import { redis } from "./lib/redis.js";
import { attachChatRealtime } from "./modules/chat/chat.realtime.js";
import { registerChatSocket } from "./modules/chat/chat.socket.js";
const app = createApp();
const httpServer = createServer(app);
const io = new Server(httpServer, {
    cors: {
        origin: env.CORS_ORIGIN === "*" ? true : env.CORS_ORIGIN,
        methods: ["GET", "POST"]
    }
});
attachChatRealtime(io);
registerChatSocket(io);
redis.connect().then(() => logInfo("redis connected")).catch((err) => logError("redis connect failed", err));
httpServer.listen(env.PORT, () => {
    logInfo(`backend listening on :${env.PORT}`);
});
