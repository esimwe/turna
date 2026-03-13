import 'package:flutter/material.dart';

class CommunityShellPreviewPage extends StatefulWidget {
  const CommunityShellPreviewPage({super.key, this.onTurnaTap});

  final VoidCallback? onTurnaTap;

  @override
  State<CommunityShellPreviewPage> createState() =>
      _CommunityShellPreviewPageState();
}

class _CommunityShellPreviewPageState extends State<CommunityShellPreviewPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _CommunityHomePage(),
      const _CommunityExplorePage(),
      _CommunityTurnaReturnPage(onTap: widget.onTurnaTap),
      const _CommunityNotificationsPage(),
      const _CommunityMyCommunitiesPage(),
    ];

    return Scaffold(
      backgroundColor: _CommunityUiTokens.background,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInOut,
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedIndex),
          child: pages[_selectedIndex],
        ),
      ),
      bottomNavigationBar: _CommunityBottomBar(
        selectedIndex: _selectedIndex,
        onSelect: (index) {
          if (index == 2 && widget.onTurnaTap != null) {
            widget.onTurnaTap!.call();
            return;
          }
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}

class _CommunityUiTokens {
  static const background = Color(0xFFF7F8F4);
  static const surface = Colors.white;
  static const surfaceSoft = Color(0xFFF1F4EC);
  static const border = Color(0xFFE2E7DA);
  static const text = Color(0xFF182018);
  static const textMuted = Color(0xFF6C756B);

  static const mint = Color(0xFF7BC6A4);
  static const sky = Color(0xFF7EC8F8);
  static const sun = Color(0xFFF6D36E);
  static const coral = Color(0xFFF39A82);
  static const lavender = Color(0xFFB8B4F8);

  static const success = Color(0xFF39B97A);

  static const pagePadding = 20.0;
  static const sectionGap = 24.0;
  static const cardRadius = 24.0;
  static const chipRadius = 999.0;

  static List<BoxShadow> get softShadow => const [
    BoxShadow(color: Color(0x12000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

class _CommunityHomePage extends StatelessWidget {
  const _CommunityHomePage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              _CommunityUiTokens.pagePadding,
              12,
              _CommunityUiTokens.pagePadding,
              140,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _CommunityHeroCard(),
                const SizedBox(height: 18),
                const _CommunityProfileCompletionCard(),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '✨',
                  title: 'Sana uygun topluluklar',
                  actionLabel: 'Tümünü gör',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 182,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const [
                      _CommunityCard(
                        emoji: '🚀',
                        title: 'Girişim Kulübü',
                        subtitle: 'Kurucular, growth ve ürün sohbetleri',
                        accent: _CommunityUiTokens.sky,
                      ),
                      SizedBox(width: 12),
                      _CommunityCard(
                        emoji: '🎨',
                        title: 'Tasarım Evi',
                        subtitle: 'UI, marka ve yaratıcı işler',
                        accent: _CommunityUiTokens.coral,
                      ),
                      SizedBox(width: 12),
                      _CommunityCard(
                        emoji: '🧠',
                        title: 'AI Circle',
                        subtitle: 'Araçlar, workflow ve yeni modeller',
                        accent: _CommunityUiTokens.lavender,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '🔥',
                  title: 'Bugün hareketli',
                ),
                const SizedBox(height: 12),
                const _CommunityDiscussionCard(
                  title: 'İlk topluluk onboarding akışı nasıl kurgulanmalı?',
                  meta: '29 mesaj  •  8 yeni cevap',
                  tag: 'Sorular',
                  accent: _CommunityUiTokens.sun,
                ),
                const SizedBox(height: 12),
                const _CommunityDiscussionCard(
                  title: 'Freelance ekip kurarken rol dağılımı',
                  meta: '14 mesaj  •  3 yeni thread',
                  tag: 'Networking',
                  accent: _CommunityUiTokens.mint,
                ),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '📅',
                  title: 'Yaklaşan etkinlikler',
                ),
                const SizedBox(height: 12),
                const _CommunityEventCard(),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '🤝',
                  title: 'Yeni kişiler',
                  actionLabel: 'Dizine git',
                ),
                const SizedBox(height: 12),
                const _CommunityMemberTile(
                  emoji: '🪄',
                  name: 'Selin T.',
                  role: 'Ürün tasarımcısı',
                  subtitle: 'İstanbul  •  Tasarım, AI, growth',
                ),
                const SizedBox(height: 10),
                const _CommunityMemberTile(
                  emoji: '🚀',
                  name: 'Emir K.',
                  role: 'Startup kurucusu',
                  subtitle: 'Ankara  •  SaaS, satış, ekip kurma',
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityExplorePage extends StatelessWidget {
  const _CommunityExplorePage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          _CommunityUiTokens.pagePadding,
          12,
          _CommunityUiTokens.pagePadding,
          140,
        ),
        children: const [
          _CommunityPageTitle(
            title: 'Keşfet',
            subtitle: 'İlgi alanına göre topluluk bul',
          ),
          SizedBox(height: 18),
          _CommunitySearchField(),
          SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CommunityChip(label: '🚀 Girişim'),
              _CommunityChip(label: '🎨 Tasarım'),
              _CommunityChip(label: '🧠 AI'),
              _CommunityChip(label: '💼 Kariyer'),
              _CommunityChip(label: '🌍 Networking'),
              _CommunityChip(label: '📚 Eğitim'),
            ],
          ),
          SizedBox(height: _CommunityUiTokens.sectionGap),
          _CommunitySectionHeader(emoji: '🌟', title: 'Öne çıkan topluluklar'),
          SizedBox(height: 12),
          _WideCommunityCard(
            emoji: '💸',
            title: 'Yatırım Masası',
            subtitle: 'Melek yatırım, fonlar ve girişim finansmanı',
            stats: '12.4K üye  •  188 aktif bugün',
            accent: _CommunityUiTokens.sun,
          ),
          SizedBox(height: 12),
          _WideCommunityCard(
            emoji: '📚',
            title: 'No-code Atölye',
            subtitle: 'Araç önerileri, otomasyon ve canlı incelemeler',
            stats: '4.3K üye  •  62 aktif bugün',
            accent: _CommunityUiTokens.sky,
          ),
          SizedBox(height: 12),
          _WideCommunityCard(
            emoji: '🎤',
            title: 'Creator Lounge',
            subtitle: 'İçerik üretimi, video formatı ve büyüme',
            stats: '6.1K üye  •  74 aktif bugün',
            accent: _CommunityUiTokens.coral,
          ),
        ],
      ),
    );
  }
}

