ALTER TABLE "Chat"
ADD COLUMN "defaultMessageExpirationUserId" TEXT;

CREATE INDEX "Chat_type_usesDefaultMessageExpiration_defaultMessageExpirationUserId_idx"
ON "Chat"("type", "usesDefaultMessageExpiration", "defaultMessageExpirationUserId");
