part of turna_app;

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
