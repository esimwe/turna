DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'ChatJoinRequestStatus'
  ) THEN
    CREATE TYPE "ChatJoinRequestStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS "ChatInviteLink" (
  "id" TEXT NOT NULL,
  "chatId" TEXT NOT NULL,
  "createdByUserId" TEXT NOT NULL,
  "token" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3),
  "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ChatInviteLink_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ChatInviteLink_token_key" ON "ChatInviteLink"("token");
CREATE INDEX IF NOT EXISTS "ChatInviteLink_chatId_createdAt_idx" ON "ChatInviteLink"("chatId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ChatInviteLink_createdByUserId_createdAt_idx" ON "ChatInviteLink"("createdByUserId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "ChatJoinRequest" (
  "id" TEXT NOT NULL,
  "chatId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "status" "ChatJoinRequestStatus" NOT NULL DEFAULT 'PENDING',
  "reviewedByUserId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "reviewedAt" TIMESTAMP(3),
  CONSTRAINT "ChatJoinRequest_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ChatJoinRequest_chatId_userId_status_key"
  ON "ChatJoinRequest"("chatId", "userId", "status");
CREATE INDEX IF NOT EXISTS "ChatJoinRequest_chatId_status_createdAt_idx"
  ON "ChatJoinRequest"("chatId", "status", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ChatJoinRequest_userId_createdAt_idx"
  ON "ChatJoinRequest"("userId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "ChatMute" (
  "id" TEXT NOT NULL,
  "chatId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "mutedByUserId" TEXT NOT NULL,
  "reason" TEXT,
  "mutedUntil" TIMESTAMP(3),
  "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ChatMute_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "ChatMute_chatId_userId_revokedAt_mutedUntil_idx"
  ON "ChatMute"("chatId", "userId", "revokedAt", "mutedUntil");
CREATE INDEX IF NOT EXISTS "ChatMute_userId_createdAt_idx"
  ON "ChatMute"("userId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "ChatBan" (
  "id" TEXT NOT NULL,
  "chatId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "bannedByUserId" TEXT NOT NULL,
  "reason" TEXT,
  "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ChatBan_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "ChatBan_chatId_userId_revokedAt_idx"
  ON "ChatBan"("chatId", "userId", "revokedAt");
CREATE INDEX IF NOT EXISTS "ChatBan_userId_createdAt_idx"
  ON "ChatBan"("userId", "createdAt" DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatInviteLink_chatId_fkey'
  ) THEN
    ALTER TABLE "ChatInviteLink"
      ADD CONSTRAINT "ChatInviteLink_chatId_fkey"
      FOREIGN KEY ("chatId") REFERENCES "Chat"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatInviteLink_createdByUserId_fkey'
  ) THEN
    ALTER TABLE "ChatInviteLink"
      ADD CONSTRAINT "ChatInviteLink_createdByUserId_fkey"
      FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatJoinRequest_chatId_fkey'
  ) THEN
    ALTER TABLE "ChatJoinRequest"
      ADD CONSTRAINT "ChatJoinRequest_chatId_fkey"
      FOREIGN KEY ("chatId") REFERENCES "Chat"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatJoinRequest_userId_fkey'
  ) THEN
    ALTER TABLE "ChatJoinRequest"
      ADD CONSTRAINT "ChatJoinRequest_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatJoinRequest_reviewedByUserId_fkey'
  ) THEN
    ALTER TABLE "ChatJoinRequest"
      ADD CONSTRAINT "ChatJoinRequest_reviewedByUserId_fkey"
      FOREIGN KEY ("reviewedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatMute_chatId_fkey'
  ) THEN
    ALTER TABLE "ChatMute"
      ADD CONSTRAINT "ChatMute_chatId_fkey"
      FOREIGN KEY ("chatId") REFERENCES "Chat"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatMute_userId_fkey'
  ) THEN
    ALTER TABLE "ChatMute"
      ADD CONSTRAINT "ChatMute_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatMute_mutedByUserId_fkey'
  ) THEN
    ALTER TABLE "ChatMute"
      ADD CONSTRAINT "ChatMute_mutedByUserId_fkey"
      FOREIGN KEY ("mutedByUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatBan_chatId_fkey'
  ) THEN
    ALTER TABLE "ChatBan"
      ADD CONSTRAINT "ChatBan_chatId_fkey"
      FOREIGN KEY ("chatId") REFERENCES "Chat"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatBan_userId_fkey'
  ) THEN
    ALTER TABLE "ChatBan"
      ADD CONSTRAINT "ChatBan_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatBan_bannedByUserId_fkey'
  ) THEN
    ALTER TABLE "ChatBan"
      ADD CONSTRAINT "ChatBan_bannedByUserId_fkey"
      FOREIGN KEY ("bannedByUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
