ALTER TABLE "Chat"
  ADD COLUMN IF NOT EXISTS "messageExpirationSeconds" INTEGER,
  ADD COLUMN IF NOT EXISTS "usesDefaultMessageExpiration" BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE "Message"
  ADD COLUMN IF NOT EXISTS "expiresAt" TIMESTAMP(3);

ALTER TABLE "UserPrivacyPreference"
  ADD COLUMN IF NOT EXISTS "defaultMessageExpirationSeconds" INTEGER;

CREATE INDEX IF NOT EXISTS "Message_chatId_expiresAt_idx"
  ON "Message"("chatId", "expiresAt");
