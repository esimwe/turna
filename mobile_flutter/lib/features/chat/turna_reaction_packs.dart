part of '../../app/turna_app.dart';

enum TurnaReactionPackStyle { standard, premium, community }

extension TurnaReactionPackStyleX on TurnaReactionPackStyle {
  static TurnaReactionPackStyle fromWire(String value) {
    switch (value.trim().toLowerCase()) {
      case 'premium':
        return TurnaReactionPackStyle.premium;
      case 'community':
        return TurnaReactionPackStyle.community;
      default:
        return TurnaReactionPackStyle.standard;
    }
  }

  String get label {
    switch (this) {
      case TurnaReactionPackStyle.premium:
        return 'Premium';
      case TurnaReactionPackStyle.community:
        return 'Topluluk';
      case TurnaReactionPackStyle.standard:
        return 'Standart';
    }
  }
}

enum TurnaReactionPackEntitlement { free, communityMember }

extension TurnaReactionPackEntitlementX on TurnaReactionPackEntitlement {
  static TurnaReactionPackEntitlement fromWire(String value) {
    switch (value.trim().toLowerCase()) {
      case 'community_member':
        return TurnaReactionPackEntitlement.communityMember;
      default:
        return TurnaReactionPackEntitlement.free;
    }
  }
}

class TurnaReactionPack {
  const TurnaReactionPack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.style,
    required this.entitlement,
    required this.unlocked,
    required this.installed,
    required this.usageCount,
    required this.emojis,
  });

  final String id;
  final String title;
  final String subtitle;
  final TurnaReactionPackStyle style;
  final TurnaReactionPackEntitlement entitlement;
  final bool unlocked;
  final bool installed;
  final int usageCount;
  final List<String> emojis;

  factory TurnaReactionPack.fromMap(Map<String, dynamic> map) {
    return TurnaReactionPack(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      subtitle: (map['subtitle'] ?? '').toString(),
      style: TurnaReactionPackStyleX.fromWire((map['style'] ?? '').toString()),
      entitlement: TurnaReactionPackEntitlementX.fromWire(
        (map['entitlement'] ?? '').toString(),
      ),
      unlocked: map['unlocked'] == true,
      installed: map['installed'] == true,
      usageCount: (map['usageCount'] as num?)?.toInt() ?? 0,
      emojis: (map['emojis'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }
}

class TurnaReactionPackPreferences {
  const TurnaReactionPackPreferences({
    this.installedPackIds = const <String>[],
    this.favoriteEmojis = const <String>[],
    this.recentEmojis = const <String>[],
  });

  final List<String> installedPackIds;
  final List<String> favoriteEmojis;
  final List<String> recentEmojis;

  factory TurnaReactionPackPreferences.fromMap(Map<String, dynamic> map) {
    return TurnaReactionPackPreferences(
      installedPackIds: (map['installedPackIds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      favoriteEmojis: (map['favoriteEmojis'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      recentEmojis: (map['recentEmojis'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }
}

class TurnaReactionPackCatalog {
  const TurnaReactionPackCatalog({
    required this.packs,
    required this.preferences,
  });

  final List<TurnaReactionPack> packs;
  final TurnaReactionPackPreferences preferences;

  factory TurnaReactionPackCatalog.fromMap(Map<String, dynamic> map) {
    return TurnaReactionPackCatalog(
      packs: (map['packs'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                TurnaReactionPack.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      preferences: TurnaReactionPackPreferences.fromMap(
        Map<String, dynamic>.from(
          map['preferences'] as Map? ?? const <String, dynamic>{},
        ),
      ),
    );
  }
}

class _TurnaReactionPackTab {
  const _TurnaReactionPackTab({
    required this.id,
    required this.label,
    required this.emojis,
    this.pack,
  });

  final String id;
  final String label;
  final List<String> emojis;
  final TurnaReactionPack? pack;
}

class TurnaPackEmojiSelection {
  const TurnaPackEmojiSelection({required this.packId, required this.emoji});

  final String packId;
  final String emoji;
}

Future<void> showTurnaReactionPackPicker({
  required BuildContext context,
  required AuthSession session,
  required Set<String> selectedEmojis,
  required Future<void> Function(String emoji, String packId) onToggleReaction,
  required VoidCallback onSessionExpired,
  String title = 'Tepki seç',
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TurnaReactionPackPickerSheet(
      session: session,
      title: title,
      mode: _TurnaReactionPackPickerMode.reaction,
      initialSelectedEmojis: selectedEmojis,
      onToggleReaction: onToggleReaction,
      onSessionExpired: onSessionExpired,
    ),
  );
}

Future<TurnaPackEmojiSelection?> showTurnaPackEmojiPicker({
  required BuildContext context,
  required AuthSession session,
  required VoidCallback onSessionExpired,
  String title = 'Emoji seç',
  String? selectedEmoji,
}) {
  return showModalBottomSheet<TurnaPackEmojiSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TurnaReactionPackPickerSheet(
      session: session,
      title: title,
      mode: _TurnaReactionPackPickerMode.single,
      initialSelectedEmoji: selectedEmoji,
      onSessionExpired: onSessionExpired,
    ),
  );
}

enum _TurnaReactionPackPickerMode { reaction, single }

class _TurnaReactionPackPickerSheet extends StatefulWidget {
  const _TurnaReactionPackPickerSheet({
    required this.session,
    required this.title,
    required this.mode,
    required this.onSessionExpired,
    this.initialSelectedEmojis = const <String>{},
    this.initialSelectedEmoji,
    this.onToggleReaction,
  });

  final AuthSession session;
  final String title;
  final _TurnaReactionPackPickerMode mode;
  final Set<String> initialSelectedEmojis;
  final String? initialSelectedEmoji;
  final Future<void> Function(String emoji, String packId)? onToggleReaction;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaReactionPackPickerSheet> createState() =>
      _TurnaReactionPackPickerSheetState();
}

class _TurnaReactionPackPickerSheetState
    extends State<_TurnaReactionPackPickerSheet> {
  TurnaReactionPackCatalog? _catalog;
  late Set<String> _selectedEmojis;
  String? _selectedTabId;
  bool _loading = true;
  bool _updatingPreferences = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedEmojis = widget.initialSelectedEmojis.toSet();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await ChatApi.fetchReactionPacks(widget.session);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
        _syncSelectedTab();
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<_TurnaReactionPackTab> get _tabs {
    final catalog = _catalog;
    if (catalog == null) return const <_TurnaReactionPackTab>[];

    final tabs = <_TurnaReactionPackTab>[];
    if (catalog.preferences.favoriteEmojis.isNotEmpty) {
      tabs.add(
        _TurnaReactionPackTab(
          id: 'favorites',
          label: 'Favori',
          emojis: catalog.preferences.favoriteEmojis,
        ),
      );
    }
    if (catalog.preferences.recentEmojis.isNotEmpty) {
      tabs.add(
        _TurnaReactionPackTab(
          id: 'recent',
          label: 'Son',
          emojis: catalog.preferences.recentEmojis,
        ),
      );
    }
    for (final pack in catalog.packs.where(
      (item) => item.unlocked && item.installed,
    )) {
      tabs.add(
        _TurnaReactionPackTab(
          id: pack.id,
          label: pack.title,
          emojis: pack.emojis,
          pack: pack,
        ),
      );
    }
    return tabs;
  }

  void _syncSelectedTab() {
    final tabs = _tabs;
    if (tabs.isEmpty) {
      _selectedTabId = null;
      return;
    }
    final stillValid = tabs.any((item) => item.id == _selectedTabId);
    if (!stillValid) {
      _selectedTabId = tabs.first.id;
    }
  }

  _TurnaReactionPackTab? get _selectedTab {
    final tabs = _tabs;
    if (tabs.isEmpty) return null;
    for (final tab in tabs) {
      if (tab.id == _selectedTabId) return tab;
    }
    return tabs.first;
  }

  TurnaReactionPack? _packForEmoji(String emoji, {String? preferredPackId}) {
    final catalog = _catalog;
    if (catalog == null) return null;
    if (preferredPackId != null) {
      final preferred = catalog.packs.where((item) {
        return item.id == preferredPackId &&
            item.unlocked &&
            item.emojis.contains(emoji);
      });
      if (preferred.isNotEmpty) return preferred.first;
    }
    final installed = catalog.packs.where(
      (item) => item.unlocked && item.installed && item.emojis.contains(emoji),
    );
    if (installed.isNotEmpty) return installed.first;
    final unlocked = catalog.packs.where(
      (item) => item.unlocked && item.emojis.contains(emoji),
    );
    if (unlocked.isNotEmpty) return unlocked.first;
    return null;
  }

  Future<void> _updatePreferences({
    List<String>? installedPackIds,
    List<String>? favoriteEmojis,
  }) async {
    setState(() => _updatingPreferences = true);
    try {
      final catalog = await ChatApi.updateReactionPackPreferences(
        widget.session,
        installedPackIds: installedPackIds,
        favoriteEmojis: favoriteEmojis,
      );
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _updatingPreferences = false;
        _syncSelectedTab();
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingPreferences = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleFavorite(String emoji) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final favorites = [...catalog.preferences.favoriteEmojis];
    if (favorites.contains(emoji)) {
      favorites.remove(emoji);
    } else {
      favorites.insert(0, emoji);
    }
    await _updatePreferences(favoriteEmojis: favorites);
  }

  Future<void> _toggleInstalledPack(TurnaReactionPack pack) async {
    if (!pack.unlocked) return;
    final catalog = _catalog;
    if (catalog == null) return;
    final installed = [...catalog.preferences.installedPackIds];
    if (installed.contains(pack.id)) {
      if (installed.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('En az bir paket kurulu kalmalı.')),
        );
        return;
      }
      installed.remove(pack.id);
    } else {
      installed.add(pack.id);
    }
    await _updatePreferences(installedPackIds: installed);
  }

  Future<void> _openManagePacks() async {
    final catalog = _catalog;
    if (catalog == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final latestCatalog = _catalog ?? catalog;
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  const Text(
                    'Emoji paketleri',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Kurulu paketler picker içinde görünür. Kilitli topluluk paketleri üye olduğunda açılır.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: TurnaColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...latestCatalog.packs.map((pack) {
                    final accent = switch (pack.style) {
                      TurnaReactionPackStyle.premium => const Color(0xFFFFF3D8),
                      TurnaReactionPackStyle.community => const Color(
                        0xFFE8F4ED,
                      ),
                      TurnaReactionPackStyle.standard => Colors.white,
                    };
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: pack.installed
                              ? TurnaColors.primary
                              : TurnaColors.border,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              pack.emojis.isEmpty ? '🙂' : pack.emojis.first,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        pack.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    _TurnaPackStyleBadge(style: pack.style),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  pack.subtitle,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: TurnaColors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${pack.usageCount} kullanım',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: TurnaColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (!pack.unlocked)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                color: TurnaColors.textMuted,
                              ),
                            )
                          else
                            Switch.adaptive(
                              value: pack.installed,
                              onChanged: _updatingPreferences
                                  ? null
                                  : (_) async {
                                      setSheetState(() {});
                                      await _toggleInstalledPack(pack);
                                      if (!mounted) return;
                                      setSheetState(() {});
                                    },
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleEmojiTap(String emoji) async {
    final selectedTab = _selectedTab;
    final pack = _packForEmoji(emoji, preferredPackId: selectedTab?.pack?.id);
    if (pack == null) return;

    if (widget.mode == _TurnaReactionPackPickerMode.single) {
      Navigator.of(
        context,
      ).pop(TurnaPackEmojiSelection(packId: pack.id, emoji: emoji));
      return;
    }

    final onToggleReaction = widget.onToggleReaction;
    if (onToggleReaction == null) return;
    try {
      await onToggleReaction(emoji, pack.id);
      if (!mounted) return;
      setState(() {
        if (_selectedEmojis.contains(emoji)) {
          _selectedEmojis.remove(emoji);
        } else {
          _selectedEmojis.add(emoji);
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaHeight = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: math.min(mediaHeight * 0.78, 620),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
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
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Tekrar dene'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Uzun basarak favorilere ekleyebilirsin.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: TurnaColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _updatingPreferences
                                ? null
                                : _openManagePacks,
                            icon: const Icon(Icons.widgets_outlined),
                            tooltip: 'Paketleri yönet',
                          ),
                        ],
                      ),
                    ),
                    if (_tabs.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Kurulu emoji paketi bulunamadı.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: TurnaColors.textMuted),
                            ),
                          ),
                        ),
                      )
                    else ...[
                      SizedBox(
                        height: 42,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final tab = _tabs[index];
                            final selected = tab.id == _selectedTabId;
                            return InkWell(
                              onTap: () =>
                                  setState(() => _selectedTabId = tab.id),
                              borderRadius: BorderRadius.circular(999),
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? TurnaColors.primary
                                      : TurnaColors.backgroundMuted,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Center(
                                  child: Text(
                                    tab.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Colors.white
                                          : TurnaColors.text,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemCount: _tabs.length,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 1,
                              ),
                          itemCount: _selectedTab?.emojis.length ?? 0,
                          itemBuilder: (context, index) {
                            final emoji = _selectedTab!.emojis[index];
                            final isFavorite = _catalog!
                                .preferences
                                .favoriteEmojis
                                .contains(emoji);
                            final isSelected =
                                widget.mode ==
                                    _TurnaReactionPackPickerMode.single
                                ? widget.initialSelectedEmoji == emoji
                                : _selectedEmojis.contains(emoji);
                            return InkWell(
                              onTap: () => _handleEmojiTap(emoji),
                              onLongPress: () => _toggleFavorite(emoji),
                              borderRadius: BorderRadius.circular(20),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? TurnaColors.primary50
                                      : TurnaColors.backgroundMuted,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? TurnaColors.primary
                                        : TurnaColors.border,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    Center(
                                      child: Text(
                                        emoji,
                                        style: const TextStyle(fontSize: 30),
                                      ),
                                    ),
                                    if (isFavorite)
                                      const Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Icon(
                                          Icons.star_rounded,
                                          size: 16,
                                          color: Color(0xFFF4B400),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _TurnaPackStyleBadge extends StatelessWidget {
  const _TurnaPackStyleBadge({required this.style});

  final TurnaReactionPackStyle style;

  @override
  Widget build(BuildContext context) {
    final (background, text) = switch (style) {
      TurnaReactionPackStyle.premium => (
        const Color(0xFFFFE8BA),
        const Color(0xFF6D4C00),
      ),
      TurnaReactionPackStyle.community => (
        const Color(0xFFDDF3E5),
        const Color(0xFF256A3A),
      ),
      TurnaReactionPackStyle.standard => (
        const Color(0xFFF2F4F3),
        TurnaColors.textMuted,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }
}

enum _TurnaComposerPanelMode { emoji, sticker }

class _TurnaStickerItem {
  const _TurnaStickerItem({
    required this.id,
    required this.emoji,
    required this.label,
    required this.colors,
  });

  final String id;
  final String emoji;
  final String label;
  final List<Color> colors;
}

class _TurnaStickerPack {
  const _TurnaStickerPack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<_TurnaStickerItem> items;
}

class _TurnaStickerSelection {
  const _TurnaStickerSelection({
    required this.packId,
    required this.packTitle,
    required this.stickerId,
    required this.emoji,
    required this.label,
    required this.colors,
  });

  final String packId;
  final String packTitle;
  final String stickerId;
  final String emoji;
  final String label;
  final List<Color> colors;
}

class _TurnaStickerTab {
  const _TurnaStickerTab({
    required this.id,
    required this.label,
    required this.previewEmoji,
    required this.items,
    this.pack,
  });

  final String id;
  final String label;
  final String previewEmoji;
  final List<_TurnaStickerItem> items;
  final _TurnaStickerPack? pack;
}

const List<_TurnaStickerPack> _turnaStickerPacks = <_TurnaStickerPack>[
  _TurnaStickerPack(
    id: 'moodies',
    title: 'Moodies',
    subtitle: 'Gunluk ruh halini renkli cikartmalarla yolla.',
    items: <_TurnaStickerItem>[
      _TurnaStickerItem(
        id: 'smile',
        emoji: '😊',
        label: 'Tatli',
        colors: <Color>[Color(0xFFFFE29F), Color(0xFFFFA99F)],
      ),
      _TurnaStickerItem(
        id: 'love',
        emoji: '🥰',
        label: 'Ask',
        colors: <Color>[Color(0xFFFFC3D8), Color(0xFFFF8FB2)],
      ),
      _TurnaStickerItem(
        id: 'cool',
        emoji: '😎',
        label: 'Cool',
        colors: <Color>[Color(0xFFB2F0FF), Color(0xFF79B8FF)],
      ),
      _TurnaStickerItem(
        id: 'mindblown',
        emoji: '🤯',
        label: 'Sok',
        colors: <Color>[Color(0xFFFFD8A8), Color(0xFFFF9E80)],
      ),
      _TurnaStickerItem(
        id: 'party',
        emoji: '🥳',
        label: 'Kutla',
        colors: <Color>[Color(0xFFE7C6FF), Color(0xFFC77DFF)],
      ),
      _TurnaStickerItem(
        id: 'sleepy',
        emoji: '😴',
        label: 'Uyku',
        colors: <Color>[Color(0xFFCDEBFF), Color(0xFF92A3FD)],
      ),
      _TurnaStickerItem(
        id: 'cry',
        emoji: '😭',
        label: 'Agliyorum',
        colors: <Color>[Color(0xFFAEE6FF), Color(0xFF71C9CE)],
      ),
      _TurnaStickerItem(
        id: 'rage',
        emoji: '😤',
        label: 'Hirs',
        colors: <Color>[Color(0xFFFFC6B3), Color(0xFFFF8A65)],
      ),
    ],
  ),
  _TurnaStickerPack(
    id: 'cozy',
    title: 'Cozy',
    subtitle: 'Kahve, sakinlik ve yavas gunler icin mini set.',
    items: <_TurnaStickerItem>[
      _TurnaStickerItem(
        id: 'coffee',
        emoji: '☕️',
        label: 'Kahve',
        colors: <Color>[Color(0xFFFFE1C6), Color(0xFFC49A6C)],
      ),
      _TurnaStickerItem(
        id: 'book',
        emoji: '📚',
        label: 'Okuma',
        colors: <Color>[Color(0xFFD6E4FF), Color(0xFF8EA7E9)],
      ),
      _TurnaStickerItem(
        id: 'headphones',
        emoji: '🎧',
        label: 'Muzik',
        colors: <Color>[Color(0xFFD8FFF1), Color(0xFF6DDCCF)],
      ),
      _TurnaStickerItem(
        id: 'leaf',
        emoji: '🌿',
        label: 'Sakin',
        colors: <Color>[Color(0xFFDFF5D8), Color(0xFF8BC34A)],
      ),
      _TurnaStickerItem(
        id: 'moon',
        emoji: '🌙',
        label: 'Gece',
        colors: <Color>[Color(0xFFD8D8FF), Color(0xFF7B7BCE)],
      ),
      _TurnaStickerItem(
        id: 'cloud',
        emoji: '☁️',
        label: 'Bulut',
        colors: <Color>[Color(0xFFF2F6FF), Color(0xFFB6CCFE)],
      ),
      _TurnaStickerItem(
        id: 'tea',
        emoji: '🍵',
        label: 'Mola',
        colors: <Color>[Color(0xFFE8FFD7), Color(0xFFA5D6A7)],
      ),
      _TurnaStickerItem(
        id: 'sparkles',
        emoji: '✨',
        label: 'Parla',
        colors: <Color>[Color(0xFFFFF2B2), Color(0xFFFFD166)],
      ),
    ],
  ),
  _TurnaStickerPack(
    id: 'hype',
    title: 'Hype',
    subtitle: 'Cevabi buyutmek istediginde kullan.',
    items: <_TurnaStickerItem>[
      _TurnaStickerItem(
        id: 'rocket',
        emoji: '🚀',
        label: 'Ucalim',
        colors: <Color>[Color(0xFFE0ECFF), Color(0xFF80B3FF)],
      ),
      _TurnaStickerItem(
        id: 'fire',
        emoji: '🔥',
        label: 'Alev',
        colors: <Color>[Color(0xFFFFD6A5), Color(0xFFFF7F51)],
      ),
      _TurnaStickerItem(
        id: 'star',
        emoji: '🌟',
        label: 'Yildiz',
        colors: <Color>[Color(0xFFFFF2A8), Color(0xFFFFC300)],
      ),
      _TurnaStickerItem(
        id: 'boom',
        emoji: '💥',
        label: 'Boom',
        colors: <Color>[Color(0xFFFFC6C6), Color(0xFFFF8A80)],
      ),
      _TurnaStickerItem(
        id: 'clap',
        emoji: '👏',
        label: 'Bravo',
        colors: <Color>[Color(0xFFFFE0B2), Color(0xFFFFB74D)],
      ),
      _TurnaStickerItem(
        id: 'trophy',
        emoji: '🏆',
        label: 'Kupayi al',
        colors: <Color>[Color(0xFFFFF1B8), Color(0xFFE0A800)],
      ),
      _TurnaStickerItem(
        id: 'spark',
        emoji: '⚡️',
        label: 'Hiz',
        colors: <Color>[Color(0xFFFFF7AE), Color(0xFFFFD54F)],
      ),
      _TurnaStickerItem(
        id: 'party-popper',
        emoji: '🎉',
        label: 'Kutlama',
        colors: <Color>[Color(0xFFFFD6E8), Color(0xFFFF9EC4)],
      ),
    ],
  ),
];

class _TurnaComposerEmojiPanel extends StatefulWidget {
  const _TurnaComposerEmojiPanel({
    required this.session,
    required this.visible,
    required this.onSelectEmoji,
    required this.onSelectSticker,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final bool visible;
  final ValueChanged<TurnaPackEmojiSelection> onSelectEmoji;
  final Future<void> Function(_TurnaStickerSelection selection) onSelectSticker;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaComposerEmojiPanel> createState() =>
      _TurnaComposerEmojiPanelState();
}

class _TurnaComposerEmojiPanelState extends State<_TurnaComposerEmojiPanel> {
  TurnaReactionPackCatalog? _catalog;
  final List<String> _sessionRecentEmojis = <String>[];
  final List<String> _sessionRecentStickerIds = <String>[];
  String? _selectedTabId;
  String? _selectedStickerTabId;
  _TurnaComposerPanelMode _mode = _TurnaComposerPanelMode.emoji;
  bool _loading = false;
  bool _updatingPreferences = false;
  bool _sendingSticker = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant _TurnaComposerEmojiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.visible && widget.visible && _catalog == null && !_loading) {
      unawaited(_load());
    }
  }

  List<String> get _recentEmojis {
    final merged = <String>[];
    for (final emoji in _sessionRecentEmojis) {
      if (!merged.contains(emoji)) {
        merged.add(emoji);
      }
    }
    for (final emoji
        in _catalog?.preferences.recentEmojis ?? const <String>[]) {
      if (!merged.contains(emoji)) {
        merged.add(emoji);
      }
    }
    return merged.take(16).toList();
  }

  List<_TurnaReactionPackTab> get _tabs {
    final catalog = _catalog;
    if (catalog == null) return const <_TurnaReactionPackTab>[];

    final tabs = <_TurnaReactionPackTab>[];
    if (catalog.preferences.favoriteEmojis.isNotEmpty) {
      tabs.add(
        _TurnaReactionPackTab(
          id: 'favorites',
          label: 'Favori',
          emojis: catalog.preferences.favoriteEmojis,
        ),
      );
    }
    if (_recentEmojis.isNotEmpty) {
      tabs.add(
        _TurnaReactionPackTab(
          id: 'recent',
          label: 'Son',
          emojis: _recentEmojis,
        ),
      );
    }
    for (final pack in catalog.packs.where(
      (item) => item.unlocked && item.installed,
    )) {
      tabs.add(
        _TurnaReactionPackTab(
          id: pack.id,
          label: pack.title,
          emojis: pack.emojis,
          pack: pack,
        ),
      );
    }
    return tabs;
  }

  List<_TurnaStickerTab> get _stickerTabs {
    final tabs = <_TurnaStickerTab>[];
    if (_sessionRecentStickerIds.isNotEmpty) {
      final recentItems = <_TurnaStickerItem>[];
      for (final id in _sessionRecentStickerIds) {
        final item = _stickerItemById(id);
        if (item != null) {
          recentItems.add(item);
        }
      }
      if (recentItems.isNotEmpty) {
        tabs.add(
          _TurnaStickerTab(
            id: 'recent',
            label: 'Son',
            previewEmoji: recentItems.first.emoji,
            items: recentItems,
          ),
        );
      }
    }
    for (final pack in _turnaStickerPacks) {
      tabs.add(
        _TurnaStickerTab(
          id: pack.id,
          label: pack.title,
          previewEmoji: pack.items.first.emoji,
          items: pack.items,
          pack: pack,
        ),
      );
    }
    return tabs;
  }

  void _syncSelectedTab() {
    final tabs = _tabs;
    if (tabs.isEmpty) {
      _selectedTabId = null;
      return;
    }
    if (!tabs.any((item) => item.id == _selectedTabId)) {
      _selectedTabId = tabs.first.id;
    }
  }

  void _syncSelectedStickerTab() {
    final tabs = _stickerTabs;
    if (tabs.isEmpty) {
      _selectedStickerTabId = null;
      return;
    }
    if (!tabs.any((item) => item.id == _selectedStickerTabId)) {
      _selectedStickerTabId = tabs.first.id;
    }
  }

  _TurnaReactionPackTab? get _selectedTab {
    final tabs = _tabs;
    if (tabs.isEmpty) return null;
    for (final tab in tabs) {
      if (tab.id == _selectedTabId) return tab;
    }
    return tabs.first;
  }

  _TurnaStickerTab? get _selectedStickerTab {
    final tabs = _stickerTabs;
    if (tabs.isEmpty) return null;
    for (final tab in tabs) {
      if (tab.id == _selectedStickerTabId) return tab;
    }
    return tabs.first;
  }

  TurnaReactionPack? _packForEmoji(String emoji, {String? preferredPackId}) {
    final catalog = _catalog;
    if (catalog == null) return null;
    if (preferredPackId != null) {
      final preferred = catalog.packs.where((item) {
        return item.id == preferredPackId &&
            item.unlocked &&
            item.emojis.contains(emoji);
      });
      if (preferred.isNotEmpty) return preferred.first;
    }
    final installed = catalog.packs.where(
      (item) => item.unlocked && item.installed && item.emojis.contains(emoji),
    );
    if (installed.isNotEmpty) return installed.first;
    final unlocked = catalog.packs.where(
      (item) => item.unlocked && item.emojis.contains(emoji),
    );
    if (unlocked.isNotEmpty) return unlocked.first;
    return null;
  }

  _TurnaStickerItem? _stickerItemById(String id) {
    for (final pack in _turnaStickerPacks) {
      for (final item in pack.items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await ChatApi.fetchReactionPacks(widget.session);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
        _syncSelectedTab();
        _syncSelectedStickerTab();
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _updatePreferences({
    List<String>? installedPackIds,
    List<String>? favoriteEmojis,
  }) async {
    setState(() => _updatingPreferences = true);
    try {
      final catalog = await ChatApi.updateReactionPackPreferences(
        widget.session,
        installedPackIds: installedPackIds,
        favoriteEmojis: favoriteEmojis,
      );
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _updatingPreferences = false;
        _syncSelectedTab();
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingPreferences = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleFavorite(String emoji) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final favorites = [...catalog.preferences.favoriteEmojis];
    if (favorites.contains(emoji)) {
      favorites.remove(emoji);
    } else {
      favorites.insert(0, emoji);
    }
    await _updatePreferences(favoriteEmojis: favorites);
  }

  Future<void> _toggleInstalledPack(TurnaReactionPack pack) async {
    if (!pack.unlocked) return;
    final catalog = _catalog;
    if (catalog == null) return;
    final installed = [...catalog.preferences.installedPackIds];
    if (installed.contains(pack.id)) {
      if (installed.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('En az bir paket kurulu kalmalı.')),
        );
        return;
      }
      installed.remove(pack.id);
    } else {
      installed.add(pack.id);
    }
    await _updatePreferences(installedPackIds: installed);
  }

  Future<void> _openManagePacks() async {
    final catalog = _catalog;
    if (catalog == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final latestCatalog = _catalog ?? catalog;
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  const Text(
                    'Emoji paketleri',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Kurulu paketler mesaj yazarken ve profil ruh halinda görünür.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: TurnaColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...latestCatalog.packs.map((pack) {
                    final accent = switch (pack.style) {
                      TurnaReactionPackStyle.premium => const Color(0xFFFFF3D8),
                      TurnaReactionPackStyle.community => const Color(
                        0xFFE8F4ED,
                      ),
                      TurnaReactionPackStyle.standard => Colors.white,
                    };
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: pack.installed
                              ? TurnaColors.primary
                              : TurnaColors.border,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              pack.emojis.isEmpty ? '🙂' : pack.emojis.first,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        pack.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    _TurnaPackStyleBadge(style: pack.style),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  pack.subtitle,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: TurnaColors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${pack.usageCount} kullanım',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: TurnaColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (!pack.unlocked)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                color: TurnaColors.textMuted,
                              ),
                            )
                          else
                            Switch.adaptive(
                              value: pack.installed,
                              onChanged: _updatingPreferences
                                  ? null
                                  : (_) async {
                                      setSheetState(() {});
                                      await _toggleInstalledPack(pack);
                                      if (!mounted) return;
                                      setSheetState(() {});
                                    },
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _handleEmojiTap(String emoji) {
    final selectedTab = _selectedTab;
    final pack = _packForEmoji(emoji, preferredPackId: selectedTab?.pack?.id);
    if (pack == null) return;

    setState(() {
      _sessionRecentEmojis.remove(emoji);
      _sessionRecentEmojis.insert(0, emoji);
      if (_sessionRecentEmojis.length > 16) {
        _sessionRecentEmojis.removeRange(16, _sessionRecentEmojis.length);
      }
    });
    widget.onSelectEmoji(
      TurnaPackEmojiSelection(packId: pack.id, emoji: emoji),
    );
  }

  Future<void> _handleStickerTap(_TurnaStickerItem sticker) async {
    if (_sendingSticker) return;
    final selectedTab = _selectedStickerTab;
    final pack =
        selectedTab?.pack ??
        _turnaStickerPacks.firstWhere(
          (item) => item.items.any((entry) => entry.id == sticker.id),
        );
    setState(() {
      _sessionRecentStickerIds.remove(sticker.id);
      _sessionRecentStickerIds.insert(0, sticker.id);
      if (_sessionRecentStickerIds.length > 16) {
        _sessionRecentStickerIds.removeRange(
          16,
          _sessionRecentStickerIds.length,
        );
      }
      _sendingSticker = true;
      _syncSelectedStickerTab();
    });
    try {
      await widget.onSelectSticker(
        _TurnaStickerSelection(
          packId: pack.id,
          packTitle: pack.title,
          stickerId: sticker.id,
          emoji: sticker.emoji,
          label: sticker.label,
          colors: sticker.colors,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _sendingSticker = false);
      }
    }
  }

  Widget _buildTabIcon(_TurnaReactionPackTab tab, bool selected) {
    if (tab.id == 'favorites') {
      return Icon(
        Icons.star_rounded,
        size: 18,
        color: selected ? Colors.white : const Color(0xFFF4B400),
      );
    }
    if (tab.id == 'recent') {
      return Icon(
        Icons.history_rounded,
        size: 18,
        color: selected ? Colors.white : TurnaColors.textMuted,
      );
    }
    final packEmoji = (tab.pack?.emojis.isNotEmpty ?? false)
        ? tab.pack!.emojis.first
        : '🙂';
    return Text(packEmoji, style: const TextStyle(fontSize: 20));
  }

  Widget _buildStickerTabIcon(_TurnaStickerTab tab, bool selected) {
    if (tab.id == 'recent') {
      return Icon(
        Icons.history_rounded,
        size: 18,
        color: selected ? Colors.white : TurnaColors.textMuted,
      );
    }
    return Text(tab.previewEmoji, style: const TextStyle(fontSize: 20));
  }

  Widget _buildModeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 38,
          decoration: BoxDecoration(
            color: selected ? TurnaColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : TurnaColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildEmojiSurface() {
    final selectedTab = _selectedTab;
    final title = selectedTab?.pack?.title ?? selectedTab?.label ?? 'İfade';
    final subtitle = selectedTab?.pack?.subtitle;
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _tabs.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final selected = tab.id == _selectedTabId;
                    return InkWell(
                      onTap: () => setState(() => _selectedTabId = tab.id),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: selected
                              ? TurnaColors.primary
                              : TurnaColors.backgroundMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : TurnaColors.border,
                          ),
                        ),
                        child: Center(child: _buildTabIcon(tab, selected)),
                      ),
                    );
                  },
                ),
              ),
            ),
            IconButton(
              onPressed: _updatingPreferences ? null : _openManagePacks,
              tooltip: 'Paketleri yönet',
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
      ),
      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_error != null)
        Expanded(
          child: Center(
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
          ),
        )
      else if (_tabs.isEmpty)
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Kurulu emoji paketi bulunamadı.',
                textAlign: TextAlign.center,
                style: TextStyle(color: TurnaColors.textMuted),
              ),
            ),
          ),
        )
      else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
          child: Column(
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: TurnaColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.04,
            ),
            itemCount: selectedTab?.emojis.length ?? 0,
            itemBuilder: (context, index) {
              final emoji = selectedTab!.emojis[index];
              final isFavorite = _catalog!.preferences.favoriteEmojis.contains(
                emoji,
              );
              return InkWell(
                onTap: () => _handleEmojiTap(emoji),
                onLongPress: () => _toggleFavorite(emoji),
                borderRadius: BorderRadius.circular(18),
                child: Ink(
                  decoration: BoxDecoration(
                    color: TurnaColors.backgroundMuted,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: TurnaColors.border),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                      if (isFavorite)
                        const Positioned(
                          top: 7,
                          right: 7,
                          child: Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Color(0xFFF4B400),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildStickerSurface() {
    final selectedTab = _selectedStickerTab;
    final title =
        selectedTab?.pack?.title ?? selectedTab?.label ?? 'Çıkartmalar';
    final subtitle = selectedTab?.pack?.subtitle;

    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _stickerTabs.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = _stickerTabs[index];
                    final selected = tab.id == _selectedStickerTabId;
                    return InkWell(
                      onTap: () =>
                          setState(() => _selectedStickerTabId = tab.id),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: selected
                              ? TurnaColors.primary
                              : TurnaColors.backgroundMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : TurnaColors.border,
                          ),
                        ),
                        child: Center(
                          child: _buildStickerTabIcon(tab, selected),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: _sendingSticker
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.auto_awesome_rounded,
                      color: TurnaColors.textMuted,
                    ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: TurnaColors.textMuted,
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              const Text(
                'Seçtiğin çıkartma gerçek resim mesajı olarak gider.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: TurnaColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.82,
          ),
          itemCount: selectedTab?.items.length ?? 0,
          itemBuilder: (context, index) {
            final item = selectedTab!.items[index];
            return InkWell(
              onTap: _sendingSticker ? null : () => _handleStickerTap(item),
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: item.colors,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: item.colors.last.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -14,
                      right: -10,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: Text(
                                item.emoji,
                                style: const TextStyle(fontSize: 42),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: TurnaColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: TurnaColors.backgroundMuted,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _buildModeChip(
                        label: 'İfade',
                        selected: _mode == _TurnaComposerPanelMode.emoji,
                        onTap: () => setState(
                          () => _mode = _TurnaComposerPanelMode.emoji,
                        ),
                      ),
                      _buildModeChip(
                        label: 'Çıkartmalar',
                        selected: _mode == _TurnaComposerPanelMode.sticker,
                        onTap: () => setState(
                          () => _mode = _TurnaComposerPanelMode.sticker,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ...(_mode == _TurnaComposerPanelMode.emoji
                ? _buildEmojiSurface()
                : _buildStickerSurface()),
          ],
        ),
      ),
    );
  }
}
