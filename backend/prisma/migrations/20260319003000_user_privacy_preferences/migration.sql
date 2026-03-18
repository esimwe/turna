DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'UserPrivacyAudience') THEN
    CREATE TYPE "UserPrivacyAudience" AS ENUM (
      'EVERYONE',
      'MY_CONTACTS',
      'EXCLUDED_CONTACTS',
      'NOBODY',
      'ONLY_SHARED_WITH'
    );
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'UserPrivacyAudience') THEN
    ALTER TYPE "UserPrivacyAudience" ADD VALUE IF NOT EXISTS 'EVERYONE';
    ALTER TYPE "UserPrivacyAudience" ADD VALUE IF NOT EXISTS 'MY_CONTACTS';
    ALTER TYPE "UserPrivacyAudience" ADD VALUE IF NOT EXISTS 'EXCLUDED_CONTACTS';
    ALTER TYPE "UserPrivacyAudience" ADD VALUE IF NOT EXISTS 'NOBODY';
    ALTER TYPE "UserPrivacyAudience" ADD VALUE IF NOT EXISTS 'ONLY_SHARED_WITH';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'UserOnlineVisibility') THEN
    CREATE TYPE "UserOnlineVisibility" AS ENUM (
      'EVERYONE',
      'SAME_AS_LAST_SEEN'
    );
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'UserOnlineVisibility') THEN
    ALTER TYPE "UserOnlineVisibility" ADD VALUE IF NOT EXISTS 'EVERYONE';
    ALTER TYPE "UserOnlineVisibility" ADD VALUE IF NOT EXISTS 'SAME_AS_LAST_SEEN';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS "UserPrivacyPreference" (
  "userId" TEXT NOT NULL,
  "lastSeenMode" "UserPrivacyAudience" NOT NULL DEFAULT 'EVERYONE',
  "lastSeenTargetUserIds" JSONB,
  "onlineMode" "UserOnlineVisibility" NOT NULL DEFAULT 'EVERYONE',
  "profilePhotoMode" "UserPrivacyAudience" NOT NULL DEFAULT 'EVERYONE',
  "profilePhotoTargetUserIds" JSONB,
  "aboutMode" "UserPrivacyAudience" NOT NULL DEFAULT 'MY_CONTACTS',
  "aboutTargetUserIds" JSONB,
  "linksMode" "UserPrivacyAudience" NOT NULL DEFAULT 'MY_CONTACTS',
  "linksTargetUserIds" JSONB,
  "groupsMode" "UserPrivacyAudience" NOT NULL DEFAULT 'EVERYONE',
  "groupsTargetUserIds" JSONB,
  "statusAllowReshare" BOOLEAN NOT NULL DEFAULT FALSE,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "UserPrivacyPreference_pkey" PRIMARY KEY ("userId")
);

CREATE INDEX IF NOT EXISTS "UserPrivacyPreference_updatedAt_idx"
  ON "UserPrivacyPreference"("updatedAt" DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'UserPrivacyPreference_userId_fkey'
  ) THEN
    ALTER TABLE "UserPrivacyPreference"
      ADD CONSTRAINT "UserPrivacyPreference_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
