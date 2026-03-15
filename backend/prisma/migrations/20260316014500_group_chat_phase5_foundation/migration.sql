CREATE TABLE IF NOT EXISTS "MessageMention" (
  "messageId" TEXT NOT NULL,
  "mentionedUserId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MessageMention_pkey" PRIMARY KEY ("messageId", "mentionedUserId")
);

CREATE INDEX IF NOT EXISTS "MessageMention_mentionedUserId_createdAt_idx"
  ON "MessageMention"("mentionedUserId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "MessageReaction" (
  "messageId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "emoji" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MessageReaction_pkey" PRIMARY KEY ("messageId", "userId", "emoji")
);

CREATE INDEX IF NOT EXISTS "MessageReaction_messageId_createdAt_idx"
  ON "MessageReaction"("messageId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "MessageReaction_userId_createdAt_idx"
  ON "MessageReaction"("userId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "ChatPinnedMessage" (
  "chatId" TEXT NOT NULL,
  "messageId" TEXT NOT NULL,
  "pinnedByUserId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "unpinnedAt" TIMESTAMP(3),
  CONSTRAINT "ChatPinnedMessage_pkey" PRIMARY KEY ("chatId", "messageId")
);

CREATE INDEX IF NOT EXISTS "ChatPinnedMessage_chatId_unpinnedAt_createdAt_idx"
  ON "ChatPinnedMessage"("chatId", "unpinnedAt", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ChatPinnedMessage_messageId_idx"
  ON "ChatPinnedMessage"("messageId");
CREATE INDEX IF NOT EXISTS "ChatPinnedMessage_pinnedByUserId_createdAt_idx"
  ON "ChatPinnedMessage"("pinnedByUserId", "createdAt" DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'MessageMention_messageId_fkey'
  ) THEN
    ALTER TABLE "MessageMention"
      ADD CONSTRAINT "MessageMention_messageId_fkey"
      FOREIGN KEY ("messageId") REFERENCES "Message"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'MessageMention_mentionedUserId_fkey'
  ) THEN
    ALTER TABLE "MessageMention"
      ADD CONSTRAINT "MessageMention_mentionedUserId_fkey"
      FOREIGN KEY ("mentionedUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'MessageReaction_messageId_fkey'
  ) THEN
    ALTER TABLE "MessageReaction"
      ADD CONSTRAINT "MessageReaction_messageId_fkey"
      FOREIGN KEY ("messageId") REFERENCES "Message"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'MessageReaction_userId_fkey'
  ) THEN
    ALTER TABLE "MessageReaction"
      ADD CONSTRAINT "MessageReaction_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatPinnedMessage_chatId_fkey'
  ) THEN
    ALTER TABLE "ChatPinnedMessage"
      ADD CONSTRAINT "ChatPinnedMessage_chatId_fkey"
      FOREIGN KEY ("chatId") REFERENCES "Chat"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatPinnedMessage_messageId_fkey'
  ) THEN
    ALTER TABLE "ChatPinnedMessage"
      ADD CONSTRAINT "ChatPinnedMessage_messageId_fkey"
      FOREIGN KEY ("messageId") REFERENCES "Message"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatPinnedMessage_pinnedByUserId_fkey'
  ) THEN
    ALTER TABLE "ChatPinnedMessage"
      ADD CONSTRAINT "ChatPinnedMessage_pinnedByUserId_fkey"
      FOREIGN KEY ("pinnedByUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
