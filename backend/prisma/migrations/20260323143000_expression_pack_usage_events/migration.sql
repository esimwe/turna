-- CreateTable
CREATE TABLE "ExpressionPackUsageEvent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "packId" TEXT NOT NULL,
    "packVersion" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "assetType" TEXT NOT NULL,
    "surface" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ExpressionPackUsageEvent_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "ExpressionPackUsageEvent"
ADD CONSTRAINT "ExpressionPackUsageEvent_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateIndex
CREATE INDEX "ExpressionPackUsageEvent_packId_packVersion_createdAt_idx"
ON "ExpressionPackUsageEvent"("packId", "packVersion", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "ExpressionPackUsageEvent_itemId_createdAt_idx"
ON "ExpressionPackUsageEvent"("itemId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "ExpressionPackUsageEvent_userId_createdAt_idx"
ON "ExpressionPackUsageEvent"("userId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "ExpressionPackUsageEvent_surface_createdAt_idx"
ON "ExpressionPackUsageEvent"("surface", "createdAt" DESC);
