part of '../../app/turna_app.dart';

Future<_PreparedComposerAttachment> _prepareTurnaProfileAvatarUpload(
  XFile file,
) async {
  final seed = buildTurnaMediaComposerSeed(
    file,
    forcedKind: ChatAttachmentKind.image,
  );
  if (seed == null) {
    throw TurnaApiException('Desteklenmeyen görsel formatı.');
  }
  return _prepareTurnaInlineImageAttachment(
    seed,
    quality: MediaComposerQuality.standard,
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionUpdated,
    required this.onLogout,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final void Function(AuthSession session) onSessionUpdated;
  final VoidCallback onLogout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TurnaUserProfile _profile;
  int _allStarredMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _profile = _profileFromSession(widget.session);
    unawaited(_loadCachedProfile());
    unawaited(_loadStarredMessageCount());
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _profile = _profileFromSession(widget.session, previous: _profile);
    if (oldWidget.session.userId != widget.session.userId ||
        oldWidget.session.token != widget.session.token) {
      unawaited(_loadCachedProfile());
      unawaited(_loadStarredMessageCount());
    }
  }

  TurnaUserProfile _profileFromSession(
    AuthSession session, {
    TurnaUserProfile? previous,
  }) {
    return buildTurnaSelfProfileFromSession(session, previous: previous);
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    setState(() {
      _profile = _profileFromSession(widget.session, previous: _profile);
    });
    unawaited(_loadStarredMessageCount());
  }

  Future<void> _openProfileEditor() async {
    await _openPage(
      ProfilePage(
        session: widget.session,
        initialProfile: _profile,
        onProfileUpdated: widget.onSessionUpdated,
        onSessionExpired: widget.onLogout,
      ),
    );
  }

  Future<void> _loadCachedProfile() async {
    final cached = await TurnaProfileLocalCache.loadSelfProfile(widget.session);
    if (!mounted || cached == null) return;
    setState(() {
      _profile = _profileFromSession(widget.session, previous: cached);
    });
  }

  Future<void> _loadStarredMessageCount() async {
    ChatInboxData? inbox = TurnaChatInboxLocalCache.peek(widget.session.userId);
    inbox ??= await TurnaChatInboxLocalCache.load(widget.session.userId);
    final chatIds = inbox?.chats.map((chat) => chat.chatId) ?? const <String>[];
    final starred = await TurnaStarredMessagesLocalCache.loadAll(
      widget.session.userId,
      knownChatIds: chatIds,
    );
    if (!mounted) return;
    setState(() {
      _allStarredMessageCount = starred.values.fold<int>(
        0,
        (sum, ids) => sum + ids.length,
      );
    });
  }

  Widget _buildSectionPanel(List<_SettingsMenuAction> actions) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 0,
              ),
              leading: Icon(
                actions[index].icon,
                color: TurnaColors.textMuted,
                size: 21,
              ),
              title: Text(
                actions[index].label,
                style: TextStyle(
                  color: TurnaColors.text,
                  fontSize: 16.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((actions[index].trailingText ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        actions[index].trailingText!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: TurnaColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black.withValues(alpha: 0.34),
                  ),
                ],
              ),
              onTap: actions[index].onTap,
            ),
            if (index != actions.length - 1)
              Divider(
                height: 1,
                indent: 58,
                endIndent: 18,
                color: Colors.black.withValues(alpha: 0.06),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final about = _profile.about?.trim();
    final statusText = (about != null && about.isNotEmpty)
        ? about
        : 'Şu anki ruh halim';
    final displayName = _profile.displayName;
    final avatarUrl = resolveTurnaSessionAvatarUrl(
      widget.session,
      overrideAvatarUrl: _profile.avatarUrl,
    );

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {},
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.search_rounded, size: 23),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {},
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [TurnaColors.shadowSoft],
                ),
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _openProfileEditor,
              borderRadius: BorderRadius.circular(32),
              child: Column(
                children: [
                  _ProfileAvatar(
                    label: displayName,
                    avatarUrl: avatarUrl,
                    authToken: widget.session.token,
                    radius: 44,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: TurnaColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                'Ayarlar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TurnaColors.textMuted,
                ),
              ),
            ),
            _buildSectionPanel([
              _SettingsMenuAction(
                icon: Icons.campaign_outlined,
                label: 'Toplu mesajlar',
                onTap: () =>
                    _openPage(const PlaceholderPage(title: 'Toplu mesajlar')),
              ),
              _SettingsMenuAction(
                icon: Icons.star_border_rounded,
                label: 'Yıldızlı',
                trailingText: _allStarredMessageCount > 0
                    ? '$_allStarredMessageCount'
                    : null,
                onTap: () => _openPage(
                  TurnaStarredMessagesPage(
                    session: widget.session,
                    callCoordinator: widget.callCoordinator,
                    onSessionExpired: widget.onLogout,
                  ),
                ),
              ),
              _SettingsMenuAction(
                icon: Icons.devices_outlined,
                label: 'Bağlı cihazlar',
                onTap: () => _openPage(
                  TurnaLinkedDevicesPage(
                    session: widget.session,
                    onSessionExpired: widget.onLogout,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            _buildSectionPanel([
              _SettingsMenuAction(
                icon: Icons.key_outlined,
                label: 'Hesap',
                onTap: () => _openPage(const AccountPage()),
              ),
              _SettingsMenuAction(
                icon: Icons.lock_outline_rounded,
                label: 'Gizlilik',
                onTap: () => _openPage(
                  TurnaPrivacyPage(
                    session: widget.session,
                    onSessionExpired: widget.onLogout,
                  ),
                ),
              ),
              _SettingsMenuAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Sohbetler',
                onTap: () =>
                    _openPage(const PlaceholderPage(title: 'Sohbetler')),
              ),
              _SettingsMenuAction(
                icon: Icons.notifications_none_rounded,
                label: 'Bildirimler',
                onTap: () =>
                    _openPage(const PlaceholderPage(title: 'Bildirimler')),
              ),
              _SettingsMenuAction(
                icon: Icons.swap_vert_rounded,
                label: 'Depolama ve veriler',
                onTap: () => _openPage(
                  const PlaceholderPage(title: 'Depolama ve veriler'),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            _buildSectionPanel([
              _SettingsMenuAction(
                icon: Icons.help_outline_rounded,
                label: 'Yardım ve geri bildirim',
                onTap: () => _openPage(
                  const PlaceholderPage(title: 'Yardım ve geri bildirim'),
                ),
              ),
              _SettingsMenuAction(
                icon: Icons.person_add_alt_1_outlined,
                label: 'Arkadaşlarınızı davet edin',
                onTap: () => _openPage(
                  const PlaceholderPage(title: 'Arkadaşlarınızı davet edin'),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Cikis yap'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE25241),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TurnaPaymentToolsPage extends StatelessWidget {
  const TurnaPaymentToolsPage({super.key});

  static const List<_TurnaPaymentToolItem> _tools = [
    _TurnaPaymentToolItem(
      title: 'Taksi Öde',
      shortDescription: '@username veya plaka ile ödeme yapın',
      longDescription:
          'Taksiciye IBAN istemeden, @username veya plaka ile saniyeler içinde ödeme yapın.',
      icon: Icons.local_taxi,
      color: Color(0xFF2F80ED),
      status: 'Yakında',
    ),
    _TurnaPaymentToolItem(
      title: 'Kişiye Para Gönder',
      shortDescription: 'Rehberden veya @username ile para yollayın',
      longDescription:
          'Bir kişiye hesap numarası istemeden, rehberden seçerek ya da @username yazarak para gönderin.',
      icon: Icons.person_rounded,
      color: Color(0xFFF59E0B),
      status: 'Yakında',
    ),
    _TurnaPaymentToolItem(
      title: 'Ödeme İste',
      shortDescription: 'Sohbetten hızlıca ödeme talebi oluşturun',
      longDescription:
          'Bir kişiden ya da müşteriden ödeme istemek için tutarı yazın, talebi gönderin ve sohbet içinde takip edin.',
      icon: Icons.chat_bubble_rounded,
      color: Color(0xFF22C55E),
      status: 'Yakında',
    ),
    _TurnaPaymentToolItem(
      title: 'QR ile Öde',
      shortDescription: 'QR okutup fiziksel ödemeyi tamamlayın',
      longDescription:
          'Kasada veya masada QR kodu okutun, kart veya Turna Cüzdan ile ödemenizi hızlıca tamamlayın.',
      icon: Icons.qr_code_scanner_rounded,
      color: Color(0xFF7C3AED),
      status: 'Yakında',
    ),
  ];

  static const _TurnaPaymentToolItem _supportItem = _TurnaPaymentToolItem(
    title: 'Destek',
    shortDescription: 'Ödeme, şikayet ve hesap sorunları için',
    longDescription:
        'Hatalı para gönderimi, ödeme sorunları, şikayetler veya hesap güvenliği ile ilgili destek alın. Turna destek ekibi size yardımcı olur.',
    icon: Icons.support_agent,
    color: Color(0xFF64748B),
    status: 'Aktif',
  );

  Future<void> _showToolSheet(
    BuildContext context,
    _TurnaPaymentToolItem item,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(item.icon, color: item.color, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              color: TurnaColors.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _TurnaPaymentStatusChip(
                            label: item.status,
                            color: item.color,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  item.shortDescription,
                  style: const TextStyle(
                    color: TurnaColors.textSoft,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.longDescription,
                  style: const TextStyle(
                    color: TurnaColors.textMuted,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: item.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      item.status == 'Aktif'
                          ? 'Destek seçeneklerini görüntüle'
                          : 'Tamam',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: TurnaColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildToolCard(BuildContext context, _TurnaPaymentToolItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _showToolSheet(context, item),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [TurnaColors.shadowSoft],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(item.icon, color: item.color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: TurnaColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.shortDescription,
                          style: const TextStyle(
                            color: TurnaColors.textMuted,
                            fontSize: 13,
                            height: 1.22,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _TurnaPaymentStatusChip(
                        label: item.status,
                        color: item.color,
                      ),
                      const SizedBox(height: 10),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.black.withValues(alpha: 0.34),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          children: [
            const TurnaOdemeHeaderMock(),
            const SizedBox(height: 8),
            _buildSectionLabel('Araçlar'),
            for (final item in _tools) _buildToolCard(context, item),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: Colors.black.withValues(alpha: 0.12),
                      thickness: 1,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Destek',
                      style: TextStyle(
                        color: TurnaColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: Colors.black.withValues(alpha: 0.12),
                      thickness: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            _buildToolCard(context, _supportItem),
          ],
        ),
      ),
    );
  }
}

class TurnaOdemeHeaderMock extends StatefulWidget {
  const TurnaOdemeHeaderMock({super.key});

  @override
  State<TurnaOdemeHeaderMock> createState() => _TurnaOdemeHeaderMockState();
}

class _TurnaOdemeHeaderMockState extends State<TurnaOdemeHeaderMock> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F9FC),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Turna Ödeme',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
          _buildWalletButton(context),
        ],
      ),
    );
  }

  Widget _buildWalletButton(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showWalletModal(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8E6F5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 17,
              color: Color(0xFF2F80ED),
            ),
            SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Turna Cüzdan',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '0,00 ₺',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            SizedBox(width: 8),
            Icon(Icons.add_circle_rounded, size: 18, color: Color(0xFF00C2FF)),
          ],
        ),
      ),
    );
  }

  void _showWalletModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _WalletMockModal(),
    );
  }
}

enum WalletMethod { card, giftCode }

class _WalletMockModal extends StatefulWidget {
  const _WalletMockModal();

  @override
  State<_WalletMockModal> createState() => _WalletMockModalState();
}

class _WalletMockModalState extends State<_WalletMockModal> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _giftCodeController = TextEditingController();

  WalletMethod? _selectedMethod;
  bool _showAmountField = false;

  @override
  void dispose() {
    _amountController.dispose();
    _giftCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF38BDF8), Color(0xFF2F80ED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Turna Cüzdan',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Cüzdanınıza bakiye eklemek için bir yöntem seçin',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildMethodCard(
                      selected: _selectedMethod == WalletMethod.card,
                      icon: Icons.credit_card_rounded,
                      title: 'Banka / Kredi Kartı',
                      subtitle: 'Kartla bakiye yükleyin',
                      onTap: () {
                        setState(() {
                          _selectedMethod = WalletMethod.card;
                          _showAmountField = false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMethodCard(
                      selected: _selectedMethod == WalletMethod.giftCode,
                      icon: Icons.redeem_rounded,
                      title: 'Hediye Kodu',
                      subtitle: 'Kod ile bakiye tanımlayın',
                      onTap: () {
                        setState(() {
                          _selectedMethod = WalletMethod.giftCode;
                          _showAmountField = false;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _buildSelectedContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedContent() {
    switch (_selectedMethod) {
      case WalletMethod.card:
        return Column(
          key: const ValueKey('card-content'),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F6FEB), Color(0xFF163EA8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F2F80ED),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.credit_card_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  SizedBox(height: 24),
                  Text(
                    '**** **** **** 4242',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Turna Kart',
                          style: TextStyle(
                            color: Color(0xFFDCEBFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '12/28',
                        style: TextStyle(
                          color: Color(0xFFDCEBFF),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _buildActionTile(
              icon: Icons.add_card_rounded,
              title: 'Kart Ekle',
              subtitle: 'Yeni bir banka veya kredi kartı ekleyin',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mock kart ekleme ekranı')),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildActionTile(
              icon: Icons.autorenew_rounded,
              title: 'Otomatik Öde',
              subtitle: 'Yakında aktif olacak',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Otomatik Öde yakında aktif olacak'),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildActionTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Bakiye Ekle',
              subtitle: 'Cüzdana tutar yükleyin',
              onTap: () {
                setState(() {
                  _showAmountField = !_showAmountField;
                });
              },
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _showAmountField
                  ? Padding(
                      key: const ValueKey('amount-field'),
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Yüklenecek tutar',
                              prefixText: '₺ ',
                              filled: true,
                              fillColor: const Color(0xFFF7F9FC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E6F5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFF2F80ED),
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Mock ödeme ekranı'),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: const Color(0xFF2F80ED),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Şimdi Öde',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );

      case WalletMethod.giftCode:
        return Column(
          key: const ValueKey('gift-code-content'),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD8E6F5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hediye Kodu',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Size verilen hediye kodunu girerek Turna Cüzdan bakiyenize tanımlayabilirsiniz.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _giftCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Kodunuzu girin',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFD8E6F5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF2F80ED),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Mock hediye kodu uygulama ekranı'),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFF2F80ED),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Kodu Uygula',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      default:
        return Container(
          key: const ValueKey('empty-content'),
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD8E6F5)),
          ),
          child: const Text(
            'Devam etmek için bir yöntem seçin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
        );
    }
  }

  Widget _buildMethodCard({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFFEEF7FF) : const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2F80ED)
                  : const Color(0xFFD8E6F5),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF2F80ED), size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF2F80ED), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnaPaymentToolItem {
  const _TurnaPaymentToolItem({
    required this.title,
    required this.shortDescription,
    required this.longDescription,
    required this.icon,
    required this.color,
    required this.status,
  });

  final String title;
  final String shortDescription;
  final String longDescription;
  final IconData icon;
  final Color color;
  final String status;
}

class _TurnaPaymentStatusChip extends StatelessWidget {
  const _TurnaPaymentStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SessionAvatar extends StatelessWidget {
  const _SessionAvatar({required this.session, this.radius = 25});

  final AuthSession session;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return _ProfileAvatar(
      label: session.displayName,
      avatarUrl: resolveTurnaSessionAvatarUrl(session),
      authToken: session.token,
      radius: radius,
    );
  }
}

class _BottomProfileTabIcon extends StatelessWidget {
  const _BottomProfileTabIcon({required this.session, this.selected = false});

  final AuthSession session;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? TurnaColors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: _SessionAvatar(session: session, radius: 11),
    );
  }
}

class _BottomCommunityTabIcon extends StatelessWidget {
  const _BottomCommunityTabIcon({this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8BE0B3), Color(0xFF7EC8F8)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF7EC8F8,
            ).withValues(alpha: selected ? 0.28 : 0.18),
            blurRadius: selected ? 18 : 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: selected
            ? Border.all(color: TurnaColors.primary, width: 1.4)
            : null,
      ),
      child: const Center(
        child: Icon(Icons.groups_rounded, size: 22, color: Colors.white),
      ),
    );
  }
}

class _SettingsMenuAction {
  const _SettingsMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingText,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailingText;
}

class _TurnaBottomBar extends StatelessWidget {
  const _TurnaBottomBar({
    required this.selectedIndex,
    required this.unreadChats,
    required this.session,
    required this.onSelect,
  });

  final int selectedIndex;
  final int unreadChats;
  final AuthSession session;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Durum',
                selected: selectedIndex == 0,
                iconBuilder: (selected) => Icon(
                  Icons.circle_outlined,
                  size: 22,
                  color: selected ? TurnaColors.primary : TurnaColors.textMuted,
                ),
                onTap: () => onSelect(0),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Aramalar',
                selected: selectedIndex == 1,
                iconBuilder: (selected) => Icon(
                  Icons.call_outlined,
                  size: 22,
                  color: selected ? TurnaColors.primary : TurnaColors.textMuted,
                ),
                onTap: () => onSelect(1),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Community',
                selected: selectedIndex == 2,
                iconBuilder: (selected) =>
                    _BottomCommunityTabIcon(selected: selected),
                onTap: () => onSelect(2),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Sohbetler',
                selected: selectedIndex == 3,
                iconBuilder: (selected) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 22,
                      color: selected
                          ? TurnaColors.primary
                          : TurnaColors.textMuted,
                    ),
                    if (unreadChats > 0)
                      Positioned(
                        right: -18,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          constraints: const BoxConstraints(minWidth: 24),
                          decoration: BoxDecoration(
                            color: TurnaColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unreadChats > 999 ? '999+' : '$unreadChats',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () => onSelect(3),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Siz',
                selected: selectedIndex == 4,
                iconBuilder: (selected) =>
                    _BottomProfileTabIcon(session: session, selected: selected),
                onTap: () => onSelect(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnaBottomBarItem extends StatelessWidget {
  const _TurnaBottomBarItem({
    required this.label,
    required this.selected,
    required this.iconBuilder,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Widget Function(bool selected) iconBuilder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? TurnaColors.primary : TurnaColors.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 28, child: Center(child: iconBuilder(selected))),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnaCachedImage extends StatelessWidget {
  const _TurnaCachedImage({
    required this.cacheKey,
    required this.imageUrl,
    required this.fit,
    this.authToken,
    this.loading,
    this.error,
  });

  final String cacheKey;
  final String imageUrl;
  final String? authToken;
  final BoxFit fit;
  final Widget? loading;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    final cachedFile = TurnaLocalMediaCache.peek(cacheKey);
    if (cachedFile != null) {
      return Image.file(
        cachedFile,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            error ?? const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }

    return FutureBuilder<File?>(
      future: TurnaLocalMediaCache.getOrDownloadFile(
        cacheKey: cacheKey,
        url: imageUrl,
        authToken: authToken,
      ),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file != null) {
          return Image.file(
            file,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                error ?? const Center(child: Icon(Icons.broken_image_outlined)),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return loading ??
              const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        return error ?? const Center(child: Icon(Icons.broken_image_outlined));
      },
    );
  }
}

String _buildAvatarCacheKey(String imageUrl) {
  final trimmed = imageUrl.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.path.trim().isEmpty) {
    return 'avatar:$trimmed';
  }

  final version = uri.queryParameters['v']?.trim();
  final normalizedPath = uri.path.trim().toLowerCase();
  if (version == null || version.isEmpty) {
    return 'avatar:$normalizedPath';
  }
  return 'avatar:$normalizedPath?v=$version';
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.label,
    required this.radius,
    this.avatarUrl,
    this.authToken,
  });

  final String label;
  final String? avatarUrl;
  final String? authToken;
  final double radius;

  Widget _buildInitial(String initial) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: TurnaColors.textInverse,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.65,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeLabel = label.trim();
    final initial = safeLabel.isEmpty
        ? '?'
        : safeLabel.characters.first.toUpperCase();
    final trimmedUrl = avatarUrl?.trim() ?? '';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: TurnaColors.avatarGradient,
        boxShadow: const [TurnaColors.shadowSoft],
      ),
      child: ClipOval(
        child: trimmedUrl.isEmpty
            ? _buildInitial(initial)
            : _TurnaCachedImage(
                cacheKey: _buildAvatarCacheKey(trimmedUrl),
                imageUrl: trimmedUrl,
                authToken: authToken,
                fit: BoxFit.cover,
                loading: _buildInitial(initial),
                error: _buildInitial(initial),
              ),
      ),
    );
  }
}

Future<void> _openAvatarViewer(
  BuildContext context, {
  required String imageUrl,
  required String title,
  required String token,
}) async {
  final trimmedUrl = imageUrl.trim();
  if (trimmedUrl.isEmpty) return;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          AvatarViewerPage(imageUrl: trimmedUrl, title: title, token: token),
    ),
  );
}

class AvatarViewerPage extends StatelessWidget {
  const AvatarViewerPage({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.token,
  });

  final String imageUrl;
  final String title;
  final String token;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: FutureBuilder<File?>(
        future: TurnaLocalMediaCache.getOrDownloadFile(
          cacheKey: 'avatar:$imageUrl',
          url: imageUrl,
          authToken: token,
        ),
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file == null) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Görsel yüklenemedi.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            );
          }

          return InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Center(
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Görsel yüklenemedi.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.session,
    this.initialProfile,
    required this.onProfileUpdated,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaUserProfile? initialProfile;
  final void Function(AuthSession session) onProfileUpdated;
  final VoidCallback onSessionExpired;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z][a-z0-9._]{2,23}$');
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _expertiseController = TextEditingController();
  final _communityRoleController = TextEditingController();
  final _interestsController = TextEditingController();
  final _socialLinksController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  TurnaUserProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _avatarBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profile =
        widget.initialProfile ??
        buildTurnaSelfProfileFromSession(widget.session);
    _applyProfile(_profile!);
    _loading = false;
    unawaited(_loadCachedProfile());
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _aboutController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _expertiseController.dispose();
    _communityRoleController.dispose();
    _interestsController.dispose();
    _socialLinksController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _normalizeUsername(String value) {
    return value.trim().toLowerCase().replaceAll('@', '');
  }

  void _handleUnauthorized() {
    widget.onSessionExpired();
  }

  Future<void> _loadCachedProfile() async {
    final cached = await TurnaProfileLocalCache.loadSelfProfile(widget.session);
    if (!mounted || cached == null) return;
    _applyProfile(cached);
    setState(() {
      _profile = cached;
      _loading = false;
    });
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = _profile == null;
      _error = null;
    });

    try {
      final profile = await ProfileApi.fetchMe(widget.session);
      final updatedSession = widget.session.copyWith(
        displayName: profile.displayName,
        username: profile.username,
        phone: profile.phone,
        avatarUrl: profile.avatarUrl,
        clearAvatarUrl: profile.avatarUrl == null,
      );
      await TurnaAuthSessionStore.save(updatedSession);
      await TurnaProfileLocalCache.saveSelfProfile(profile);
      if (!mounted) return;
      _applyProfile(profile);
      setState(() {
        _profile = profile;
        _loading = false;
      });
      widget.onProfileUpdated(updatedSession);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      _handleUnauthorized();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _applyProfile(TurnaUserProfile profile) {
    _displayNameController.text = profile.displayName;
    _usernameController.text = profile.username ?? '';
    _aboutController.text = profile.about ?? '';
    _cityController.text = profile.city ?? '';
    _countryController.text = profile.country ?? '';
    _expertiseController.text = profile.expertise ?? '';
    _communityRoleController.text = profile.communityRole ?? '';
    _interestsController.text = profile.interests.join('\n');
    _socialLinksController.text = profile.socialLinks.join('\n');
    _phoneController.text = profile.phone ?? '';
    _emailController.text = profile.email ?? '';
  }

  List<String> _listValuesForField(_ProfileEditableField field, String value) {
    final splitter = field == _ProfileEditableField.socialLinks
        ? RegExp(r'\n+')
        : RegExp(r'[\n,]+');
    final seen = <String>{};
    return value
        .split(splitter)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && seen.add(item))
        .toList();
  }

  String _displayValueForField(_ProfileEditableField field) {
    final raw = _valueForField(field).trim();
    switch (field) {
      case _ProfileEditableField.interests:
      case _ProfileEditableField.socialLinks:
        final items = _listValuesForField(field, raw);
        return items.join('  •  ');
      default:
        return raw;
    }
  }

  List<String> _communityMissingFields() {
    final missing = <String>[];
    if (_displayNameController.text.trim().isEmpty) missing.add('Ad');
    if (_aboutController.text.trim().isEmpty) missing.add('Kısa bio');
    if ((_profile?.avatarUrl ?? widget.session.avatarUrl)?.trim().isEmpty !=
        false) {
      missing.add('Profil fotoğrafı');
    }
    if (_expertiseController.text.trim().isEmpty) {
      missing.add('Uzmanlık alanı');
    }
    if (_cityController.text.trim().isEmpty ||
        _countryController.text.trim().isEmpty) {
      missing.add('Şehir / ülke');
    }
    if (_listValuesForField(
      _ProfileEditableField.interests,
      _interestsController.text,
    ).isEmpty) {
      missing.add('İlgi alanları');
    }
    if (_listValuesForField(
      _ProfileEditableField.socialLinks,
      _socialLinksController.text,
    ).isEmpty) {
      missing.add('Sosyal linkler');
    }
    if (_communityRoleController.text.trim().isEmpty) {
      missing.add('Topluluktaki rol');
    }
    return missing;
  }

  Future<void> _commitProfile(
    TurnaUserProfile updatedProfile, {
    String? successMessage,
  }) async {
    _applyProfile(updatedProfile);
    setState(() {
      _profile = updatedProfile;
    });

    final updatedSession = widget.session.copyWith(
      displayName: updatedProfile.displayName,
      username: updatedProfile.username,
      phone: updatedProfile.phone,
      avatarUrl: updatedProfile.avatarUrl,
      clearAvatarUrl: updatedProfile.avatarUrl == null,
    );
    await TurnaAuthSessionStore.save(updatedSession);
    await TurnaProfileLocalCache.saveSelfProfile(updatedProfile);
    await TurnaUserProfileLocalCache.save(updatedProfile);
    widget.onProfileUpdated(updatedSession);
    await TurnaAnalytics.logEvent('profile_updated', {
      'user_id': updatedSession.userId,
    });

    if (!mounted || successMessage == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  Future<void> _pickAvatar() async {
    final previousAvatarUrl = resolveTurnaSessionAvatarUrl(
      widget.session,
      overrideAvatarUrl: _profile?.avatarUrl,
    );
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() {
      _avatarBusy = true;
      _error = null;
    });

    try {
      final prepared = await _prepareTurnaProfileAvatarUpload(file);
      final upload = await ProfileApi.createAvatarUpload(
        widget.session,
        contentType: prepared.contentType,
        fileName: prepared.fileName,
      );

      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: prepared.bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Avatar yüklenemedi.');
      }

      final updatedProfile = await ProfileApi.completeAvatarUpload(
        widget.session,
        objectKey: upload.objectKey,
      );
      if (previousAvatarUrl != null && previousAvatarUrl.trim().isNotEmpty) {
        await TurnaLocalMediaCache.remove(
          _buildAvatarCacheKey(previousAvatarUrl),
        );
      }
      if (!mounted) return;
      await _commitProfile(
        updatedProfile,
        successMessage: 'Avatar güncellendi.',
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      _handleUnauthorized();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    final previousAvatarUrl = resolveTurnaSessionAvatarUrl(
      widget.session,
      overrideAvatarUrl: _profile?.avatarUrl,
    );
    setState(() {
      _avatarBusy = true;
      _error = null;
    });

    try {
      final updatedProfile = await ProfileApi.deleteAvatar(widget.session);
      if (previousAvatarUrl != null && previousAvatarUrl.trim().isNotEmpty) {
        await TurnaLocalMediaCache.remove(
          _buildAvatarCacheKey(previousAvatarUrl),
        );
      }
      if (!mounted) return;
      await _commitProfile(
        updatedProfile,
        successMessage: 'Avatar kaldırıldı.',
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      _handleUnauthorized();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _showAvatarActions() async {
    if (_saving || _avatarBusy) return;
    final hasAvatar =
        (_profile?.avatarUrl ?? widget.session.avatarUrl)?.trim().isNotEmpty ==
        true;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar();
              },
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: TurnaColors.error,
                ),
                title: const Text(
                  'Fotoğrafı kaldır',
                  style: TextStyle(color: TurnaColors.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removeAvatar();
                },
              ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Vazgeç'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  String _valueForField(_ProfileEditableField field) => switch (field) {
    _ProfileEditableField.username => _usernameController.text,
    _ProfileEditableField.about => _aboutController.text,
    _ProfileEditableField.displayName => _displayNameController.text,
    _ProfileEditableField.city => _cityController.text,
    _ProfileEditableField.country => _countryController.text,
    _ProfileEditableField.expertise => _expertiseController.text,
    _ProfileEditableField.communityRole => _communityRoleController.text,
    _ProfileEditableField.interests => _interestsController.text,
    _ProfileEditableField.socialLinks => _socialLinksController.text,
    _ProfileEditableField.email => _emailController.text,
    _ProfileEditableField.phone => _phoneController.text,
  };

  String? _validateField(_ProfileEditableField field, String value) {
    final trimmed = value.trim();
    switch (field) {
      case _ProfileEditableField.displayName:
        if (trimmed.length < 2) return 'Ad en az 2 karakter olmalı.';
        return null;
      case _ProfileEditableField.username:
        final normalized = _normalizeUsername(trimmed);
        if (normalized.length < 3) {
          return 'Kullanıcı adı en az 3 karakter olmalı.';
        }
        if (!_usernamePattern.hasMatch(normalized)) {
          return 'Kullanıcı adı uygun değil. Küçük harf, rakam, nokta ve alt çizgi kullan.';
        }
        return null;
      case _ProfileEditableField.email:
        if (trimmed.isEmpty) return null;
        if (!_emailPattern.hasMatch(trimmed)) {
          return 'Geçerli bir email adresi gir.';
        }
        return null;
      case _ProfileEditableField.phone:
        if (trimmed.isEmpty) return 'Telefon numarası gerekli.';
        if (trimmed.length < 6) return 'Telefon numarası çok kısa.';
        return null;
      case _ProfileEditableField.city:
      case _ProfileEditableField.country:
      case _ProfileEditableField.expertise:
      case _ProfileEditableField.communityRole:
      case _ProfileEditableField.interests:
      case _ProfileEditableField.socialLinks:
      case _ProfileEditableField.about:
        return null;
    }
  }

  Future<void> _saveField(_ProfileEditableField field, String rawValue) async {
    final value = field == _ProfileEditableField.username
        ? _normalizeUsername(rawValue)
        : rawValue.trim();
    final validationError = _validateField(field, value);
    if (validationError != null) {
      throw TurnaApiException(validationError);
    }

    final displayName = field == _ProfileEditableField.displayName
        ? value
        : _displayNameController.text.trim();
    final username = field == _ProfileEditableField.username
        ? value
        : _normalizeUsername(_usernameController.text);
    final about = field == _ProfileEditableField.about
        ? value
        : _aboutController.text.trim();
    final city = field == _ProfileEditableField.city
        ? value
        : _cityController.text.trim();
    final country = field == _ProfileEditableField.country
        ? value
        : _countryController.text.trim();
    final expertise = field == _ProfileEditableField.expertise
        ? value
        : _expertiseController.text.trim();
    final communityRole = field == _ProfileEditableField.communityRole
        ? value
        : _communityRoleController.text.trim();
    final interests = field == _ProfileEditableField.interests
        ? _listValuesForField(field, value)
        : _listValuesForField(
            _ProfileEditableField.interests,
            _interestsController.text,
          );
    final socialLinks = field == _ProfileEditableField.socialLinks
        ? _listValuesForField(field, value)
        : _listValuesForField(
            _ProfileEditableField.socialLinks,
            _socialLinksController.text,
          );
    final phone = field == _ProfileEditableField.phone
        ? value
        : _phoneController.text.trim();
    final email = field == _ProfileEditableField.email
        ? value
        : _emailController.text.trim();

    final usernameError = _validateField(
      _ProfileEditableField.username,
      username,
    );
    if (usernameError != null) {
      throw TurnaApiException(usernameError);
    }

    final currentUsername = _normalizeUsername(_profile?.username ?? '');
    if (username != currentUsername) {
      final available = await ProfileApi.checkUsernameAvailability(
        widget.session,
        username,
      );
      if (!available) {
        throw TurnaApiException('Bu kullanıcı adı kullanılıyor.');
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updatedProfile = await ProfileApi.updateMe(
        widget.session,
        displayName: displayName,
        username: username,
        about: about,
        city: city,
        country: country,
        expertise: expertise,
        communityRole: communityRole,
        interests: interests,
        socialLinks: socialLinks,
        phone: phone,
        email: email,
      );
      if (!mounted) return;
      await _commitProfile(
        updatedProfile,
        successMessage: '${field.label} güncellendi.',
      );
    } on TurnaUnauthorizedException {
      if (!mounted) rethrow;
      _handleUnauthorized();
      throw TurnaApiException('Oturum süresi doldu.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openFieldEditor(_ProfileEditableField field) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ProfileFieldEditorPage(
          field: field,
          initialValue: _valueForField(field),
          session: widget.session,
          currentUsername: _normalizeUsername(_profile?.username ?? ''),
          onSave: (value) => _saveField(field, value),
        ),
      ),
    );
  }

  Widget _buildFieldSection(
    _ProfileEditableField field, {
    String? overrideValue,
    String? overridePlaceholder,
    VoidCallback? onTap,
  }) {
    final rawValue = overrideValue ?? _valueForField(field).trim();
    final hasValue = rawValue.isNotEmpty;
    final displayValue = hasValue
        ? rawValue
        : (overridePlaceholder ?? field.placeholder);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              field.sectionTitle,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6E7472),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              title: Text(
                displayValue,
                style: TextStyle(
                  fontSize: 16,
                  color: hasValue
                      ? const Color(0xFF202124)
                      : TurnaColors.success,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9BA09F),
              ),
              onTap: (_saving || _avatarBusy)
                  ? null
                  : (onTap ?? () => _openFieldEditor(field)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        _error!,
        style: const TextStyle(color: Color(0xFFC0392B), fontSize: 13),
      ),
    );
  }

  Widget _buildProfileBody(TurnaUserProfile profile) {
    final displayName = _displayNameController.text.trim().isEmpty
        ? widget.session.displayName
        : _displayNameController.text.trim();
    final avatarUrl = resolveTurnaSessionAvatarUrl(
      widget.session,
      overrideAvatarUrl: profile.avatarUrl,
    );
    final username = _normalizeUsername(_usernameController.text);
    final communityMissing = _communityMissingFields();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Center(
          child: GestureDetector(
            onTap: () {
              if (avatarUrl == null || avatarUrl.trim().isEmpty) return;
              _openAvatarViewer(
                context,
                imageUrl: avatarUrl,
                title: displayName,
                token: widget.session.token,
              );
            },
            child: _ProfileAvatar(
              label: displayName,
              avatarUrl: avatarUrl,
              authToken: widget.session.token,
              radius: 58,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: (_saving || _avatarBusy) ? null : _showAvatarActions,
            style: TextButton.styleFrom(
              foregroundColor: TurnaColors.success,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(_avatarBusy ? 'Yükleniyor...' : 'Düzenle'),
          ),
        ),
        const SizedBox(height: 8),
        _buildErrorBanner(),
        _buildFieldSection(
          _ProfileEditableField.username,
          overrideValue: username.isEmpty ? '' : '@$username',
        ),
        _buildFieldSection(
          _ProfileEditableField.about,
          overridePlaceholder: 'Neler oluyor?',
        ),
        _buildFieldSection(_ProfileEditableField.displayName),
        _buildFieldSection(_ProfileEditableField.email),
        _buildFieldSection(_ProfileEditableField.phone),
        const SizedBox(height: 6),
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Community profili',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF202124),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                communityMissing.isEmpty
                    ? 'Community katılımı için gereken alanlar tamam görünüyor.'
                    : 'Community giriş kapısı için eksik alanlar: ${communityMissing.join(', ')}.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: communityMissing.isEmpty
                      ? TurnaColors.success
                      : const Color(0xFF6E7472),
                ),
              ),
            ],
          ),
        ),
        _buildFieldSection(_ProfileEditableField.expertise),
        _buildFieldSection(_ProfileEditableField.communityRole),
        _buildFieldSection(_ProfileEditableField.city),
        _buildFieldSection(_ProfileEditableField.country),
        _buildFieldSection(
          _ProfileEditableField.interests,
          overrideValue: _displayValueForField(_ProfileEditableField.interests),
          overridePlaceholder: 'İlgi alanlarını ekle',
        ),
        _buildFieldSection(
          _ProfileEditableField.socialLinks,
          overrideValue: _displayValueForField(
            _ProfileEditableField.socialLinks,
          ),
          overridePlaceholder: 'Sosyal link ekle',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (_loading && profile == null) {
      return Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          backgroundColor: TurnaColors.backgroundSoft,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('Profil'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          backgroundColor: TurnaColors.backgroundSoft,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('Profil'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Profil yüklenemedi.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadProfile,
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.backgroundSoft,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Profil',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildProfileBody(profile),
    );
  }
}

enum _ProfileEditableField {
  username,
  about,
  displayName,
  email,
  phone,
  expertise,
  communityRole,
  city,
  country,
  interests,
  socialLinks,
}

extension _ProfileEditableFieldX on _ProfileEditableField {
  String get label => switch (this) {
    _ProfileEditableField.username => 'Kullanıcı adı',
    _ProfileEditableField.about => 'Hakkında',
    _ProfileEditableField.displayName => 'Ad',
    _ProfileEditableField.email => 'Email',
    _ProfileEditableField.phone => 'Telefon',
    _ProfileEditableField.expertise => 'Uzmanlık alanı',
    _ProfileEditableField.communityRole => 'Topluluktaki rol',
    _ProfileEditableField.city => 'Şehir',
    _ProfileEditableField.country => 'Ülke',
    _ProfileEditableField.interests => 'İlgi alanları',
    _ProfileEditableField.socialLinks => 'Sosyal linkler',
  };

  String get sectionTitle => switch (this) {
    _ProfileEditableField.username => 'Kullanıcı adı',
    _ProfileEditableField.about => 'Hakkımda',
    _ProfileEditableField.displayName => 'Ad',
    _ProfileEditableField.email => 'Email',
    _ProfileEditableField.phone => 'Telefon numarası',
    _ProfileEditableField.expertise => 'Uzmanlık alanı',
    _ProfileEditableField.communityRole => 'Topluluktaki rol',
    _ProfileEditableField.city => 'Şehir',
    _ProfileEditableField.country => 'Ülke',
    _ProfileEditableField.interests => 'İlgi alanları',
    _ProfileEditableField.socialLinks => 'Sosyal linkler',
  };

  String get placeholder => switch (this) {
    _ProfileEditableField.username => 'Kullanıcı adı ekle',
    _ProfileEditableField.about => 'Neler oluyor?',
    _ProfileEditableField.displayName => 'Ad ekle',
    _ProfileEditableField.email => 'Email ekle',
    _ProfileEditableField.phone => 'Telefon numarası ekle',
    _ProfileEditableField.expertise => 'Uzmanlık alanını yaz',
    _ProfileEditableField.communityRole => 'Topluluktaki rolünü yaz',
    _ProfileEditableField.city => 'Şehir ekle',
    _ProfileEditableField.country => 'Ülke ekle',
    _ProfileEditableField.interests => 'Her satıra bir ilgi alanı yaz',
    _ProfileEditableField.socialLinks => 'Her satıra bir link ekle',
  };

  String? get description => switch (this) {
    _ProfileEditableField.username => 'Kullanıcılar bu ad ile sizi bulabilir.',
    _ProfileEditableField.about =>
      'Profilinizde kısa bir durum olarak görünür.',
    _ProfileEditableField.displayName =>
      'Etkileşimde bulunduğunuz kullanıcıların kişilerinde kayıtlı değilseniz bu ad görünür.',
    _ProfileEditableField.email =>
      'Hesap bildirimleri ve güvenlik işlemleri için kullanılabilir.',
    _ProfileEditableField.phone => 'Telefon numaranız hesabınızla ilişkilidir.',
    _ProfileEditableField.expertise =>
      'Örnek: UI tasarım, growth, frontend, yatırım.',
    _ProfileEditableField.communityRole =>
      'Örnek: mentor, eğitmen, kurucu, aktif üye.',
    _ProfileEditableField.city => 'Topluluk içinde bulunduğun şehri belirtir.',
    _ProfileEditableField.country =>
      'Topluluk keşfi ve filtreleme için kullanılır.',
    _ProfileEditableField.interests =>
      'Virgül veya alt alta yazarak birden fazla alan ekleyebilirsin.',
    _ProfileEditableField.socialLinks =>
      'LinkedIn, X, GitHub veya kişisel site linklerini her satıra bir tane yaz.',
  };

  TextInputType get keyboardType => switch (this) {
    _ProfileEditableField.email => TextInputType.emailAddress,
    _ProfileEditableField.phone => TextInputType.phone,
    _ => TextInputType.text,
  };

  int get maxLines => switch (this) {
    _ProfileEditableField.about => 4,
    _ProfileEditableField.interests => 4,
    _ProfileEditableField.socialLinks => 5,
    _ => 1,
  };

  TextCapitalization get textCapitalization => switch (this) {
    _ProfileEditableField.displayName => TextCapitalization.words,
    _ProfileEditableField.about => TextCapitalization.sentences,
    _ProfileEditableField.city => TextCapitalization.words,
    _ProfileEditableField.country => TextCapitalization.words,
    _ProfileEditableField.expertise => TextCapitalization.sentences,
    _ProfileEditableField.communityRole => TextCapitalization.sentences,
    _ProfileEditableField.interests => TextCapitalization.sentences,
    _ => TextCapitalization.none,
  };

  String? get prefixText => this == _ProfileEditableField.username ? '@' : null;

  List<TextInputFormatter> get inputFormatters => switch (this) {
    _ProfileEditableField.username => [
      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._@]')),
      TextInputFormatter.withFunction((oldValue, newValue) {
        final normalized = newValue.text
            .toLowerCase()
            .replaceAll('@', '')
            .replaceAll(RegExp(r'[^a-z0-9._]+'), '');
        return TextEditingValue(
          text: normalized,
          selection: TextSelection.collapsed(offset: normalized.length),
        );
      }),
    ],
    _ => const [],
  };
}

class _ProfileFieldEditorPage extends StatefulWidget {
  const _ProfileFieldEditorPage({
    required this.field,
    required this.initialValue,
    required this.session,
    required this.currentUsername,
    required this.onSave,
  });

  final _ProfileEditableField field;
  final String initialValue;
  final AuthSession session;
  final String currentUsername;
  final Future<void> Function(String value) onSave;

  @override
  State<_ProfileFieldEditorPage> createState() =>
      _ProfileFieldEditorPageState();
}

class _ProfileFieldEditorPageState extends State<_ProfileFieldEditorPage> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z][a-z0-9._]{2,23}$');
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  late final TextEditingController _controller;
  bool _saving = false;
  bool _usernameChecking = false;
  bool? _usernameAvailable;
  String? _usernameMessage;
  String? _error;
  Timer? _usernameCheckDebounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_handleChanged);
    if (widget.field == _ProfileEditableField.username) {
      _scheduleUsernameCheck();
    }
  }

  @override
  void dispose() {
    _usernameCheckDebounce?.cancel();
    _controller.removeListener(_handleChanged);
    _controller.dispose();
    super.dispose();
  }

  String _normalizeUsername(String value) {
    return value.trim().toLowerCase().replaceAll('@', '');
  }

  String get _normalizedValue {
    if (widget.field == _ProfileEditableField.username) {
      return _normalizeUsername(_controller.text);
    }
    return _controller.text.trim();
  }

  bool get _hasChanges => _normalizedValue != widget.initialValue.trim();

  void _handleChanged() {
    if (!mounted) return;
    if (widget.field == _ProfileEditableField.username) {
      _scheduleUsernameCheck();
      return;
    }
    setState(() => _error = null);
  }

  String? _validateInput(String value) {
    switch (widget.field) {
      case _ProfileEditableField.displayName:
        if (value.length < 2) return 'Ad en az 2 karakter olmalı.';
        return null;
      case _ProfileEditableField.username:
        if (value.length < 3) return 'Kullanıcı adı en az 3 karakter olmalı.';
        if (!_usernamePattern.hasMatch(value)) {
          return 'Kullanıcı adı uygun değil. Küçük harf, rakam, nokta ve alt çizgi kullan.';
        }
        return null;
      case _ProfileEditableField.email:
        if (value.isEmpty) return null;
        if (!_emailPattern.hasMatch(value)) {
          return 'Geçerli bir email adresi gir.';
        }
        return null;
      case _ProfileEditableField.phone:
        if (value.isEmpty) return 'Telefon numarası gerekli.';
        if (value.length < 6) return 'Telefon numarası çok kısa.';
        return null;
      case _ProfileEditableField.city:
      case _ProfileEditableField.country:
      case _ProfileEditableField.expertise:
      case _ProfileEditableField.communityRole:
      case _ProfileEditableField.interests:
      case _ProfileEditableField.socialLinks:
      case _ProfileEditableField.about:
        return null;
    }
  }

  void _scheduleUsernameCheck() {
    final raw = _normalizeUsername(_controller.text);
    _usernameCheckDebounce?.cancel();

    if (raw.isEmpty) {
      setState(() {
        _usernameChecking = false;
        _usernameAvailable = false;
        _usernameMessage = 'Kullanıcı adı en az 3 karakter olmalı.';
      });
      return;
    }

    final formatError = _validateInput(raw);
    if (formatError != null) {
      setState(() {
        _usernameChecking = false;
        _usernameAvailable = false;
        _usernameMessage = formatError;
      });
      return;
    }

    if (raw == widget.currentUsername) {
      setState(() {
        _usernameChecking = false;
        _usernameAvailable = true;
        _usernameMessage = 'Mevcut kullanıcı adın.';
      });
      return;
    }

    setState(() {
      _usernameChecking = true;
      _usernameAvailable = null;
      _usernameMessage = 'Kontrol ediliyor...';
    });

    _usernameCheckDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final available = await ProfileApi.checkUsernameAvailability(
          widget.session,
          raw,
        );
        if (!mounted) return;
        if (_normalizeUsername(_controller.text) != raw) return;
        setState(() {
          _usernameChecking = false;
          _usernameAvailable = available;
          _usernameMessage = available
              ? 'Kullanıcı adı uygun.'
              : 'Bu kullanıcı adı kullanılıyor.';
        });
      } catch (error) {
        if (!mounted) return;
        if (_normalizeUsername(_controller.text) != raw) return;
        setState(() {
          _usernameChecking = false;
          _usernameAvailable = false;
          _usernameMessage = error.toString();
        });
      }
    });
  }

  Future<void> _handleSave() async {
    final value = _normalizedValue;
    final validationError = _validateInput(value);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    if (widget.field == _ProfileEditableField.username) {
      if (_usernameChecking) {
        setState(() => _error = 'Kullanıcı adı kontrolü tamamlanmadı.');
        return;
      }
      if (_usernameAvailable == false) {
        setState(() => _error = 'Bu kullanıcı adı kullanılıyor.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.onSave(value);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !_saving && _hasChanges;

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.backgroundSoft,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 78,
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text(
            'İptal',
            style: TextStyle(fontSize: 16, color: Color(0xFF202124)),
          ),
        ),
        centerTitle: true,
        title: Text(
          widget.field.sectionTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: canSave ? _handleSave : null,
            child: Text(
              _saving ? 'Kaydediliyor' : 'Kaydet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: canSave ? TurnaColors.primary : const Color(0xFFADB3B1),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.field.keyboardType,
            textCapitalization: widget.field.textCapitalization,
            maxLines: widget.field.maxLines,
            inputFormatters: widget.field.inputFormatters,
            decoration: InputDecoration(
              hintText: widget.field.placeholder,
              prefixText: widget.field.prefixText,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: TurnaColors.primary),
              ),
              suffixIcon: widget.field == _ProfileEditableField.username
                  ? (_usernameChecking
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _usernameAvailable == true
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: TurnaColors.success,
                          )
                        : _usernameAvailable == false
                        ? const Icon(
                            Icons.cancel_rounded,
                            color: TurnaColors.error,
                          )
                        : null)
                  : null,
            ),
          ),
          if (widget.field == _ProfileEditableField.username &&
              _usernameMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _usernameMessage!,
              style: TextStyle(
                fontSize: 13,
                color: _usernameAvailable == true
                    ? TurnaColors.success
                    : _usernameAvailable == false
                    ? TurnaColors.error
                    : TurnaColors.textMuted,
              ),
            ),
          ] else if (widget.field.description != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.field.description!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Color(0xFF7A817D),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: TurnaColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.session,
    required this.userId,
    required this.fallbackName,
    this.fallbackAvatarUrl,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String userId;
  final String fallbackName;
  final String? fallbackAvatarUrl;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  TurnaUserProfile? _profile;
  _UserConversationStats? _conversationStats;
  TurnaChatDetail? _chatDetail;
  int _starredMessageCount = 0;
  bool _loading = false;
  bool _statsLoading = true;
  bool _chatLockEnabled = false;
  String? _error;

  String get _conversationChatId =>
      ChatApi.buildDirectChatId(widget.session.userId, widget.userId);

  @override
  void initState() {
    super.initState();
    _profile =
        TurnaUserProfileLocalCache.peek(widget.userId) ??
        TurnaUserProfile(
          id: widget.userId,
          displayName: widget.fallbackName,
          avatarUrl: widget.fallbackAvatarUrl,
        );
    _chatDetail = TurnaChatDetailLocalCache.peek(
      widget.session.userId,
      _conversationChatId,
    );
    unawaited(_loadCachedState());
    unawaited(_refreshData());
    unawaited(_loadStarredMessageCount());
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _loadProfile(),
      _loadConversationStats(),
      _loadChatDetail(),
      _loadStarredMessageCount(),
    ]);
  }

  Future<void> _loadCachedState() async {
    final cachedProfile = await TurnaUserProfileLocalCache.load(widget.userId);
    final cachedDetail = await TurnaChatDetailLocalCache.load(
      widget.session.userId,
      _conversationChatId,
    );
    final cachedMessages = await TurnaChatHistoryLocalCache.load(
      widget.session.userId,
      _conversationChatId,
    );
    if (!mounted) return;
    setState(() {
      if (cachedProfile != null) {
        _profile = cachedProfile;
      }
      if (cachedDetail != null) {
        _chatDetail = cachedDetail;
      }
      if (cachedMessages.isNotEmpty) {
        _conversationStats = _buildConversationStats(cachedMessages);
        _statsLoading = false;
      }
    });
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = _profile == null;
      _error = null;
    });

    try {
      final profile = await ProfileApi.fetchUser(widget.session, widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_profile == null) {
          _error = error.toString();
        }
      });
    }
  }

  Future<void> _loadConversationStats() async {
    if (mounted) {
      setState(() {
        _statsLoading = _conversationStats == null;
      });
    }

    try {
      final allMessages = <ChatMessage>[];
      String? before;
      var hasMore = true;

      while (hasMore) {
        final page = await ChatApi.fetchMessagesPage(
          widget.session.token,
          _conversationChatId,
          cacheOwnerId: widget.session.userId,
          before: before,
          limit: 100,
        );
        allMessages.addAll(page.items);
        hasMore = page.hasMore;
        before = page.nextBefore;
        if (page.items.isEmpty) break;
      }

      if (!mounted) return;
      setState(() {
        _conversationStats = _buildConversationStats(allMessages);
        _statsLoading = false;
      });
    } catch (error) {
      turnaLog('user profile conversation stats failed', {
        'userId': widget.userId,
        'error': error.toString(),
      });
      if (!mounted) return;
      setState(() {
        _statsLoading = false;
      });
    }
  }

  Future<void> _loadChatDetail() async {
    try {
      final detail = await ChatApi.fetchChatDetail(
        widget.session,
        _conversationChatId,
      );
      if (!mounted) return;
      setState(() => _chatDetail = detail);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (_) {}
  }

  Future<void> _loadStarredMessageCount() async {
    final count = await TurnaStarredMessagesLocalCache.countForChat(
      widget.session.userId,
      _conversationChatId,
    );
    if (!mounted) return;
    setState(() => _starredMessageCount = count);
  }

  _UserConversationStats _buildConversationStats(List<ChatMessage> messages) {
    var attachmentCount = 0;
    var totalBytes = 0;
    for (final message in messages) {
      totalBytes += utf8.encode(message.text).length;
      for (final attachment in message.attachments) {
        attachmentCount += 1;
        totalBytes += attachment.sizeBytes;
      }
    }
    return _UserConversationStats(
      attachmentCount: attachmentCount,
      totalBytes: totalBytes,
    );
  }

  Future<void> _startCall(TurnaCallType type) async {
    try {
      final started = await CallApi.startCall(
        widget.session,
        calleeId: widget.userId,
        type: type,
      );
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OutgoingCallPage(
            session: widget.session,
            coordinator: widget.callCoordinator,
            initialCall: started,
            onSessionExpired: widget.onSessionExpired,
          ),
        ),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showPlaceholderAction(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label yakinda eklenecek.')));
  }

  String _messageExpirationSummary() {
    return formatTurnaMessageExpirationLabel(
      _chatDetail?.messageExpirationSeconds,
    );
  }

  Future<void> _openConversationMessageExpiration() async {
    final result = await Navigator.push<int?>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaMessageExpirationSelectionPage(
          title: 'Süreli mesajlar',
          prompt: 'Bu sohbette yeni mesajlar ne kadar süre sonra kaybolsun?',
          initialSeconds: _chatDetail?.messageExpirationSeconds,
          footerText:
              'Bu ayar değiştirildikten sonra gönderilen yeni mesajlar seçtiğiniz sürenin sonunda bu sohbetten kaldırılır. Mevcut mesajlar etkilenmez.',
        ),
      ),
    );
    final currentSeconds = _chatDetail?.messageExpirationSeconds;
    if (result == currentSeconds) return;

    try {
      final detail = await ChatApi.updateDirectMessageExpiration(
        widget.session,
        chatId: _conversationChatId,
        messageExpirationSeconds: result,
      );
      if (!mounted) return;
      setState(() => _chatDetail = detail);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  ChatPreview _buildConversationPreview(String displayName, String? avatarUrl) {
    final phone = _profile?.phone?.trim();
    return ChatPreview(
      chatId: _conversationChatId,
      name: displayName,
      message: '',
      time: '',
      chatType: TurnaChatType.direct,
      avatarUrl: avatarUrl,
      phone: phone == null || phone.isEmpty ? null : phone,
      peerId: widget.userId,
    );
  }

  Future<void> _openConversationStarredMessages(
    String displayName,
    String? avatarUrl,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TurnaStarredMessagesPage(
          session: widget.session,
          chat: _buildConversationPreview(displayName, avatarUrl),
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted) return;
    unawaited(_loadStarredMessageCount());
  }

  String _formatConversationCount() {
    if (_statsLoading) return '...';
    return '${_conversationStats?.attachmentCount ?? 0}';
  }

  String _formatConversationStorage() {
    if (_statsLoading) return '...';
    final bytes = _conversationStats?.totalBytes ?? 0;
    return formatBytesLabel(bytes).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final name = profile?.displayName ?? widget.fallbackName;
    final avatarUrl = profile?.avatarUrl;

    if (_loading && profile == null) {
      return Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          backgroundColor: TurnaColors.backgroundSoft,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('Kişi bilgisi'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          backgroundColor: TurnaColors.backgroundSoft,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('Kişi bilgisi'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Kullanıcı profili yüklenemedi.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadProfile,
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final about = profile.about?.trim();
    final username = profile.username?.trim();
    final subtitle = about == null || about.isEmpty
        ? 'Merhaba! Ben Turna kullaniyorum.'
        : about;
    final displayedUsername = username == null || username.isEmpty
        ? null
        : '@$username';

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.backgroundSoft,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Kişi bilgisi',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => _showPlaceholderAction('Duzenle'),
            child: const Text(
              'Duzenle',
              style: TextStyle(
                color: Color(0xFF202124),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Center(
            child: GestureDetector(
              onTap: avatarUrl == null || avatarUrl.trim().isEmpty
                  ? null
                  : () => _openAvatarViewer(
                      context,
                      imageUrl: avatarUrl,
                      title: name,
                      token: widget.session.token,
                    ),
              child: _ProfileAvatar(
                label: name,
                avatarUrl: avatarUrl,
                authToken: widget.session.token,
                radius: 56,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          if (displayedUsername != null) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                displayedUsername,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF68706C),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Center(
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF727A76),
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _UserProfileActionButton(
                  icon: Icons.call_outlined,
                  label: 'Sesli',
                  onTap: () => _startCall(TurnaCallType.audio),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UserProfileActionButton(
                  icon: Icons.videocam_outlined,
                  label: 'Goruntulu',
                  onTap: () => _startCall(TurnaCallType.video),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UserProfileActionButton(
                  icon: Icons.search_outlined,
                  label: 'Ara',
                  onTap: () => _showPlaceholderAction('Sohbet ici arama'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _UserProfileGroupCard(
            children: [
              _UserProfileRow(
                icon: Icons.photo_library_outlined,
                title: 'Medya, bağlantı ve belgeler',
                trailingText: _formatConversationCount(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConversationMediaPage(
                      session: widget.session,
                      chatId: ChatApi.buildDirectChatId(
                        widget.session.userId,
                        widget.userId,
                      ),
                      peerName: name,
                    ),
                  ),
                ),
              ),
              _UserProfileRow(
                icon: Icons.folder_outlined,
                title: 'Depolama alanini yonet',
                trailingText: _formatConversationStorage(),
                onTap: () => _showPlaceholderAction('Depolama alani'),
              ),
              _UserProfileRow(
                icon: Icons.star_border_rounded,
                title: 'Yıldızlı',
                trailingText: '$_starredMessageCount',
                onTap: () => _openConversationStarredMessages(name, avatarUrl),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UserProfileGroupCard(
            children: [
              _UserProfileRow(
                icon: Icons.notifications_none_outlined,
                title: 'Bildirimler',
                onTap: () => _showPlaceholderAction('Bildirim ayarlari'),
              ),
              _UserProfileRow(
                icon: Icons.palette_outlined,
                title: 'Sohbet temasi',
                onTap: () => _showPlaceholderAction('Sohbet temasi'),
              ),
              _UserProfileRow(
                icon: Icons.photo_outlined,
                title: "Fotograflar'a Kaydet",
                trailingText: 'Varsayilan',
                onTap: () => _showPlaceholderAction("Fotograflar'a kaydet"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UserProfileGroupCard(
            children: [
              _UserProfileRow(
                icon: Icons.timer_outlined,
                title: 'Sureli mesajlar',
                trailingText: _messageExpirationSummary(),
                onTap: _openConversationMessageExpiration,
              ),
              _UserProfileSwitchRow(
                icon: Icons.lock_outline_rounded,
                title: 'Sohbeti kilitle',
                subtitle: 'Bu sohbeti bu cihazda kilitleyin ve gizleyin.',
                value: _chatLockEnabled,
                onChanged: (value) => setState(() => _chatLockEnabled = value),
              ),
              _UserProfileRow(
                icon: Icons.shield_outlined,
                title: 'Gelismis sohbet gizliligi',
                trailingText: 'Kapali',
                onTap: () =>
                    _showPlaceholderAction('Gelismis sohbet gizliligi'),
              ),
              _UserProfileRow(
                icon: Icons.lock_person_outlined,
                title: 'Sifreleme',
                subtitle: 'Kisisel mesajlar ve aramalar uctan uca sifrelidir.',
                onTap: () => _showPlaceholderAction('Sifreleme bilgisi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TurnaStarredMessageEntry {
  const _TurnaStarredMessageEntry({required this.chat, required this.message});

  final ChatPreview chat;
  final ChatMessage message;
}

enum _TurnaStarredDeleteAction { forMe, forEveryone }

class TurnaStarredMessagesPage extends StatefulWidget {
  const TurnaStarredMessagesPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
    this.chat,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;
  final ChatPreview? chat;

  @override
  State<TurnaStarredMessagesPage> createState() =>
      _TurnaStarredMessagesPageState();
}

class _TurnaStarredMessagesPageState extends State<TurnaStarredMessagesPage> {
  List<_TurnaStarredMessageEntry> _entries = const [];
  String? _error;

  bool get _isSingleChatMode => widget.chat != null;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLocalEntries());
    unawaited(_load());
  }

  Future<void> _restoreLocalEntries() async {
    try {
      final entries = _isSingleChatMode
          ? await _loadEntriesForChat(widget.chat!, localOnly: true)
          : await _loadEntriesForAllChats(localOnly: true);
      if (!mounted) return;
      setState(() {
        _entries = entries;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);

    try {
      final entries = _isSingleChatMode
          ? await _loadEntriesForChat(widget.chat!)
          : await _loadEntriesForAllChats();
      if (!mounted) return;
      setState(() {
        _entries = entries;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_entries.isEmpty) {
          _error = error.toString();
        }
      });
    }
  }

  Future<List<_TurnaStarredMessageEntry>> _loadEntriesForAllChats({
    bool localOnly = false,
  }) async {
    ChatInboxData? inbox = TurnaChatInboxLocalCache.peek(widget.session.userId);
    inbox ??= await TurnaChatInboxLocalCache.load(widget.session.userId);
    if (!localOnly) {
      try {
        inbox = await ChatApi.fetchChats(widget.session);
      } on TurnaUnauthorizedException {
        rethrow;
      } catch (_) {}
    }

    final knownChatIds = inbox?.chats.map((chat) => chat.chatId) ?? const [];
    final starredByChat = await TurnaStarredMessagesLocalCache.loadAll(
      widget.session.userId,
      knownChatIds: knownChatIds,
    );
    final chatIndex = <String, ChatPreview>{
      for (final chat in inbox?.chats ?? const <ChatPreview>[])
        chat.chatId: chat,
    };
    final entries = <_TurnaStarredMessageEntry>[];

    for (final entry in starredByChat.entries) {
      final chat =
          chatIndex[entry.key] ??
          await _buildFallbackChatPreview(entry.key, localOnly: localOnly);
      if (chat == null) continue;
      entries.addAll(
        await _loadEntriesForChat(
          chat,
          presetStarredIds: entry.value,
          localOnly: localOnly,
        ),
      );
    }

    entries.sort(
      (a, b) =>
          compareTurnaTimestamps(b.message.createdAt, a.message.createdAt),
    );
    return entries;
  }

  Future<ChatPreview?> _buildFallbackChatPreview(
    String chatId, {
    bool localOnly = false,
  }) async {
    var detail = TurnaChatDetailLocalCache.peek(widget.session.userId, chatId);
    detail ??= await TurnaChatDetailLocalCache.load(
      widget.session.userId,
      chatId,
    );
    if (detail == null && !localOnly) {
      try {
        detail = await ChatApi.fetchChatDetail(widget.session, chatId);
      } on TurnaUnauthorizedException {
        rethrow;
      } catch (_) {}
    }
    if (detail == null) return null;

    final phone =
        detail.chatType == TurnaChatType.direct &&
            detail.title.trim().startsWith('+')
        ? detail.title.trim()
        : null;
    return ChatPreview(
      chatId: chatId,
      name: TurnaContactsDirectory.resolveDisplayLabel(
        phone: phone,
        fallbackName: detail.title,
      ),
      message: '',
      time: '',
      chatType: detail.chatType,
      memberPreviewNames: detail.memberPreviewNames,
      phone: phone,
      avatarUrl: detail.avatarUrl,
      memberCount: detail.memberCount,
      myRole: detail.myRole,
      description: detail.description,
      isPublic: detail.isPublic,
    );
  }

  Future<List<_TurnaStarredMessageEntry>> _loadEntriesForChat(
    ChatPreview chat, {
    Set<String>? presetStarredIds,
    bool localOnly = false,
  }) async {
    final targetIds =
        presetStarredIds ??
        await TurnaStarredMessagesLocalCache.load(
          widget.session.userId,
          chat.chatId,
        );
    if (targetIds.isEmpty) return const [];

    final foundById = <String, ChatMessage>{};

    void collect(Iterable<ChatMessage> messages) {
      for (final message in messages) {
        if (targetIds.contains(message.id)) {
          foundById[message.id] = message;
        }
      }
    }

    collect(
      await TurnaChatHistoryLocalCache.load(widget.session.userId, chat.chatId),
    );

    if (localOnly) {
      final entries = foundById.values
          .map(
            (message) =>
                _TurnaStarredMessageEntry(chat: chat, message: message),
          )
          .toList();
      entries.sort(
        (a, b) =>
            compareTurnaTimestamps(b.message.createdAt, a.message.createdAt),
      );
      return entries;
    }

    String? before;
    var hasMore = true;
    var pageCount = 0;
    while (foundById.length < targetIds.length && hasMore && pageCount < 12) {
      final page = await ChatApi.fetchMessagesPage(
        widget.session.token,
        chat.chatId,
        cacheOwnerId: widget.session.userId,
        before: before,
        limit: 100,
      );
      collect(page.items);
      hasMore = page.hasMore;
      before = page.nextBefore;
      pageCount += 1;
      if (page.items.isEmpty) break;
    }

    if (foundById.length != targetIds.length) {
      await TurnaStarredMessagesLocalCache.save(
        widget.session.userId,
        chat.chatId,
        foundById.keys,
      );
    }

    final entries = foundById.values
        .map(
          (message) => _TurnaStarredMessageEntry(chat: chat, message: message),
        )
        .toList();
    entries.sort(
      (a, b) =>
          compareTurnaTimestamps(b.message.createdAt, a.message.createdAt),
    );
    return entries;
  }

  String _senderLabelFor(_TurnaStarredMessageEntry entry) {
    if (entry.message.senderId == widget.session.userId) return 'Siz';
    final displayName = entry.message.senderDisplayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return entry.chat.name;
  }

  String? _chatLabelFor(_TurnaStarredMessageEntry entry) {
    if (_isSingleChatMode) return null;
    final name = entry.chat.name.trim();
    return name.isEmpty ? null : name;
  }

  String? _avatarUrlFor(_TurnaStarredMessageEntry entry) {
    if (entry.message.senderId == widget.session.userId) {
      return resolveTurnaSessionAvatarUrl(widget.session);
    }
    return entry.chat.avatarUrl;
  }

  String _previewTextFor(ChatMessage message) {
    if ((message.systemType ?? '').trim().isNotEmpty) {
      final text = sanitizeTurnaChatPreviewText(message.text);
      return text.trim().isNotEmpty ? text.trim() : 'Sistem mesajı';
    }
    final parsed = parseTurnaMessageText(message.text);
    if (parsed.location != null) return parsed.location!.previewLabel;
    if (parsed.contact != null) return parsed.contact!.previewLabel;
    final text = sanitizeTurnaChatPreviewText(message.text).trim();
    if (text.isNotEmpty) return text;
    if (message.attachments.isEmpty) return 'Mesaj';
    final first = message.attachments.first;
    if (isTurnaAudioAttachment(first)) return 'Ses kaydı';
    if (isTurnaImageAttachment(first)) return 'Fotoğraf';
    if (isTurnaVideoAttachment(first)) return 'Video';
    return 'Dosya';
  }

  String? _copyableTextFor(ChatMessage message) {
    final text = parseTurnaMessageText(message.text).text.trim();
    return text.isEmpty ? null : text;
  }

  String _formatStarredDayLabel(String iso) {
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(messageDay).inDays;
    if (diffDays == 0) return 'Bugün';
    if (diffDays == 1) return 'Dün';
    if (diffDays > 1 && diffDays < 7) {
      const labels = <String>[
        'Pazartesi',
        'Salı',
        'Çarşamba',
        'Perşembe',
        'Cuma',
        'Cumartesi',
        'Pazar',
      ];
      return labels[dt.weekday - 1];
    }
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd.$mm.${dt.year}';
  }

  Future<void> _openEntry(_TurnaStarredMessageEntry entry) async {
    await Navigator.push<void>(
      context,
      buildChatRoomRoute(
        chat: entry.chat,
        session: widget.session,
        callCoordinator: widget.callCoordinator,
        onSessionExpired: widget.onSessionExpired,
        initialFocusMessageId: entry.message.id,
      ),
    );
    if (!mounted) return;
    unawaited(_load());
  }

  Future<void> _copyEntryText(_TurnaStarredMessageEntry entry) async {
    final text = _copyableTextFor(entry.message);
    if (text == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kopyalanacak metin yok.')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mesaj kopyalandı.')));
  }

  Future<void> _removeStarFromEntry(
    _TurnaStarredMessageEntry entry, {
    bool showSnackBar = true,
  }) async {
    final ids = await TurnaStarredMessagesLocalCache.load(
      widget.session.userId,
      entry.chat.chatId,
    );
    ids.remove(entry.message.id);
    await TurnaStarredMessagesLocalCache.save(
      widget.session.userId,
      entry.chat.chatId,
      ids,
    );
    if (!mounted) return;
    setState(() {
      _entries = _entries
          .where(
            (item) =>
                item.chat.chatId != entry.chat.chatId ||
                item.message.id != entry.message.id,
          )
          .toList(growable: false);
    });
    if (!showSnackBar) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Yıldız kaldırıldı.')));
  }

  static const List<String> _starredReactionOptions = <String>[
    '👍',
    '❤️',
    '😂',
    '🔥',
    '👏',
    '😮',
    '😢',
    '🙏',
  ];

  bool _canPinEntry(_TurnaStarredMessageEntry entry) {
    return entry.chat.chatType == TurnaChatType.group;
  }

  bool _entryHasMyReaction(_TurnaStarredMessageEntry entry, String emoji) {
    return entry.message.reactions.any(
      (reaction) =>
          reaction.emoji == emoji &&
          reaction.userIds.contains(widget.session.userId),
    );
  }

  Future<void> _replaceEntryMessage(
    _TurnaStarredMessageEntry entry,
    ChatMessage updatedMessage,
  ) async {
    await TurnaChatHistoryLocalCache.mergePage(
      widget.session.userId,
      entry.chat.chatId,
      [updatedMessage],
    );
    if (!mounted) return;
    setState(() {
      _entries = _entries
          .map(
            (item) =>
                item.chat.chatId == entry.chat.chatId &&
                    item.message.id == entry.message.id
                ? _TurnaStarredMessageEntry(
                    chat: item.chat,
                    message: updatedMessage,
                  )
                : item,
          )
          .toList(growable: false);
    });
  }

  Future<void> _togglePinEntry(_TurnaStarredMessageEntry entry) async {
    if (!_canPinEntry(entry)) return;
    final nextPinned = !entry.message.isPinned;
    try {
      if (nextPinned) {
        await ChatApi.pinMessage(widget.session, messageId: entry.message.id);
      } else {
        await ChatApi.unpinMessage(widget.session, messageId: entry.message.id);
      }
      final updatedMessage = entry.message.copyWith(isPinned: nextPinned);
      await _replaceEntryMessage(entry, updatedMessage);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextPinned ? 'Mesaj sabitlendi.' : 'Sabitleme kaldırıldı.',
          ),
        ),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleReactionEntry(
    _TurnaStarredMessageEntry entry,
    String emoji,
  ) async {
    try {
      final updatedMessage = _entryHasMyReaction(entry, emoji)
          ? await ChatApi.removeReaction(
              widget.session,
              messageId: entry.message.id,
              emoji: emoji,
            )
          : await ChatApi.addReaction(
              widget.session,
              messageId: entry.message.id,
              emoji: emoji,
            );
      await _replaceEntryMessage(entry, updatedMessage);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tepki güncellendi.')));
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showReactionPickerForEntry(
    _TurnaStarredMessageEntry entry,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tepki seç',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _starredReactionOptions.map((emoji) {
                    final selected = _entryHasMyReaction(entry, emoji);
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _toggleReactionEntry(entry, emoji);
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? TurnaColors.primary50
                              : TurnaColors.backgroundMuted,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : TurnaColors.border,
                          ),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _forwardEntry(_TurnaStarredMessageEntry entry) async {
    final targetChat = await Navigator.push<ChatPreview>(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardMessagePickerPage(
          session: widget.session,
          currentChatId: entry.chat.chatId,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || targetChat == null) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${targetChat.name} sohbetine iletiliyor...')),
      );

    try {
      final parsed = parseTurnaMessageText(entry.message.text);
      final drafts = <OutgoingAttachmentDraft>[];
      for (final attachment in entry.message.attachments) {
        final file = await TurnaLocalMediaCache.getOrDownloadFile(
          cacheKey: 'attachment:${attachment.objectKey}',
          url: attachment.url?.trim() ?? '',
          authToken: widget.session.token,
        );
        if (file == null) {
          throw TurnaApiException('İletilecek ek yüklenemedi.');
        }
        final bytes = await file.readAsBytes();
        final upload = await ChatApi.createAttachmentUpload(
          widget.session,
          chatId: targetChat.chatId,
          kind: attachment.kind,
          contentType: attachment.contentType,
          fileName: attachment.fileName ?? 'dosya',
        );
        final uploadRes = await http.put(
          Uri.parse(upload.uploadUrl),
          headers: upload.headers,
          body: bytes,
        );
        if (uploadRes.statusCode >= 400) {
          throw TurnaApiException('İletilecek ek yüklenemedi.');
        }
        drafts.add(
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: attachment.kind,
            transferMode: attachment.transferMode,
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            sizeBytes: attachment.sizeBytes > 0
                ? attachment.sizeBytes
                : bytes.length,
            width: attachment.width,
            height: attachment.height,
            durationSeconds: attachment.durationSeconds,
          ),
        );
      }

      await ChatApi.sendMessage(
        widget.session,
        chatId: targetChat.chatId,
        text: parsed.text.trim().isEmpty ? null : parsed.text.trim(),
        attachments: drafts,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${targetChat.name} sohbetine iletildi.')),
        );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteEntry(_TurnaStarredMessageEntry entry) async {
    final action = await showModalBottomSheet<_TurnaStarredDeleteAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Benden sil'),
                onTap: () =>
                    Navigator.pop(context, _TurnaStarredDeleteAction.forMe),
              ),
              if (entry.message.senderId == widget.session.userId)
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Herkesten sil'),
                  onTap: () => Navigator.pop(
                    context,
                    _TurnaStarredDeleteAction.forEveryone,
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (action == null) return;

    try {
      if (action == _TurnaStarredDeleteAction.forEveryone) {
        final updated = await ChatApi.deleteMessageForEveryone(
          widget.session,
          messageId: entry.message.id,
        );
        await TurnaChatHistoryLocalCache.mergePage(
          widget.session.userId,
          entry.chat.chatId,
          [updated],
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        final key = 'turna_soft_deleted_messages_${entry.chat.chatId}';
        final nextIds = <String>{
          ...(prefs.getStringList(key) ?? const <String>[]),
          entry.message.id,
        };
        await prefs.setStringList(key, nextIds.toList());
      }

      await _removeStarFromEntry(entry, showSnackBar: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == _TurnaStarredDeleteAction.forEveryone
                ? 'Mesaj herkesten silindi.'
                : 'Mesaj bu cihazdan silindi.',
          ),
        ),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _reportEntry(_TurnaStarredMessageEntry entry) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        const reasons = ['Spam', 'Taciz', 'Uygunsuz içerik', 'Sahte hesap'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in reasons)
                ListTile(
                  title: Text(item),
                  onTap: () => Navigator.pop(sheetContext, item),
                ),
            ],
          ),
        );
      },
    );
    if (reason == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Şikayet kaydedildi: $reason')));
  }

  Future<void> _showEntryActions(_TurnaStarredMessageEntry entry) async {
    final copyText = _copyableTextFor(entry.message);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.forward_outlined),
                title: const Text('İlet'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _forwardEntry(entry);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('Kopyala'),
                enabled: copyText != null,
                onTap: copyText == null
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _copyEntryText(entry);
                      },
              ),
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: const Text('Yıldızı kaldır'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeStarFromEntry(entry);
                },
              ),
              if (_canPinEntry(entry))
                ListTile(
                  leading: Icon(
                    entry.message.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                  ),
                  title: Text(
                    entry.message.isPinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _togglePinEntry(entry);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('Tepki ver'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReactionPickerForEntry(entry);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Şikayet Et'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _reportEntry(entry);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: TurnaColors.error,
                ),
                title: const Text(
                  'Sil',
                  style: TextStyle(color: TurnaColors.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteEntry(entry);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPreviewBubble(_TurnaStarredMessageEntry entry) {
    final mine = entry.message.senderId == widget.session.userId;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.68,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: mine ? TurnaColors.chatOutgoing : TurnaColors.chatIncoming,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(TurnaChatTokens.bubbleRadius),
            topRight: const Radius.circular(TurnaChatTokens.bubbleRadius),
            bottomLeft: Radius.circular(
              mine
                  ? TurnaChatTokens.bubbleRadiusTail
                  : TurnaChatTokens.bubbleRadius,
            ),
            bottomRight: Radius.circular(
              mine
                  ? TurnaChatTokens.bubbleRadius
                  : TurnaChatTokens.bubbleRadiusTail,
            ),
          ),
          boxShadow: const [TurnaColors.shadowBubble],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _previewTextFor(entry.message),
              style: TextStyle(
                fontSize: 15.5,
                height: 1.26,
                color: mine
                    ? TurnaColors.chatOutgoingText
                    : TurnaColors.chatIncomingText,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: _MessageMetaFooter(
                timeLabel: formatTurnaLocalClock(entry.message.createdAt),
                mine: mine,
                status: entry.message.status,
                edited: entry.message.isEdited,
                starred: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(_TurnaStarredMessageEntry entry) {
    final senderLabel = _senderLabelFor(entry);
    final chatLabel = _chatLabelFor(entry);
    return InkWell(
      onTap: () => _openEntry(entry),
      onLongPress: () => _showEntryActions(entry),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ProfileAvatar(
                  label: senderLabel,
                  avatarUrl: _avatarUrlFor(entry),
                  authToken: widget.session.token,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        senderLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: TurnaColors.text,
                        ),
                      ),
                      if (chatLabel != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          chatLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: TurnaColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _formatStarredDayLabel(entry.message.createdAt),
                  style: const TextStyle(
                    fontSize: 13,
                    color: TurnaColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildPreviewBubble(entry),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.backgroundSoft,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Yıldızlı',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: _error != null && _entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: TurnaColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Tekrar dene'),
                    ),
                  ],
                ),
              ),
            )
          : _entries.isEmpty
          ? const _CenteredState(
              icon: Icons.star_border_rounded,
              title: 'Henüz yıldızlı mesaj yok',
              message:
                  'Mesajlara uzun basıp yıldız eklediğinde burada görünecek.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                itemCount: _entries.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 58,
                  endIndent: 16,
                  color: Colors.black.withValues(alpha: 0.07),
                ),
                itemBuilder: (context, index) => _buildEntry(_entries[index]),
              ),
            ),
    );
  }
}

class _UserProfileActionButton extends StatelessWidget {
  const _UserProfileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: TurnaColors.primary, size: 23),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF202124),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserConversationStats {
  const _UserConversationStats({
    required this.attachmentCount,
    required this.totalBytes,
  });

  final int attachmentCount;
  final int totalBytes;
}

enum _ConversationLibraryTab { media, links, documents }

extension _ConversationLibraryTabX on _ConversationLibraryTab {
  String get label => switch (this) {
    _ConversationLibraryTab.media => 'Medya',
    _ConversationLibraryTab.links => 'Bağlantılar',
    _ConversationLibraryTab.documents => 'Belgeler',
  };
}

class ConversationMediaPage extends StatefulWidget {
  const ConversationMediaPage({
    super.key,
    required this.session,
    required this.chatId,
    required this.peerName,
  });

  final AuthSession session;
  final String chatId;
  final String peerName;

  @override
  State<ConversationMediaPage> createState() => _ConversationMediaPageState();
}

class _ConversationMediaPageState extends State<ConversationMediaPage> {
  _ConversationLibraryTab _selectedTab = _ConversationLibraryTab.media;
  bool _loading = true;
  String? _error;
  List<_ConversationMediaItem> _mediaItems = const [];
  List<_ConversationMonthSection<_ConversationLinkItem>> _linkSections =
      const [];
  List<_ConversationMonthSection<_ConversationDocumentItem>> _documentSections =
      const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadCachedContent());
    unawaited(_loadContent());
  }

  Future<void> _loadCachedContent() async {
    final messages = await TurnaChatHistoryLocalCache.load(
      widget.session.userId,
      widget.chatId,
    );
    if (!mounted || messages.isEmpty) return;
    _applyMessages(messages, fromCache: true);
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading =
          _mediaItems.isEmpty &&
          _linkSections.isEmpty &&
          _documentSections.isEmpty;
      _error = null;
    });

    try {
      final messages = await _fetchAllMessages();
      _applyMessages(messages, fromCache: false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_mediaItems.isEmpty &&
            _linkSections.isEmpty &&
            _documentSections.isEmpty) {
          _error = error.toString();
        }
      });
    }
  }

  Future<List<ChatMessage>> _fetchAllMessages() async {
    final items = <ChatMessage>[];
    String? before;
    var hasMore = true;

    while (hasMore) {
      final page = await ChatApi.fetchMessagesPage(
        widget.session.token,
        widget.chatId,
        cacheOwnerId: widget.session.userId,
        before: before,
        limit: 100,
      );
      items.addAll(page.items);
      hasMore = page.hasMore;
      before = page.nextBefore;
      if (page.items.isEmpty) break;
    }

    return items;
  }

  void _applyMessages(List<ChatMessage> messages, {required bool fromCache}) {
    messages.sort(
      (a, b) => _messageTimestamp(b).compareTo(_messageTimestamp(a)),
    );

    final mediaItems = <_ConversationMediaItem>[];
    final linkItems = <_ConversationLinkItem>[];
    final documentItems = <_ConversationDocumentItem>[];
    final seenLinks = <String>{};

    for (final message in messages) {
      final parsed = parseTurnaMessageText(message.text);
      if (parsed.deletedForEveryone) continue;
      final createdAt = _messageTimestamp(message);

      for (final attachment in message.attachments) {
        if (isTurnaImageAttachment(attachment) ||
            isTurnaVideoAttachment(attachment)) {
          mediaItems.add(
            _ConversationMediaItem(
              message: message,
              attachment: attachment,
              createdAt: createdAt,
            ),
          );
          continue;
        }
        if (!isTurnaAudioAttachment(attachment)) {
          documentItems.add(
            _ConversationDocumentItem(
              message: message,
              attachment: attachment,
              createdAt: createdAt,
            ),
          );
        }
      }

      final normalizedText = parsed.text.trim();
      if (normalizedText.isEmpty) continue;
      for (final uri in extractTurnaUrls(normalizedText)) {
        final key = '${message.id}|${uri.toString()}';
        if (!seenLinks.add(key)) continue;
        linkItems.add(
          _ConversationLinkItem(
            message: message,
            uri: uri,
            createdAt: createdAt,
            messageText: normalizedText,
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _mediaItems = mediaItems;
      _linkSections = _buildMonthSections(linkItems, (item) => item.createdAt);
      _documentSections = _buildMonthSections(
        documentItems,
        (item) => item.createdAt,
      );
      _loading = false;
      if (!fromCache) {
        _error = null;
      }
    });
  }

  DateTime _messageTimestamp(ChatMessage message) {
    final created = DateTime.tryParse(message.createdAt);
    if (created != null) return created.toLocal();
    final edited = DateTime.tryParse(message.editedAt ?? '');
    if (edited != null) return edited.toLocal();
    return DateTime.now();
  }

  String _formatViewerTimestamp(String iso) {
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final year = parsed.year.toString();
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  List<ChatGalleryMediaItem> _buildGalleryItems() {
    final items = <ChatGalleryMediaItem>[];
    for (final item in _mediaItems) {
      final url = item.attachment.url?.trim() ?? '';
      if (url.isEmpty) continue;
      items.add(
        ChatGalleryMediaItem(
          message: item.message,
          attachment: item.attachment,
          senderLabel: item.message.senderId == widget.session.userId
              ? 'Sen'
              : widget.peerName,
          cacheKey: 'library:${item.attachment.objectKey}',
          url: url,
        ),
      );
    }
    return items;
  }

  List<_ConversationMonthSection<T>> _buildMonthSections<T>(
    List<T> items,
    DateTime Function(T item) getDate,
  ) {
    if (items.isEmpty) return const [];

    final sections = <_ConversationMonthSection<T>>[];
    String? activeKey;
    for (final item in items) {
      final date = getDate(item);
      final sectionKey = '${date.year}-${date.month}';
      if (sectionKey != activeKey) {
        sections.add(
          _ConversationMonthSection<T>(
            label: _formatTurkishMonthYear(date),
            items: <T>[item],
          ),
        );
        activeKey = sectionKey;
      } else {
        sections.last.items.add(item);
      }
    }

    return sections;
  }

  String _formatTurkishMonthYear(DateTime date) {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Future<void> _openMedia(_ConversationMediaItem item) async {
    final url = item.attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      _showSnackBar('Medya açılamadı.');
      return;
    }
    final galleryItems = _buildGalleryItems();
    final initialIndex = galleryItems.indexWhere(
      (entry) =>
          entry.message?.id == item.message.id &&
          entry.attachment.objectKey == item.attachment.objectKey,
    );
    final itemsToOpen = initialIndex < 0
        ? [
            ChatGalleryMediaItem(
              message: item.message,
              attachment: item.attachment,
              senderLabel: item.message.senderId == widget.session.userId
                  ? 'Sen'
                  : widget.peerName,
              cacheKey: 'library:${item.attachment.objectKey}',
              url: url,
            ),
          ]
        : galleryItems;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatAttachmentViewerPage(
          session: widget.session,
          items: itemsToOpen,
          initialIndex: initialIndex < 0 ? 0 : initialIndex,
          autoOpenInitialVideoFullscreen: isTurnaVideoAttachment(
            item.attachment,
          ),
          formatTimestamp: _formatViewerTimestamp,
        ),
      ),
    );
  }

  Future<void> _openExternalUri(Uri uri, String errorText) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showSnackBar(errorText);
    }
  }

  Future<void> _openDocument(_ConversationDocumentItem item) async {
    final url = item.attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      _showSnackBar('Belge açılamadı.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDocumentAttachmentPage(
          session: widget.session,
          attachment: item.attachment,
          cacheKey: 'library:${item.attachment.objectKey}',
          url: url,
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSegmentedTabs() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          for (final tab in _ConversationLibraryTab.values)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedTab = tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: _selectedTab == tab
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _selectedTab == tab
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _selectedTab == tab
                          ? const Color(0xFF202124)
                          : const Color(0xFF636A68),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const _CenteredState(
        icon: Icons.photo_library_outlined,
        title: 'İçerik hazırlanıyor',
        message: 'Son bilinen medya ve bağlantılar getiriliyor.',
      );
    }
    if (_error != null) {
      return _CenteredState(
        icon: Icons.error_outline_rounded,
        title: 'İçerik yüklenemedi',
        message: _error!,
        primaryLabel: 'Tekrar dene',
        onPrimary: _loadContent,
      );
    }

    return switch (_selectedTab) {
      _ConversationLibraryTab.media => _buildMediaTab(),
      _ConversationLibraryTab.links => _buildLinksTab(),
      _ConversationLibraryTab.documents => _buildDocumentsTab(),
    };
  }

  Widget _buildMediaTab() {
    if (_mediaItems.isEmpty) {
      return const _CenteredListState(
        icon: Icons.photo_library_outlined,
        title: 'Medya yok',
        message: 'Bu sohbette henüz fotoğraf veya video paylaşılmamış.',
      );
    }

    final hasVideo = _mediaItems.any(
      (item) => isTurnaVideoAttachment(item.attachment),
    );
    final footerLabel = hasVideo
        ? '${_mediaItems.length} Medya'
        : '${_mediaItems.length} Fotoğraf';

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = _mediaItems[index];
              return GestureDetector(
                onTap: () => _openMedia(item),
                child: _ConversationMediaTile(
                  item: item,
                  authToken: widget.session.token,
                ),
              );
            }, childCount: _mediaItems.length),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 26),
            child: Center(
              child: Text(
                footerLabel,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF4A5150),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLinksTab() {
    if (_linkSections.isEmpty) {
      return const _CenteredListState(
        icon: Icons.link_rounded,
        title: 'Bağlantı yok',
        message: 'Bu sohbette henüz bağlantı paylaşılmamış.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        for (final section in _linkSections) ...[
          _ConversationSectionHeader(label: section.label),
          const SizedBox(height: 8),
          for (final item in section.items) ...[
            _ConversationLinkTile(
              item: item,
              onTap: () => _openExternalUri(item.uri, 'Bağlantı açılamadı.'),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _buildDocumentsTab() {
    final totalDocuments = _documentSections.fold<int>(
      0,
      (sum, section) => sum + section.items.length,
    );
    if (totalDocuments == 0) {
      return const _CenteredListState(
        icon: Icons.insert_drive_file_outlined,
        title: 'Belge yok',
        message: 'Bu sohbette henüz belge paylaşılmamış.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        for (final section in _documentSections) ...[
          _ConversationSectionHeader(label: section.label),
          const SizedBox(height: 8),
          for (final item in section.items) ...[
            _ConversationDocumentTile(
              item: item,
              onTap: () => _openDocument(item),
            ),
            const SizedBox(height: 10),
          ],
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: Text(
              '$totalDocuments Belge',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF4A5150),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _buildSegmentedTabs(),
        ),
        actions: const [
          Center(
            child: Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text(
                'Seç',
                style: TextStyle(
                  color: Color(0xFF1C2120),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class _ConversationMediaItem {
  const _ConversationMediaItem({
    required this.message,
    required this.attachment,
    required this.createdAt,
  });

  final ChatMessage message;
  final ChatAttachment attachment;
  final DateTime createdAt;
}

class _ConversationLinkItem {
  const _ConversationLinkItem({
    required this.message,
    required this.uri,
    required this.createdAt,
    required this.messageText,
  });

  final ChatMessage message;
  final Uri uri;
  final DateTime createdAt;
  final String messageText;
}

class _ConversationDocumentItem {
  const _ConversationDocumentItem({
    required this.message,
    required this.attachment,
    required this.createdAt,
  });

  final ChatMessage message;
  final ChatAttachment attachment;
  final DateTime createdAt;
}

class _ConversationMonthSection<T> {
  _ConversationMonthSection({required this.label, required this.items});

  final String label;
  final List<T> items;
}

class _ConversationSectionHeader extends StatelessWidget {
  const _ConversationSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF3E4443),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ConversationMediaTile extends StatelessWidget {
  const _ConversationMediaTile({required this.item, required this.authToken});

  final _ConversationMediaItem item;
  final String authToken;

  @override
  Widget build(BuildContext context) {
    final attachment = item.attachment;
    final imageUrl = attachment.url?.trim() ?? '';
    final isVideo = isTurnaVideoAttachment(attachment);

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFE6E9EE)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!isVideo && imageUrl.isNotEmpty)
            _TurnaCachedImage(
              cacheKey: 'library:${attachment.objectKey}',
              imageUrl: imageUrl,
              authToken: authToken,
              fit: BoxFit.cover,
              loading: const ColoredBox(color: Color(0xFFE2E5EA)),
              error: const ColoredBox(
                color: Color(0xFFE2E5EA),
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                  ),
                ),
              ),
            )
          else
            isVideo
                ? _TurnaVideoThumbnail(
                    cacheKey: 'library:${attachment.objectKey}',
                    url: imageUrl,
                    authToken: authToken,
                    contentType: attachment.contentType,
                    fileName: attachment.fileName,
                    fit: BoxFit.cover,
                    loading: Container(
                      color: const Color(0xFFCFD5DE),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                    error: Container(
                      color: const Color(0xFFCFD5DE),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Container(
                    color: const Color(0xFFCFD5DE),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
          if (isVideo)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x12000000), Color(0x4D000000)],
                  ),
                ),
              ),
            ),
          if (isVideo)
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 34,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

class _ConversationLinkTile extends StatelessWidget {
  const _ConversationLinkTile({required this.item, required this.onTap});

  final _ConversationLinkItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TurnaLinkPreviewMetadata>(
      future: TurnaLinkPreviewCache.resolve(item.uri),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final host = preview?.host.isNotEmpty == true
            ? preview!.host
            : item.uri.host.replaceFirst(
                RegExp(r'^www\.', caseSensitive: false),
                '',
              );
        final title = (preview?.title.trim().isNotEmpty ?? false)
            ? preview!.title.trim()
            : host;
        final messageText = item.messageText
            .replaceAll(kTurnaSharedUrlPattern, '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: TurnaColors.backgroundMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.link_rounded,
                      color: TurnaColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.22,
                            color: Color(0xFF171C1B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (messageText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            messageText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF4F5654),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          preview?.displayUrl ?? item.uri.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF7D8380),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9BA09F),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConversationDocumentTile extends StatelessWidget {
  const _ConversationDocumentTile({required this.item, required this.onTap});

  final _ConversationDocumentItem item;
  final VoidCallback onTap;

  String _extensionLabel(ChatAttachment attachment) {
    final fileName = (attachment.fileName ?? '').trim();
    if (fileName.contains('.')) {
      return fileName.split('.').last.toLowerCase();
    }
    final contentType = attachment.contentType.toLowerCase();
    if (contentType.contains('/')) {
      return contentType.split('/').last.toLowerCase();
    }
    return 'dosya';
  }

  @override
  Widget build(BuildContext context) {
    final attachment = item.attachment;
    final extension = _extensionLabel(attachment);
    final title = (attachment.fileName ?? '').trim().isEmpty
        ? 'Belge'
        : attachment.fileName!.trim();
    final meta = '${formatBytesLabel(attachment.sizeBytes)} • $extension';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 62,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE0E5EA)),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.insert_drive_file_outlined,
                      color: TurnaColors.textMuted,
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      extension.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7A817D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        color: Color(0xFF171C1B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF7A817D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserProfileGroupCard extends StatelessWidget {
  const _UserProfileGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 54, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _UserProfileRow extends StatelessWidget {
  const _UserProfileRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, size: 22, color: const Color(0xFF2B2F2D)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF202124),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.22,
                  color: Color(0xFF7A817D),
                ),
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(
              trailingText!,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF7A817D),
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF979D99)),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _UserProfileSwitchRow extends StatelessWidget {
  const _UserProfileSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 22, color: const Color(0xFF2B2F2D)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF202124),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.22,
                    color: Color(0xFF7A817D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: TurnaColors.primary,
            activeTrackColor: TurnaColors.primary100,
          ),
        ],
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Security notifications'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SecurityNotificationsPage(),
              ),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.key_outlined),
            title: Text('Passkeys'),
          ),
          const ListTile(
            leading: Icon(Icons.email_outlined),
            title: Text('Email address'),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Two-step verification'),
          ),
          const ListTile(
            leading: Icon(Icons.numbers_outlined),
            title: Text('Change number'),
          ),
          const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('Request account info'),
          ),
          const ListTile(
            leading: Icon(Icons.person_add_alt_outlined),
            title: Text('Add account'),
          ),
          const ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete account'),
          ),
        ],
      ),
    );
  }
}

class SecurityNotificationsPage extends StatefulWidget {
  const SecurityNotificationsPage({super.key});

  @override
  State<SecurityNotificationsPage> createState() =>
      _SecurityNotificationsPageState();
}

class _SecurityNotificationsPageState extends State<SecurityNotificationsPage> {
  bool enabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.lock, size: 54, color: TurnaColors.primary),
          const SizedBox(height: 12),
          const Text(
            'Security features for your account',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Turna uses secure connections and device protections today. End-to-end encryption for chats and calls is planned for a future update.',
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.message_outlined),
            title: Text('Text and voice messages'),
          ),
          const ListTile(
            leading: Icon(Icons.call_outlined),
            title: Text('Audio and video calls'),
          ),
          const ListTile(
            leading: Icon(Icons.photo_outlined),
            title: Text('photos, videos and documents'),
          ),
          const ListTile(
            leading: Icon(Icons.location_on_outlined),
            title: Text('Location sharing'),
          ),
          const ListTile(
            leading: Icon(Icons.circle_outlined),
            title: Text('Status updates'),
          ),
          SwitchListTile(
            value: enabled,
            onChanged: (v) => setState(() => enabled = v),
            title: const Text('Show Security notifications on this device'),
          ),
        ],
      ),
    );
  }
}

