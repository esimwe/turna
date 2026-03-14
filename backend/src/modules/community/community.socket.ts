import type { Server, Socket } from "socket.io";
import { z } from "zod";
import { prisma } from "../../lib/prisma.js";
import { assertUserCanAccessAppById } from "../../lib/user-access.js";
import { logError, logInfo } from "../../lib/logger.js";
import { communityChannelRoom } from "./community.realtime.js";

const prismaCommunity = (prisma as unknown as { community: any }).community;
const prismaCommunityChannel = (prisma as unknown as { communityChannel: any }).communityChannel;

const joinCommunityChannelSchema = z.object({
  communityId: z.string().trim().min(1).max(255),
  channelId: z.string().trim().min(1).max(255)
});

async function findCommunityChannelAccess(
  communityIdOrSlug: string,
  channelIdOrSlug: string,
  userId: string
) {
  const community = await prismaCommunity.findFirst({
    where: {
      OR: [{ id: communityIdOrSlug }, { slug: communityIdOrSlug }]
    },
    select: {
      id: true,
      memberships: {
        where: { userId },
        select: { userId: true }
      }
    }
  });

  if (!community) {
    return { community: null, membership: null, channel: null };
  }

  const membership = community.memberships?.[0] ?? null;
  const channel = await prismaCommunityChannel.findFirst({
    where: {
      communityId: community.id,
      OR: [{ id: channelIdOrSlug }, { slug: channelIdOrSlug }]
    },
    select: {
      id: true,
      slug: true
    }
  });

  return { community, membership, channel };
}

export function registerCommunitySocket(io: Server): void {
  io.on("connection", (socket: Socket) => {
    const userId = typeof socket.data.userId === "string" ? (socket.data.userId as string) : null;
    if (!userId) {
      return;
    }

    socket.on("community:channel:join", async (payload) => {
      const parsed = joinCommunityChannelSchema.safeParse(payload);
      if (!parsed.success) {
        socket.emit("community:error", {
          code: "validation_error",
          details: parsed.error.flatten()
        });
        return;
      }

      try {
        await assertUserCanAccessAppById(userId);
        const access = await findCommunityChannelAccess(
          parsed.data.communityId,
          parsed.data.channelId,
          userId
        );

        if (!access.community) {
          socket.emit("community:error", { code: "community_not_found" });
          return;
        }
        if (!access.membership) {
          socket.emit("community:error", { code: "community_membership_required" });
          return;
        }
        if (!access.channel) {
          socket.emit("community:error", { code: "community_channel_not_found" });
          return;
        }

        socket.join(communityChannelRoom(access.channel.id));
        socket.emit("community:channel:joined", {
          communityId: access.community.id,
          channelId: access.channel.id,
          slug: access.channel.slug
        });
        logInfo("community:channel:join ok", {
          socketId: socket.id,
          userId,
          communityId: access.community.id,
          channelId: access.channel.id
        });
      } catch (error) {
        socket.emit("community:error", { code: "community_join_failed" });
        logError("community:channel:join failed", error);
      }
    });

    socket.on("community:channel:leave", (payload) => {
      const parsed = joinCommunityChannelSchema.safeParse(payload);
      if (!parsed.success) {
        return;
      }

      socket.leave(communityChannelRoom(parsed.data.channelId));
      logInfo("community:channel:leave ok", {
        socketId: socket.id,
        userId,
        communityId: parsed.data.communityId,
        channelId: parsed.data.channelId
      });
    });
  });
}
