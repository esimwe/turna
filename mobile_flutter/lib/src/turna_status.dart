part of '../main.dart';

const List<Color> _kStatusTextBackgrounds = <Color>[
  Color(0xFF1F6FEB),
  Color(0xFF0F766E),
  Color(0xFF7C3AED),
  Color(0xFFD97706),
  Color(0xFFBE123C),
  Color(0xFF374151),
];
const int _kStatusGalleryPageSize = 24;
const Size _kStatusGalleryThumbSize = Size(160, 160);
const Size _kStatusCollageOutputSize = Size(1080, 1920);

List<cam.CameraDescription>? _kStatusCameraCache;

enum TurnaStatusCaptureMode { photo, video }

enum _StatusEntryTab { photos, albums }

class _StatusStoryFont {
  const _StatusStoryFont({required this.label, this.fontFamily});

  final String label;
  final String? fontFamily;
}

const List<_StatusStoryFont> _kStatusStoryFonts = <_StatusStoryFont>[
  _StatusStoryFont(label: 'Modern', fontFamily: 'SF Pro Display'),
  _StatusStoryFont(label: 'Klasik', fontFamily: 'Helvetica Neue'),
  _StatusStoryFont(label: 'Avenir', fontFamily: 'Avenir Next'),
  _StatusStoryFont(label: 'Serif', fontFamily: 'Georgia'),
  _StatusStoryFont(label: 'Daktilo', fontFamily: 'Courier'),
  _StatusStoryFont(label: 'Not', fontFamily: 'Noteworthy'),
];

class _StatusCollageLayout {
  const _StatusCollageLayout({
    required this.id,
    required this.label,
    required this.slots,
  });

  final String id;
  final String label;
  final List<Rect> slots;
}

const List<_StatusCollageLayout> _kStatusCollageLayouts = [
  _StatusCollageLayout(
    id: 'split-v',
    label: 'Iki dikey',
    slots: [Rect.fromLTWH(0, 0, 0.5, 1), Rect.fromLTWH(0.5, 0, 0.5, 1)],
  ),
  _StatusCollageLayout(
    id: 'split-h',
    label: 'Iki yatay',
    slots: [Rect.fromLTWH(0, 0, 1, 0.5), Rect.fromLTWH(0, 0.5, 1, 0.5)],
  ),
  _StatusCollageLayout(
    id: 'hero-right',
    label: 'Buyuk sol',
    slots: [
      Rect.fromLTWH(0, 0, 0.58, 1),
      Rect.fromLTWH(0.58, 0, 0.42, 0.5),
      Rect.fromLTWH(0.58, 0.5, 0.42, 0.5),
    ],
  ),
  _StatusCollageLayout(
    id: 'hero-top',
    label: 'Buyuk ust',
    slots: [
      Rect.fromLTWH(0, 0, 1, 0.56),
      Rect.fromLTWH(0, 0.56, 0.5, 0.44),
      Rect.fromLTWH(0.5, 0.56, 0.5, 0.44),
    ],
  ),
  _StatusCollageLayout(
    id: 'quad',
    label: 'Dortlu',
    slots: [
      Rect.fromLTWH(0, 0, 0.5, 0.5),
      Rect.fromLTWH(0.5, 0, 0.5, 0.5),
      Rect.fromLTWH(0, 0.5, 0.5, 0.5),
      Rect.fromLTWH(0.5, 0.5, 0.5, 0.5),
    ],
  ),
];

class StatusesPage extends StatefulWidget {
  const StatusesPage({
    super.key,
    required this.session,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final VoidCallback onSessionExpired;

  @override
  State<StatusesPage> createState() => _StatusesPageState();
}

class _StatusesPageState extends State<StatusesPage> {
  late Future<TurnaStatusFeedData> _feedFuture;
  TurnaStatusFeedData? _cachedFeed;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _feedFuture = _buildFeedFuture();
  }

  @override
  void didUpdateWidget(covariant StatusesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.session.userId != widget.session.userId) {
      _cachedFeed = null;
      _feedFuture = _buildFeedFuture();
    }
  }

  Future<TurnaStatusFeedData> _buildFeedFuture() {
    return TurnaStatusApi.fetchFeed(widget.session);
  }

  void _scheduleReload() {
    _feedFuture = _buildFeedFuture();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(_scheduleReload);
    try {
      await _feedFuture;
    } catch (_) {}
  }

