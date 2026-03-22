CREATE TYPE "ScheduledMessageStatus" AS ENUM (
  'PENDING',
  'PROCESSING',
  'SENT',
  'CANCELED',
  'FAILED'
);

CREATE TABLE "ScheduledMessage" (
  "id" TEXT NOT NULL,
  "chatId" TEXT NOT NULL,
  "senderId" TEXT NOT NULL,
  "text" TEXT NOT NULL,
  "silent" BOOLEAN NOT NULL DEFAULT FALSE,
  "scheduledFor" TIMESTAMP(3) NOT NULL,
  "status" "ScheduledMessageStatus" NOT NULL DEFAULT 'PENDING',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "sentAt" TIMESTAMP(3),
  "canceledAt" TIMESTAMP(3),
  "lastError" TEXT,
  "deliveredMessageId" TEXT,
  CONSTRAINT "ScheduledMessage_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ScheduledMessage_chatId_fkey" FOREIGN KEY ("chatId") REFERENCES "Chat"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "ScheduledMessage_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "ScheduledMessage_status_scheduledFor_idx"
  ON "ScheduledMessage"("status", "scheduledFor");

CREATE INDEX "ScheduledMessage_chatId_senderId_status_scheduledFor_idx"
  ON "ScheduledMessage"("chatId", "senderId", "status", "scheduledFor");