class _CommunityNotificationsPage extends StatelessWidget {
  const _CommunityNotificationsPage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          _CommunityUiTokens.pagePadding,
          12,
          _CommunityUiTokens.pagePadding,
          140,
        ),
        children: const [
          _CommunityPageTitle(
            title: 'Bildirimler',
            subtitle: 'Topluluk hareketleri burada',
          ),
          SizedBox(height: 18),
          _NotificationTile(
            emoji: '🔥',
            title: 'Threadine 8 yeni cevap geldi',
            subtitle: 'AI Circle  •  5 dk önce',
          ),
          SizedBox(height: 12),
          _NotificationTile(
            emoji: '🤝',
            title: 'Yeni mesaj isteği',
            subtitle: 'Girişim Kulübü içinden Selin sana ulaştı',
          ),
          SizedBox(height: 12),
          _NotificationTile(
            emoji: '📅',
            title: 'Etkinlik yarın başlıyor',
            subtitle: 'Creator Lounge  •  Canlı yayın oturumu',
          ),
          SizedBox(height: 12),
          _NotificationTile(
            emoji: '📌',
            title: 'Yeni yönetici duyurusu',
            subtitle: 'Tasarım Evi  •  Haftalık özet paylaşıldı',
          ),
        ],
      ),
    );
  }
}

class _CommunityMyCommunitiesPage extends StatelessWidget {
  const _CommunityMyCommunitiesPage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          _CommunityUiTokens.pagePadding,
          12,
          _CommunityUiTokens.pagePadding,
          140,
        ),
        children: const [
          _CommunityPageTitle(
            title: 'Topluluklarım',
            subtitle: 'Dahil olduğun alanlar',
          ),
          SizedBox(height: 18),
          _WideCommunityCard(
            emoji: '🚀',
            title: 'Girişim Kulübü',
            subtitle: 'Kurucu, growth ve ürün ekipleri',
            stats: 'Rolün: Mentor  •  31 yeni mesaj',
            accent: _CommunityUiTokens.sky,
          ),
          SizedBox(height: 12),
          _WideCommunityCard(
            emoji: '🎨',
            title: 'Tasarım Evi',
            subtitle: 'UI, branding ve tasarım sistemi',
            stats: 'Rolün: Üye  •  9 yeni mesaj',
            accent: _CommunityUiTokens.coral,
          ),
          SizedBox(height: 12),
          _WideCommunityCard(
            emoji: '🧠',
            title: 'AI Circle',
            subtitle: 'Araçlar, prompt akışları, otomasyon',
            stats: 'Rolün: Admin  •  17 yeni mesaj',
            accent: _CommunityUiTokens.lavender,
          ),
        ],
      ),
    );
  }
}

