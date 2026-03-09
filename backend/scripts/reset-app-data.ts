import {
  DeleteObjectsCommand,
  ListObjectsV2Command,
  S3Client
} from "@aws-sdk/client-s3";

const args = new Set(process.argv.slice(2));
const dryRun = args.has("--dry-run");
const includeAdmin = args.has("--include-admin");
const yes = args.has("--yes");
const showHelp = args.has("--help") || args.has("-h");

let env: any;
let prisma: any;
let prismaClient: any;
let redis: any;

if (showHelp) {
  console.log(`
Turna uygulama verisini sifirlar.

Varsayilan:
- kullanicilar
- mesajlar
- sohbetler
- aramalar
- raporlar
- OTP/session/device kayitlari
- Redis OTP key'leri
- R2 icindeki avatars/ ve chat-media/ dosyalari
silinir.

Korunanlar:
- admin kullanicilari
- admin audit loglari
- feature flags
- country policies

Kullanim:
  npm --prefix backend run reset:app-data -- --dry-run
  npm --prefix backend run reset:app-data -- --yes
  npm --prefix backend run reset:app-data -- --yes --include-admin
`);
  process.exit(0);
}

if (!dryRun && !yes) {
  console.error(
    "Bu islem yikicidir. Calistirmak icin --yes ekle. Once --dry-run ile kontrol et."
  );
  process.exit(1);
}

function hasR2Config(): boolean {
  return Boolean(
    env.R2_BUCKET &&
      env.R2_ENDPOINT &&
      env.R2_ACCESS_KEY_ID &&
      env.R2_SECRET_ACCESS_KEY
  );
}

function getR2Client(): S3Client {
  return new S3Client({
    region: "auto",
    endpoint: env.R2_ENDPOINT,
    forcePathStyle: true,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID!,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY!
    }
  });
}

async function listAllKeysByPrefix(
  client: S3Client,
  bucket: string,
  prefix: string
): Promise<string[]> {
  const keys: string[] = [];
  let continuationToken: string | undefined;

  do {
    const response = await client.send(
      new ListObjectsV2Command({
        Bucket: bucket,
        Prefix: prefix,
        ContinuationToken: continuationToken
      })
    );

    for (const item of response.Contents ?? []) {
      if (item.Key) {
        keys.push(item.Key);
      }
    }

    continuationToken = response.IsTruncated
      ? response.NextContinuationToken
      : undefined;
  } while (continuationToken);

  return keys;
}

async function deleteKeys(
  client: S3Client,
  bucket: string,
  keys: string[]
): Promise<number> {
  let deleted = 0;
  for (let index = 0; index < keys.length; index += 1000) {
    const chunk = keys.slice(index, index + 1000);
    if (chunk.length === 0) continue;

    await client.send(
      new DeleteObjectsCommand({
        Bucket: bucket,
        Delete: {
          Objects: chunk.map((key) => ({ Key: key })),
          Quiet: true
        }
      })
    );
    deleted += chunk.length;
  }
  return deleted;
}

async function deleteRedisKeysByPrefix(prefix: string): Promise<number> {
  let deleted = 0;
  let cursor = "0";

  do {
    const [nextCursor, keys] = await redis.scan(
      cursor,
      "MATCH",
      `${prefix}*`,
      "COUNT",
      200
    );
    cursor = nextCursor;
    if (keys.length > 0) {
      deleted += await redis.del(...keys);
    }
  } while (cursor !== "0");

  return deleted;
}

