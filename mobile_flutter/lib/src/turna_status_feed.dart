part of '../main.dart';

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
