part of '../../app/turna_app.dart';

class _VoiceMessageBubble extends StatefulWidget {
  const _VoiceMessageBubble({
    required this.attachment,
    required this.mine,
    required this.authToken,
    this.onLongPress,
    this.overlayFooter,
  });

  final ChatAttachment attachment;
  final bool mine;
  final String authToken;
  final VoidCallback? onLongPress;
  final Widget? overlayFooter;

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
  final ap.AudioPlayer _player = ap.AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  String? _preparedUrl;
  String? _preparedPath;
  Uint8List? _preparedBytes;

  int get _effectiveDurationMillis => _duration.inMilliseconds <= 0
      ? math.max(1, (widget.attachment.durationSeconds ?? 0) * 1000)
      : _duration.inMilliseconds;

  @override
  void initState() {
    super.initState();
    final configuredDuration = widget.attachment.durationSeconds;
    if (configuredDuration != null && configuredDuration > 0) {
      _duration = Duration(seconds: configuredDuration);
    }
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == ap.PlayerState.playing);
    });
    _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
    _player.onDurationChanged.listen((duration) {
      if (!mounted || duration == Duration.zero) return;
      setState(() => _duration = duration);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration() {
    final effective = _duration == Duration.zero
        ? Duration(seconds: widget.attachment.durationSeconds ?? 0)
        : _duration;
    if (effective <= Duration.zero) return '--:--';
    final minutes = effective.inMinutes.toString().padLeft(2, '0');
    final seconds = (effective.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  bool _isPreparedForUrl(String url) {
    return _preparedUrl == url &&
        (_preparedBytes != null || _preparedPath != null);
  }

  Future<void> _seekToRelativePosition(double localDx, double width) async {
    final url = widget.attachment.url?.trim() ?? '';
    if (url.isEmpty || width <= 0 || !_isPreparedForUrl(url)) return;

    final progress = (localDx / width).clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (_effectiveDurationMillis * progress).round(),
    );

    try {
      await _player.seek(target);
      if (!mounted) return;
      setState(() => _position = target);
    } catch (error) {
      turnaLog('voice seek failed', error);
    }
  }

  Future<void> _togglePlayback() async {
    final url = widget.attachment.url?.trim() ?? '';
    final mimeType = widget.attachment.contentType.trim().isEmpty
        ? null
        : widget.attachment.contentType.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ses kaydı bağlantısı hazır değil.')),
      );
      return;
    }
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (_preparedUrl == url && _preparedPath != null) {
        final shouldReplayFromStart =
            _position == Duration.zero ||
            (_duration > Duration.zero &&
                _position >= _duration - const Duration(milliseconds: 320));
        if (shouldReplayFromStart) {
          final preparedBytes = _preparedBytes;
          if (preparedBytes != null) {
            await _player.play(
              ap.BytesSource(preparedBytes, mimeType: mimeType),
            );
          } else {
            await _player.play(
              ap.DeviceFileSource(_preparedPath!, mimeType: mimeType),
            );
          }
          return;
        }
        await _player.resume();
        return;
      }
      _preparedUrl = url;
      final cachedFile = await TurnaLocalMediaCache.getOrDownloadFile(
        cacheKey: 'attachment:${widget.attachment.objectKey}',
        url: url,
        authToken: widget.authToken,
      );
      if (cachedFile == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ses kaydı indirilemedi.')),
        );
        return;
      }
      _preparedPath = cachedFile.path;
      final bytes = await cachedFile.readAsBytes();
      _preparedBytes = bytes;
      await _player.play(ap.BytesSource(bytes, mimeType: mimeType));
    } catch (error) {
      turnaLog('voice playback failed', error);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ses kaydı oynatılamadı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = widget.overlayFooter != null;
    final progress = (_position.inMilliseconds / _effectiveDurationMillis)
        .clamp(0.0, 1.0);
    final backgroundColor = showOverlay
        ? (widget.mine ? TurnaColors.chatOutgoing : Colors.white)
        : (widget.mine
              ? Colors.white.withValues(alpha: 0.26)
              : TurnaColors.chatUnreadBg);
    final accentColor = widget.mine
        ? TurnaColors.chatOutgoingText
        : TurnaColors.primary;
    final playButtonColor = widget.mine
        ? Colors.white.withValues(alpha: 0.34)
        : TurnaColors.primary;
    final playIconColor = widget.mine
        ? TurnaColors.chatOutgoingText
        : Colors.white;
    final subColor = widget.mine
        ? TurnaColors.chatOutgoingText.withValues(alpha: 0.74)
        : TurnaColors.textMuted;
    return Padding(
      padding: EdgeInsets.only(bottom: showOverlay ? 0 : 8),
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: Container(
          width: 236,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: showOverlay
                ? Border.all(
                    color: widget.mine
                        ? TurnaColors.chatOutgoing.withValues(alpha: 0.92)
                        : TurnaColors.border,
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _togglePlayback,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: playButtonColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: playIconColor,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) => unawaited(
                            _seekToRelativePosition(
                              details.localPosition.dx,
                              constraints.maxWidth,
                            ),
                          ),
                          onHorizontalDragUpdate: (details) => unawaited(
                            _seekToRelativePosition(
                              details.localPosition.dx,
                              constraints.maxWidth,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _VoiceWaveformStrip(
                                color: accentColor,
                                fadedColor: accentColor.withValues(alpha: 0.3),
                                activeBars: math.max(
                                  1,
                                  (_VoiceWaveformStrip.barCount * progress)
                                      .round(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    _formatDuration(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: subColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        minHeight: 3,
                                        value: progress,
                                        backgroundColor: accentColor.withValues(
                                          alpha: 0.16,
                                        ),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              accentColor,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (showOverlay) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: widget.overlayFooter!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceWaveformStrip extends StatelessWidget {
  const _VoiceWaveformStrip({
    required this.color,
    required this.activeBars,
    this.fadedColor,
  });

  static const List<double> _bars = <double>[
    7,
    11,
    9,
    15,
    10,
    17,
    8,
    13,
    18,
    11,
    15,
    9,
    16,
    12,
    8,
    14,
    19,
    10,
    13,
    9,
  ];

  static int get barCount => _bars.length;

  final Color color;
  final Color? fadedColor;
  final int activeBars;

  @override
  Widget build(BuildContext context) {
    final inactiveColor = fadedColor ?? color.withValues(alpha: 0.22);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List<Widget>.generate(_bars.length, (index) {
        final highlighted = index < activeBars;
        return Container(
          width: 3,
          height: _bars[index],
          margin: EdgeInsets.only(right: index == _bars.length - 1 ? 0 : 3),
          decoration: BoxDecoration(
            color: highlighted ? color : inactiveColor,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _VoiceComposerAction extends StatelessWidget {
  const _VoiceComposerAction({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: foregroundColor, size: 22),
        ),
      ),
    );
  }
}
