DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ChatPolicyScope') THEN
    CREATE TYPE "ChatPolicyScope" AS ENUM (
      'OWNER_ONLY',
      'ADMIN_ONLY',
      'EDITOR_ONLY',
      'EVERYONE'
    );
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ChatPolicyScope') THEN
    ALTER TYPE "ChatPolicyScope" ADD VALUE IF NOT EXISTS 'OWNER_ONLY';
    ALTER TYPE "ChatPolicyScope" ADD VALUE IF NOT EXISTS 'ADMIN_ONLY';
    ALTER TYPE "ChatPolicyScope" ADD VALUE IF NOT EXISTS 'EDITOR_ONLY';
    ALTER TYPE "ChatPolicyScope" ADD VALUE IF NOT EXISTS 'EVERYONE';
  END IF;
END $$;

ALTER TABLE "Chat"
  ADD COLUMN IF NOT EXISTS "whoCanSend" "ChatPolicyScope" NOT NULL DEFAULT 'EVERYONE',
  ADD COLUMN IF NOT EXISTS "whoCanEditInfo" "ChatPolicyScope" NOT NULL DEFAULT 'EDITOR_ONLY',
  ADD COLUMN IF NOT EXISTS "whoCanInvite" "ChatPolicyScope" NOT NULL DEFAULT 'ADMIN_ONLY',
  ADD COLUMN IF NOT EXISTS "whoCanAddMembers" "ChatPolicyScope" NOT NULL DEFAULT 'ADMIN_ONLY',
  ADD COLUMN IF NOT EXISTS "historyVisibleToNewMembers" BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE "Chat"
SET "whoCanAddMembers" = CASE
  WHEN "memberAddPolicy"::text = 'OWNER_ONLY' THEN 'OWNER_ONLY'::"ChatPolicyScope"
  WHEN "memberAddPolicy"::text = 'ADMIN_ONLY' THEN 'ADMIN_ONLY'::"ChatPolicyScope"
  WHEN "memberAddPolicy"::text = 'EDITOR_ONLY' THEN 'EDITOR_ONLY'::"ChatPolicyScope"
  ELSE 'EVERYONE'::"ChatPolicyScope"
END
WHERE "type" = 'GROUP';