class _TurnaLinkedWebQrPayload {
  const _TurnaLinkedWebQrPayload({
    required this.requestId,
    required this.secret,
  });

  final String requestId;
  final String secret;

  static _TurnaLinkedWebQrPayload? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'turna' && uri.host == 'web-login') {
      final requestId = uri.queryParameters['requestId']?.trim() ?? '';
      final secret = uri.queryParameters['secret']?.trim() ?? '';
      if (requestId.isNotEmpty && secret.isNotEmpty) {
        return _TurnaLinkedWebQrPayload(requestId: requestId, secret: secret);
      }
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final requestId = decoded['requestId']?.toString().trim() ?? '';
        final secret = decoded['secret']?.toString().trim() ?? '';
        if (requestId.isNotEmpty && secret.isNotEmpty) {
          return _TurnaLinkedWebQrPayload(requestId: requestId, secret: secret);
        }
      }
    } catch (_) {}
    return null;
  }
}

class TurnaLinkedDevicesPage extends StatefulWidget {
  const TurnaLinkedDevicesPage({
    super.key,
    required this.session,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final VoidCallback onSessionExpired;

  @override
  State<TurnaLinkedDevicesPage> createState() => _TurnaLinkedDevicesPageState();
}

class _TurnaLinkedDevicesPageState extends State<TurnaLinkedDevicesPage> {
  List<TurnaLinkedDeviceSession> _sessions = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final sessions = await AuthApi.fetchLinkedDevices(widget.session);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _error = null;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    }
  }

