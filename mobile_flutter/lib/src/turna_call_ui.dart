part of '../main.dart';

class CallsPage extends StatefulWidget {
  const CallsPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  int _refreshTick = 0;
  String? _startingCallHistoryId;
  late Future<List<TurnaCallHistoryItem>> _callsFuture;

  @override
  void initState() {
    super.initState();
    _callsFuture = _buildCallsFuture();
    widget.callCoordinator.addListener(_onCallUpdate);
  }

  @override
  void didUpdateWidget(covariant CallsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.userId != widget.session.userId ||
        oldWidget.session.token != widget.session.token) {
      _reloadCalls();
    }
  }

  @override
  void dispose() {
    widget.callCoordinator.removeListener(_onCallUpdate);
    super.dispose();
  }

  void _onCallUpdate() {
    if (!mounted) return;
    _reloadCalls();
  }

  Future<List<TurnaCallHistoryItem>> _buildCallsFuture() {
    return CallApi.fetchCalls(widget.session, refreshTick: _refreshTick);
  }

  void _reloadCalls() {
    if (!mounted) return;
    setState(() {
      _refreshTick++;
      _callsFuture = _buildCallsFuture();
    });
  }

  Future<void> _openPeerProfile(TurnaCallHistoryItem item) async {
    final peerId = item.peer.id.trim();
    if (peerId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kişi bilgisi açılamadı.')));
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          session: widget.session,
          userId: peerId,
          fallbackName: item.peer.displayName,
          fallbackAvatarUrl: item.peer.avatarUrl,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );

    if (!mounted) return;
    _reloadCalls();
  }

  Future<void> _startCall(TurnaCallHistoryItem item) async {
    final peerId = item.peer.id.trim();
    if (peerId.isEmpty || _startingCallHistoryId == item.id) {
      if (peerId.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Arama başlatılamadı.')));
      }
      return;
    }

    setState(() => _startingCallHistoryId = item.id);

    try {
      final started = await CallApi.startCall(
        widget.session,
        calleeId: peerId,
        type: item.type,
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

      if (!mounted) return;
      _reloadCalls();
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted && _startingCallHistoryId == item.id) {
        setState(() => _startingCallHistoryId = null);
      }
    }
  }

  String _formatTime(String? iso) {
    return formatTurnaLocalClock(iso);
  }

  String _statusLabel(TurnaCallHistoryItem item) {
    switch (item.status) {
      case TurnaCallStatus.accepted:
        if (item.durationSeconds != null && item.durationSeconds! > 0) {
          final minutes = item.durationSeconds! ~/ 60;
          final seconds = item.durationSeconds! % 60;
          return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        }
        return 'Baglandi';
      case TurnaCallStatus.declined:
        return 'Reddedildi';
      case TurnaCallStatus.missed:
        return 'Cevapsız';
      case TurnaCallStatus.cancelled:
        return 'İptal edildi';
      case TurnaCallStatus.ended:
        return 'Sonlandi';
      case TurnaCallStatus.ringing:
        return 'Caliyor';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aramalar')),
      body: FutureBuilder<List<TurnaCallHistoryItem>>(
        future: _callsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            final isAuthError = error is TurnaUnauthorizedException;
            if (isAuthError) {
              return buildTurnaSessionExpiredRedirect(widget.onSessionExpired);
            }
            return _CenteredState(
              icon: Icons.call_missed_outgoing,
              title: 'Aramalar yüklenemedi',
              message: error.toString(),
              primaryLabel: 'Tekrar dene',
              onPrimary: _reloadCalls,
            );
          }

          final calls = snapshot.data ?? const [];
          if (calls.isEmpty) {
            return const _CenteredState(
              icon: Icons.call_outlined,
              title: 'Henüz arama yok',
              message: 'Yaptığın ve aldığın aramalar burada listelenecek.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _reloadCalls(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: calls.length,
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                indent: 76,
                endIndent: 16,
                color: Color(0x12000000),
              ),
              itemBuilder: (context, index) {
                final item = calls[index];
                final isStartingCall = _startingCallHistoryId == item.id;
                final isMissed =
                    item.status == TurnaCallStatus.missed ||
                    item.status == TurnaCallStatus.declined;
                return ListTile(
                  onTap: () => _openPeerProfile(item),
                  leading: _ProfileAvatar(
                    label: item.peer.displayName,
                    avatarUrl: item.peer.avatarUrl,
                    authToken: widget.session.token,
                    radius: 22,
                  ),
                  title: Text(
                    item.peer.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Row(
                    children: [
                      Icon(
                        item.direction == 'incoming'
                            ? Icons.call_received
                            : Icons.call_made,
                        size: 16,
                        color: isMissed
                            ? Colors.red.shade400
                            : TurnaColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _statusLabel(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  trailing: SizedBox(
                    width: 58,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(item.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1,
                            color: Color(0xFF777C79),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: isStartingCall ? null : () => _startCall(item),
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: Center(
                              child: isStartingCall
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      item.type == TurnaCallType.video
                                          ? Icons.videocam_outlined
                                          : Icons.call_outlined,
                                      size: 22,
                                      color: const Color(0xFF777C79),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({
    super.key,
    required this.session,
    required this.coordinator,
    required this.incoming,
    required this.onSessionExpired,
    this.returnChatOnExit,
  });

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaIncomingCallEvent incoming;
  final VoidCallback onSessionExpired;
  final ChatPreview? returnChatOnExit;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  bool _busy = false;

  String get _wakeLockReason => 'incoming-call:${widget.incoming.call.id}';

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_handleCoordinator);
    unawaited(TurnaDisplayWakeLock.acquire(_wakeLockReason));
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinator);
    unawaited(TurnaDisplayWakeLock.release(_wakeLockReason));
    super.dispose();
  }

  void _handleCoordinator() {
    final terminal = widget.coordinator.consumeTerminal(
      widget.incoming.call.id,
    );
    if (terminal == null || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final accepted = await CallApi.acceptCall(
        widget.session,
        callId: widget.incoming.call.id,
      );
      widget.coordinator.clearCall(widget.incoming.call.id);
      if (!mounted) return;
      final callSession = kTurnaCallUiController.obtainSession(
        session: widget.session,
        coordinator: widget.coordinator,
        call: accepted.call,
        connect: accepted.connect,
        onSessionExpired: widget.onSessionExpired,
        returnChatOnExit: widget.returnChatOnExit,
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'active-call'),
          builder: (_) => ActiveCallPage(callSession: callSession),
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
      setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CallApi.declineCall(
        widget.session,
        callId: widget.incoming.call.id,
      );
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onSessionExpired();
      }
    } catch (_) {}

    widget.coordinator.clearCall(widget.incoming.call.id);
    await TurnaNativeCallManager.endCallUi(widget.incoming.call.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.incoming.call;
    final isVideo = call.type == TurnaCallType.video;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1112),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Stack(
              children: [
                Center(
                  child: _CallIdentityPanel(
                    authToken: widget.session.token,
                    displayName: call.peer.displayName,
                    avatarUrl: call.peer.avatarUrl,
                    subtitle: isVideo ? 'Görüntülü arama' : 'Sesli arama',
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton(
                          heroTag: 'decline_${call.id}',
                          backgroundColor: Colors.red.shade400,
                          onPressed: _busy ? null : _decline,
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 72),
                        FloatingActionButton(
                          heroTag: 'accept_${call.id}',
                          backgroundColor: TurnaColors.primary,
                          onPressed: _busy ? null : _accept,
                          child: Icon(
                            isVideo ? Icons.videocam : Icons.call,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OutgoingCallPage extends StatefulWidget {
  const OutgoingCallPage({
    super.key,
    required this.session,
    required this.coordinator,
    required this.initialCall,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaCallSummary initialCall;
  final VoidCallback onSessionExpired;

  @override
  State<OutgoingCallPage> createState() => _OutgoingCallPageState();
}

class _OutgoingCallPageState extends State<OutgoingCallPage> {
  bool _ending = false;
  bool _navigatedToActive = false;
  bool _closed = false;

  String get _wakeLockReason => 'outgoing-call:${widget.initialCall.id}';

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_handleCoordinator);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCoordinator());
    unawaited(TurnaDisplayWakeLock.acquire(_wakeLockReason));
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinator);
    unawaited(TurnaDisplayWakeLock.release(_wakeLockReason));
    super.dispose();
  }

  void _handleCoordinator() {
    if (!mounted || _navigatedToActive) return;
    final accepted = widget.coordinator.consumeAccepted(widget.initialCall.id);
    if (accepted != null) {
      _navigatedToActive = true;
      widget.coordinator.clearCall(widget.initialCall.id);
      final callSession = kTurnaCallUiController.obtainSession(
        session: widget.session,
        coordinator: widget.coordinator,
        call: accepted.call,
        connect: accepted.connect,
        onSessionExpired: widget.onSessionExpired,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ActiveCallPage(callSession: callSession),
        ),
      );
      return;
    }

    final terminal = widget.coordinator.consumeTerminal(widget.initialCall.id);
    if (terminal == null) return;

    final message = switch (terminal.kind) {
      'declined' => 'Arama reddedildi.',
      'missed' => 'Cevap yok.',
      _ => 'Arama sonlandı.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    _closePage();
  }

  void _closePage() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _cancelCall() async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      await CallApi.endCall(widget.session, callId: widget.initialCall.id);
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onSessionExpired();
      }
    } catch (_) {}

    widget.coordinator.clearCall(widget.initialCall.id);
    await TurnaNativeCallManager.endCallUi(widget.initialCall.id);
    _closePage();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.initialCall;
    return Scaffold(
      backgroundColor: const Color(0xFF101314),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(
                call.peer.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                call.type == TurnaCallType.video
                    ? 'Görüntülü arama çalıyor...'
                    : 'Sesli arama çalıyor...',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB7BCB9), fontSize: 16),
              ),
              Expanded(
                child: Center(
                  child: _ProfileAvatar(
                    label: call.peer.displayName,
                    avatarUrl: call.peer.avatarUrl,
                    authToken: widget.session.token,
                    radius: 66,
                  ),
                ),
              ),
              _AudioCallControlDock(
                children: [
                  const _AudioCallControlButton(
                    onTap: null,
                    icon: Icon(Icons.videocam_outlined),
                  ),
                  const _AudioCallControlButton(
                    onTap: null,
                    icon: Icon(Icons.hearing_rounded),
                  ),
                  const _AudioCallControlButton(
                    onTap: null,
                    icon: Icon(Icons.mic_none_rounded),
                  ),
                  _AudioCallControlButton(
                    onTap: _ending ? null : _cancelCall,
                    icon: const Icon(Icons.call_end_rounded),
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallIdentityPanel extends StatelessWidget {
  const _CallIdentityPanel({
    required this.authToken,
    required this.displayName,
    required this.avatarUrl,
    required this.subtitle,
  });

  final String authToken;
  final String displayName;
  final String? avatarUrl;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfileAvatar(
            label: displayName,
            avatarUrl: avatarUrl,
            authToken: authToken,
            radius: 48,
          ),
          const SizedBox(height: 20),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB7BCB9), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _MiniCallOverlay extends StatelessWidget {
  const _MiniCallOverlay({required this.session});

  final TurnaManagedCallSession session;

  @override
  Widget build(BuildContext context) {
    final remoteVideo = session.adapter.primaryRemoteVideoTrack;
    return Positioned(
      right: 16,
      top: 92,
      width: 138,
      height: 196,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => kTurnaCallUiController.expandMini(session),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                remoteVideo != null && session.call.type == TurnaCallType.video
                    ? lk.VideoTrackRenderer(remoteVideo)
                    : Container(
                        color: const Color(0xFF111416),
                        child: Center(
                          child: _ProfileAvatar(
                            label: session.call.peer.displayName,
                            avatarUrl: session.call.peer.avatarUrl,
                            authToken: session.session.token,
                            radius: 26,
                          ),
                        ),
                      ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.44),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      session.call.peer.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioCallControlDock extends StatelessWidget {
  const _AudioCallControlDock({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

class _AudioCallControlButton extends StatelessWidget {
  const _AudioCallControlButton({
    this.onTap,
    this.icon,
    this.child,
    this.active = false,
    this.destructive = false,
  });

  final VoidCallback? onTap;
  final Widget? icon;
  final Widget? child;
  final bool active;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = destructive
        ? const Color(0xFFFF445A)
        : active
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFF2A2D31);
    final foregroundColor = onTap == null && !destructive
        ? Colors.white38
        : Colors.white;

    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: IconTheme(
              data: IconThemeData(size: 24, color: foregroundColor),
              child: child ?? icon ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

class ActiveCallPage extends StatefulWidget {
  const ActiveCallPage({super.key, required this.callSession});

  final TurnaManagedCallSession callSession;

  @override
  State<ActiveCallPage> createState() => _ActiveCallPageState();
}

enum _CallPreviewCorner { topLeft, topRight, bottomLeft, bottomRight }

class _ActiveCallPageState extends State<ActiveCallPage> {
  late final TurnaManagedCallSession _callSession;
  bool _ending = false;
  bool _handledSessionEnd = false;
  bool _leaving = false;
  bool _showingVideoUpgradeDialog = false;
  int _lastNoticeRevision = 0;
  String? _lastHandledVideoUpgradeRequestId;
  bool _showLocalVideoPrimary = false;
  _CallPreviewCorner _previewCorner = _CallPreviewCorner.topRight;
  Offset? _previewDragTopLeft;
  bool _previewDragMoved = false;

  static const double _previewMargin = 16;
  static const double _previewWidth = 96;
  static const double _previewHeight = 170;
  static const double _previewBottomReserved = 112;
  static const double _previewSnapThreshold = 84;

  @override
  void initState() {
    super.initState();
    _callSession = widget.callSession;
    kTurnaCallUiController.hideMini();
    _callSession
      ..addListener(_refresh)
      ..setFullScreenVisible(true);
    unawaited(_callSession.ensureStarted());
  }

  @override
  void dispose() {
    _callSession
      ..removeListener(_refresh)
      ..setFullScreenVisible(false);
    kTurnaCallUiController.releaseFullScreenSession(_callSession);
    super.dispose();
  }

  void _refresh() {
    if (_callSession.ended && !_handledSessionEnd && mounted) {
      _handledSessionEnd = true;
      final message = _callSession.terminalMessage;
      if (message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      _leaveCallView();
      return;
    }
    _maybeShowUpgradeNotice();
    _maybeShowVideoUpgradeDialog();
    if (mounted) {
      setState(() {});
    }
  }

  void _maybeShowUpgradeNotice() {
    if (!mounted || _callSession.noticeRevision == _lastNoticeRevision) return;
    _lastNoticeRevision = _callSession.noticeRevision;
    final message = _callSession.noticeMessage?.trim();
    if (message == null || message.isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _maybeShowVideoUpgradeDialog() {
    final request = _callSession.pendingVideoUpgradeRequest;
    if (!mounted ||
        request == null ||
        request.requestId == _lastHandledVideoUpgradeRequestId ||
        _showingVideoUpgradeDialog) {
      return;
    }

    _showingVideoUpgradeDialog = true;
    _lastHandledVideoUpgradeRequestId = request.requestId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _showingVideoUpgradeDialog = false;
        return;
      }

      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Görüntülü arama isteği'),
            content: Text(
              '${request.call.peer.displayName} görüntülü aramaya geçmek istiyor.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Reddet'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Onayla'),
              ),
            ],
          );
        },
      );

      _showingVideoUpgradeDialog = false;
      if (!mounted) return;
      await _callSession.respondVideoUpgrade(accept: accepted == true);
    });
  }

  void _leaveCallView() {
    if (_leaving) return;
    _leaving = true;
    final returnChat = _callSession.returnChatOnExit;
    if (returnChat == null) {
      Navigator.of(context).pop();
      return;
    }

    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      buildChatRoomRoute(
        chat: returnChat,
        session: _callSession.session,
        callCoordinator: _callSession.coordinator,
        onSessionExpired: _callSession.onSessionExpired,
      ),
      (route) => route.isFirst,
    );
  }

  void _minimizeCall() {
    if (_callSession.call.type != TurnaCallType.video) {
      _leaveCallView();
      return;
    }
    kTurnaCallUiController.showMini(_callSession);
    Navigator.of(context).pop();
  }

  Future<void> _endCall() async {
    if (_ending) return;
    setState(() => _ending = true);
    await _callSession.endCall();
    if (mounted) {
      _leaveCallView();
    }
  }

  Future<void> _requestVideoUpgrade() async {
    await _callSession.requestVideoUpgrade();
  }

  void _toggleVideoSwap() {
    final adapter = _callSession.adapter;
    if (_callSession.call.type != TurnaCallType.video ||
        !adapter.cameraEnabled ||
        adapter.localVideoTrack == null ||
        adapter.primaryRemoteVideoTrack == null) {
      return;
    }
    setState(() => _showLocalVideoPrimary = !_showLocalVideoPrimary);
  }

  Offset _previewAnchorOffset(Size size, _CallPreviewCorner corner) {
    final maxLeft = math.max(
      _previewMargin,
      size.width - _previewMargin - _previewWidth,
    );
    final bottomTop = math.max(
      _previewMargin,
      size.height - _previewBottomReserved - _previewHeight,
    );
    return switch (corner) {
      _CallPreviewCorner.topLeft => const Offset(
        _previewMargin,
        _previewMargin,
      ),
      _CallPreviewCorner.topRight => Offset(maxLeft, _previewMargin),
      _CallPreviewCorner.bottomLeft => Offset(_previewMargin, bottomTop),
      _CallPreviewCorner.bottomRight => Offset(maxLeft, bottomTop),
    };
  }

  Offset _clampPreviewOffset(Size size, Offset value) {
    final maxLeft = math.max(
      _previewMargin,
      size.width - _previewMargin - _previewWidth,
    );
    final maxTop = math.max(
      _previewMargin,
      size.height - _previewBottomReserved - _previewHeight,
    );
    return Offset(
      value.dx.clamp(_previewMargin, maxLeft),
      value.dy.clamp(_previewMargin, maxTop),
    );
  }

  void _startPreviewDrag(Size size) {
    _previewDragTopLeft ??= _previewAnchorOffset(size, _previewCorner);
    _previewDragMoved = false;
  }

  void _updatePreviewDrag(Size size, DragUpdateDetails details) {
    final base =
        _previewDragTopLeft ?? _previewAnchorOffset(size, _previewCorner);
    if (details.delta.distanceSquared > 1) {
      _previewDragMoved = true;
    }
    setState(() {
      _previewDragTopLeft = _clampPreviewOffset(size, base + details.delta);
    });
  }

  void _endPreviewDrag(Size size) {
    final dragTopLeft = _previewDragTopLeft;
    if (dragTopLeft == null) return;
    if (!_previewDragMoved) {
      _previewDragTopLeft = null;
      _toggleVideoSwap();
      return;
    }

    final targetCenter =
        dragTopLeft + const Offset(_previewWidth / 2, _previewHeight / 2);
    _CallPreviewCorner? snappedCorner;
    var snappedDistance = double.infinity;

    for (final corner in _CallPreviewCorner.values) {
      final cornerCenter =
          _previewAnchorOffset(size, corner) +
          const Offset(_previewWidth / 2, _previewHeight / 2);
      final distance = (cornerCenter - targetCenter).distance;
      if (distance < snappedDistance) {
        snappedDistance = distance;
        snappedCorner = corner;
      }
    }

    setState(() {
      if (snappedCorner != null && snappedDistance <= _previewSnapThreshold) {
        _previewCorner = snappedCorner;
      }
      _previewDragTopLeft = null;
      _previewDragMoved = false;
    });
  }

  void _cancelPreviewDrag() {
    if (_previewDragTopLeft == null) return;
    setState(() {
      _previewDragTopLeft = null;
      _previewDragMoved = false;
    });
  }

  Widget _buildCallControlButton({
    required VoidCallback? onPressed,
    required Widget child,
    Color backgroundColor = Colors.white12,
    double size = 64,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: onPressed == null
            ? backgroundColor.withValues(alpha: 0.45)
            : backgroundColor,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: IconTheme(
              data: const IconThemeData(size: 28, color: Colors.white),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryCallPlaceholder() {
    final adapter = _callSession.adapter;
    return Container(
      color: const Color(0xFF101314),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProfileAvatar(
              label: _callSession.call.peer.displayName,
              avatarUrl: _callSession.call.peer.avatarUrl,
              authToken: _callSession.session.token,
              radius: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _callSession.call.peer.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              adapter.connecting
                  ? 'Bağlanıyor...'
                  : (adapter.connected
                        ? _callSession.formatDuration()
                        : (adapter.error ?? 'Arama hazırlanıyor')),
              style: const TextStyle(color: Color(0xFFB7BCB9), fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCallScreen(LiveKitCallAdapter adapter) {
    final requestPending = _callSession.outgoingVideoUpgradeRequestId != null;
    final cameraEnabled =
        _callSession.canRequestVideoUpgrade && !requestPending;
    final statusText = adapter.connecting
        ? 'Bağlanıyor...'
        : (adapter.connected ? _callSession.formatDuration() : 'Aranıyor...');

    return Scaffold(
      backgroundColor: const Color(0xFF101314),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(
                _callSession.call.peer.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB7BCB9), fontSize: 16),
              ),
              Expanded(
                child: Center(
                  child: _ProfileAvatar(
                    label: _callSession.call.peer.displayName,
                    avatarUrl: _callSession.call.peer.avatarUrl,
                    authToken: _callSession.session.token,
                    radius: 66,
                  ),
                ),
              ),
              _AudioCallControlDock(
                children: [
                  _AudioCallControlButton(
                    onTap: cameraEnabled ? _requestVideoUpgrade : null,
                    icon: requestPending
                        ? null
                        : const Icon(Icons.videocam_outlined),
                    child: requestPending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                  _AudioCallControlButton(
                    onTap: adapter.connecting
                        ? null
                        : () => adapter.toggleSpeaker(),
                    icon: Icon(
                      adapter.speakerEnabled
                          ? Icons.volume_up_rounded
                          : Icons.hearing_rounded,
                    ),
                    active: adapter.speakerEnabled,
                  ),
                  _AudioCallControlButton(
                    onTap: adapter.connecting
                        ? null
                        : () => adapter.toggleMicrophone(),
                    icon: Icon(
                      adapter.microphoneEnabled
                          ? Icons.mic_none_rounded
                          : Icons.mic_off_rounded,
                    ),
                    active: !adapter.microphoneEnabled,
                  ),
                  _AudioCallControlButton(
                    onTap: _ending ? null : _endCall,
                    icon: const Icon(Icons.call_end_rounded),
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoWaitingScreen(
    LiveKitCallAdapter adapter, {
    required lk.VideoTrack? localVideo,
  }) {
    return Scaffold(
      backgroundColor: const Color(0xFF101314),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewport = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        _callSession.call.peer.displayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        adapter.connecting
                            ? 'Bağlanıyor...'
                            : _callSession.formatDuration(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB7BCB9),
                          fontSize: 16,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _ProfileAvatar(
                            label: _callSession.call.peer.displayName,
                            avatarUrl: _callSession.call.peer.avatarUrl,
                            authToken: _callSession.session.token,
                            radius: 66,
                          ),
                        ),
                      ),
                      _AudioCallControlDock(
                        children: [
                          _AudioCallControlButton(
                            onTap: adapter.connecting
                                ? null
                                : () => adapter.toggleCamera(),
                            icon: Icon(
                              adapter.cameraEnabled
                                  ? Icons.videocam
                                  : Icons.videocam_off,
                            ),
                            active: adapter.cameraEnabled,
                          ),
                          _AudioCallControlButton(
                            onTap: adapter.connecting
                                ? null
                                : () => adapter.toggleSpeaker(),
                            icon: Icon(
                              adapter.speakerEnabled
                                  ? Icons.volume_up_rounded
                                  : Icons.hearing_rounded,
                            ),
                            active: adapter.speakerEnabled,
                          ),
                          _AudioCallControlButton(
                            onTap: adapter.connecting
                                ? null
                                : () => adapter.toggleMicrophone(),
                            icon: Icon(
                              adapter.microphoneEnabled
                                  ? Icons.mic_none_rounded
                                  : Icons.mic_off_rounded,
                            ),
                            active: !adapter.microphoneEnabled,
                          ),
                          _AudioCallControlButton(
                            onTap: _ending ? null : _endCall,
                            icon: const Icon(Icons.call_end_rounded),
                            destructive: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildFloatingVideoPreview(
                  viewport: viewport,
                  adapter: adapter,
                  localVideo: localVideo,
                  remoteVideo: null,
                  showLocalVideoPrimary: false,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoPreviewCard({required Widget child, Widget? overlay}) {
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          ...?overlay == null ? null : <Widget>[overlay],
        ],
      ),
    );
  }

  Widget _buildSelfPreviewPlaceholder() {
    return Container(
      color: const Color(0xFF1A1F20),
      child: Center(
        child: _ProfileAvatar(
          label: _callSession.session.displayName,
          avatarUrl: resolveTurnaSessionAvatarUrl(_callSession.session),
          authToken: _callSession.session.token,
          radius: 22,
        ),
      ),
    );
  }

  Widget _buildFloatingVideoPreview({
    required Size viewport,
    required LiveKitCallAdapter adapter,
    required lk.VideoTrack? localVideo,
    required lk.VideoTrack? remoteVideo,
    required bool showLocalVideoPrimary,
  }) {
    final previewOffset =
        _previewDragTopLeft ?? _previewAnchorOffset(viewport, _previewCorner);

    final localPreview = adapter.cameraEnabled && localVideo != null
        ? IgnorePointer(
            child: lk.VideoTrackRenderer(
              localVideo,
              key: ValueKey(
                'preview-local-${_callSession.call.id}-${adapter.cameraPosition.name}',
              ),
              fit: lk.VideoViewFit.cover,
              mirrorMode: adapter.cameraPosition == lk.CameraPosition.front
                  ? lk.VideoViewMirrorMode.mirror
                  : lk.VideoViewMirrorMode.off,
            ),
          )
        : _buildSelfPreviewPlaceholder();

    Widget previewChild;
    if (showLocalVideoPrimary && remoteVideo != null) {
      previewChild = IgnorePointer(
        child: lk.VideoTrackRenderer(
          remoteVideo,
          key: ValueKey('preview-remote-${_callSession.call.id}'),
          fit: lk.VideoViewFit.cover,
        ),
      );
    } else {
      previewChild = localPreview;
    }

    return Positioned(
      left: previewOffset.dx,
      top: previewOffset.dy,
      width: _previewWidth,
      height: _previewHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _startPreviewDrag(viewport),
        onPanUpdate: (details) => _updatePreviewDrag(viewport, details),
        onPanEnd: (_) => _endPreviewDrag(viewport),
        onPanCancel: _cancelPreviewDrag,
        child: _buildVideoPreviewCard(
          child: previewChild,
          overlay: adapter.cameraEnabled
              ? Positioned(
                  right: 8,
                  bottom: 8,
                  child: _buildCallControlButton(
                    size: 36,
                    backgroundColor: Colors.black54,
                    onPressed: adapter.connecting
                        ? null
                        : () => adapter.flipCamera(),
                    child: const Icon(
                      Icons.cameraswitch_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adapter = _callSession.adapter;
    final remoteVideo = adapter.primaryRemoteVideoTrack;
    final localVideo = adapter.localVideoTrack;
    final isVideo = _callSession.call.type == TurnaCallType.video;
    if (!isVideo) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _leaveCallView();
          }
        },
        child: _buildAudioCallScreen(adapter),
      );
    }
    if (remoteVideo == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _minimizeCall();
          }
        },
        child: _buildVideoWaitingScreen(adapter, localVideo: localVideo),
      );
    }

    final canSwapVideoViews =
        isVideo && localVideo != null && adapter.cameraEnabled;
    final showLocalVideoPrimary = canSwapVideoViews && _showLocalVideoPrimary;
    final localPreviewMirrorMode =
        adapter.cameraPosition == lk.CameraPosition.front
        ? lk.VideoViewMirrorMode.mirror
        : lk.VideoViewMirrorMode.off;

    Widget primaryContent;
    if (isVideo && showLocalVideoPrimary) {
      primaryContent = lk.VideoTrackRenderer(
        localVideo,
        key: ValueKey(
          'primary-local-${_callSession.call.id}-${adapter.cameraPosition.name}',
        ),
        fit: lk.VideoViewFit.cover,
        mirrorMode: localPreviewMirrorMode,
      );
    } else if (isVideo) {
      primaryContent = lk.VideoTrackRenderer(
        remoteVideo,
        key: ValueKey('primary-remote-${_callSession.call.id}'),
        fit: lk.VideoViewFit.cover,
      );
    } else {
      primaryContent = _buildPrimaryCallPlaceholder();
    }

    return PopScope(
      canPop: !isVideo,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isVideo) {
          _minimizeCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF101314),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: isVideo ? _minimizeCall : _leaveCallView,
          ),
          title: Text(_callSession.call.peer.displayName),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Stack(
                children: [
                  Positioned.fill(child: primaryContent),
                  if (isVideo)
                    _buildFloatingVideoPreview(
                      viewport: viewport,
                      adapter: adapter,
                      localVideo: localVideo,
                      remoteVideo: remoteVideo,
                      showLocalVideoPrimary: showLocalVideoPrimary,
                    ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (isVideo) ...[
                          _buildCallControlButton(
                            onPressed: adapter.connecting
                                ? null
                                : () => adapter.toggleCamera(),
                            child: Icon(
                              adapter.cameraEnabled
                                  ? Icons.videocam
                                  : Icons.videocam_off,
                              color: Colors.white,
                            ),
                          ),
                        ],
                        _buildCallControlButton(
                          onPressed: adapter.connecting
                              ? null
                              : () => adapter.toggleSpeaker(),
                          child: Icon(
                            adapter.speakerEnabled
                                ? Icons.volume_up
                                : Icons.hearing,
                            color: Colors.white,
                          ),
                        ),
                        _buildCallControlButton(
                          onPressed: adapter.connecting
                              ? null
                              : () => adapter.toggleMicrophone(),
                          child: Icon(
                            adapter.microphoneEnabled
                                ? Icons.mic
                                : Icons.mic_off,
                            color: Colors.white,
                          ),
                        ),
                        _buildCallControlButton(
                          backgroundColor: Colors.red.shade400,
                          onPressed: _ending ? null : _endCall,
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
