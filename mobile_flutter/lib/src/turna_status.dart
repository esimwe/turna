part of '../main.dart';

const List<Color> _kStatusTextBackgrounds = <Color>[
  Color(0xFF1F6FEB),
  Color(0xFF0F766E),
  Color(0xFF7C3AED),
  Color(0xFFD97706),
  Color(0xFFBE123C),
  Color(0xFF374151),
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
  final ImagePicker _picker = ImagePicker();
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

  Future<void> _pickAndComposeMedia(TurnaStatusType type) async {
    try {
      final XFile? file = switch (type) {
        TurnaStatusType.video => await _picker.pickVideo(
          source: ImageSource.gallery,
        ),
        _ => await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: kInlineImagePickerQuality,
          maxWidth: kInlineImagePickerMaxDimension,
          maxHeight: kInlineImagePickerMaxDimension,
        ),
      };
      if (file == null || !mounted) return;

      final posted = await Navigator.push<bool>(
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
      if (posted == true && mounted) {
        setState(_scheduleReload);
      }
    } catch (error) {
      if (!mounted) return;
      _handleError(error);
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
      setState(_scheduleReload);
    }
  }

  Future<void> _showComposeSheet(TurnaStatusPrivacySettings privacy) async {
    final action = await showModalBottomSheet<String>(
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
                const Text(
                  'Durum paylaş',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: TurnaColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _privacyModeLabel(privacy.mode),
                  style: const TextStyle(
                    fontSize: 13,
                    color: TurnaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                _StatusActionSheetTile(
                  icon: Icons.edit_rounded,
                  title: 'Metin durumu',
                  subtitle: 'Renkli arka plan üstünde kısa bir durum paylaş.',
                  onTap: () => Navigator.pop(context, 'text'),
                ),
                const SizedBox(height: 10),
                _StatusActionSheetTile(
                  icon: Icons.photo_rounded,
                  title: 'Fotoğraf durumu',
                  subtitle: 'Galeriden bir fotoğraf seç ve 24 saat paylaş.',
                  onTap: () => Navigator.pop(context, 'image'),
                ),
                const SizedBox(height: 10),
                _StatusActionSheetTile(
                  icon: Icons.videocam_rounded,
                  title: 'Video durumu',
                  subtitle:
                      'Kısa bir video seç. En fazla $kStatusMaxVideoDurationSeconds saniye.',
                  onTap: () => Navigator.pop(context, 'video'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'text':
        await _openTextComposer();
        break;
      case 'image':
        await _pickAndComposeMedia(TurnaStatusType.image);
        break;
      case 'video':
        await _pickAndComposeMedia(TurnaStatusType.video);
        break;
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
                    : () => _showComposeSheet(data.privacy),
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
                        _showComposeSheet(data.privacy);
                      },
                      onAdd: () => _showComposeSheet(data.privacy),
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
                        onCreate: () => _showComposeSheet(data.privacy),
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

class _StatusActionSheetTile extends StatelessWidget {
  const _StatusActionSheetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TurnaColors.backgroundSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
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
                child: Icon(icon, color: TurnaColors.primary),
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
                        color: TurnaColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: TurnaColors.textMuted,
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
  int _selectedColorIndex = 0;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
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

  @override
  Widget build(BuildContext context) {
    final background = _kStatusTextBackgrounds[_selectedColorIndex];
    final textColor = _statusTextForegroundFor(background);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: Text(
              _saving ? 'Gönderiliyor...' : 'Paylaş',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: 700,
                    maxLines: null,
                    minLines: 4,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 30,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Bir durum yaz...',
                      hintStyle: TextStyle(
                        color: textColor.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                      counterStyle: TextStyle(
                        color: textColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: List<Widget>.generate(
                  _kStatusTextBackgrounds.length,
                  (index) {
                    final color = _kStatusTextBackgrounds[index];
                    final selected = index == _selectedColorIndex;
                    return GestureDetector(
                      onTap: _saving
                          ? null
                          : () => setState(() => _selectedColorIndex = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: selected ? 42 : 36,
                        height: selected ? 42 : 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: selected ? 0.9 : 0.5,
                            ),
                            width: selected ? 3 : 1.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusMediaComposerPage extends StatefulWidget {
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

  @override
  State<StatusMediaComposerPage> createState() =>
      _StatusMediaComposerPageState();
}

class _StatusMediaComposerPageState extends State<StatusMediaComposerPage> {
  vp.VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.type == TurnaStatusType.video) {
      final controller = vp.VideoPlayerController.file(File(widget.file.path));
      _videoController = controller;
      _videoInitFuture = controller.initialize().then((_) {
        controller
          ..setLooping(true)
          ..play();
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final bytes = await widget.file.readAsBytes();
      final fileName = widget.file.name.trim().isEmpty
          ? 'durum-${DateTime.now().millisecondsSinceEpoch}'
          : widget.file.name.trim();
      final contentType = widget.file.mimeType?.trim().isNotEmpty == true
          ? widget.file.mimeType!.trim()
          : (guessContentTypeForFileName(fileName) ??
                (widget.type == TurnaStatusType.video
                    ? 'video/mp4'
                    : 'image/jpeg'));

      int? width;
      int? height;
      int? durationSeconds;

      if (widget.type == TurnaStatusType.image) {
        final image = await decodeImageFromList(bytes);
        width = image.width;
        height = image.height;
      } else {
        final controller = _videoController;
        if (controller == null) {
          throw TurnaApiException('Video hazırlanamadi.');
        }
        if (_videoInitFuture != null) {
          await _videoInitFuture;
        }
        durationSeconds = controller.value.duration.inSeconds;
        if (durationSeconds > kStatusMaxVideoDurationSeconds) {
          throw TurnaApiException(
            'Video en fazla $kStatusMaxVideoDurationSeconds saniye olabilir.',
          );
        }
        width = controller.value.size.width.round();
        height = controller.value.size.height.round();
      }

      final upload = await TurnaStatusApi.createUpload(
        widget.session,
        type: widget.type,
        contentType: contentType,
        fileName: fileName,
      );

      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Dosya yüklenemedi.');
      }

      await TurnaStatusApi.createMediaStatus(
        widget.session,
        type: widget.type,
        objectKey: upload.objectKey,
        contentType: contentType,
        fileName: fileName,
        sizeBytes: bytes.length,
        width: width,
        height: height,
        durationSeconds: durationSeconds,
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

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.type == TurnaStatusType.video;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: Text(
              _saving ? 'Paylaşılıyor...' : 'Paylaş',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: isVideo
                ? FutureBuilder<void>(
                    future: _videoInitFuture,
                    builder: (context, snapshot) {
                      final controller = _videoController;
                      if (snapshot.connectionState != ConnectionState.done ||
                          controller == null ||
                          !controller.value.isInitialized) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return GestureDetector(
                        onTap: () {
                          if (controller.value.isPlaying) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                          setState(() {});
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(
                              child: AspectRatio(
                                aspectRatio: controller.value.aspectRatio,
                                child: vp.VideoPlayer(controller),
                              ),
                            ),
                            if (!controller.value.isPlaying)
                              Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.42),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 38,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  )
                : Center(
                    child: Image.file(
                      File(widget.file.path),
                      fit: BoxFit.contain,
                    ),
                  ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                isVideo
                    ? 'Video durumları $kStatusMaxVideoDurationSeconds saniyeye kadar paylaşılır ve 24 saat sonra silinir.'
                    : 'Fotoğraf durumları 24 saat görünür.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
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
      return Container(
        color: bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          item.text?.trim().isNotEmpty == true ? item.text!.trim() : 'Durum',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fg,
            fontSize: 30,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
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

String _privacyModeLabel(TurnaStatusPrivacyMode mode) {
  switch (mode) {
    case TurnaStatusPrivacyMode.excludedContacts:
      return 'Gizlilik: Hariç tutulanlar';
    case TurnaStatusPrivacyMode.onlySharedWith:
      return 'Gizlilik: Sadece paylaştıklarım';
    case TurnaStatusPrivacyMode.myContacts:
      return 'Gizlilik: Kişilerim';
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