  Future<void> _openScanner() async {
    final linked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TurnaLinkedDevicesScannerPage(
          session: widget.session,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || linked != true) return;
    unawaited(_load());
  }

  String _formatRelativeSeen(String iso) {
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return 'Az önce';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return 'Bugün ${formatTurnaLocalClock(iso)}';
    if (diff.inDays == 1) return 'Dün ${formatTurnaLocalClock(iso)}';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd.$mm.${dt.year}';
  }

  String _formatConnectedAt(String iso) {
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return '';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${dt.year} • $hh:$min';
  }

  IconData _iconForSession(TurnaLinkedDeviceSession session) {
    final source = '${session.deviceLabel} ${session.userAgent ?? ''}'
        .toLowerCase();
    if (source.contains('mac') || source.contains('safari')) {
      return Icons.laptop_mac_rounded;
    }
    if (source.contains('windows') || source.contains('edge')) {
      return Icons.laptop_windows_rounded;
    }
    if (source.contains('linux')) {
      return Icons.computer_rounded;
    }
    if (source.contains('chrome') ||
        source.contains('firefox') ||
        source.contains('opera') ||
        source.contains('browser')) {
      return Icons.language_rounded;
    }
    return Icons.devices_rounded;
  }

  Future<void> _removeSession(TurnaLinkedDeviceSession session) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.link_off_rounded,
                  color: TurnaColors.error,
                ),
                title: const Text(
                  'Bu cihazın bağlantısını kaldır',
                  style: TextStyle(color: TurnaColors.error),
                ),
                subtitle: Text(session.deviceLabel),
                onTap: () => Navigator.pop(sheetContext, true),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Vazgeç'),
                onTap: () => Navigator.pop(sheetContext, false),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;

    try {
      await AuthApi.revokeLinkedDevice(widget.session, sessionId: session.id);
      if (!mounted) return;
      setState(() {
        _sessions = _sessions
            .where((item) => item.id != session.id)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bağlı cihaz kaldırıldı.')));
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      child: Column(
        children: [
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF8EE),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 18,
                  top: 24,
                  child: Icon(
                    Icons.phone_iphone_rounded,
                    size: 34,
                    color: TurnaColors.primary.withValues(alpha: 0.88),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 20,
                  child: Icon(
                    Icons.laptop_mac_rounded,
                    size: 40,
                    color: TurnaColors.primary,
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [TurnaColors.shadowBubble],
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: TurnaColors.primary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "Turna'yı başka cihazlarda da kullan",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: TurnaColors.text,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Web oturumu açmak için bilgisayarındaki Turna QR kodunu tara. Onay verdiğinde web otomatik giriş yapar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.35,
              color: TurnaColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 15,
                  color: TurnaColors.textMuted,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Bağlı oturumların tamamı cihaz bazlı yönetilir.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: TurnaColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(TurnaLinkedDeviceSession session) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF8EE),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(_iconForSession(session), color: TurnaColors.primary),
      ),
      title: Text(
        session.deviceLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Son aktif ${_formatRelativeSeen(session.lastSeenAt)}\nBağlandı ${_formatConnectedAt(session.createdAt)}',
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: TurnaColors.textMuted,
          ),
        ),
      ),
      trailing: IconButton(
        onPressed: () => _removeSession(session),
        icon: const Icon(Icons.link_off_rounded),
        color: TurnaColors.textMuted,
        tooltip: 'Bağlantıyı kaldır',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.backgroundSoft,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Bağlı cihazlar',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  _buildHero(),
                  if (_sessions.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: Text(
                        'Bağlı web oturumları',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: TurnaColors.textMuted,
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < _sessions.length;
                            index++
                          ) ...[
                            if (index > 0)
                              Divider(
                                height: 1,
                                indent: 74,
                                endIndent: 16,
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            _buildSessionTile(_sessions[index]),
                          ],
                        ],
                      ),
                    ),
                  ] else if ((_error ?? '').trim().isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: TurnaColors.textMuted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _openScanner,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Cihaz bağla'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TurnaLinkedDevicesScannerPage extends StatefulWidget {
  const TurnaLinkedDevicesScannerPage({
    super.key,
    required this.session,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final VoidCallback onSessionExpired;

  @override
  State<TurnaLinkedDevicesScannerPage> createState() =>
      _TurnaLinkedDevicesScannerPageState();
}

class _TurnaLinkedDevicesScannerPageState
    extends State<TurnaLinkedDevicesScannerPage> {
  bool _started = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startScan());
    });
  }

  Future<void> _startScan() async {
    if (_busy) return;
    setState(() {
      _started = true;
      _busy = true;
      _message = null;
    });

    try {
      final raw = await TurnaMediaBridge.scanQrCode();
      if (!mounted) return;
      if (raw == null) {
        Navigator.pop(context, false);
        return;
      }

      final payload = _TurnaLinkedWebQrPayload.tryParse(raw);
      if (payload == null) {
        setState(() {
          _busy = false;
          _message = 'Bu QR kodu Turna Web için geçerli değil.';
        });
        return;
      }

      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Turna Web bağlansın mı?'),
            content: const Text(
              'Bu QR kodunu onayladığında bilgisayardaki Turna Web otomatik giriş yapar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Bağla'),
              ),
            ],
          );
        },
      );
      if (approved != true) {
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }

      final result = await AuthApi.confirmWebLogin(
        widget.session,
        requestId: payload.requestId,
        secret: payload.secret,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.deviceLabel} için giriş yapıldı. Web oturumu açıldı.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('İptal'),
        ),
        leadingWidth: 72,
        centerTitle: true,
        title: const Text(
          'QR kodunu tara',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F7F8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Column(
                  children: [
                    Text(
                      'web.turna.im adresini veya masaüstü Turna ekranını aç.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: TurnaColors.text,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'QR kodu göründüğünde kamera açılır. Kodu okutup onay verdiğinde web otomatik giriş yapar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: TurnaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 360),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7F8),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 76,
                            color: TurnaColors.primary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _message ??
                              (_started
                                  ? 'Kamera açıldıktan sonra QR kodunu okut.'
                                  : 'QR tarayıcı hazır.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: TurnaColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy ? null : _startScan,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(_busy ? 'Kamera açık' : 'Tamam'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Text(
                'Telefon numarasıyla web girişi yok. Bu akış sadece QR ile çalışır.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: TurnaColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title is coming in V1 build.')),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF7D8380)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF5C625F)),
            ),
            if (primaryLabel != null && onPrimary != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CenteredListState extends StatelessWidget {
  const _CenteredListState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF7D8380)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5C625F)),
          ),
        ],
      ),
    );
  }
}