async function collectSummary() {
  const [
    users,
    chats,
    messages,
    attachments,
    calls,
    reports,
    sessions,
    otpCodes,
    deviceTokens,
    chatFolders,
    userContacts,
    admins,
    adminAuditLogs,
    featureFlags,
    countryPolicies
  ] = await Promise.all([
    prismaClient.user.count(),
    prismaClient.chat.count(),
    prismaClient.message.count(),
    prismaClient.messageAttachment.count(),
    prismaClient.call.count(),
    prismaClient.reportCase.count(),
    prismaClient.authSession.count(),
    prismaClient.otpCode.count(),
    prismaClient.deviceToken.count(),
    prismaClient.chatFolder.count(),
    prismaClient.userContact.count(),
    prismaClient.adminUser.count(),
    prismaClient.adminAuditLog.count(),
    prismaClient.featureFlag.count(),
    prismaClient.countryPolicy.count()
  ]);

  return {
    users,
    chats,
    messages,
    attachments,
    calls,
    reports,
    sessions,
    otpCodes,
    deviceTokens,
    chatFolders,
    userContacts,
    admins,
    adminAuditLogs,
    featureFlags,
    countryPolicies
  };
}

async function wipeDatabase() {
  const operations = [
    prismaClient.reportCase.deleteMany({}),
    prismaClient.callEvent.deleteMany({}),
    prismaClient.call.deleteMany({}),
    prismaClient.messageAttachment.deleteMany({}),
    prismaClient.message.deleteMany({}),
    prismaClient.chatMember.deleteMany({}),
    prismaClient.chatFolder.deleteMany({}),
    prismaClient.userContact.deleteMany({}),
    prismaClient.chat.deleteMany({}),
    prismaClient.userBlock.deleteMany({}),
    prismaClient.deviceToken.deleteMany({}),
    prismaClient.authSession.deleteMany({}),
    prismaClient.otpCode.deleteMany({}),
    prismaClient.user.deleteMany({})
  ];

  if (includeAdmin) {
    operations.push(
      prismaClient.adminAuditLog.deleteMany({}),
      prismaClient.featureFlag.deleteMany({}),
      prismaClient.countryPolicy.deleteMany({}),
      prismaClient.adminUser.deleteMany({})
    );
  }

  await prisma.$transaction(operations);
}

async function main() {
  const envModule = await import("../src/config/env.js");
  const prismaModule = await import("../src/lib/prisma.js");
  const redisModule = await import("../src/lib/redis.js");

  env = envModule.env;
  prisma = prismaModule.prisma;
  prismaClient = prisma as any;
  redis = redisModule.redis;

  console.log("Turna reset basliyor...");
  console.log(`Mod: ${dryRun ? "dry-run" : "apply"}`);
  console.log(`Admin korunacak: ${includeAdmin ? "hayir" : "evet"}`);

  const before = await collectSummary();
  console.table(before);

  let r2AvatarKeys = 0;
  let r2ChatMediaKeys = 0;

  if (hasR2Config()) {
    const client = getR2Client();
    const bucket = env.R2_BUCKET!;
    const [avatarKeys, chatMediaKeys] = await Promise.all([
      listAllKeysByPrefix(client, bucket, "avatars/"),
      listAllKeysByPrefix(client, bucket, "chat-media/")
    ]);

    r2AvatarKeys = avatarKeys.length;
    r2ChatMediaKeys = chatMediaKeys.length;

    console.table({
      r2Avatars: r2AvatarKeys,
      r2ChatMedia: r2ChatMediaKeys
    });

    if (!dryRun) {
      const deletedAvatarKeys = await deleteKeys(client, bucket, avatarKeys);
      const deletedChatMediaKeys = await deleteKeys(
        client,
        bucket,
        chatMediaKeys
      );
      console.table({
        deletedR2Avatars: deletedAvatarKeys,
        deletedR2ChatMedia: deletedChatMediaKeys
      });
    }
  } else {
    console.log("R2 config yok; R2 temizligi atlandi.");
  }

  if (!dryRun) {
    await wipeDatabase();
    const deletedOtpRedisKeys = await deleteRedisKeysByPrefix("otp:");
    console.table({ deletedOtpRedisKeys });

    const after = await collectSummary();
    console.table(after);
    console.log("Turna uygulama verisi sifirlandi.");
  } else {
    console.log("Dry-run tamamlandi. Gercek silme icin --yes ile tekrar calistir.");
  }
}

main()
  .catch((error) => {
    console.error("Reset basarisiz:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await prisma.$disconnect();
    } catch {}
    try {
      if (redis.status !== "end") {
        await redis.quit();
      }
    } catch {}
  });
