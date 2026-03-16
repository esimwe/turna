part of '../main.dart';

class ChatGalleryMediaItem {
  const ChatGalleryMediaItem({
    required this.attachment,
    required this.senderLabel,
    required this.cacheKey,
    required this.url,
    this.message,
  });

  final ChatAttachment attachment;
  final ChatMessage? message;
  final String senderLabel;
  final String cacheKey;
  final String url;
}

class ChatAttachmentViewerPage extends StatefulWidget {
  ChatAttachmentViewerPage({
    super.key,
    required this.session,
    required this.items,
    this.initialIndex = 0,
    this.autoOpenInitialVideoFullscreen = false,
    this.formatTimestamp,
    this.isStarred,
    this.onReply,
    this.onForward,
    this.onToggleStar,
    this.onDeleteForMe,
  }) : assert(items.isNotEmpty, 'items must not be empty.');

  final AuthSession session;
  final List<ChatGalleryMediaItem> items;
  final int initialIndex;
  final bool autoOpenInitialVideoFullscreen;
  final String Function(String iso)? formatTimestamp;
  final bool Function(ChatMessage message)? isStarred;
  final Future<void> Function(ChatMessage message)? onReply;
  final Future<void> Function(ChatMessage message)? onForward;
  final Future<void> Function(ChatMessage message)? onToggleStar;
  final Future<void> Function(ChatMessage message)? onDeleteForMe;

  @override
  State<ChatAttachmentViewerPage> createState() =>
      _ChatAttachmentViewerPageState();
}

class _ChatAttachmentViewerPageState extends State<ChatAttachmentViewerPage> {
  late List<ChatGalleryMediaItem> _items;
  late int _currentIndex;
  late final PageController _pageController;
  bool _didHandleInitialVideoFullscreen = false;

  ChatGalleryMediaItem get _currentItem => _items[_currentIndex];