class _CommunityTurnaReturnPage extends StatelessWidget {
  const _CommunityTurnaReturnPage({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(_CommunityUiTokens.pagePadding),
          child: _SurfaceCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: _CommunityUiTokens.surfaceSoft,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('💬', style: TextStyle(fontSize: 34)),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Turna moduna dön',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Community içindeki istekler kabul olunca birebir sohbetler burada devam eder.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: _CommunityUiTokens.text,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Turna moduna geç'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityHeroCard extends StatelessWidget {
  const _CommunityHeroCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF8F2), Color(0xFFF8F2E7)],
        ),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('🌿', style: TextStyle(fontSize: 18)),
                SizedBox(width: 8),
                Text(
                  'Community',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Bugün hangi toplulukta görünmek istiyorsun?',
              style: TextStyle(
                fontSize: 29,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.text,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Canlı sohbet, sorular, kaynaklar ve güvenli networking aynı akışta.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _CommunityMetricPill(label: '🔥 12 aktif oda'),
                _CommunityMetricPill(label: '📅 3 etkinlik'),
                _CommunityMetricPill(label: '🤝 5 yeni kişi'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityProfileCompletionCard extends StatelessWidget {
  const _CommunityProfileCompletionCard();

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🧩', style: TextStyle(fontSize: 18)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Community profiline son dokunuş',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
              ),
              Text(
                '%72',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _CommunityUiTokens.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              value: 0.72,
              minHeight: 8,
              backgroundColor: _CommunityUiTokens.surfaceSoft,
              color: _CommunityUiTokens.success,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Uzmanlık alanı ve ilgi alanlarını tamamla. Topluluklara katılım ve mesaj isteği için gerekli.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityPageTitle extends StatelessWidget {
  const _CommunityPageTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w700,
            color: _CommunityUiTokens.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            color: _CommunityUiTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class _CommunitySectionHeader extends StatelessWidget {
  const _CommunitySectionHeader({
    required this.emoji,
    required this.title,
    this.actionLabel,
  });

  final String emoji;
  final String title;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.text,
            ),
          ),
        ),
        if (actionLabel != null)
          Text(
            actionLabel!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
      ],
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 222,
      child: _SurfaceCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WideCommunityCard extends StatelessWidget {
  const _WideCommunityCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.stats,
    required this.accent,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final String stats;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  stats,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityDiscussionCard extends StatelessWidget {
  const _CommunityDiscussionCard({
    required this.title,
    required this.meta,
    required this.tag,
    required this.accent,
  });

  final String title;
  final String meta;
  final String tag;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommunityChip(
            label: tag,
            backgroundColor: accent.withValues(alpha: 0.16),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            meta,
            style: const TextStyle(
              fontSize: 13,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityEventCard extends StatelessWidget {
  const _CommunityEventCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6EFD9), Color(0xFFF4F8EA)],
        ),
        borderRadius: BorderRadius.circular(_CommunityUiTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎙️ Canlı oturum',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Topluluk onboarding deneyimi nasıl tasarlanır?',
              style: TextStyle(
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Yarın 20:30  •  148 kişi katılıyor',
              style: TextStyle(
                fontSize: 13,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityMemberTile extends StatelessWidget {
  const _CommunityMemberTile({
    required this.emoji,
    required this.name,
    required this.role,
    required this.subtitle,
  });

  final String emoji;
  final String name;
  final String role;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _CommunityUiTokens.surfaceSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: _CommunityUiTokens.textMuted,
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  final String emoji;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _CommunityUiTokens.surfaceSoft,
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunitySearchField extends StatelessWidget {
  const _CommunitySearchField();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _CommunityUiTokens.border),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: _CommunityUiTokens.textMuted),
            SizedBox(width: 10),
            Text(
              'Topluluk, konu veya kişi ara',
              style: TextStyle(
                fontSize: 14,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityMetricPill extends StatelessWidget {
  const _CommunityMetricPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _CommunityUiTokens.text,
          ),
        ),
      ),
    );
  }
}

class _CommunityChip extends StatelessWidget {
  const _CommunityChip({required this.label, this.backgroundColor});

  final String label;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? _CommunityUiTokens.surfaceSoft,
        borderRadius: BorderRadius.circular(_CommunityUiTokens.chipRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _CommunityUiTokens.text,
          ),
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _CommunityUiTokens.surface,
        borderRadius: BorderRadius.circular(_CommunityUiTokens.cardRadius),
        border: Border.all(color: _CommunityUiTokens.border),
        boxShadow: _CommunityUiTokens.softShadow,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _CommunityBottomBar extends StatelessWidget {
  const _CommunityBottomBar({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = <({String emoji, String label})>[
      (emoji: '🏡', label: 'Ana Sayfa'),
      (emoji: '🧭', label: 'Keşfet'),
      (emoji: '💬', label: 'Turna'),
      (emoji: '🔔', label: 'Bildirimler'),
      (emoji: '🌿', label: 'Topluluklarım'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _CommunityUiTokens.border),
            boxShadow: _CommunityUiTokens.softShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: List<Widget>.generate(items.length, (index) {
                final item = items[index];
                final selected = index == selectedIndex;
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onSelect(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? _CommunityUiTokens.surfaceSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: _CommunityUiTokens.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
