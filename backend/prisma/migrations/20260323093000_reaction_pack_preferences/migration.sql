ALTER TABLE "User"
ADD COLUMN "moodEmoji" TEXT;

CREATE TABLE "UserReactionPreference" (
  "userId" TEXT NOT NULL,
  "installedPackIds" JSONB,
  "favoriteEmojis" JSONB,
  "recentEmojis" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "UserReactionPreference_pkey" PRIMARY KEY ("userId"),
  CONSTRAINT "UserReactionPreference_userId_fkey" FOREIGN KEY ("userId")
    REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "UserReactionPreference_updatedAt_idx"
ON "UserReactionPreference"("updatedAt" DESC);

CREATE TABLE "ReactionPackUsageEvent" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "packId" TEXT NOT NULL,
  "emoji" TEXT NOT NULL,
  "surface" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "ReactionPackUsageEvent_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ReactionPackUsageEvent_userId_fkey" FOREIGN KEY ("userId")
    REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "ReactionPackUsageEvent_packId_createdAt_idx"
ON "ReactionPackUsageEvent"("packId", "createdAt" DESC);

CREATE INDEX "ReactionPackUsageEvent_userId_createdAt_idx"
ON "ReactionPackUsageEvent"("userId", "createdAt" DESC);

CREATE INDEX "ReactionPackUsageEvent_surface_createdAt_idx"
ON "ReactionPackUsageEvent"("surface", "createdAt" DESC);