  @override
  void initState() {
    super.initState();
    _items = List<ChatGalleryMediaItem>.from(widget.items);
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpenInitialVideoFullscreen();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _titleFor(ChatGalleryMediaItem item) {
    if (item.senderLabel.trim().isNotEmpty) return item.senderLabel;
    return item.attachment.fileName ?? 'Medya';
  }

  String? _subtitleFor(ChatGalleryMediaItem item) {
    final message = item.message;
    if (message == null || widget.formatTimestamp == null) return null;
    return widget.formatTimestamp!(message.createdAt);
  }

  bool _isStarred(ChatGalleryMediaItem item) {
    final message = item.message;
    if (message == null || widget.isStarred == null) return false;
    return widget.isStarred!(message);
  }

  Future<File> _resolveFile(ChatGalleryMediaItem item) async {
    final file = await TurnaLocalMediaCache.getOrDownloadFile(
      cacheKey: item.cacheKey,
      url: item.url,
      authToken: widget.session.token,
    );
    if (file != null) return file;
    throw TurnaApiException('Medya indirilemedi.');
  }

  Future<void> _saveCurrentMedia() async {
    try {
      final file = await _resolveFile(_currentItem);
      await TurnaMediaBridge.saveToGallery(
        path: file.path,
        mimeType: _currentItem.attachment.contentType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Medya cihaza kaydedildi.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _shareCurrentMedia() async {
    try {
      final file = await _resolveFile(_currentItem);
      await TurnaMediaBridge.shareFile(
        path: file.path,
        mimeType: _currentItem.attachment.contentType,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showShareOptions() async {
    final message = _currentItem.message;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Kaydet'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _saveCurrentMedia();
                },
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('Paylaş'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _shareCurrentMedia();
                },
              ),
              if (message != null && widget.onForward != null)
                ListTile(
                  leading: const Icon(Icons.forward_rounded),
                  title: const Text('İlet'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await widget.onForward!(message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _replyToCurrent() async {
    final message = _currentItem.message;
    if (message == null || widget.onReply == null) return;
    await widget.onReply!(message);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _forwardCurrent() async {
    final message = _currentItem.message;
    if (message == null || widget.onForward == null) return;
    await widget.onForward!(message);
  }

  Future<void> _toggleStarCurrent() async {
    final message = _currentItem.message;
    if (message == null || widget.onToggleStar == null) return;
    await widget.onToggleStar!(message);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteCurrentForMe() async {
    final message = _currentItem.message;
    if (message == null || widget.onDeleteForMe == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Medyayı benden sil'),
        content: const Text(
          'Bu medya bu cihazdan ve sohbet görünümünden kaldırılacak. Karşı tarafta kalmaya devam edecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Benden sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final removedItem = _currentItem;
    await widget.onDeleteForMe!(message);
    await TurnaLocalMediaCache.remove(removedItem.cacheKey);
    if (!mounted) return;

    if (_items.length == 1) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _items.removeAt(_currentIndex);
      if (_currentIndex >= _items.length) {
        _currentIndex = _items.length - 1;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex);
      }
    });
  }

  Future<void> _maybeOpenInitialVideoFullscreen() async {
    if (_didHandleInitialVideoFullscreen ||
        !widget.autoOpenInitialVideoFullscreen ||
        !_isVideoAttachment(_currentItem.attachment) ||
        !mounted) {
      return;
    }
    _didHandleInitialVideoFullscreen = true;
    await _openCurrentVideoFullscreen();
  }

  Future<void> _openCurrentVideoFullscreen() async {
    final item = _currentItem;
    if (!_isVideoAttachment(item.attachment)) return;
    try {
      final cachedFile = await TurnaLocalMediaCache.getOrDownloadFile(
        cacheKey: item.cacheKey,
        url: item.url,
        authToken: widget.session.token,
      );
      if (cachedFile == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video yüklenemedi.')));
        return;
      }
      final preparedFile = await TurnaLocalMediaCache.prepareMediaFile(
        cacheKey: item.cacheKey,
        sourceFile: cachedFile,
        mimeType: item.attachment.contentType,
        fileName: item.attachment.fileName,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) =>
              _TurnaFullscreenVideoPage(file: preparedFile),
          opaque: false,
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 160),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Video yüklenemedi.')));
    }
  }

  Widget _buildTitle() {
    final subtitle = _subtitleFor(_currentItem);
    if (subtitle == null || subtitle.isEmpty) {
      return Text(_titleFor(_currentItem));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _titleFor(_currentItem),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.78),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnailStrip() {
    if (_items.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 58,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = _items[index];
          final selected = index == _currentIndex;
          return GestureDetector(
            onTap: () => _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            ),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? Colors.white : Colors.white24,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _isVideoAttachment(item.attachment)
                  ? _TurnaVideoThumbnail(
                      cacheKey: item.cacheKey,
                      url: item.url,
                      authToken: widget.session.token,
                      contentType: item.attachment.contentType,
                      fileName: item.attachment.fileName,
                      fit: BoxFit.cover,
                      loading: Container(
                        color: const Color(0xFF1E2932),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                        ),
                      ),
                      error: Container(
                        color: const Color(0xFF1E2932),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : _TurnaCachedImage(
                      cacheKey: item.cacheKey,
                      imageUrl: item.url,
                      authToken: widget.session.token,
                      fit: BoxFit.cover,
                      loading: const ColoredBox(color: Color(0xFF29333B)),
                      error: const ColoredBox(
                        color: Color(0xFF29333B),
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    final color = active ? const Color(0xFFFFD54F) : Colors.white;
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: onTap == null ? Colors.white38 : color, size: 26),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentItem;
    final canReply = current.message != null && widget.onReply != null;
    final canForward = current.message != null && widget.onForward != null;
    final canStar = current.message != null && widget.onToggleStar != null;
    final canDelete = current.message != null && widget.onDeleteForMe != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: _buildTitle(),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _items.length,
              onPageChanged: (value) => setState(() => _currentIndex = value),
              itemBuilder: (context, index) => _TurnaAttachmentPageAsset(
                item: _items[index],
                authToken: widget.session.token,
                onOpenFullscreen: _isVideoAttachment(_items[index].attachment)
                    ? _openCurrentVideoFullscreen
                    : null,
              ),
            ),
          ),
          if (canReply)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, bottom: 8),
                child: TextButton.icon(
                  onPressed: _replyToCurrent,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.reply_rounded, size: 18),
                  label: const Text('Yanıtlayın'),
                ),
              ),
            ),
          _buildThumbnailStrip(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.ios_share_rounded,
                  onTap: _showShareOptions,
                ),
                _buildActionButton(
                  icon: Icons.forward_rounded,
                  onTap: canForward ? _forwardCurrent : null,
                ),
                _buildActionButton(
                  icon: _isStarred(current)
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  onTap: canStar ? _toggleStarCurrent : null,
                  active: _isStarred(current),
                ),
                _buildActionButton(
                  icon: Icons.delete_outline_rounded,
                  onTap: canDelete ? _deleteCurrentForMe : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnaAttachmentPageAsset extends StatelessWidget {
  const _TurnaAttachmentPageAsset({
    required this.item,
    required this.authToken,
    this.onOpenFullscreen,
  });

  final ChatGalleryMediaItem item;
  final String authToken;
  final Future<void> Function()? onOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    if (_isVideoAttachment(item.attachment)) {
      return _TurnaAttachmentVideoSurface(
        item: item,
        authToken: authToken,
        onOpenFullscreen: onOpenFullscreen,
      );
    }

    return FutureBuilder<File?>(
      future: TurnaLocalMediaCache.getOrDownloadFile(
        cacheKey: item.cacheKey,
        url: item.url,
        authToken: authToken,
      ),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Görsel yüklenemedi.',
              style: TextStyle(color: Colors.white),
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
    );
  }
}

class _TurnaAttachmentVideoSurface extends StatefulWidget {
  const _TurnaAttachmentVideoSurface({
    required this.item,
    required this.authToken,
    this.onOpenFullscreen,
  });

  final ChatGalleryMediaItem item;
  final String authToken;
  final Future<void> Function()? onOpenFullscreen;

  @override
  State<_TurnaAttachmentVideoSurface> createState() =>
      _TurnaAttachmentVideoSurfaceState();
}

class _TurnaAttachmentVideoSurfaceState
    extends State<_TurnaAttachmentVideoSurface> {
  vp.VideoPlayerController? _controller;
  Future<void>? _initFuture;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant _TurnaAttachmentVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.cacheKey != widget.item.cacheKey ||
        oldWidget.item.url != widget.item.url) {
      _disposeController();
      _prepare();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _initFuture = null;
  }

  Future<void> _prepare() async {
    setState(() => _error = null);
    try {
      final cachedFile = await TurnaLocalMediaCache.getOrDownloadFile(
        cacheKey: widget.item.cacheKey,
        url: widget.item.url,
        authToken: widget.authToken,
      );
      if (cachedFile == null) {
        if (!mounted) return;
        setState(() => _error = 'Video yüklenemedi.');
        return;
      }
      final file = await TurnaLocalMediaCache.prepareMediaFile(
        cacheKey: widget.item.cacheKey,
        sourceFile: cachedFile,
        mimeType: widget.item.attachment.contentType,
        fileName: widget.item.attachment.fileName,
      );
      final controller = vp.VideoPlayerController.file(file);
      final initFuture = controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initFuture = initFuture;
      });
      await initFuture;
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Video yüklenemedi.');
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white)),
      );
    }

    final controller = _controller;
    final initFuture = _initFuture;
    if (controller == null || initFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        return GestureDetector(
          onTap: widget.onOpenFullscreen == null
              ? _togglePlayback
              : () => widget.onOpenFullscreen!(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio <= 0
                      ? 16 / 9
                      : controller.value.aspectRatio,
                  child: vp.VideoPlayer(controller),
                ),
              ),
              if (!controller.value.isPlaying)
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.38),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: vp.VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const vp.VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
              if (widget.onOpenFullscreen != null)
                Positioned(
                  right: 16,
                  top: 16,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.34),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => widget.onOpenFullscreen!(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.open_in_full_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TurnaFullscreenVideoPage extends StatefulWidget {
  const _TurnaFullscreenVideoPage({required this.file});

  final File file;

  @override
  State<_TurnaFullscreenVideoPage> createState() =>
      _TurnaFullscreenVideoPageState();
}

class _TurnaFullscreenVideoPageState extends State<_TurnaFullscreenVideoPage> {
  vp.VideoPlayerController? _controller;
  Future<void>? _initFuture;
  String? _error;
  double _dragOffsetY = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final controller = vp.VideoPlayerController.file(widget.file);
      final initFuture = controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initFuture = initFuture;
      });
      await initFuture;
      await controller.play();
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Video yüklenemedi.');
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  void _dismiss() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initFuture = _initFuture;
    final progress = (_dragOffsetY.abs() / 220).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - (progress * 0.35)),
      body: GestureDetector(
        onVerticalDragUpdate: (details) {
          setState(() {
            _dragOffsetY = (_dragOffsetY + details.delta.dy).clamp(
              -260.0,
              260.0,
            );
          });
        },
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (_dragOffsetY.abs() > 140 || velocity.abs() > 900) {
            _dismiss();
            return;
          }
          setState(() => _dragOffsetY = 0);
        },
        child: SafeArea(
          child: Stack(
            children: [
              Transform.translate(
                offset: Offset(0, _dragOffsetY),
                child: Center(
                  child: _error != null
                      ? Text(
                          _error!,
                          style: const TextStyle(color: Colors.white),
                        )
                      : (controller == null || initFuture == null)
                      ? const CircularProgressIndicator(color: Colors.white)
                      : FutureBuilder<void>(
                          future: initFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                    ConnectionState.done ||
                                !controller.value.isInitialized) {
                              return const CircularProgressIndicator(
                                color: Colors.white,
                              );
                            }
                            return GestureDetector(
                              onTap: _togglePlayback,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Center(
                                    child: AspectRatio(
                                      aspectRatio:
                                          controller.value.aspectRatio <= 0
                                          ? 16 / 9
                                          : controller.value.aspectRatio,
                                      child: vp.VideoPlayer(controller),
                                    ),
                                  ),
                                  if (!controller.value.isPlaying)
                                    Container(
                                      width: 84,
                                      height: 84,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.38,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 46,
                                      ),
                                    ),
                                  Positioned(
                                    left: 18,
                                    right: 18,
                                    bottom: 22,
                                    child: vp.VideoProgressIndicator(
                                      controller,
                                      allowScrubbing: true,
                                      colors: const vp.VideoProgressColors(
                                        playedColor: Colors.white,
                                        bufferedColor: Colors.white38,
                                        backgroundColor: Colors.white24,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              Positioned(
                top: 8,
                right: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.34),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _dismiss,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum MediaComposerQuality { sd, hd }

extension MediaComposerQualityX on MediaComposerQuality {
  String get label => name.toUpperCase();

  double get imageMaxDimension {
    switch (this) {
      case MediaComposerQuality.sd:
        return kInlineImageSdMaxDimension;
      case MediaComposerQuality.hd:
        return kInlineImageHdMaxDimension;
    }
  }

  int get jpegQuality {
    switch (this) {
      case MediaComposerQuality.sd:
        return 74;
      case MediaComposerQuality.hd:
        return 86;
    }
  }
}

class _TurnaVideoThumbnail extends StatefulWidget {
  const _TurnaVideoThumbnail({
    required this.cacheKey,
    required this.url,
    required this.authToken,
    required this.contentType,
    required this.fileName,
    required this.fit,
    required this.loading,
    required this.error,
  });

  final String cacheKey;
  final String url;
  final String authToken;
  final String contentType;
  final String? fileName;
  final BoxFit fit;
  final Widget loading;
  final Widget error;

  @override
  State<_TurnaVideoThumbnail> createState() => _TurnaVideoThumbnailState();
}

class _TurnaVideoThumbnailState extends State<_TurnaVideoThumbnail> {
  vp.VideoPlayerController? _controller;
  Future<void>? _initFuture;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant _TurnaVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey || oldWidget.url != widget.url) {
      _disposeController();
      _prepare();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _initFuture = null;
  }

  Future<void> _prepare() async {
    setState(() => _failed = false);
    try {
      final cachedFile = await TurnaLocalMediaCache.getOrDownloadFile(
        cacheKey: widget.cacheKey,
        url: widget.url,
        authToken: widget.authToken,
      );
      if (cachedFile == null) {
        if (!mounted) return;
        setState(() => _failed = true);
        return;
      }
      if (!mounted) return;
      final file = await TurnaLocalMediaCache.prepareMediaFile(
        cacheKey: widget.cacheKey,
        sourceFile: cachedFile,
        mimeType: widget.contentType,
        fileName: widget.fileName,
      );
      final controller = vp.VideoPlayerController.file(file);
      await controller.setLooping(false);
      final initFuture = controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initFuture = initFuture;
      });
      await initFuture;
      await controller.pause();
      await controller.seekTo(Duration.zero);
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initFuture = null;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initFuture = _initFuture;
    if (_failed) {
      return widget.error;
    }
    if (controller == null || initFuture == null) {
      return widget.loading;
    }

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return widget.loading;
        }
        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: widget.fit,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: vp.VideoPlayer(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MediaComposerSeed {
  MediaComposerSeed({
    required this.kind,
    required this.file,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
  });

  final ChatAttachmentKind kind;
  final XFile file;
  final String fileName;
  final String contentType;
  final int sizeBytes;
}

typedef _MediaComposerPreparedSend =
    Future<dynamic> Function(
      List<_PreparedComposerAttachment> attachments,
      String? caption,
      MediaComposerQuality quality,
    );

class _MediaCropPreset {
  const _MediaCropPreset({
    required this.id,
    required this.label,
    this.aspectRatio,
    this.useOriginalAspect = false,
    this.fullImage = false,
    this.freeform = false,
  });

  final String id;
  final String label;
  final double? aspectRatio;
  final bool useOriginalAspect;
  final bool fullImage;
  final bool freeform;
}

enum _MediaComposerCropHandle { topLeft, topRight, bottomLeft, bottomRight }

class _MediaComposerPage extends StatefulWidget {
  const _MediaComposerPage({
    required this.session,
    required this.items,
    required this.onSessionExpired,
    this.chat,
    this.onPreparedSend,
    this.captionEnabled = true,
  }) : assert(
         chat != null || onPreparedSend != null,
         'chat veya onPreparedSend verilmelidir.',
       );

  final AuthSession session;
  final ChatPreview? chat;
  final List<MediaComposerSeed> items;
  final VoidCallback onSessionExpired;
  final _MediaComposerPreparedSend? onPreparedSend;
  final bool captionEnabled;

  @override
  State<_MediaComposerPage> createState() => _MediaComposerPageState();
}

class _MediaComposerPageState extends State<_MediaComposerPage> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _inlineTextController = TextEditingController();
  final FocusNode _inlineTextFocusNode = FocusNode();
  late final PageController _pageController;
  late final List<_MediaComposerItem> _items;
  int _selectedIndex = 0;
  bool _cropMode = false;
  bool _drawMode = false;
  bool _sending = false;
  String? _sendingLabel;
  String? _activeTextOverlayId;
  MediaComposerQuality _quality = MediaComposerQuality.sd;
  double _overlayInteractionBaseScale = 1;
  double _brushSizeFactor = 0.011;
  bool _eraserMode = false;

  _MediaComposerItem get _currentItem => _items[_selectedIndex];

  _MediaComposerTextOverlay? get _activeTextOverlay {
    final overlayId = _activeTextOverlayId;
    if (overlayId == null) return null;
    for (final overlay in _currentItem.textOverlays) {
      if (overlay.id == overlayId) return overlay;
    }
    return null;
  }

  Rect get _currentWorkingCropRect =>
      _currentItem.draftCropRectNormalized ??
      _currentItem.cropRectNormalized ??
      _defaultCropRectFor(_currentItem);

  String get _currentWorkingCropPresetId =>
      _currentItem.draftCropPresetId ?? _currentItem.cropPresetId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _items = widget.items.map(_MediaComposerItem.fromSeed).toList();
    for (final item in _items.where((item) => item.isImage)) {
      unawaited(_primeImageSize(item));
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _inlineTextController.dispose();
    _inlineTextFocusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _primeImageSize(_MediaComposerItem item) async {
    if (!item.isImage || item.sourceSize != null) return;
    final bytes = await item.file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    if (!mounted) return;
    setState(() => item.sourceSize = size);
  }

  Future<void> _showComingSoon(String text) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Rect _displayCropRectFor(_MediaComposerItem item) {
    if (identical(item, _currentItem) && _cropMode) {
      return kComposerFullCropRectNormalized;
    }
    return item.cropRectNormalized ?? kComposerFullCropRectNormalized;
  }

  double _effectiveAspectRatioFor(_MediaComposerItem item, Rect displayCrop) {
    final base = item.sourceSize ?? const Size(1, 1);
    final rotatedWidth = item.rotationTurns.isOdd ? base.height : base.width;
    final rotatedHeight = item.rotationTurns.isOdd ? base.width : base.height;
    return math.max(
      0.1,
      (rotatedWidth * displayCrop.width) /
          math.max(0.1, rotatedHeight * displayCrop.height),
    );
  }

  Size _rotatedSourceSize(_MediaComposerItem item) {
    final base = item.sourceSize ?? const Size(1, 1);
    return item.rotationTurns.isOdd
        ? Size(base.height, base.width)
        : Size(base.width, base.height);
  }

  _MediaCropPreset _cropPresetForId(String id) {
    return _kComposerCropPresets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => _kComposerCropPresets.first,
    );
  }

  double _resolvedCropAspectRatio(
    _MediaComposerItem item,
    _MediaCropPreset preset,
  ) {
    if (preset.useOriginalAspect) {
      final size = _rotatedSourceSize(item);
      return size.width / math.max(0.1, size.height);
    }
    return preset.aspectRatio ?? 1;
  }

  Rect _cropRectForPreset(
    _MediaComposerItem item,
    _MediaCropPreset preset, {
    Offset? center,
  }) {
    if (preset.fullImage) return kComposerFullCropRectNormalized;
    if (preset.freeform) {
      final existing = item.cropRectNormalized;
      if (existing != null &&
          existing != kComposerFullCropRectNormalized &&
          existing.width < 1 &&
          existing.height < 1) {
        return _clampCropRect(existing);
      }
      return Rect.fromLTWH(
        kComposerCropInitialInset,
        kComposerCropInitialInset,
        1 - (kComposerCropInitialInset * 2),
        1 - (kComposerCropInitialInset * 2),
      );
    }

    final imageSize = _rotatedSourceSize(item);
    final imageAspect = imageSize.width / math.max(0.1, imageSize.height);
    final targetAspect = _resolvedCropAspectRatio(item, preset);
    final normalizedAspect = targetAspect / math.max(0.1, imageAspect);
    final available = 1 - (kComposerCropInitialInset * 2);

    var width = available;
    var height = width / math.max(0.1, normalizedAspect);
    if (height > available) {
      height = available;
      width = height * normalizedAspect;
    }

    width = width.clamp(kComposerCropMinSide, 1.0).toDouble();
    height = height.clamp(kComposerCropMinSide, 1.0).toDouble();

    final anchor =
        center ?? item.cropRectNormalized?.center ?? const Offset(0.5, 0.5);
    return _clampCropRect(
      Rect.fromCenter(center: anchor, width: width, height: height),
    );
  }

  double? _lockedNormalizedCropAspectRatio(_MediaComposerItem item) {
    final preset = identical(item, _currentItem) && _cropMode
        ? _cropPresetForId(_currentWorkingCropPresetId)
        : _cropPresetForId(item.cropPresetId);
    if (preset.freeform || preset.fullImage) return null;
    final imageSize = _rotatedSourceSize(item);
    final imageAspect = imageSize.width / math.max(0.1, imageSize.height);
    final targetAspect = _resolvedCropAspectRatio(item, preset);
    return targetAspect / math.max(0.1, imageAspect);
  }

  Rect _normalizedCropToRect(Rect normalizedCrop, Size size) {
    return Rect.fromLTWH(
      normalizedCrop.left * size.width,
      normalizedCrop.top * size.height,
      normalizedCrop.width * size.width,
      normalizedCrop.height * size.height,
    );
  }

  Rect _clampCropRect(Rect rect) {
    final minSide = kComposerCropMinSide;
    var left = rect.left;
    var top = rect.top;
    var right = rect.right;
    var bottom = rect.bottom;

    if ((right - left) < minSide) {
      right = left + minSide;
    }
    if ((bottom - top) < minSide) {
      bottom = top + minSide;
    }

    if (left < 0) {
      right -= left;
      left = 0;
    }
    if (top < 0) {
      bottom -= top;
      top = 0;
    }
    if (right > 1) {
      left -= right - 1;
      right = 1;
    }
    if (bottom > 1) {
      top -= bottom - 1;
      bottom = 1;
    }

    left = left.clamp(0.0, 1.0 - minSide).toDouble();
    top = top.clamp(0.0, 1.0 - minSide).toDouble();
    right = right.clamp(left + minSide, 1.0).toDouble();
    bottom = bottom.clamp(top + minSide, 1.0).toDouble();

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _defaultCropRectFor(_MediaComposerItem item) {
    return _cropRectForPreset(item, _cropPresetForId(item.cropPresetId));
  }

  void _beginCropEditing() {
    _currentItem.draftCropPresetId = _currentItem.cropPresetId;
    _currentItem.draftCropRectNormalized =
        _currentItem.cropRectNormalized ?? _defaultCropRectFor(_currentItem);
    _cropMode = true;
  }

  void _cancelCropEditing() {
    setState(() {
      _currentItem.draftCropRectNormalized = null;
      _currentItem.draftCropPresetId = null;
      _cropMode = false;
    });
  }

  void _applyCropEditing() {
    setState(() {
      _currentItem.cropPresetId = _currentWorkingCropPresetId;
      _currentItem.cropRectNormalized = _currentWorkingCropRect;
      _currentItem.draftCropRectNormalized = null;
      _currentItem.draftCropPresetId = null;
      _cropMode = false;
    });
  }

  void _applyCropPreset(_MediaCropPreset preset) {
    if (!_currentItem.isImage) return;
    final currentCenter = _currentWorkingCropRect.center;
    setState(() {
      _currentItem.draftCropPresetId = preset.id;
      _currentItem.draftCropRectNormalized = _cropRectForPreset(
        _currentItem,
        preset,
        center: currentCenter,
      );
    });
  }

  void _toggleQuality() {
    setState(() {
      _quality = _quality == MediaComposerQuality.sd
          ? MediaComposerQuality.hd
          : MediaComposerQuality.sd;
    });
  }

  Future<void> _toggleCropMode() async {
    if (_currentItem.kind == ChatAttachmentKind.video) {
      await _showComingSoon(
        'Kırpma şu an sadece fotoğraflarda açık. Video kırpmaya sonra geçeceğiz.',
      );
      return;
    }

    _finishTextEditing();
    if (_cropMode) {
      _applyCropEditing();
      return;
    }

    setState(() {
      _drawMode = false;
      _eraserMode = false;
      if (_currentItem.cropRectNormalized == null) {
        _currentItem.cropPresetId = 'free';
      }
      _beginCropEditing();
    });
  }

  String _nextTextOverlayId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_currentItem.textOverlays.length + 1}';
  }

  void _requestInlineTextFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inlineTextFocusNode.requestFocus();
    });
  }

  void _finishTextEditing() {
    final overlayId = _activeTextOverlayId;
    if (overlayId == null) return;

    final overlay = _activeTextOverlay;
    if (overlay == null) {
      if (mounted) {
        setState(() => _activeTextOverlayId = null);
      }
      _inlineTextController.clear();
      _inlineTextFocusNode.unfocus();
      return;
    }

    final nextText = _inlineTextController.text.trim();
    setState(() {
      if (nextText.isEmpty) {
        _currentItem.textOverlays.removeWhere((item) => item.id == overlayId);
      } else {
        overlay.text = nextText;
      }
      _activeTextOverlayId = null;
    });
    _inlineTextController.clear();
    _inlineTextFocusNode.unfocus();
  }

  void _beginNewTextOverlay({
    required String initialText,
    required bool requestKeyboard,
    bool activateOverlay = true,
  }) {
    if (!_currentItem.isImage) return;
    _finishTextEditing();

    final overlay = _MediaComposerTextOverlay(
      id: _nextTextOverlayId(),
      text: initialText,
      position: kComposerOverlayDefaultPosition,
      scale: 1,
      colorValue: _currentItem.markupColorValue,
    );

    setState(() {
      _cropMode = false;
      _drawMode = false;
      _currentItem.textOverlays.add(overlay);
      _activeTextOverlayId = activateOverlay ? overlay.id : null;
      _inlineTextController.value = activateOverlay
          ? TextEditingValue(
              text: initialText,
              selection: TextSelection.collapsed(offset: initialText.length),
            )
          : const TextEditingValue();
    });

    if (requestKeyboard && activateOverlay) {
      _requestInlineTextFocus();
    } else {
      _inlineTextFocusNode.unfocus();
    }
  }

  void _beginEditingTextOverlay(
    _MediaComposerTextOverlay overlay, {
    required bool requestKeyboard,
  }) {
    if (!_currentItem.isImage) return;
    setState(() {
      _cropMode = false;
      _drawMode = false;
      _activeTextOverlayId = overlay.id;
      _inlineTextController.value = TextEditingValue(
        text: overlay.text,
        selection: TextSelection.collapsed(offset: overlay.text.length),
      );
    });

    if (requestKeyboard) {
      _requestInlineTextFocus();
    } else {
      _inlineTextFocusNode.unfocus();
    }
  }

  Future<void> _editOverlayText({required bool emojiMode}) async {
    if (!_currentItem.isImage) {
      await _showComingSoon('Bu düzenleme şu an sadece fotoğraflarda açık.');
      return;
    }

    if (emojiMode) {
      final selectedEmoji = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF171A19),
        builder: (sheetContext) {
          const emojis = [
            '🙂',
            '😍',
            '🔥',
            '❤️',
            '👏',
            '🎉',
            '😂',
            '😎',
            '🚀',
            '✨',
            '🤝',
            '🫶',
          ];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final emoji in emojis)
                    InkWell(
                      onTap: () => Navigator.pop(sheetContext, emoji),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF222725),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
      if (selectedEmoji == null || !mounted) return;
      _beginNewTextOverlay(
        initialText: selectedEmoji,
        requestKeyboard: false,
        activateOverlay: false,
      );
      return;
    }

    _beginNewTextOverlay(initialText: '', requestKeyboard: true);
  }

  void _syncActiveTextOverlay(String value) {
    final overlay = _activeTextOverlay;
    if (overlay == null) return;
    setState(() {
      overlay.text = value;
    });
  }

  void _toggleDrawMode() {
    if (!_currentItem.isImage) {
      _showComingSoon('Çizim modu şu an sadece fotoğraflarda açık.');
      return;
    }
    _finishTextEditing();
    setState(() {
      _cropMode = false;
      _drawMode = !_drawMode;
      if (!_drawMode) {
        _eraserMode = false;
      }
    });
  }

  void _setBrushSize(double widthFactor) {
    setState(() {
      _eraserMode = false;
      _brushSizeFactor = widthFactor;
    });
  }

  void _toggleEraser() {
    setState(() {
      _eraserMode = !_eraserMode;
    });
  }

  void _rotateCurrent() {
    if (!_currentItem.isImage) {
      _showComingSoon('Döndürme şu an sadece fotoğraflarda açık.');
      return;
    }
    _finishTextEditing();
    setState(() {
      _currentItem.rotationTurns = (_currentItem.rotationTurns + 1) % 4;
      final preset = _cropPresetForId(_currentWorkingCropPresetId);
      final nextCrop = _cropMode
          ? _cropRectForPreset(
              _currentItem,
              preset,
              center: _currentWorkingCropRect.center,
            )
          : null;
      if (_cropMode) {
        _currentItem.draftCropRectNormalized = nextCrop;
      } else {
        _currentItem.cropRectNormalized = nextCrop;
      }
    });
  }

  void _undoCurrentStroke() {
    if (!_currentItem.isImage || _currentItem.strokes.isEmpty) return;
    setState(() {
      _currentItem.strokes.removeLast();
    });
  }

  Offset _normalizePoint(Offset point, Size size, Rect displayCrop) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx =
        displayCrop.left +
        ((point.dx.clamp(0.0, safeWidth) / safeWidth) * displayCrop.width);
    final dy =
        displayCrop.top +
        ((point.dy.clamp(0.0, safeHeight) / safeHeight) * displayCrop.height);
    return Offset(dx, dy);
  }

  Offset _projectPointToDisplay(Offset point, Rect displayCrop) {
    return Offset(
      ((point.dx - displayCrop.left) / displayCrop.width).toDouble(),
      ((point.dy - displayCrop.top) / displayCrop.height).toDouble(),
    );
  }

  Offset _clampOverlayPosition(Offset position, {Rect? bounds}) {
    final rect = bounds ?? kComposerFullCropRectNormalized;
    final marginX = math.min(0.14, rect.width * 0.14);
    final marginY = math.min(0.12, rect.height * 0.12);
    return Offset(
      position.dx.clamp(rect.left + marginX, rect.right - marginX).toDouble(),
      position.dy.clamp(rect.top + marginY, rect.bottom - marginY).toDouble(),
    );
  }

  void _setMarkupColor(double value) {
    if (!_currentItem.isImage) return;
    final clampedValue = value.clamp(0.0, 1.0).toDouble();
    setState(() {
      _currentItem.markupColorValue = clampedValue;
      final activeOverlay = _activeTextOverlay;
      if (activeOverlay != null) {
        activeOverlay.colorValue = clampedValue;
      }
    });
  }

  void _handleOverlayScaleStart(_MediaComposerTextOverlay overlay) {
    _overlayInteractionBaseScale = overlay.scale;
  }

  void _handleOverlayScaleUpdate(
    _MediaComposerTextOverlay overlay,
    ScaleUpdateDetails details,
    Size size,
    Rect displayCrop,
  ) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final movedPosition = Offset(
      overlay.position.dx +
          ((details.focalPointDelta.dx / safeWidth) * displayCrop.width),
      overlay.position.dy +
          ((details.focalPointDelta.dy / safeHeight) * displayCrop.height),
    );

    setState(() {
      overlay.position = _clampOverlayPosition(
        movedPosition,
        bounds: displayCrop,
      );
      overlay.scale = (_overlayInteractionBaseScale * details.scale)
          .clamp(0.7, 3.2)
          .toDouble();
    });
  }

  void _startStroke(Offset point, Size size, Rect displayCrop) {
    if (!_drawMode || !_currentItem.isImage) return;
    if (_eraserMode) {
      _eraseAtPoint(point, size, displayCrop);
      return;
    }
    setState(() {
      _currentItem.strokes.add(
        _MediaComposerStroke(
          color: _currentItem.markupColor,
          widthFactor: _brushSizeFactor,
          points: [_normalizePoint(point, size, displayCrop)],
        ),
      );
    });
  }

  void _appendStroke(Offset point, Size size, Rect displayCrop) {
    if (!_drawMode || !_currentItem.isImage || _currentItem.strokes.isEmpty) {
      if (_drawMode && _eraserMode && _currentItem.isImage) {
        _eraseAtPoint(point, size, displayCrop);
      }
      return;
    }
    if (_eraserMode) {
      _eraseAtPoint(point, size, displayCrop);
      return;
    }
    setState(() {
      _currentItem.strokes.last.points.add(
        _normalizePoint(point, size, displayCrop),
      );
    });
  }

  void _eraseAtPoint(Offset point, Size size, Rect displayCrop) {
    final target = _normalizePoint(point, size, displayCrop);
    final radius = _brushSizeFactor * 2.2;
    final nextStrokes = <_MediaComposerStroke>[];

    for (final stroke in _currentItem.strokes) {
      final nextSegments = <List<Offset>>[];
      var currentSegment = <Offset>[];
      for (final itemPoint in stroke.points) {
        final shouldErase = (itemPoint - target).distance <= radius;
        if (shouldErase) {
          if (currentSegment.length > 1) {
            nextSegments.add(List<Offset>.from(currentSegment));
          } else if (currentSegment.length == 1) {
            nextSegments.add(List<Offset>.from(currentSegment));
          }
          currentSegment = <Offset>[];
          continue;
        }
        currentSegment.add(itemPoint);
      }

      if (currentSegment.isNotEmpty) {
        nextSegments.add(List<Offset>.from(currentSegment));
      }

      for (final segment in nextSegments) {
        if (segment.isEmpty) continue;
        nextStrokes.add(
          _MediaComposerStroke(
            color: stroke.color,
            widthFactor: stroke.widthFactor,
            points: segment,
          ),
        );
      }
    }

    setState(() {
      _currentItem.strokes
        ..clear()
        ..addAll(nextStrokes);
    });
  }

  void _moveCropRect(DragUpdateDetails details, Size size) {
    final currentCrop = _currentWorkingCropRect;
    if (!_cropMode) return;
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx = details.delta.dx / safeWidth;
    final dy = details.delta.dy / safeHeight;

    setState(() {
      _currentItem.draftCropRectNormalized = _clampCropRect(
        currentCrop.shift(Offset(dx, dy)),
      );
    });
  }

  Rect _buildLockedCropRect({
    required _MediaComposerCropHandle handle,
    required Offset anchor,
    required double width,
    required double aspectRatio,
  }) {
    final height = width / math.max(0.1, aspectRatio);
    switch (handle) {
      case _MediaComposerCropHandle.topLeft:
        return Rect.fromLTRB(
          anchor.dx - width,
          anchor.dy - height,
          anchor.dx,
          anchor.dy,
        );
      case _MediaComposerCropHandle.topRight:
        return Rect.fromLTRB(
          anchor.dx,
          anchor.dy - height,
          anchor.dx + width,
          anchor.dy,
        );
      case _MediaComposerCropHandle.bottomLeft:
        return Rect.fromLTRB(
          anchor.dx - width,
          anchor.dy,
          anchor.dx,
          anchor.dy + height,
        );
      case _MediaComposerCropHandle.bottomRight:
        return Rect.fromLTRB(
          anchor.dx,
          anchor.dy,
          anchor.dx + width,
          anchor.dy + height,
        );
    }
  }

  Rect _clampLockedCropRect({
    required _MediaComposerCropHandle handle,
    required Offset anchor,
    required double desiredWidth,
    required double aspectRatio,
  }) {
    final minHeight = math.max(
      kComposerCropMinSide,
      kComposerCropMinSide / aspectRatio,
    );
    final minWidth = math.max(kComposerCropMinSide, minHeight * aspectRatio);

    late final double maxWidth;
    late final double maxHeight;
    switch (handle) {
      case _MediaComposerCropHandle.topLeft:
        maxWidth = anchor.dx;
        maxHeight = anchor.dy;
        break;
      case _MediaComposerCropHandle.topRight:
        maxWidth = 1 - anchor.dx;
        maxHeight = anchor.dy;
        break;
      case _MediaComposerCropHandle.bottomLeft:
        maxWidth = anchor.dx;
        maxHeight = 1 - anchor.dy;
        break;
      case _MediaComposerCropHandle.bottomRight:
        maxWidth = 1 - anchor.dx;
        maxHeight = 1 - anchor.dy;
        break;
    }

    var width = desiredWidth
        .clamp(minWidth, math.max(minWidth, maxWidth))
        .toDouble();
    var height = width / aspectRatio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspectRatio;
    }
    if (height < minHeight) {
      height = minHeight;
      width = height * aspectRatio;
    }
    width = width.clamp(minWidth, math.max(minWidth, maxWidth)).toDouble();
    height = height.clamp(minHeight, math.max(minHeight, maxHeight)).toDouble();
    return _buildLockedCropRect(
      handle: handle,
      anchor: anchor,
      width: width,
      aspectRatio: aspectRatio,
    );
  }

  void _resizeCropRect(
    _MediaComposerCropHandle handle,
    DragUpdateDetails details,
    Size size,
  ) {
    final currentCrop = _currentWorkingCropRect;
    if (!_cropMode) return;
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final dx = details.delta.dx / safeWidth;
    final dy = details.delta.dy / safeHeight;
    final lockedAspectRatio = _lockedNormalizedCropAspectRatio(_currentItem);

    if (lockedAspectRatio == null) {
      var next = currentCrop;
      switch (handle) {
        case _MediaComposerCropHandle.topLeft:
          next = Rect.fromLTRB(
            currentCrop.left + dx,
            currentCrop.top + dy,
            currentCrop.right,
            currentCrop.bottom,
          );
          break;
        case _MediaComposerCropHandle.topRight:
          next = Rect.fromLTRB(
            currentCrop.left,
            currentCrop.top + dy,
            currentCrop.right + dx,
            currentCrop.bottom,
          );
          break;
        case _MediaComposerCropHandle.bottomLeft:
          next = Rect.fromLTRB(
            currentCrop.left + dx,
            currentCrop.top,
            currentCrop.right,
            currentCrop.bottom + dy,
          );
          break;
        case _MediaComposerCropHandle.bottomRight:
          next = Rect.fromLTRB(
            currentCrop.left,
            currentCrop.top,
            currentCrop.right + dx,
            currentCrop.bottom + dy,
          );
          break;
      }

      setState(() {
        _currentItem.draftCropRectNormalized = _clampCropRect(next);
      });
      return;
    }

    late final Offset anchor;
    late final double desiredWidth;
    switch (handle) {
      case _MediaComposerCropHandle.topLeft:
        anchor = currentCrop.bottomRight;
        desiredWidth = math.max(
          currentCrop.width - dx,
          (currentCrop.height - dy) * lockedAspectRatio,
        );
        break;
      case _MediaComposerCropHandle.topRight:
        anchor = currentCrop.bottomLeft;
        desiredWidth = math.max(
          currentCrop.width + dx,
          (currentCrop.height - dy) * lockedAspectRatio,
        );
        break;
      case _MediaComposerCropHandle.bottomLeft:
        anchor = currentCrop.topRight;
        desiredWidth = math.max(
          currentCrop.width - dx,
          (currentCrop.height + dy) * lockedAspectRatio,
        );
        break;
      case _MediaComposerCropHandle.bottomRight:
        anchor = currentCrop.topLeft;
        desiredWidth = math.max(
          currentCrop.width + dx,
          (currentCrop.height + dy) * lockedAspectRatio,
        );
        break;
    }

    setState(() {
      _currentItem.draftCropRectNormalized = _clampLockedCropRect(
        handle: handle,
        anchor: anchor,
        desiredWidth: desiredWidth,
        aspectRatio: lockedAspectRatio,
      );
    });
  }

  Future<void> _send() async {
    if (_sending || _items.isEmpty) return;
    if (_cropMode) {
      _applyCropEditing();
    }
    _finishTextEditing();

    setState(() {
      _sending = true;
      _sendingLabel = 'Hazırlanıyor...';
    });

    try {
      final preparedAttachments = <_PreparedComposerAttachment>[];
      final attachments = <OutgoingAttachmentDraft>[];
      for (var index = 0; index < _items.length; index++) {
        final item = _items[index];
        if (mounted) {
          setState(() {
            _sendingLabel = '${index + 1}/${_items.length} yükleniyor';
          });
        }

        final prepared = await _prepareAttachment(item);
        preparedAttachments.add(prepared);
        if (widget.onPreparedSend != null) {
          continue;
        }
        final chat = widget.chat!;
        final upload = await ChatApi.createAttachmentUpload(
          widget.session,
          chatId: chat.chatId,
          kind: prepared.kind,
          contentType: prepared.contentType,
          fileName: prepared.fileName,
        );

        final uploadRes = await http.put(
          Uri.parse(upload.uploadUrl),
          headers: upload.headers,
          body: prepared.bytes,
        );
        if (uploadRes.statusCode >= 400) {
          throw TurnaApiException('Dosya yüklenemedi.');
        }

        attachments.add(
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: prepared.kind,
            fileName: prepared.fileName,
            contentType: prepared.contentType,
            sizeBytes: prepared.bytes.length,
            width: prepared.width,
            height: prepared.height,
          ),
        );
      }

      final caption = _captionController.text.trim();
      final normalizedCaption = caption.isEmpty ? null : caption;

      if (widget.onPreparedSend != null) {
        final result = await widget.onPreparedSend!(
          preparedAttachments,
          normalizedCaption,
          _quality,
        );
        if (!mounted) return;
        Navigator.pop(context, result);
        return;
      }

      final chat = widget.chat!;
      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: chat.chatId,
        text: normalizedCaption,
        attachments: attachments,
      );

      await TurnaAnalytics.logEvent('attachment_sent', {
        'chat_id': chat.chatId,
        'quality': _quality.name,
        'count': attachments.length,
        'kind': attachments.length == 1 ? attachments.first.kind.name : 'album',
      });

      if (!mounted) return;
      Navigator.pop(context, message);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingLabel = null;
        });
      }
    }
  }

  Future<_PreparedComposerAttachment> _prepareAttachment(
    _MediaComposerItem item,
  ) async {
    final sourceBytes = await item.file.readAsBytes();

    if (!item.isImage) {
      return _PreparedComposerAttachment(
        kind: item.kind,
        fileName: item.fileName,
        contentType: item.contentType,
        bytes: sourceBytes,
      );
    }

    await _primeImageSize(item);
    return _renderImageAttachment(item, sourceBytes);
  }

  List<_MediaComposerStroke> _transformStrokesForCrop(
    List<_MediaComposerStroke> strokes,
    Rect cropRect,
  ) {
    if (cropRect == kComposerFullCropRectNormalized) return strokes;
    return strokes
        .map(
          (stroke) => _MediaComposerStroke(
            color: stroke.color,
            widthFactor: stroke.widthFactor,
            points: stroke.points
                .map(
                  (point) => Offset(
                    (point.dx - cropRect.left) / cropRect.width,
                    (point.dy - cropRect.top) / cropRect.height,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  List<_MediaComposerTextOverlay> _transformTextOverlaysForCrop(
    List<_MediaComposerTextOverlay> overlays,
    Rect cropRect,
  ) {
    if (cropRect == kComposerFullCropRectNormalized) return overlays;
    return overlays
        .map(
          (overlay) => _MediaComposerTextOverlay(
            id: overlay.id,
            text: overlay.text,
            position: Offset(
              (overlay.position.dx - cropRect.left) / cropRect.width,
              (overlay.position.dy - cropRect.top) / cropRect.height,
            ),
            scale: overlay.scale,
            colorValue: overlay.colorValue,
          ),
        )
        .toList();
  }

  Future<ui.Image> _renderRotatedImage(
    ui.Image sourceImage, {
    required int rotationTurns,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final srcRect = Rect.fromLTWH(
      0,
      0,
      sourceImage.width.toDouble(),
      sourceImage.height.toDouble(),
    );
    final paint = Paint()..isAntiAlias = true;

    switch (rotationTurns % 4) {
      case 1:
        canvas.save();
        canvas.translate(width.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, height.toDouble(), width.toDouble()),
          paint,
        );
        canvas.restore();
        break;
      case 2:
        canvas.save();
        canvas.translate(width.toDouble(), height.toDouble());
        canvas.rotate(math.pi);
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          paint,
        );
        canvas.restore();
        break;
      case 3:
        canvas.save();
        canvas.translate(0, height.toDouble());
        canvas.rotate(-math.pi / 2);
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, height.toDouble(), width.toDouble()),
          paint,
        );
        canvas.restore();
        break;
      default:
        canvas.drawImageRect(
          sourceImage,
          srcRect,
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          paint,
        );
    }

    return recorder.endRecording().toImage(width, height);
  }

  Future<_PreparedComposerAttachment> _renderImageAttachment(
    _MediaComposerItem item,
    Uint8List sourceBytes,
  ) async {
    final codec = await ui.instantiateImageCodec(sourceBytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final inputSize = Size(
      sourceImage.width.toDouble(),
      sourceImage.height.toDouble(),
    );
    final rotatedInputSize = item.rotationTurns.isOdd
        ? Size(inputSize.height, inputSize.width)
        : inputSize;
    final rotatedWidth = math.max(1, rotatedInputSize.width.round());
    final rotatedHeight = math.max(1, rotatedInputSize.height.round());
    final rotatedImage = await _renderRotatedImage(
      sourceImage,
      rotationTurns: item.rotationTurns,
      width: rotatedWidth,
      height: rotatedHeight,
    );
    final cropRect = item.cropRectNormalized ?? kComposerFullCropRectNormalized;
    final cropSrcRect = Rect.fromLTWH(
      cropRect.left * rotatedWidth,
      cropRect.top * rotatedHeight,
      cropRect.width * rotatedWidth,
      cropRect.height * rotatedHeight,
    );
    final scaledSize = _scaleToMax(
      cropSrcRect.size,
      _quality.imageMaxDimension,
    );
    final outputWidth = math.max(1, scaledSize.width.round());
    final outputHeight = math.max(1, scaledSize.height.round());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawImageRect(
      rotatedImage,
      cropSrcRect,
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
      paint,
    );

    _paintComposerStrokes(
      canvas,
      size: Size(outputWidth.toDouble(), outputHeight.toDouble()),
      strokes: _transformStrokesForCrop(item.strokes, cropRect),
    );
    _paintComposerTextOverlays(
      canvas,
      size: Size(outputWidth.toDouble(), outputHeight.toDouble()),
      overlays: _transformTextOverlaysForCrop(item.textOverlays, cropRect),
    );

    final rendered = await recorder.endRecording().toImage(
      outputWidth,
      outputHeight,
    );
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw TurnaApiException('Görsel hazırlanamadı.');
    }
    final encodedImage = img.Image.fromBytes(
      width: outputWidth,
      height: outputHeight,
      bytes: data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final jpgBytes = Uint8List.fromList(
      img.encodeJpg(encodedImage, quality: _quality.jpegQuality),
    );

    return _PreparedComposerAttachment(
      kind: item.kind,
      fileName: replaceFileExtension(item.fileName, 'jpg'),
      contentType: 'image/jpeg',
      bytes: jpgBytes,
      width: outputWidth,
      height: outputHeight,
    );
  }

  Size _scaleToMax(Size size, double maxDimension) {
    final longestSide = math.max(size.width, size.height);
    if (longestSide <= maxDimension) return size;
    final scale = maxDimension / longestSide;
    return Size(size.width * scale, size.height * scale);
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentItem;

    return Scaffold(
      backgroundColor: const Color(0xFF101312),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101312),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _toggleQuality,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: TurnaColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _quality.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Kirp',
            onPressed: _toggleCropMode,
            color: _cropMode ? TurnaColors.primary : null,
            icon: const Icon(Icons.crop_outlined),
          ),
          IconButton(
            tooltip: 'Yazı',
            onPressed: _cropMode
                ? null
                : () => _editOverlayText(emojiMode: false),
            icon: const Icon(Icons.text_fields_outlined),
          ),
          IconButton(
            tooltip: 'Çiz',
            onPressed: _cropMode ? null : _toggleDrawMode,
            color: _drawMode ? TurnaColors.primary : null,
            icon: const Icon(Icons.draw_outlined),
          ),
          IconButton(
            tooltip: 'Emoji',
            onPressed: _cropMode
                ? null
                : () => _editOverlayText(emojiMode: true),
            icon: const Icon(Icons.emoji_emotions_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  children: [
                    if (_drawMode && current.isImage)
                      Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ComposerToolChip(
                                label: 'İnce',
                                selected:
                                    !_eraserMode && _brushSizeFactor == 0.008,
                                onTap: () => _setBrushSize(0.008),
                              ),
                              const SizedBox(width: 8),
                              _ComposerToolChip(
                                label: 'Orta',
                                selected:
                                    !_eraserMode && _brushSizeFactor == 0.011,
                                onTap: () => _setBrushSize(0.011),
                              ),
                              const SizedBox(width: 8),
                              _ComposerToolChip(
                                label: 'Kalın',
                                selected:
                                    !_eraserMode && _brushSizeFactor == 0.016,
                                onTap: () => _setBrushSize(0.016),
                              ),
                              const SizedBox(width: 8),
                              _ComposerToolChip(
                                label: 'Silgi',
                                selected: _eraserMode,
                                onTap: _toggleEraser,
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _undoCurrentStroke,
                                child: const Text('Geri al'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        physics: _cropMode
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        itemCount: _items.length,
                        onPageChanged: (index) {
                          _finishTextEditing();
                          setState(() {
                            _selectedIndex = index;
                            _cropMode = false;
                            _drawMode = false;
                            _eraserMode = false;
                            for (final item in _items) {
                              item.draftCropRectNormalized = null;
                              item.draftCropPresetId = null;
                            }
                          });
                        },
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _buildPreviewPage(item);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_items.length > 1)
              SizedBox(
                height: 92,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  scrollDirection: Axis.horizontal,
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final selected = index == _selectedIndex;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: item.isImage
                              ? Image.file(
                                  File(item.file.path),
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: const Color(0xFF1F2322),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.videocam_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_cropMode && current.isImage)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 16, 10),
                child: Row(
                  children: [
                    _ComposerOverlayPillButton(
                      icon: Icons.rotate_90_degrees_ccw_outlined,
                      onTap: _rotateCurrent,
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<String>(
                      initialValue: _currentWorkingCropPresetId,
                      onSelected: (value) =>
                          _applyCropPreset(_cropPresetForId(value)),
                      color: const Color(0xFF1A1F1D),
                      itemBuilder: (_) => _kComposerCropPresets
                          .map(
                            (preset) => PopupMenuItem<String>(
                              value: preset.id,
                              child: Text(
                                preset.label,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC1A1F1D),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.crop_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _cropPresetForId(
                                _currentWorkingCropPresetId,
                              ).label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _cancelCropEditing,
                      child: const Text(
                        'İptal',
                        style: TextStyle(color: Color(0xFFB7BCB9)),
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: TurnaColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _applyCropEditing,
                      child: const Text('Tamam'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.captionEnabled)
                    Expanded(
                      child: TextField(
                        controller: _captionController,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Açıklama ekle',
                          hintStyle: const TextStyle(color: Color(0xFF7C8380)),
                          filled: true,
                          fillColor: const Color(0xFF162033),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  if (widget.captionEnabled) const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_sendingLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _sendingLabel!,
                            style: const TextStyle(
                              color: Color(0xFFB8BFBC),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      FloatingActionButton.small(
                        backgroundColor: TurnaColors.primary,
                        onPressed: _sending ? null : _send,
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPage(_MediaComposerItem item) {
    if (!item.isImage) {
      return Center(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF181D1C),
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.videocam_outlined,
                size: 56,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(
                item.fileName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatBytesLabel(item.sizeBytes),
                style: const TextStyle(color: Color(0xFFB8BFBC), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCurrent = identical(item, _currentItem);
        final isCropingCurrent = isCurrent && _cropMode;
        final activeOverlay = isCurrent ? _activeTextOverlay : null;
        final displayCrop = isCropingCurrent
            ? kComposerFullCropRectNormalized
            : _displayCropRectFor(item);
        final aspectRatio = _effectiveAspectRatioFor(item, displayCrop);
        var width = constraints.maxWidth;
        var height = width / aspectRatio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * aspectRatio;
        }
        final canvasSize = Size(width, height);
        final transformedStrokes = _transformStrokesForCrop(
          item.strokes,
          displayCrop,
        );
        final cropRect = isCropingCurrent
            ? _currentWorkingCropRect
            : (item.cropRectNormalized ?? _defaultCropRectFor(item));
        final cropFrame = _normalizedCropToRect(cropRect, canvasSize);

        final Widget imageLayer;
        if (displayCrop == kComposerFullCropRectNormalized) {
          imageLayer = RotatedBox(
            quarterTurns: item.rotationTurns,
            child: Image.file(File(item.file.path), fit: BoxFit.fill),
          );
        } else {
          final expandedWidth = width / displayCrop.width;
          final expandedHeight = height / displayCrop.height;
          imageLayer = ClipRect(
            child: Transform.translate(
              offset: Offset(
                -(displayCrop.left * expandedWidth),
                -(displayCrop.top * expandedHeight),
              ),
              child: SizedBox(
                width: expandedWidth,
                height: expandedHeight,
                child: RotatedBox(
                  quarterTurns: item.rotationTurns,
                  child: Image.file(File(item.file.path), fit: BoxFit.fill),
                ),
              ),
            ),
          );
        }

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _drawMode
                ? (details) => _startStroke(
                    details.localPosition,
                    canvasSize,
                    displayCrop,
                  )
                : null,
            onPanUpdate: _drawMode
                ? (details) => _appendStroke(
                    details.localPosition,
                    canvasSize,
                    displayCrop,
                  )
                : null,
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageLayer,
                    if (isCurrent && _activeTextOverlay != null)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _finishTextEditing,
                          child: Container(color: Colors.black45),
                        ),
                      ),
                    for (final overlay in item.textOverlays)
                      Builder(
                        builder: (_) {
                          final displayPosition = _projectPointToDisplay(
                            overlay.position,
                            displayCrop,
                          );
                          return Align(
                            alignment: Alignment(
                              (displayPosition.dx * 2) - 1,
                              (displayPosition.dy * 2) - 1,
                            ),
                            child:
                                isCurrent && overlay.id == _activeTextOverlayId
                                ? ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: width * 0.82,
                                    ),
                                    child: TextField(
                                      controller: _inlineTextController,
                                      focusNode: _inlineTextFocusNode,
                                      autofocus: false,
                                      maxLines: 4,
                                      minLines: 1,
                                      textAlign: TextAlign.center,
                                      cursorColor: overlay.color,
                                      style: TextStyle(
                                        color: overlay.color,
                                        fontWeight: FontWeight.w700,
                                        fontSize:
                                            math.max(18, width * 0.06) *
                                            overlay.scale,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 10,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onChanged: _syncActiveTextOverlay,
                                      onSubmitted: (_) => _finishTextEditing(),
                                    ),
                                  )
                                : GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: _drawMode || _cropMode
                                        ? null
                                        : () => _beginEditingTextOverlay(
                                            overlay,
                                            requestKeyboard: true,
                                          ),
                                    onScaleStart: _drawMode || _cropMode
                                        ? null
                                        : (_) =>
                                              _handleOverlayScaleStart(overlay),
                                    onScaleUpdate: _drawMode || _cropMode
                                        ? null
                                        : (details) =>
                                              _handleOverlayScaleUpdate(
                                                overlay,
                                                details,
                                                canvasSize,
                                                displayCrop,
                                              ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: width * 0.82,
                                      ),
                                      child: Text(
                                        overlay.text,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: overlay.color,
                                          fontWeight: FontWeight.w700,
                                          fontSize:
                                              math.max(18, width * 0.06) *
                                              overlay.scale,
                                          shadows: const [
                                            Shadow(
                                              color: Colors.black54,
                                              blurRadius: 10,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _MediaComposerStrokePainter(
                          strokes: transformedStrokes,
                        ),
                      ),
                    ),
                    if (isCurrent && _cropMode)
                      Positioned.fill(
                        child: _ComposerCropOverlay(
                          cropFrame: cropFrame,
                          onMove: (details) =>
                              _moveCropRect(details, canvasSize),
                          onResize: (handle, details) =>
                              _resizeCropRect(handle, details, canvasSize),
                        ),
                      ),
                    if (isCurrent && (_drawMode || activeOverlay != null))
                      Positioned(
                        right: 12,
                        top: 16,
                        bottom: 16,
                        child: _ComposerColorSlider(
                          value:
                              activeOverlay?.colorValue ??
                              item.markupColorValue,
                          color: activeOverlay?.color ?? item.markupColor,
                          onChanged: _setMarkupColor,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ComposerColorSlider extends StatelessWidget {
  const _ComposerColorSlider({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  void _updateFromOffset(Offset localPosition, double height) {
    final safeHeight = height <= 0 ? 1.0 : height;
    onChanged((localPosition.dy / safeHeight).clamp(0.0, 1.0).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _updateFromOffset(details.localPosition, trackHeight),
          onVerticalDragStart: (details) =>
              _updateFromOffset(details.localPosition, trackHeight),
          onVerticalDragUpdate: (details) =>
              _updateFromOffset(details.localPosition, trackHeight),
          child: SizedBox(
            width: 34,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: 16,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: kComposerPaletteStops,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                ),
                Positioned(
                  top: (trackHeight - 24) * value.clamp(0.0, 1.0).toDouble(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
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
}

class _ComposerCropOverlay extends StatelessWidget {
  const _ComposerCropOverlay({
    required this.cropFrame,
    required this.onMove,
    required this.onResize,
  });

  final Rect cropFrame;
  final ValueChanged<DragUpdateDetails> onMove;
  final void Function(
    _MediaComposerCropHandle handle,
    DragUpdateDetails details,
  )
  onResize;

  @override
  Widget build(BuildContext context) {
    const handleSize = 30.0;
    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ComposerCropOverlayPainter(cropFrame: cropFrame),
          ),
        ),
        Positioned.fromRect(
          rect: cropFrame,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: onMove,
            child: const SizedBox.expand(),
          ),
        ),
        _buildHandle(
          center: cropFrame.topLeft,
          handle: _MediaComposerCropHandle.topLeft,
          handleSize: handleSize,
        ),
        _buildHandle(
          center: cropFrame.topRight,
          handle: _MediaComposerCropHandle.topRight,
          handleSize: handleSize,
        ),
        _buildHandle(
          center: cropFrame.bottomLeft,
          handle: _MediaComposerCropHandle.bottomLeft,
          handleSize: handleSize,
        ),
        _buildHandle(
          center: cropFrame.bottomRight,
          handle: _MediaComposerCropHandle.bottomRight,
          handleSize: handleSize,
        ),
      ],
    );
  }

  Widget _buildHandle({
    required Offset center,
    required _MediaComposerCropHandle handle,
    required double handleSize,
  }) {
    return Positioned(
      left: center.dx - (handleSize / 2),
      top: center.dy - (handleSize / 2),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) => onResize(handle, details),
        child: Container(
          width: handleSize,
          height: handleSize,
          alignment: Alignment.center,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF101312), width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerCropOverlayPainter extends CustomPainter {
  const _ComposerCropOverlayPainter({required this.cropFrame});

  final Rect cropFrame;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(cropFrame);
    final overlay = Path.combine(PathOperation.difference, outer, inner);

    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );
    canvas.drawRect(
      cropFrame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final thirdWidth = cropFrame.width / 3;
    final thirdHeight = cropFrame.height / 3;

    for (var index = 1; index <= 2; index++) {
      final dx = cropFrame.left + (thirdWidth * index);
      canvas.drawLine(
        Offset(dx, cropFrame.top),
        Offset(dx, cropFrame.bottom),
        gridPaint,
      );

      final dy = cropFrame.top + (thirdHeight * index);
      canvas.drawLine(
        Offset(cropFrame.left, dy),
        Offset(cropFrame.right, dy),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ComposerCropOverlayPainter oldDelegate) {
    return oldDelegate.cropFrame != cropFrame;
  }
}

class _ComposerOverlayPillButton extends StatelessWidget {
  const _ComposerOverlayPillButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB81A1F1D),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _ComposerToolChip extends StatelessWidget {
  const _ComposerToolChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? TurnaColors.primary : const Color(0xFF162033),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaComposerItem {
  _MediaComposerItem({
    required this.kind,
    required this.file,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
  });

  factory _MediaComposerItem.fromSeed(MediaComposerSeed seed) {
    return _MediaComposerItem(
      kind: seed.kind,
      file: seed.file,
      fileName: seed.fileName,
      contentType: seed.contentType,
      sizeBytes: seed.sizeBytes,
    );
  }

  final ChatAttachmentKind kind;
  final XFile file;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final List<_MediaComposerStroke> strokes = [];
  final List<_MediaComposerTextOverlay> textOverlays = [];
  Rect? cropRectNormalized;
  Rect? draftCropRectNormalized;
  String cropPresetId = 'original';
  String? draftCropPresetId;
  double markupColorValue = 0;
  int rotationTurns = 0;
  Size? sourceSize;

  bool get isImage => kind == ChatAttachmentKind.image;

  Color get markupColor => composerColorForValue(markupColorValue);

  bool get hasMarkup =>
      rotationTurns != 0 ||
      strokes.isNotEmpty ||
      textOverlays.isNotEmpty ||
      (cropRectNormalized != null &&
          cropRectNormalized != kComposerFullCropRectNormalized);

  double get effectiveAspectRatio {
    final base = sourceSize ?? const Size(1, 1);
    final width = rotationTurns.isOdd ? base.height : base.width;
    final height = rotationTurns.isOdd ? base.width : base.height;
    return math.max(0.1, width / math.max(0.1, height));
  }
}

class _MediaComposerTextOverlay {
  _MediaComposerTextOverlay({
    required this.id,
    required this.text,
    required this.position,
    required this.scale,
    required this.colorValue,
  });

  final String id;
  String text;
  Offset position;
  double scale;
  double colorValue;

  Color get color => composerColorForValue(colorValue);
}

class _MediaComposerStroke {
  _MediaComposerStroke({
    required this.color,
    required this.points,
    required this.widthFactor,
  });

  final Color color;
  final List<Offset> points;
  final double widthFactor;
}

class _PreparedComposerAttachment {
  _PreparedComposerAttachment({
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.bytes,
    this.width,
    this.height,
  });

  final ChatAttachmentKind kind;
  final String fileName;
  final String contentType;
  final Uint8List bytes;
  final int? width;
  final int? height;
}

class _MediaComposerStrokePainter extends CustomPainter {
  const _MediaComposerStrokePainter({required this.strokes});

  final List<_MediaComposerStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    _paintComposerStrokes(canvas, size: size, strokes: strokes);
  }

  @override
  bool shouldRepaint(covariant _MediaComposerStrokePainter oldDelegate) {
    return true;
  }
}

void _paintComposerStrokes(
  Canvas canvas, {
  required Size size,
  required List<_MediaComposerStroke> strokes,
}) {
  for (final stroke in strokes) {
    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3, size.shortestSide * stroke.widthFactor);
    if (stroke.points.isEmpty) continue;
    if (stroke.points.length == 1) {
      final point = Offset(
        stroke.points.first.dx * size.width,
        stroke.points.first.dy * size.height,
      );
      canvas.drawCircle(point, paint.strokeWidth * 0.5, paint);
      continue;
    }

    final path = Path();
    final first = stroke.points.first;
    path.moveTo(first.dx * size.width, first.dy * size.height);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }
}

void _paintComposerTextOverlays(
  Canvas canvas, {
  required Size size,
  required List<_MediaComposerTextOverlay> overlays,
}) {
  for (final overlay in overlays) {
    final value = overlay.text.trim();
    if (value.isEmpty) continue;

    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: overlay.color,
          fontWeight: FontWeight.w700,
          fontSize: math.max(28, size.width * 0.06) * overlay.scale,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2)),
          ],
        ),
      ),
    )..layout(maxWidth: size.width * 0.82);

    final marginX = size.width * 0.04;
    final marginY = size.height * 0.04;
    final left = (size.width * overlay.position.dx) - (painter.width / 2);
    final top = (size.height * overlay.position.dy) - (painter.height / 2);

    painter.paint(
      canvas,
      Offset(
        left.clamp(marginX, size.width - painter.width - marginX).toDouble(),
        top.clamp(marginY, size.height - painter.height - marginY).toDouble(),
      ),
    );
  }
}
