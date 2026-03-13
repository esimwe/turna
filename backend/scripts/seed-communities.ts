import "dotenv/config";
import { prisma } from "../src/lib/prisma.js";

const prismaCommunity = (prisma as unknown as { community: any }).community;
const prismaCommunityChannel = (prisma as unknown as { communityChannel: any }).communityChannel;
const prismaCommunityMembership = (prisma as unknown as { communityMembership: any }).communityMembership;
const prismaUser = (prisma as unknown as { user: any }).user;

const args = process.argv.slice(2);

function readArg(name: string): string | null {
  const index = args.indexOf(name);
  if (index < 0) return null;
  return args[index + 1]?.trim() || null;
}

const username = readArg("--username");
const userId = readArg("--user-id");

const communityDefinitions = [
  {
    slug: "girisim-kulubu",
    name: "Girişim Kulübü",
    tagline: "Kurucular, ürün ekipleri ve growth odaklı sohbetler",
    description:
      "Startup kurucuları, growth ekipleri ve ürün insanları için canlı sohbet, soru-cevap ve kaynak alanı.",
    emoji: "🚀",
    coverGradientFrom: "#8BE0B3",
    coverGradientTo: "#7EC8F8",
    welcomeTitle: "Kurucular burada birbirini hızlandırır",
    welcomeDescription:
      "Önce tanışma kanalına kısa bir giriş bırak, sonra sorular alanında ihtiyacın olan konuyu aç.",
    entryChecklist: [
      "Kendini tanıt ve ne inşa ettiğini paylaş.",
      "İlgilendiğin growth veya ürün başlığını takip et.",
      "Bir soruya cevap vererek görünür olmaya başla."
    ],
    rules: [
      "Link bırakmadan önce kısa bağlam ver.",
      "DM istemeden önce ortak kanal etkileşimi kur.",
      "Yatırım ve satış vaatlerinde net ol, spam yapma."
    ],
    channels: [
      {
        slug: "genel",
        name: "Genel",
        description: "Topluluğun ana sohbet alanı",
        type: "CHAT",
        sortOrder: 1,
        isDefault: true
      },
      {
        slug: "tanisma",
        name: "Tanışma",
        description: "Yeni gelenler burada kendini tanıtır",
        type: "CHAT",
        sortOrder: 2,
        isDefault: false
      },
      {
        slug: "sorular",
        name: "Sorular",
        description: "Yapılandırılmış soru-cevap alanı",
        type: "QUESTION",
        sortOrder: 3,
        isDefault: false
      }
    ]
  },
  {
    slug: "tasarim-evi",
    name: "Tasarım Evi",
    tagline: "UI, marka ve sistem tasarımı odaklı topluluk",
    description:
      "Arayüz, marka, motion ve tasarım sistemi alanlarında çalışan kişiler için düzenli topluluk alanı.",
    emoji: "🎨",
    coverGradientFrom: "#F39A82",
    coverGradientTo: "#F6D36E",
    welcomeTitle: "İşlerin değil, düşünme biçimin de görünür olsun",
    welcomeDescription:
      "Case paylaş, geri bildirim iste ve kaynaklar alanındaki sabit içeriklerden akışı kaçırma.",
    entryChecklist: [
      "Tanışma mesajında uzmanlık alanını yaz.",
      "Kaynaklar kanalındaki başlangıç setini incele.",
      "Bir tasarım problemine geri bildirim bırak."
    ],
    rules: [
      "Eleştiriyi somut ve saygılı ver.",
      "Portfolyo paylaşırken hedefini açık yaz.",
      "Duyurular kanalı dışında promosyon yapma."
    ],
    channels: [
      {
        slug: "genel",
        name: "Genel",
        description: "Tasarım sohbetleri",
        type: "CHAT",
        sortOrder: 1,
        isDefault: true
      },
      {
        slug: "duyurular",
        name: "Duyurular",
        description: "Yalnızca ekip duyuruları",
        type: "ANNOUNCEMENT",
        sortOrder: 2,
        isDefault: false
      },
      {
        slug: "kaynaklar",
        name: "Kaynaklar",
        description: "Sabit tasarım kaynakları",
        type: "RESOURCE",
        sortOrder: 3,
        isDefault: false
      }
    ]
  },
  {
    slug: "ai-circle",
    name: "AI Circle",
    tagline: "Araçlar, workflow ve üretkenlik odaklı AI topluluğu",
    description:
      "AI araçları, prompt workflow'ları ve yeni model kullanımları için canlı ve düzenli community alanı.",
    emoji: "🧠",
    coverGradientFrom: "#B8B4F8",
    coverGradientTo: "#7EC8F8",
    welcomeTitle: "Araç listesi değil, çalışan sistemler konuşulur",
    welcomeDescription:
      "Kullandığın workflow'u paylaş, soru aç ve etkinlikler alanından canlı oturumları takip et.",
    entryChecklist: [
      "En sık kullandığın AI aracını yaz.",
      "Workflow kanalında bir akış sorusu aç veya cevapla.",
      "Etkinlikler alanından bir oturumu takvime ekle."
    ],
    rules: [
      "Model çıktısını bağlamsız paylaşma.",
      "Gizli veri içeren prompt veya ekran görüntüsü atma.",
      "Abartılı performans iddialarını kanıtsız yayma."
    ],
    channels: [
      {
        slug: "genel",
        name: "Genel",
        description: "AI sohbetlerinin ana alanı",
        type: "CHAT",
        sortOrder: 1,
        isDefault: true
      },
      {
        slug: "workflow",
        name: "Workflow",
        description: "Kullanılan akışlar ve sistemler",
        type: "QUESTION",
        sortOrder: 2,
        isDefault: false
      },
      {
        slug: "etkinlikler",
        name: "Etkinlikler",
        description: "Canlı yayın ve buluşma alanı",
        type: "EVENT",
        sortOrder: 3,
        isDefault: false
      }
    ]
  }
] as const;

