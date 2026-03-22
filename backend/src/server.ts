import { createServer } from "http";
import { createAdapter } from "@socket.io/redis-adapter";
import { Server } from "socket.io";
import { createApp } from "./app.js";
import { env } from "./config/env.js";
import { logError, logInfo, logWarn } from "./lib/logger.js";
import { createRedisConnection, redis } from "./lib/redis.js";
import { attachChatRealtime } from "./modules/chat/chat.realtime.js";
import { startScheduledMessageDispatcher } from "./modules/chat/chat.scheduled.js";
import { registerChatSocket } from "./modules/chat/chat.socket.js";
import { attachCommunityRealtime } from "./modules/community/community.realtime.js";
import { registerCommunitySocket } from "./modules/community/community.socket.js";

const app = createApp();
const httpServer = createServer(app);

const io = new Server(httpServer, {
  cors: {
    origin: env.CORS_ORIGIN === "*" ? true : env.CORS_ORIGIN,
    methods: ["GET", "POST"]
  }
});

attachChatRealtime(io);
attachCommunityRealtime(io);
registerChatSocket(io);
registerCommunitySocket(io);

async function configureRedisBackedRealtime(): Promise<void> {
  try {
    await redis.connect();
    logInfo("redis connected");

    const pubClient = createRedisConnection();
    const subClient = pubClient.duplicate();
    await Promise.all([pubClient.connect(), subClient.connect()]);

    io.adapter(createAdapter(pubClient, subClient));
    logInfo("socket.io redis adapter configured");
  } catch (err: unknown) {
    logError("redis connect failed", err);
    logWarn("socket.io redis adapter unavailable, falling back to single-node realtime");
  }
}

async function bootstrapServer(): Promise<void> {
  await configureRedisBackedRealtime();
  startScheduledMessageDispatcher();
  httpServer.listen(env.PORT, env.BIND_HOST, () => {
    logInfo(`backend listening on ${env.BIND_HOST}:${env.PORT}`);
  });
}

void bootstrapServer();