  void _handleError(Object error) {
    if (error is TurnaUnauthorizedException) {
      widget.onSessionExpired();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _openUserFeed(String userId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => StatusViewerPage(
          session: widget.session,
          userId: userId,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted) return;
    setState(_scheduleReload);
  }

  Future<void> _openPrivacySettings(TurnaStatusPrivacySettings current) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StatusPrivacySettingsPage(
          session: widget.session,
          initialSettings: current,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(_scheduleReload);
    }
  }

  Future<void> _openCapturePage(TurnaStatusPrivacySettings privacy) async {
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StatusCreationEntryPage(
          session: widget.session,
          privacy: privacy,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (posted == true && mounted) {
      setState(_scheduleReload);
    }
  }

  Future<void> _toggleMuted(TurnaStatusAuthorSummary summary) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final muted = await TurnaStatusApi.setMuted(
        widget.session,
        userId: summary.user.id,
        muted: !summary.muted,
      );
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            muted
                ? '${summary.user.resolvedDisplayName} sessize alındı.'
                : '${summary.user.resolvedDisplayName} için durum sesi açıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TurnaStatusFeedData>(
      future: _feedFuture,
      initialData: _cachedFeed,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _cachedFeed;
        if (snapshot.hasData) {
          _cachedFeed = snapshot.data;
        }

        return Scaffold(
          backgroundColor: TurnaColors.backgroundSoft,
          appBar: AppBar(
            title: const Text('Durum'),
            actions: [
              IconButton(
                tooltip: 'Gizlilik',
                onPressed: data == null
                    ? null
                    : () => _openPrivacySettings(data.privacy),
                icon: const Icon(Icons.privacy_tip_outlined),
              ),
              IconButton(
                tooltip: 'Durum paylaş',
                onPressed: data == null
                    ? null
                    : () => _openCapturePage(data.privacy),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          body: Builder(
            builder: (context) {
              if (data == null &&
                  snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (data == null) {
                return _StatusErrorView(
                  title: 'Durumlar yüklenemedi',
                  onRetry: _reload,
                );
              }

              final updates = data.updates;
              final mutedUpdates = data.mutedUpdates;

              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    _MyStatusTile(
                      session: widget.session,
                      summary: data.mine,
                      onTap: () {
                        if (data.mine.hasStatuses) {
                          _openUserFeed(widget.session.userId);
                          return;
                        }
                        _openCapturePage(data.privacy);
                      },
                      onAdd: () => _openCapturePage(data.privacy),
                    ),
                    const SizedBox(height: 18),
                    if (updates.isNotEmpty) ...[
                      const _StatusSectionLabel('Yeni güncellemeler'),
                      const SizedBox(height: 10),
                      ...updates.map(
                        (summary) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _StatusSummaryTile(
                            summary: summary,
                            session: widget.session,
                            onTap: () => _openUserFeed(summary.user.id),
                            onMuteToggle: () => _toggleMuted(summary),
                          ),
                        ),
                      ),
                    ],
                    if (updates.isEmpty && mutedUpdates.isEmpty)
                      _StatusEmptyView(
                        onCreate: () => _openCapturePage(data.privacy),
                      ),
                    if (mutedUpdates.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const _StatusSectionLabel('Sessize alınanlar'),
                      const SizedBox(height: 10),
                      ...mutedUpdates.map(
                        (summary) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _StatusSummaryTile(
                            summary: summary,
                            session: widget.session,
                            onTap: () => _openUserFeed(summary.user.id),
                            onMuteToggle: () => _toggleMuted(summary),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MyStatusTile extends StatelessWidget {
  const _MyStatusTile({
    required this.session,
    required this.summary,
    required this.onTap,
    required this.onAdd,
  });

  final AuthSession session;
  final TurnaStatusMySummary summary;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final subtitle = summary.hasStatuses
        ? '${summary.previewText ?? 'Durum paylaşıldı'} • ${_formatStatusRelativeTime(summary.latestAt)}'
        : 'Fotoğraf, video veya metin durumunu paylaş';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _StatusRingAvatar(
                    radius: 28,
                    label: session.displayName,
                    avatarUrl: resolveTurnaSessionAvatarUrl(session),
                    authToken: session.token,
                    highlighted: summary.hasStatuses,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: TurnaColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Benim durumum',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: TurnaColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: TurnaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: TurnaColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusSummaryTile extends StatelessWidget {
  const _StatusSummaryTile({
    required this.summary,
    required this.session,
    required this.onTap,
    required this.onMuteToggle,
  });

  final TurnaStatusAuthorSummary summary;
  final AuthSession session;
  final VoidCallback onTap;
  final VoidCallback onMuteToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              _StatusRingAvatar(
                radius: 26,
                label: summary.user.resolvedDisplayName,
                avatarUrl: summary.user.avatarUrl,
                authToken: session.token,
                highlighted: summary.hasUnviewed,
                muted: summary.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.user.resolvedDisplayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TurnaColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.previewText} • ${_formatStatusRelativeTime(summary.latestAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: summary.hasUnviewed
                            ? TurnaColors.textSoft
                            : TurnaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (_) => onMuteToggle(),
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'mute',
                    child: Text(summary.muted ? 'Sesi aç' : 'Sessize al'),
                  ),
                ],
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: TurnaColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRingAvatar extends StatelessWidget {
  const _StatusRingAvatar({
    required this.radius,
    required this.label,
    required this.authToken,
    this.avatarUrl,
    this.highlighted = false,
    this.muted = false,
  });

  final double radius;
  final String label;
  final String authToken;
  final String? avatarUrl;
  final bool highlighted;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ringColor = muted
        ? const Color(0xFFCBD5E1)
        : highlighted
        ? TurnaColors.primary
        : const Color(0xFFD8E6F5);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: highlighted && !muted
            ? const LinearGradient(
                colors: [TurnaColors.accent, TurnaColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        border: highlighted || muted
            ? null
            : Border.all(color: ringColor, width: 1.6),
        color: highlighted || muted ? null : Colors.transparent,
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: muted ? ringColor : Colors.white,
            width: muted ? 2 : 3,
          ),
        ),
        child: _ProfileAvatar(
          label: label,
          avatarUrl: avatarUrl,
          authToken: authToken,
          radius: radius,
        ),
      ),
    );
  }
}

class _StatusSectionLabel extends StatelessWidget {
  const _StatusSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: TurnaColors.textMuted,
        ),
      ),
    );
  }
}

class _StatusEmptyView extends StatelessWidget {
  const _StatusEmptyView({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: TurnaColors.primary50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.auto_awesome_motion_rounded,
              color: TurnaColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Henüz yeni durum yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: TurnaColors.text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'İlk fotoğrafını, videonu veya metin durumunu paylaş. Paylaştıkların 24 saat görünür.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: TurnaColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Durum paylaş'),
          ),
        ],
      ),
    );
  }
}

class _StatusErrorView extends StatelessWidget {
  const _StatusErrorView({required this.title, required this.onRetry});

  final String title;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: TurnaColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: TurnaColors.text,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}

class StatusCreationEntryPage extends StatefulWidget {
  const StatusCreationEntryPage({
    super.key,
    required this.session,
    required this.privacy,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaStatusPrivacySettings privacy;
  final VoidCallback onSessionExpired;

  @override
  State<StatusCreationEntryPage> createState() =>
      _StatusCreationEntryPageState();
}

class _StatusCreationEntryPageState extends State<StatusCreationEntryPage> {
  _StatusEntryTab _tab = _StatusEntryTab.photos;
  bool _loading = true;
  String? _error;
  List<pm.AssetPathEntity> _albums = const <pm.AssetPathEntity>[];
  pm.AssetPathEntity? _selectedAlbum;
  List<pm.AssetEntity> _assets = const <pm.AssetEntity>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadGallery());
  }

  Future<void> _loadGallery({pm.AssetPathEntity? selectedAlbum}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final permission = await pm.PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        throw TurnaApiException('Galeri erisimi verilmedi.');
      }
      final albums = await pm.PhotoManager.getAssetPathList(
        onlyAll: false,
        type: pm.RequestType.common,
        filterOption: pm.FilterOptionGroup(
          orders: const <pm.OrderOption>[
            pm.OrderOption(type: pm.OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      final effectiveAlbum =
          selectedAlbum ??
          _selectedAlbum ??
          (albums.isEmpty ? null : albums.first);
      final assets = effectiveAlbum == null
          ? const <pm.AssetEntity>[]
          : await effectiveAlbum.getAssetListPaged(
              page: 0,
              size: _kStatusGalleryPageSize,
            );
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _selectedAlbum = effectiveAlbum;
        _assets = assets;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is TurnaApiException
            ? error.message
            : 'Galeri yuklenemedi.';
      });
    }
  }

  Future<void> _openCamera() async {
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StatusCapturePage(
          session: widget.session,
          privacy: widget.privacy,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (posted == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _openTextComposer() async {
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TextStatusComposerPage(
          session: widget.session,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (posted == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _openAsset(pm.AssetEntity asset) async {
    final file = await asset.file;
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Medya dosyasi acilamadi.')));
      return;
    }
    final fileName = file.uri.pathSegments.isEmpty
        ? 'durum-${DateTime.now().millisecondsSinceEpoch}'
        : file.uri.pathSegments.last;
    final type = asset.type == pm.AssetType.video
        ? TurnaStatusType.video
        : TurnaStatusType.image;
    if (!mounted) return;
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StatusMediaComposerPage(
          session: widget.session,
          file: XFile(
            file.path,
            name: fileName,
            mimeType: guessContentTypeForFileName(fileName),
          ),
          type: type,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (posted == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget _buildTabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? TurnaColors.text : TurnaColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.42,
          child: Column(
            children: [
              Container(
                height: 74,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: TurnaColors.primary, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: TurnaColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotosGrid() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: TurnaColors.textMuted),
          ),
        ),
      );
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _assets.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return GestureDetector(
            onTap: _openCamera,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_camera_rounded,
                    color: TurnaColors.text,
                    size: 30,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Kamera',
                    style: TextStyle(
                      color: TurnaColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final asset = _assets[index - 1];
        return _StatusGalleryAssetTile(
          asset: asset,
          onTap: () => _openAsset(asset),
        );
      },
    );
  }

  Widget _buildAlbumsList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_albums.isEmpty) {
      return const Center(
        child: Text(
          'Album bulunamadi.',
          style: TextStyle(color: TurnaColors.textMuted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: _albums.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final album = _albums[index];
        final selected = album.id == _selectedAlbum?.id;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              setState(() => _tab = _StatusEntryTab.photos);
              await _loadGallery(selectedAlbum: album);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_album_outlined,
                    color: selected
                        ? TurnaColors.primary
                        : TurnaColors.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      album.name,
                      style: const TextStyle(
                        color: TurnaColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: TurnaColors.primary,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9EDF2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _buildTabButton(
                            label: 'Fotoğraflar',
                            selected: _tab == _StatusEntryTab.photos,
                            onTap: () =>
                                setState(() => _tab = _StatusEntryTab.photos),
                          ),
                          _buildTabButton(
                            label: 'Albümler',
                            selected: _tab == _StatusEntryTab.albums,
                            onTap: () =>
                                setState(() => _tab = _StatusEntryTab.albums),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: Row(
                children: [
                  _buildQuickAction(
                    icon: Icons.text_fields_rounded,
                    label: 'Metin',
                    onTap: _openTextComposer,
                  ),
                  const SizedBox(width: 8),
                  _buildQuickAction(
                    icon: Icons.music_note_rounded,
                    label: 'Müzik',
                    onTap: null,
                  ),
                  const SizedBox(width: 8),
                  _buildQuickAction(
                    icon: Icons.grid_view_rounded,
                    label: 'Yerleşim',
                    onTap: null,
                  ),
                  const SizedBox(width: 8),
                  _buildQuickAction(
                    icon: Icons.mic_none_rounded,
                    label: 'Ses',
                    onTap: null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _tab == _StatusEntryTab.photos
                  ? _buildPhotosGrid()
                  : _buildAlbumsList(),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusCapturePage extends StatefulWidget {
  const StatusCapturePage({
    super.key,
    required this.session,
    required this.privacy,
    required this.onSessionExpired,
    this.initialMode = TurnaStatusCaptureMode.photo,
  });

  final AuthSession session;
  final TurnaStatusPrivacySettings privacy;
  final VoidCallback onSessionExpired;
  final TurnaStatusCaptureMode initialMode;

  @override
  State<StatusCapturePage> createState() => _StatusCapturePageState();
}

class _StatusCapturePageState extends State<StatusCapturePage>
    with WidgetsBindingObserver {
  cam.CameraController? _cameraController;
  Future<void>? _cameraInitFuture;
  List<cam.CameraDescription> _cameras = const [];
  cam.CameraDescription? _selectedCamera;
  TurnaStatusCaptureMode _mode = TurnaStatusCaptureMode.photo;
  bool _cameraInitializing = true;
  bool _cameraBusy = false;
  String? _cameraError;
  bool _galleryLoading = true;
  String? _galleryError;
  List<pm.AssetEntity> _recentAssets = const [];
  bool _collagePickerVisible = false;
  _StatusCollageLayout? _collageLayout;
  final List<XFile> _collageFrames = <XFile>[];
  bool _recording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  cam.FlashMode _flashMode = cam.FlashMode.off;

  bool get _cameraReady {
    final controller = _cameraController;
    return !_cameraInitializing &&
        _cameraError == null &&
        controller != null &&
        controller.value.isInitialized;
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrap());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _disposeCamera();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(
        _initializeCamera(
          preferredLensDirection:
              _selectedCamera?.lensDirection ?? cam.CameraLensDirection.back,
        ),
      );
    }
  }

  Future<void> _bootstrap() async {
    await _initializeCamera(
      preferredLensDirection: cam.CameraLensDirection.back,
    );
    if (!mounted) return;
    unawaited(_loadGalleryAfterWarmup());
  }

  Future<void> _loadGalleryAfterWarmup() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    await _loadGallery();
  }

  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    _cameraInitFuture = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<List<cam.CameraDescription>> _loadAvailableCameras() async {
    final cached = _kStatusCameraCache;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final cameras = await cam.availableCameras();
    _kStatusCameraCache = cameras;
    return cameras;
  }

  cam.CameraDescription _pickCamera(
    List<cam.CameraDescription> cameras,
    cam.CameraLensDirection preferredLensDirection,
  ) {
    for (final camera in cameras) {
      if (camera.lensDirection == preferredLensDirection) {
        return camera;
      }
    }
    return cameras.first;
  }

  Future<void> _initializeCamera({
    required cam.CameraLensDirection preferredLensDirection,
  }) async {
    if (!mounted) return;
    turnaLog('status camera init start', {
      'mode': _mode.name,
      'preferredLensDirection': preferredLensDirection.name,
    });
    setState(() {
      _cameraInitializing = true;
      _cameraError = null;
    });

    final previous = _cameraController;
    try {
      final cameras = await _loadAvailableCameras();
      if (cameras.isEmpty) {
        throw TurnaApiException('Kamera bulunamadi.');
      }
      final selected = _pickCamera(cameras, preferredLensDirection);
      final isVideoMode = _mode == TurnaStatusCaptureMode.video;
      final resolutionPreset = Platform.isIOS
          ? (isVideoMode
                ? cam.ResolutionPreset.medium
                : cam.ResolutionPreset.high)
          : (isVideoMode
                ? cam.ResolutionPreset.high
                : cam.ResolutionPreset.veryHigh);
      final controller = cam.CameraController(
        selected,
        resolutionPreset,
        enableAudio: isVideoMode,
      );
      _cameras = cameras;
      _selectedCamera = selected;
      _cameraController = controller;
      _cameraInitFuture = controller.initialize().then((_) async {
        try {
          await controller.setFlashMode(_flashMode);
        } catch (_) {}
        if (!Platform.isIOS) {
          try {
            await controller.lockCaptureOrientation(
              DeviceOrientation.portraitUp,
            );
          } catch (_) {}
        }
      });
      await _cameraInitFuture;
      await previous?.dispose();
      if (!mounted || _cameraController != controller) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraInitializing = false;
        _cameraError = null;
      });
      turnaLog('status camera init success', {
        'lensDirection': selected.lensDirection.name,
        'aspectRatio': controller.value.aspectRatio,
        'resolutionPreset': resolutionPreset.name,
      });
    } catch (error) {
      await previous?.dispose();
      turnaLog('status camera init failed', {'error': '$error'});
      if (!mounted) return;
      setState(() {
        _cameraController = null;
        _cameraInitFuture = null;
        _cameraInitializing = false;
        _cameraError = error is TurnaApiException
            ? error.message
            : 'Kamera acilamadi.';
      });
    }
  }

  Future<void> _loadGallery() async {
    if (!mounted) return;
    turnaLog('status gallery load start');
    setState(() {
      _galleryLoading = true;
      _galleryError = null;
    });

    try {
      final permission = await pm.PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        throw TurnaApiException('Galeri erisimi verilmedi.');
      }
      final albums = await pm.PhotoManager.getAssetPathList(
        onlyAll: true,
        type: pm.RequestType.common,
        filterOption: pm.FilterOptionGroup(
          orders: const <pm.OrderOption>[
            pm.OrderOption(type: pm.OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      final recent = albums.isEmpty ? null : albums.first;
      final assets = recent == null
          ? const <pm.AssetEntity>[]
          : await recent.getAssetListPaged(
              page: 0,
              size: _kStatusGalleryPageSize,
            );
      if (!mounted) return;
      setState(() {
        _recentAssets = assets;
        _galleryLoading = false;
        _galleryError = null;
      });
      turnaLog('status gallery load success', {'count': assets.length});
    } catch (error) {
      turnaLog('status gallery load failed', {'error': '$error'});
      if (!mounted) return;
      setState(() {
        _galleryLoading = false;
        _galleryError = error is TurnaApiException
            ? error.message
            : 'Galeri yuklenemedi.';
      });
    }
  }

  Future<void> _setMode(TurnaStatusCaptureMode mode) async {
    if (_mode == mode || _cameraBusy || _recording) return;
    setState(() {
      _mode = mode;
      if (mode != TurnaStatusCaptureMode.photo) {
        _collagePickerVisible = false;
        _collageLayout = null;
        _collageFrames.clear();
      }
    });
    await _initializeCamera(
      preferredLensDirection:
          _selectedCamera?.lensDirection ?? cam.CameraLensDirection.back,
    );
  }

  void _handlePreviewSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 220) return;
    if (velocity < 0 && _mode == TurnaStatusCaptureMode.photo) {
      _setMode(TurnaStatusCaptureMode.video);
    } else if (velocity > 0 && _mode == TurnaStatusCaptureMode.video) {
      _setMode(TurnaStatusCaptureMode.photo);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _cameraBusy || _recording) return;
    final current =
        _selectedCamera?.lensDirection ?? cam.CameraLensDirection.back;
    final next = current == cam.CameraLensDirection.front
        ? cam.CameraLensDirection.back
        : cam.CameraLensDirection.front;
    await _initializeCamera(preferredLensDirection: next);
  }

  Future<bool?> _openMediaComposer(XFile file, TurnaStatusType type) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StatusMediaComposerPage(
          session: widget.session,
          file: file,
          type: type,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _handleCapturePressed() async {
    if (_mode == TurnaStatusCaptureMode.video) {
      if (_recording) {
        await _stopVideoRecording();
      } else {
        await _startVideoRecording();
      }
      return;
    }
    await _takePhoto();
  }

  Future<void> _takePhoto() async {
    if (_cameraBusy || !_cameraReady) return;
    final controller = _cameraController;
    if (controller == null) return;
    setState(() => _cameraBusy = true);
    try {
      if (_cameraInitFuture != null) {
        await _cameraInitFuture;
      }
      final file = await controller.takePicture();
      if (!mounted) return;
      if (_collageLayout != null) {
        await _appendCollageFrame(file);
      } else {
        final posted = await _openMediaComposer(file, TurnaStatusType.image);
        if (posted == true && mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        error is TurnaApiException ? error.message : 'Fotograf cekilemedi.',
      );
    } finally {
      if (mounted) {
        setState(() => _cameraBusy = false);
      }
    }
  }

  Future<void> _startVideoRecording() async {
    if (_cameraBusy || !_cameraReady) return;
    final controller = _cameraController;
    if (controller == null) return;
    setState(() {
      _cameraBusy = true;
    });
    try {
      if (_cameraInitFuture != null) {
        await _cameraInitFuture;
      }
      if (Platform.isIOS) {
        await controller.prepareForVideoRecording();
      }
      await controller.startVideoRecording();
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        final next = _recordingDuration + const Duration(seconds: 1);
        if (next.inSeconds >= kStatusMaxVideoDurationSeconds) {
          timer.cancel();
          _stopVideoRecording();
          return;
        }
        setState(() => _recordingDuration = next);
      });
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordingDuration = Duration.zero;
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage('Video kaydi baslatilamadi.');
    } finally {
      if (mounted) {
        setState(() => _cameraBusy = false);
      }
    }
  }

  Future<void> _stopVideoRecording() async {
    final controller = _cameraController;
    if (controller == null || !_recording) return;
    setState(() => _cameraBusy = true);
    _recordingTimer?.cancel();
    try {
      final file = await controller.stopVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordingDuration = Duration.zero;
      });
      final posted = await _openMediaComposer(file, TurnaStatusType.video);
      if (posted == true && mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordingDuration = Duration.zero;
      });
      _showMessage('Video kaydi durdurulamadi.');
    } finally {
      if (mounted) {
        setState(() => _cameraBusy = false);
      }
    }
  }

  Future<void> _appendCollageFrame(XFile file) async {
    final layout = _collageLayout;
    if (layout == null) return;
    setState(() {
      if (_collageFrames.length >= layout.slots.length) {
        _collageFrames.clear();
      }
      _collageFrames.add(file);
    });
    if (_collageFrames.length < layout.slots.length) {
      _showMessage(
        '${_collageFrames.length}/${layout.slots.length} kare yerlestirildi.',
      );
      return;
    }

    try {
      final collageFile = await _renderCollageFile(layout, _collageFrames);
      if (!mounted) return;
      final posted = await _openMediaComposer(
        collageFile,
        TurnaStatusType.image,
      );
      if (posted == true && mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        error is TurnaApiException ? error.message : 'Kolaj hazirlanamadi.',
      );
    } finally {
      if (mounted) {
        setState(() => _collageFrames.clear());
      }
    }
  }

  Future<XFile> _renderCollageFile(
    _StatusCollageLayout layout,
    List<XFile> frames,
  ) async {
    final width = _kStatusCollageOutputSize.width.round();
    final height = _kStatusCollageOutputSize.height.round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    final backgroundPaint = Paint()..color = Colors.black;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      backgroundPaint,
    );

    for (var index = 0; index < layout.slots.length; index += 1) {
      final slot = layout.slots[index];
      final bytes = await frames[index].readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final targetRect = Rect.fromLTWH(
        slot.left * width,
        slot.top * height,
        slot.width * width,
        slot.height * height,
      );
      canvas.save();
      canvas.clipRect(targetRect);
      _paintStatusCoverImage(canvas, image, targetRect);
      canvas.restore();
    }

    final rendered = await recorder.endRecording().toImage(width, height);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw TurnaApiException('Kolaj hazirlanamadi.');
    }
    final encoded = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final jpgBytes = Uint8List.fromList(img.encodeJpg(encoded, quality: 92));
    final tempDir = await getTemporaryDirectory();
    final fileName =
        'status-collage-${DateTime.now().millisecondsSinceEpoch}.jpg';
    final output = File('${tempDir.path}/$fileName');
    await output.writeAsBytes(jpgBytes, flush: true);
    return XFile(output.path, mimeType: 'image/jpeg', name: fileName);
  }

  Future<void> _handleGalleryAssetTap(pm.AssetEntity asset) async {
    if (_cameraBusy) return;
    final file = await asset.file;
    if (file == null) {
      _showMessage('Medya dosyasi acilamadi.');
      return;
    }
    final fileName = file.uri.pathSegments.isEmpty
        ? 'durum-${DateTime.now().millisecondsSinceEpoch}'
        : file.uri.pathSegments.last;
    final type = asset.type == pm.AssetType.video
        ? TurnaStatusType.video
        : TurnaStatusType.image;
    final picked = XFile(
      file.path,
      name: fileName,
      mimeType: guessContentTypeForFileName(fileName),
    );
    if (_collageLayout != null && type == TurnaStatusType.image) {
      await _appendCollageFrame(picked);
      return;
    }
    final posted = await _openMediaComposer(picked, type);
    if (posted == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _openGallerySheet() async {
    if (_cameraBusy || _recording) return;
    if (_recentAssets.isEmpty && !_galleryLoading) {
      await _loadGallery();
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      const Text(
                        'Son zamanlarda',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (_galleryLoading) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      }
                      if (_galleryError != null) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _galleryError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        );
                      }
                      if (_recentAssets.isEmpty) {
                        return const Center(
                          child: Text(
                            'Galeride gosterilecek medya bulunamadi.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                            ),
                        itemCount: _recentAssets.length,
                        itemBuilder: (context, index) {
                          final asset = _recentAssets[index];
                          return _StatusGalleryAssetTile(
                            asset: asset,
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              await _handleGalleryAssetTap(asset);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (controller == null || !_cameraReady || _cameraBusy || _recording) {
      return;
    }
    final next = _flashMode == cam.FlashMode.off
        ? cam.FlashMode.always
        : cam.FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (!mounted) return;
      setState(() => _flashMode = next);
    } catch (_) {
      _showMessage('Flash ayarlanamadi.');
    }
  }

  Future<void> _switchToTextComposer() async {
    if (_cameraBusy || _recording) return;
    final posted = await Navigator.pushReplacement<bool, bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TextStatusComposerPage(
          session: widget.session,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (posted == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  void _toggleCollagePicker() {
    if (_mode != TurnaStatusCaptureMode.photo || _cameraBusy || _recording) {
      return;
    }
    setState(() {
      _collagePickerVisible = !_collagePickerVisible;
    });
  }

  void _selectCollageLayout(_StatusCollageLayout? layout) {
    setState(() {
      _collageLayout = layout;
      _collageFrames.clear();
      _collagePickerVisible = false;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildPreviewLayer() {
    final controller = _cameraController;
    if (_cameraError != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              color: Colors.white70,
              size: 42,
            ),
            const SizedBox(height: 14),
            Text(
              _cameraError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      );
    }
    if (_cameraInitializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Colors.white),
      );
    }
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: cam.CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildCollageOverlay() {
    final layout = _collageLayout;
    if (layout == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: List<Widget>.generate(layout.slots.length, (index) {
                final slot = layout.slots[index];
                final left = slot.left * constraints.maxWidth;
                final top = slot.top * constraints.maxHeight;
                final width = slot.width * constraints.maxWidth;
                final height = slot.height * constraints.maxHeight;
                final file = index < _collageFrames.length
                    ? File(_collageFrames[index].path)
                    : null;
                return Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white70, width: 1.1),
                      color: file == null
                          ? Colors.black.withValues(alpha: 0.24)
                          : Colors.transparent,
                    ),
                    child: file == null
                        ? Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : Image.file(file, fit: BoxFit.cover),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final collageSlots = _collageLayout?.slots.length ?? 0;
    final collageProgress = collageSlots == 0
        ? null
        : '${_collageFrames.length}/$collageSlots kare';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (_mode == TurnaStatusCaptureMode.photo)
                  _StatusCaptureTopButton(
                    icon: Icons.grid_view_rounded,
                    selected: _collagePickerVisible || _collageLayout != null,
                    onTap: _toggleCollagePicker,
                  ),
                if (_mode == TurnaStatusCaptureMode.photo)
                  const SizedBox(width: 10),
                if (collageProgress != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      collageProgress,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const Spacer(),
                _StatusCaptureTopButton(
                  icon: _flashMode == cam.FlashMode.off
                      ? Icons.flash_off_rounded
                      : Icons.flash_on_rounded,
                  onTap: _toggleFlash,
                ),
                const SizedBox(width: 10),
                _StatusCaptureTopButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            if (_mode == TurnaStatusCaptureMode.photo &&
                _collagePickerVisible) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _StatusCollageLayoutTile(
                      label: 'Tekli',
                      selected: _collageLayout == null,
                      onTap: () => _selectCollageLayout(null),
                      child: const Icon(
                        Icons.crop_portrait_rounded,
                        color: Colors.white,
                      ),
                    ),
                    ..._kStatusCollageLayouts.map(
                      (layout) => _StatusCollageLayoutTile(
                        label: layout.label,
                        selected: _collageLayout?.id == layout.id,
                        onTap: () => _selectCollageLayout(layout),
                        child: _StatusCollageLayoutPreview(layout: layout),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_recording)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${_recordingDuration.inSeconds.toString().padLeft(2, '0')} sn',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatusGalleryLauncherButton(
                  asset: _recentAssets.isEmpty ? null : _recentAssets.first,
                  onTap: _openGallerySheet,
                ),
                _StatusCaptureShutterButton(
                  mode: _mode,
                  recording: _recording,
                  busy: _cameraBusy,
                  onTap: _handleCapturePressed,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        '1x',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusCaptureTopButton(
                      icon: Icons.cameraswitch_rounded,
                      compact: true,
                      onTap: _switchCamera,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusModeChip(
                    label: 'VIDEO',
                    selected: _mode == TurnaStatusCaptureMode.video,
                    onTap: () => _setMode(TurnaStatusCaptureMode.video),
                  ),
                  _StatusModeChip(
                    label: 'FOTOGRAF',
                    selected: _mode == TurnaStatusCaptureMode.photo,
                    onTap: () => _setMode(TurnaStatusCaptureMode.photo),
                  ),
                  _StatusModeChip(
                    label: 'METIN',
                    selected: false,
                    onTap: _switchToTextComposer,
                  ),
                  const _StatusModeChip(
                    label: 'SES',
                    selected: false,
                    enabled: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onHorizontalDragEnd: _handlePreviewSwipe,
        child: Stack(
          children: [
            Positioned.fill(child: _buildPreviewLayer()),
            _buildCollageOverlay(),
            Positioned(left: 0, right: 0, top: 0, child: _buildTopBar()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomControls(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCaptureTopButton extends StatelessWidget {
  const _StatusCaptureTopButton({
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.compact = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 42.0 : 46.0;
    return Material(
      color: selected
          ? TurnaColors.primary.withValues(alpha: 0.92)
          : Colors.black.withValues(alpha: 0.34),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _StatusModeChip extends StatelessWidget {
  const _StatusModeChip({
    required this.label,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Colors.white38
        : selected
        ? const Color(0xFFF7D543)
        : Colors.white;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatusCaptureShutterButton extends StatelessWidget {
  const _StatusCaptureShutterButton({
    required this.mode,
    required this.recording,
    required this.busy,
    required this.onTap,
  });

  final TurnaStatusCaptureMode mode;
  final bool recording;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isVideo = mode == TurnaStatusCaptureMode.video;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: busy ? 0.42 : 0.95),
            width: 4,
          ),
          color: Colors.white.withValues(alpha: 0.12),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: recording ? 28 : 62,
            height: recording ? 28 : 62,
            decoration: BoxDecoration(
              color: isVideo ? const Color(0xFFEF4444) : Colors.white,
              borderRadius: BorderRadius.circular(recording ? 10 : 31),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusGalleryLauncherButton extends StatelessWidget {
  const _StatusGalleryLauncherButton({
    required this.asset,
    required this.onTap,
  });

  final pm.AssetEntity? asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          color: Colors.black.withValues(alpha: 0.3),
        ),
        clipBehavior: Clip.antiAlias,
        child: asset == null
            ? const Icon(Icons.photo_library_outlined, color: Colors.white)
            : FutureBuilder<Uint8List?>(
                future: asset!.thumbnailDataWithSize(
                  pm.ThumbnailSize(
                    _kStatusGalleryThumbSize.width.round(),
                    _kStatusGalleryThumbSize.height.round(),
                  ),
                  quality: 90,
                ),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null || bytes.isEmpty) {
                    return const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                    );
                  }
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),
      ),
    );
  }
}

class _StatusGalleryAssetTile extends StatelessWidget {
  const _StatusGalleryAssetTile({required this.asset, required this.onTap});

  final pm.AssetEntity asset;
  final VoidCallback onTap;

  String _durationLabel(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remaining = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remaining';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: asset.thumbnailDataWithSize(
                pm.ThumbnailSize(
                  _kStatusGalleryThumbSize.width.round(),
                  _kStatusGalleryThumbSize.height.round(),
                ),
                quality: 88,
              ),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null || bytes.isEmpty) {
                  return ColoredBox(
                    color: Colors.white.withValues(alpha: 0.06),
                    child: const Icon(
                      Icons.photo_outlined,
                      color: Colors.white70,
                    ),
                  );
                }
                return Image.memory(bytes, fit: BoxFit.cover);
              },
            ),
            if (asset.type == pm.AssetType.video)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Row(
                  children: [
                    const Icon(
                      Icons.videocam_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _durationLabel(asset.duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusCollageLayoutTile extends StatelessWidget {
  const _StatusCollageLayoutTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 86,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? TurnaColors.primary.withValues(alpha: 0.92)
                : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: selected ? 0.22 : 0.1),
            ),
          ),
          child: Column(
            children: [
              Expanded(child: Center(child: child)),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCollageLayoutPreview extends StatelessWidget {
  const _StatusCollageLayoutPreview({required this.layout});

  final _StatusCollageLayout layout;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: layout.slots.map((slot) {
                return Positioned(
                  left: slot.left * constraints.maxWidth,
                  top: slot.top * constraints.maxHeight,
                  width: slot.width * constraints.maxWidth,
                  height: slot.height * constraints.maxHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.75),
                        width: 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class TextStatusComposerPage extends StatefulWidget {
  const TextStatusComposerPage({
    super.key,
    required this.session,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final VoidCallback onSessionExpired;

  @override
  State<TextStatusComposerPage> createState() => _TextStatusComposerPageState();
}

class _TextStatusComposerPageState extends State<TextStatusComposerPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedColorIndex = 0;
  int _selectedFontIndex = 0;
  bool _saving = false;
  Offset _textPosition = const Offset(0.5, 0.5);
  double _textScale = 1;
  double _textScaleBase = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;

    final background = _kStatusTextBackgrounds[_selectedColorIndex];
    final textColor = _statusTextForegroundFor(background);

    setState(() => _saving = true);
    try {
      await TurnaStatusApi.createTextStatus(
        widget.session,
        text: text,
        backgroundColor: _colorToHex(background),
        textColor: _colorToHex(textColor),
        textLayout: TurnaStatusTextLayout(
          x: _textPosition.dx,
          y: _textPosition.dy,
          scale: _textScale,
          fontFamily: _kStatusStoryFonts[_selectedFontIndex].fontFamily,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Offset _clampTextPosition(Offset value) {
    return Offset(value.dx.clamp(0.18, 0.82), value.dy.clamp(0.18, 0.82));
  }

  void _handleScaleStart() {
    _textScaleBase = _textScale;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, Size canvasSize) {
    setState(() {
      _textScale = (_textScaleBase * details.scale).clamp(0.8, 2.8);
      _textPosition = _clampTextPosition(
        Offset(
          _textPosition.dx + (details.focalPointDelta.dx / canvasSize.width),
          _textPosition.dy + (details.focalPointDelta.dy / canvasSize.height),
        ),
      );
    });
  }

  Future<void> _openFontPicker() async {
    final nextIndex = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C2730),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            itemBuilder: (context, index) {
              final preset = _kStatusStoryFonts[index];
              final selected = index == _selectedFontIndex;
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                tileColor: selected
                    ? TurnaColors.primary.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.04),
                title: Text(
                  preset.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamily: preset.fontFamily,
                  ),
                ),
                trailing: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: TurnaColors.accent,
                      )
                    : null,
                onTap: () => Navigator.pop(context, index),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemCount: _kStatusStoryFonts.length,
          ),
        );
      },
    );
    if (nextIndex == null || !mounted) return;
    setState(() => _selectedFontIndex = nextIndex);
  }

  Future<void> _openPalettePicker() async {
    final nextIndex = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C2730),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: List<Widget>.generate(_kStatusTextBackgrounds.length, (
                index,
              ) {
                final color = _kStatusTextBackgrounds[index];
                final selected = index == _selectedColorIndex;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: selected ? 50 : 42,
                    height: selected ? 50 : 42,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: selected ? 0.95 : 0.5,
                        ),
                        width: selected ? 3 : 1.4,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
    if (nextIndex == null || !mounted) return;
    setState(() => _selectedColorIndex = nextIndex);
  }

  Future<void> _switchToCamera(TurnaStatusCaptureMode mode) async {
    if (_saving) return;
    final posted = await Navigator.pushReplacement<bool, bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StatusCapturePage(
          session: widget.session,
          privacy: TurnaStatusPrivacySettings(
            mode: TurnaStatusPrivacyMode.myContacts,
          ),
          onSessionExpired: widget.onSessionExpired,
          initialMode: mode,
        ),
      ),
    );
    if (posted == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget _buildActionButton({
    required Widget child,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.26),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Center(child: child)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = _kStatusTextBackgrounds[_selectedColorIndex];
    final textColor = _statusTextForegroundFor(background);
    final fontPreset = _kStatusStoryFonts[_selectedFontIndex];

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  _buildActionButton(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  _buildActionButton(
                    onTap: _openFontPicker,
                    child: const Text(
                      'Aa',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildActionButton(
                    onTap: _openPalettePicker,
                    child: const Icon(
                      Icons.palette_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildActionButton(
                    onTap: _saving ? () {} : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final offset = Offset(
                    (_textPosition.dx - 0.5) * constraints.maxWidth,
                    (_textPosition.dy - 0.5) * constraints.maxHeight,
                  );
                  return Center(
                    child: Transform.translate(
                      offset: offset,
                      child: Transform.scale(
                        scale: _textScale,
                        child: GestureDetector(
                          onTap: () => _focusNode.requestFocus(),
                          onScaleStart: (_) => _handleScaleStart(),
                          onScaleUpdate: (details) =>
                              _handleScaleUpdate(details, constraints.biggest),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.84,
                            ),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autofocus: true,
                              maxLength: 700,
                              maxLines: null,
                              minLines: 1,
                              textAlign: TextAlign.center,
                              cursorColor: textColor,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 34,
                                height: 1.16,
                                fontWeight: FontWeight.w800,
                                fontFamily: fontPreset.fontFamily,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black26,
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              decoration: InputDecoration(
                                hintText: 'Durum güncellemesi yazı',
                                hintStyle: TextStyle(
                                  color: textColor.withValues(alpha: 0.42),
                                  fontWeight: FontWeight.w700,
                                  fontFamily: fontPreset.fontFamily,
                                ),
                                border: InputBorder.none,
                                counterStyle: TextStyle(
                                  color: textColor.withValues(alpha: 0.78),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusModeChip(
                        label: 'VIDEO',
                        selected: false,
                        onTap: () =>
                            _switchToCamera(TurnaStatusCaptureMode.video),
                      ),
                      _StatusModeChip(
                        label: 'FOTOGRAF',
                        selected: false,
                        onTap: () =>
                            _switchToCamera(TurnaStatusCaptureMode.photo),
                      ),
                      const _StatusModeChip(label: 'METIN', selected: true),
                      const _StatusModeChip(
                        label: 'SES',
                        selected: false,
                        enabled: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusMediaComposerPage extends StatelessWidget {
  const StatusMediaComposerPage({
    super.key,
    required this.session,
    required this.file,
    required this.type,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final XFile file;
  final TurnaStatusType type;
  final VoidCallback onSessionExpired;

  Future<bool> _submitPrepared(
    List<_PreparedComposerAttachment> attachments,
    String? caption,
    MediaComposerQuality quality,
  ) async {
    if (attachments.isEmpty) {
      throw TurnaApiException('Paylasilacak medya bulunamadi.');
    }
    final prepared = attachments.first;
    final fileName = prepared.fileName.trim().isEmpty
        ? 'durum-${DateTime.now().millisecondsSinceEpoch}'
        : prepared.fileName.trim();
    final contentType = prepared.contentType.trim().isEmpty
        ? (type == TurnaStatusType.video ? 'video/mp4' : 'image/jpeg')
        : prepared.contentType.trim();

    int? width = prepared.width;
    int? height = prepared.height;
    int? durationSeconds;

    if (type == TurnaStatusType.video) {
      final controller = vp.VideoPlayerController.file(File(file.path));
      try {
        await controller.initialize();
        durationSeconds = controller.value.duration.inSeconds;
        if (durationSeconds > kStatusMaxVideoDurationSeconds) {
          throw TurnaApiException(
            'Video en fazla $kStatusMaxVideoDurationSeconds saniye olabilir.',
          );
        }
        width = controller.value.size.width.round();
        height = controller.value.size.height.round();
      } finally {
        await controller.dispose();
      }
    }

    final upload = await TurnaStatusApi.createUpload(
      session,
      type: type,
      contentType: contentType,
      fileName: fileName,
    );

    final uploadRes = await http.put(
      Uri.parse(upload.uploadUrl),
      headers: upload.headers,
      body: prepared.bytes,
    );
    if (uploadRes.statusCode >= 400) {
      throw TurnaApiException('Dosya yüklenemedi.');
    }

    await TurnaStatusApi.createMediaStatus(
      session,
      type: type,
      objectKey: upload.objectKey,
      contentType: contentType,
      fileName: fileName,
      sizeBytes: prepared.bytes.length,
      width: width,
      height: height,
      durationSeconds: durationSeconds,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    int sizeBytes = 0;
    try {
      sizeBytes = File(file.path).lengthSync();
    } catch (_) {}

    return _MediaComposerPage(
      session: session,
      items: [
        MediaComposerSeed(
          kind: type == TurnaStatusType.video
              ? ChatAttachmentKind.video
              : ChatAttachmentKind.image,
          file: file,
          fileName: file.name.trim().isEmpty
              ? 'durum-${DateTime.now().millisecondsSinceEpoch}'
              : file.name.trim(),
          contentType: file.mimeType?.trim().isNotEmpty == true
              ? file.mimeType!.trim()
              : (guessContentTypeForFileName(file.name) ??
                    (type == TurnaStatusType.video
                        ? 'video/mp4'
                        : 'image/jpeg')),
          sizeBytes: sizeBytes,
        ),
      ],
      onSessionExpired: onSessionExpired,
      onPreparedSend: _submitPrepared,
      captionEnabled: false,
    );
  }
}

class StatusViewerPage extends StatefulWidget {
  const StatusViewerPage({
    super.key,
    required this.session,
    required this.userId,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String userId;
  final VoidCallback onSessionExpired;

  @override
  State<StatusViewerPage> createState() => _StatusViewerPageState();
}

class _StatusViewerPageState extends State<StatusViewerPage> {
  late Future<TurnaStatusUserFeed> _feedFuture;
  TurnaStatusUserFeed? _feed;
  int _index = 0;
  Timer? _imageTimer;
  double _progress = 0;
  bool _statusMarkedBusy = false;
  vp.VideoPlayerController? _videoController;
  Future<void>? _videoFuture;

  @override
  void initState() {
    super.initState();
    _feedFuture = TurnaStatusApi.fetchUserFeed(widget.session, widget.userId);
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.pop(context);
  }

  Future<void> _activateCurrentItem() async {
    _imageTimer?.cancel();
    _imageTimer = null;
    await _disposeVideo();

    final feed = _feed;
    if (feed == null || feed.items.isEmpty || !mounted) return;
    final item = feed.items[_index];
    _progress = 0;
    if (!feed.own && !item.viewedByMe && !_statusMarkedBusy) {
      _statusMarkedBusy = true;
      TurnaStatusApi.markViewed(
        widget.session,
        item.id,
      ).catchError((_) {}).whenComplete(() => _statusMarkedBusy = false);
    }

    if (item.isVideo && item.url != null) {
      await _prepareVideo(item);
      return;
    }
    _startImageTimer();
  }

  void _startImageTimer() {
    _imageTimer?.cancel();
    const totalMs = 5000;
    var elapsed = 0;
    _imageTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      elapsed += 50;
      if (!mounted) return;
      setState(() {
        _progress = (elapsed / totalMs).clamp(0, 1).toDouble();
      });
      if (elapsed >= totalMs) {
        timer.cancel();
        _goNext();
      }
    });
  }

  Future<void> _disposeVideo() async {
    await _videoController?.dispose();
    _videoController = null;
    _videoFuture = null;
  }

  Future<void> _prepareVideo(TurnaStatusItem item) async {
    final url = item.url;
    if (url == null || url.trim().isEmpty) {
      _startImageTimer();
      return;
    }

    try {
      final cachedFile = await TurnaLocalMediaCache.getOrDownloadFile(
        cacheKey: 'status:${item.objectKey ?? item.id}',
        url: url,
        authToken: widget.session.token,
      );
      if (cachedFile == null) {
        _startImageTimer();
        return;
      }
      final preparedFile = await TurnaLocalMediaCache.prepareMediaFile(
        cacheKey: 'status:${item.objectKey ?? item.id}',
        sourceFile: cachedFile,
        mimeType: item.contentType,
        fileName: item.fileName,
      );
      final controller = vp.VideoPlayerController.file(preparedFile);
      final future = controller.initialize().then((_) async {
        await controller.setLooping(false);
        await controller.play();
      });
      controller.addListener(() {
        if (!mounted || !controller.value.isInitialized) return;
        final totalMs = controller.value.duration.inMilliseconds;
        final posMs = controller.value.position.inMilliseconds;
        if (totalMs > 0) {
          setState(() {
            _progress = (posMs / totalMs).clamp(0, 1).toDouble();
          });
        }
        if (!controller.value.isPlaying &&
            controller.value.position >= controller.value.duration &&
            totalMs > 0) {
          _goNext();
        }
      });
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _videoFuture = future;
      });
      await future;
    } catch (_) {
      if (!mounted) return;
      _startImageTimer();
    }
  }

  void _goNext() {
    final feed = _feed;
    if (feed == null) return;
    if (_index >= feed.items.length - 1) {
      _close();
      return;
    }
    setState(() {
      _index++;
      _progress = 0;
    });
    unawaited(_activateCurrentItem());
  }

  void _goPrevious() {
    if (_index <= 0) return;
    setState(() {
      _index--;
      _progress = 0;
    });
    unawaited(_activateCurrentItem());
  }

  Future<void> _showViewers(TurnaStatusItem item) async {
    try {
      final viewers = await TurnaStatusApi.fetchViewers(
        widget.session,
        item.id,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${viewers.length} görüntüleme',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: TurnaColors.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (viewers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'Bu durumu henüz gören olmadı.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: viewers.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          color: TurnaColors.divider,
                        ),
                        itemBuilder: (context, index) {
                          final viewer = viewers[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: _ProfileAvatar(
                              label: viewer.user.resolvedDisplayName,
                              avatarUrl: viewer.user.avatarUrl,
                              authToken: widget.session.token,
                              radius: 22,
                            ),
                            title: Text(viewer.user.resolvedDisplayName),
                            subtitle: Text(
                              _formatStatusRelativeTime(viewer.viewedAt),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<TurnaStatusUserFeed>(
        future: _feedFuture,
        builder: (context, snapshot) {
          final feed = snapshot.data ?? _feed;
          if (snapshot.hasData && _feed != snapshot.data) {
            _feed = snapshot.data;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              unawaited(_activateCurrentItem());
            });
          }

          if (feed == null &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (snapshot.hasError || feed == null || feed.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.history_toggle_off_rounded,
                      color: Colors.white70,
                      size: 44,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Durum bulunamadı',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _close, child: const Text('Kapat')),
                  ],
                ),
              ),
            );
          }

          final item = feed.items[_index];

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final width = MediaQuery.of(context).size.width;
              if (details.localPosition.dx < width * 0.35) {
                _goPrevious();
              } else {
                _goNext();
              }
            },
            child: Stack(
              children: [
                Positioned.fill(child: _buildStatusBody(item)),
                Positioned(
                  left: 12,
                  right: 12,
                  top: MediaQuery.of(context).padding.top + 10,
                  child: Row(
                    children: List<Widget>.generate(feed.items.length, (index) {
                      final value = index < _index
                          ? 1.0
                          : index == _index
                          ? _progress
                          : 0.0;
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: EdgeInsets.only(
                            right: index == feed.items.length - 1 ? 0 : 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: FractionallySizedBox(
                            widthFactor: value,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: MediaQuery.of(context).padding.top + 24,
                  child: Row(
                    children: [
                      _ProfileAvatar(
                        label: feed.user.resolvedDisplayName,
                        avatarUrl: feed.user.avatarUrl,
                        authToken: widget.session.token,
                        radius: 21,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              feed.user.resolvedDisplayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              _formatStatusRelativeTime(item.createdAt),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _close,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (feed.own)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 18,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: GestureDetector(
                        onTap: () => _showViewers(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.remove_red_eye_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.viewedCount} görüntüleme',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBody(TurnaStatusItem item) {
    if (item.isText) {
      final bg = _colorFromHex(item.backgroundColor, const Color(0xFF1F6FEB));
      final fg = _colorFromHex(item.textColor, Colors.white);
      final layout =
          item.textLayout ??
          TurnaStatusTextLayout(x: 0.5, y: 0.5, scale: 1, fontFamily: null);
      return ColoredBox(
        color: bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final offset = Offset(
              (layout.x - 0.5) * constraints.maxWidth,
              (layout.y - 0.5) * constraints.maxHeight,
            );
            return Center(
              child: Transform.translate(
                offset: offset,
                child: Transform.scale(
                  scale: layout.scale,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.82,
                    ),
                    child: Text(
                      item.text?.trim().isNotEmpty == true
                          ? item.text!.trim()
                          : 'Durum',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fg,
                        fontSize: 32,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        fontFamily: layout.fontFamily,
                        shadows: const [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    if (item.isVideo) {
      final controller = _videoController;
      final future = _videoFuture;
      if (controller == null || future == null) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return FutureBuilder<void>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              !controller.value.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          return Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: vp.VideoPlayer(controller),
            ),
          );
        },
      );
    }

    final imageUrl = item.url?.trim() ?? '';
    if (imageUrl.isEmpty) {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white70,
          size: 42,
        ),
      );
    }

    return _TurnaCachedImage(
      cacheKey: 'status:${item.objectKey ?? item.id}',
      imageUrl: imageUrl,
      authToken: widget.session.token,
      fit: BoxFit.contain,
      loading: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      error: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white70,
          size: 42,
        ),
      ),
    );
  }
}

class StatusPrivacySettingsPage extends StatefulWidget {
  const StatusPrivacySettingsPage({
    super.key,
    required this.session,
    required this.initialSettings,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaStatusPrivacySettings initialSettings;
  final VoidCallback onSessionExpired;

  @override
  State<StatusPrivacySettingsPage> createState() =>
      _StatusPrivacySettingsPageState();
}

class _StatusPrivacySettingsPageState extends State<StatusPrivacySettingsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<TurnaRegisteredContact> _contacts = const <TurnaRegisteredContact>[];
  late TurnaStatusPrivacyMode _mode;
  late Set<String> _selectedUserIds;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialSettings.mode;
    _selectedUserIds = widget.initialSettings.targetUserIds.toSet();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final contacts = await ChatApi.fetchRegisteredContacts(widget.session);
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await TurnaStatusApi.updatePrivacySettings(
        widget.session,
        mode: _mode,
        targetUserIds: _selectedUserIds.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Iterable<TurnaRegisteredContact> get _filteredContacts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    return _contacts.where((contact) {
      final haystack = [
        contact.resolvedTitle,
        contact.username ?? '',
        contact.phone ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    });
  }

  bool get _needsSelection =>
      _mode == TurnaStatusPrivacyMode.excludedContacts ||
      _mode == TurnaStatusPrivacyMode.onlySharedWith;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        title: const Text('Durum gizliliği'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: Text(
              _saving ? 'Kaydediliyor...' : 'Kaydet',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _StatusPrivacyOptionTile(
                  title: 'Kişilerim',
                  subtitle:
                      'Durumlarını rehberindeki kayıtlı Turna kullanıcıları görür.',
                  selected: _mode == TurnaStatusPrivacyMode.myContacts,
                  onTap: () =>
                      setState(() => _mode = TurnaStatusPrivacyMode.myContacts),
                ),
                const SizedBox(height: 10),
                _StatusPrivacyOptionTile(
                  title: 'Hariç tutulanlar',
                  subtitle: 'Rehberinden seçtiklerin dışında herkes görür.',
                  selected: _mode == TurnaStatusPrivacyMode.excludedContacts,
                  onTap: () => setState(
                    () => _mode = TurnaStatusPrivacyMode.excludedContacts,
                  ),
                ),
                const SizedBox(height: 10),
                _StatusPrivacyOptionTile(
                  title: 'Sadece paylaştıklarım',
                  subtitle: 'Durumu sadece seçtiğin kişiler görür.',
                  selected: _mode == TurnaStatusPrivacyMode.onlySharedWith,
                  onTap: () => setState(
                    () => _mode = TurnaStatusPrivacyMode.onlySharedWith,
                  ),
                ),
                if (_needsSelection) ...[
                  const SizedBox(height: 18),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Kişi ara',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_contacts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Seçilebilir kişi görünmüyor. Rehberini senkronladıktan sonra burada kayıtlı Turna kullanıcılarını seçebilirsin.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    )
                  else
                    ..._filteredContacts.map((contact) {
                      final selected = _selectedUserIds.contains(contact.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          child: CheckboxListTile(
                            value: selected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedUserIds.add(contact.id);
                                } else {
                                  _selectedUserIds.remove(contact.id);
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.trailing,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            secondary: _ProfileAvatar(
                              label: contact.resolvedTitle,
                              avatarUrl: contact.avatarUrl,
                              authToken: widget.session.token,
                              radius: 20,
                            ),
                            title: Text(contact.resolvedTitle),
                            subtitle: Text(
                              contact.username?.trim().isNotEmpty == true
                                  ? '@${contact.username}'
                                  : (contact.phone ?? 'Turna kullanıcısı'),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ],
            ),
    );
  }
}

class _StatusPrivacyOptionTile extends StatelessWidget {
  const _StatusPrivacyOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: TurnaColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: TurnaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? TurnaColors.primary : TurnaColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatStatusRelativeTime(String? raw) {
  final value = DateTime.tryParse(raw ?? '')?.toLocal();
  if (value == null) return '';
  final now = DateTime.now();
  final diff = now.difference(value);
  if (diff.inSeconds < 60) return 'Az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(value.year, value.month, value.day);
  final clock = formatTurnaLocalClock(value.toIso8601String());
  if (date == today) return clock;
  if (date == today.subtract(const Duration(days: 1))) {
    return 'Dün $clock';
  }
  return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')} $clock';
}

Color _statusTextForegroundFor(Color background) {
  return background.computeLuminance() > 0.45 ? Colors.black : Colors.white;
}

String _colorToHex(Color color) {
  final value = color.toARGB32();
  final hex = value.toRadixString(16).padLeft(8, '0').toUpperCase();
  return '#${hex.substring(2)}';
}

Color _colorFromHex(String? raw, Color fallback) {
  final value = raw?.trim() ?? '';
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length != 6 && hex.length != 8) {
    return fallback;
  }
  final normalized = hex.length == 6 ? 'FF$hex' : hex;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return fallback;
  return Color(parsed);
}

void _paintStatusCoverImage(Canvas canvas, ui.Image image, Rect targetRect) {
  final outputSize = targetRect.size;
  final inputSize = Size(image.width.toDouble(), image.height.toDouble());
  final fitted = applyBoxFit(BoxFit.cover, inputSize, outputSize);
  final src = Alignment.center.inscribe(fitted.source, Offset.zero & inputSize);
  final dst = Alignment.center.inscribe(fitted.destination, targetRect);
  canvas.drawImageRect(image, src, dst, Paint()..isAntiAlias = true);
}