async function resolveTargetUser(): Promise<{ id: string } | null> {
  if (userId) {
    return prismaUser.findUnique({
      where: { id: userId },
      select: { id: true }
    });
  }

  if (username) {
    return prismaUser.findFirst({
      where: { username },
      select: { id: true }
    });
  }

  return null;
}

async function main() {
  const targetUser = await resolveTargetUser();

  for (const definition of communityDefinitions) {
    const community = await prismaCommunity.upsert({
      where: { slug: definition.slug },
      update: {
        name: definition.name,
        tagline: definition.tagline,
        description: definition.description,
        emoji: definition.emoji,
        coverGradientFrom: definition.coverGradientFrom,
        coverGradientTo: definition.coverGradientTo,
        welcomeTitle: definition.welcomeTitle,
        welcomeDescription: definition.welcomeDescription,
        entryChecklist: definition.entryChecklist,
        rules: definition.rules,
        isListed: true,
        visibility: "PUBLIC"
      },
      create: {
        slug: definition.slug,
        name: definition.name,
        tagline: definition.tagline,
        description: definition.description,
        emoji: definition.emoji,
        coverGradientFrom: definition.coverGradientFrom,
        coverGradientTo: definition.coverGradientTo,
        welcomeTitle: definition.welcomeTitle,
        welcomeDescription: definition.welcomeDescription,
        entryChecklist: definition.entryChecklist,
        rules: definition.rules,
        isListed: true,
        visibility: "PUBLIC"
      },
      select: { id: true, slug: true, name: true }
    });

    await prismaCommunityChannel.deleteMany({
      where: { communityId: community.id }
    });

    await prismaCommunityChannel.createMany({
      data: definition.channels.map((channel) => ({
        communityId: community.id,
        slug: channel.slug,
        name: channel.name,
        description: channel.description,
        type: channel.type,
        sortOrder: channel.sortOrder,
        isDefault: channel.isDefault
      }))
    });

    if (targetUser) {
      await prismaCommunityMembership.upsert({
        where: {
          communityId_userId: {
            communityId: community.id,
            userId: targetUser.id
          }
        },
        update: {},
        create: {
          communityId: community.id,
          userId: targetUser.id,
          role: definition.slug === "girisim-kulubu" ? "MENTOR" : "MEMBER"
        }
      });
    }

    console.log(`seeded community: ${community.slug}`);
  }

  if (targetUser) {
    console.log(`joined seeded communities for user: ${targetUser.id}`);
  } else {
    console.log("seeded communities without memberships");
  }
}

main()
  .catch((error) => {
    console.error("community seed failed", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
