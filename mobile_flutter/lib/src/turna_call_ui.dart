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

class GroupCallPage extends StatefulWidget {
  const GroupCallPage({
    super.key,
    required this.session,
    required this.chat,
    required this.chatClient,
    required this.connect,
    required this.myRole,
    required this.onSessionExpired,
    this.initialState,
  });

  final AuthSession session;
  final ChatPreview chat;
  final TurnaSocketClient chatClient;
  final TurnaCallConnectPayload connect;
  final String? myRole;
  final TurnaGroupCallState? initialState;
  final VoidCallback onSessionExpired;

  @override
  State<GroupCallPage> createState() => _GroupCallPageState();
}

class _GroupCallPageState extends State<GroupCallPage> {
  late final LiveKitCallAdapter _adapter = LiveKitCallAdapter(
    connectPayload: widget.connect,
    videoEnabled: widget.connect.type == TurnaCallType.video,
  );
  bool _leaving = false;
  bool _savingModeration = false;
  int _durationSeconds = 0;
  Timer? _durationTicker;
  bool _hasSyncedCallState = false;

  TurnaGroupCallState? get _groupCallState =>
      _hasSyncedCallState
      ? widget.chatClient.activeGroupCallState
      : (widget.chatClient.activeGroupCallState ?? widget.initialState);

  bool get _canModerateCall {
    final role = (widget.myRole ?? '').trim().toUpperCase();
    return role == 'OWNER' || role == 'ADMIN' || role == 'EDITOR';
  }

  bool get _canSpeak {
    final state = _groupCallState;
    if (state == null) return true;
    final role = (widget.myRole ?? '').trim().toUpperCase();
    switch (state.microphonePolicy.trim().toUpperCase()) {
      case 'LISTEN_ONLY':
        return false;
      case 'ADMINS_ONLY':
        return role == 'OWNER' || role == 'ADMIN' || role == 'EDITOR';
      default:
        return true;
    }
  }

  bool get _canEnableCamera {
    if (widget.connect.type != TurnaCallType.video) return false;
    final state = _groupCallState;
    if (state == null) return true;
    final role = (widget.myRole ?? '').trim().toUpperCase();
    switch (state.cameraPolicy.trim().toUpperCase()) {
      case 'DISABLED':
        return false;
      case 'ADMINS_ONLY':
        return role == 'OWNER' || role == 'ADMIN' || role == 'EDITOR';
      default:
        return true;
    }
  }

  @override
  void initState() {
    super.initState();
    _hasSyncedCallState = widget.chatClient.activeGroupCallState != null;
    _adapter.addListener(_handleAdapterChanged);
    widget.chatClient.addListener(_handleGroupCallStateChanged);
    unawaited(_adapter.connect());
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_adapter.connected || !mounted) return;
      setState(() => _durationSeconds++);
    });
  }

  @override
  void dispose() {
    _durationTicker?.cancel();
    widget.chatClient.removeListener(_handleGroupCallStateChanged);
    _adapter.removeListener(_handleAdapterChanged);
    _adapter.dispose();
    super.dispose();
  }

  void _handleAdapterChanged() {
    unawaited(_enforceModerationState());
    if (!mounted) return;
    setState(() {});
  }

  void _handleGroupCallStateChanged() {
    _hasSyncedCallState = true;
    if (widget.chatClient.activeGroupCallState == null && mounted && !_leaving) {
      Navigator.of(context).maybePop();
      return;
    }
    unawaited(_enforceModerationState());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _enforceModerationState() async {
    if (!_adapter.connected) return;
    if (!_canSpeak && _adapter.microphoneEnabled) {
      try {
        await _adapter.toggleMicrophone();
      } catch (_) {}
    }
    if (!_canEnableCamera && _adapter.cameraEnabled) {
      try {
        await _adapter.toggleCamera();
      } catch (_) {}
    }
  }

  Future<void> _leaveCall() async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _adapter.disconnect();
      await CallApi.leaveGroupCall(
        widget.session,
        chatId: widget.chat.chatId,
        roomName: widget.connect.roomName,
      );
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onSessionExpired();
      }
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatDuration() {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String? _restrictionText() {
    final state = _groupCallState;
    if (state == null) return null;
    final messages = <String>[];
    switch (state.microphonePolicy.trim().toUpperCase()) {
      case 'LISTEN_ONLY':
        messages.add('Bu çağrı dinleme modunda.');
        break;
      case 'ADMINS_ONLY':
        if (!_canSpeak) {
          messages.add('Bu çağrıda sadece yönetici rolü konuşabilir.');
        }
        break;
    }
    switch (state.cameraPolicy.trim().toUpperCase()) {
      case 'DISABLED':
        if (widget.connect.type == TurnaCallType.video) {
          messages.add('Kamera açma şu an kapalı.');
        }
        break;
      case 'ADMINS_ONLY':
        if (!_canEnableCamera && widget.connect.type == TurnaCallType.video) {
          messages.add('Kamera yalnızca yönetici rollerde açılabilir.');
        }
        break;
    }
    if (messages.isEmpty) return null;
    return messages.join(' ');
  }

  Future<void> _openModerationSheet() async {
    if (!_canModerateCall || _savingModeration) return;
    final state = _groupCallState;
    if (state == null) return;
    final next = await showModalBottomSheet<Map<String, String>>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        String microphonePolicy = state.microphonePolicy;
        String cameraPolicy = state.cameraPolicy;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Çağrı moderasyonu',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Mikrofon',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    RadioListTile<String>(
                      value: 'EVERYONE',
                      groupValue: microphonePolicy,
                      onChanged: (value) => setModalState(
                        () => microphonePolicy = value ?? 'EVERYONE',
                      ),
                      title: const Text('Herkes konuşabilir'),
                    ),
                    RadioListTile<String>(
                      value: 'ADMINS_ONLY',
                      groupValue: microphonePolicy,
                      onChanged: (value) => setModalState(
                        () => microphonePolicy = value ?? 'ADMINS_ONLY',
                      ),
                      title: const Text('Sadece yönetici rolleri konuşabilir'),
                    ),
                    RadioListTile<String>(
                      value: 'LISTEN_ONLY',
                      groupValue: microphonePolicy,
                      onChanged: (value) => setModalState(
                        () => microphonePolicy = value ?? 'LISTEN_ONLY',
                      ),
                      title: const Text('Dinleme modu'),
                    ),
                    if (widget.connect.type == TurnaCallType.video) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Kamera',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      RadioListTile<String>(
                        value: 'EVERYONE',
                        groupValue: cameraPolicy,
                        onChanged: (value) => setModalState(
                          () => cameraPolicy = value ?? 'EVERYONE',
                        ),
                        title: const Text('Herkes kamera açabilir'),
                      ),
                      RadioListTile<String>(
                        value: 'ADMINS_ONLY',
                        groupValue: cameraPolicy,
                        onChanged: (value) => setModalState(
                          () => cameraPolicy = value ?? 'ADMINS_ONLY',
                        ),
                        title: const Text(
                          'Sadece yönetici rolleri kamera açabilir',
                        ),
                      ),
                      RadioListTile<String>(
                        value: 'DISABLED',
                        groupValue: cameraPolicy,
                        onChanged: (value) => setModalState(
                          () => cameraPolicy = value ?? 'DISABLED',
                        ),
                        title: const Text('Kameraları kapat'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop({
                          'microphonePolicy': microphonePolicy,
                          'cameraPolicy': cameraPolicy,
                        }),
                        child: const Text('Uygula'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (next == null) return;

    setState(() => _savingModeration = true);
    try {
      final updated = await CallApi.updateGroupCallModeration(
        widget.session,
        chatId: widget.chat.chatId,
        microphonePolicy: next['microphonePolicy'],
        cameraPolicy: widget.connect.type == TurnaCallType.video
            ? next['cameraPolicy']
            : 'DISABLED',
      );
      widget.chatClient.setActiveGroupCallState(updated);
      await _enforceModerationState();
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onSessionExpired();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _savingModeration = false);
      }
    }
  }

  List<_GroupCallParticipantViewData> _participantViews() {
    final items = <_GroupCallParticipantViewData>[];
    final localParticipant = _adapter.localParticipant;
    if (localParticipant != null) {
      items.add(
        _GroupCallParticipantViewData(
          id: localParticipant.identity,
          displayName: localParticipant.name.trim().isNotEmpty
              ? localParticipant.name.trim()
              : widget.session.displayName,
          isLocal: true,
          isSpeaking: localParticipant.isSpeaking,
          audioLevel: localParticipant.audioLevel,
          videoTrack: _adapter.localVideoTrack,
        ),
      );
    }

    for (final participant in _adapter.remoteParticipants) {
      items.add(
        _GroupCallParticipantViewData(
          id: participant.identity,
          displayName: participant.name.trim().isNotEmpty
              ? participant.name.trim()
              : 'Katılımcı',
          isLocal: false,
          isSpeaking: participant.isSpeaking,
          audioLevel: participant.audioLevel,
          videoTrack: _adapter.videoTrackForParticipant(participant),
        ),
      );
    }

    items.sort((a, b) {
      if (a.isSpeaking != b.isSpeaking) return a.isSpeaking ? -1 : 1;
      final levelCompare = b.audioLevel.compareTo(a.audioLevel);
      if (levelCompare != 0) return levelCompare;
      if (a.videoTrack != null && b.videoTrack == null) return -1;
      if (a.videoTrack == null && b.videoTrack != null) return 1;
      if (a.isLocal != b.isLocal) return a.isLocal ? 1 : -1;
      return a.displayName.compareTo(b.displayName);
    });
    return items;
  }

  _GroupCallParticipantViewData? _spotlightParticipant(
    List<_GroupCallParticipantViewData> items,
  ) {
    if (items.isEmpty) return null;
    for (final item in items) {
      if (item.isSpeaking) return item;
    }
    for (final item in items) {
      if (item.videoTrack != null) return item;
    }
    return items.first;
  }

  Widget _buildParticipantTile(
    _GroupCallParticipantViewData item, {
    bool spotlight = false,
  }) {
    final hasVideo = item.videoTrack != null && widget.connect.type == TurnaCallType.video;
    final borderColor = item.isSpeaking
        ? TurnaColors.success
        : Colors.white.withValues(alpha: 0.08);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111416),
        borderRadius: BorderRadius.circular(spotlight ? 24 : 18),
        border: Border.all(color: borderColor, width: item.isSpeaking ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo)
            lk.VideoTrackRenderer(
              item.videoTrack!,
              fit: lk.VideoViewFit.cover,
              mirrorMode: item.isLocal
                  ? (_adapter.cameraPosition == lk.CameraPosition.front
                        ? lk.VideoViewMirrorMode.mirror
                        : lk.VideoViewMirrorMode.off)
                  : lk.VideoViewMirrorMode.off,
            )
          else
            Container(
              color: const Color(0xFF171C1E),
              child: Center(
                child: _ProfileAvatar(
                  label: item.displayName,
                  avatarUrl: item.isLocal
                      ? resolveTurnaSessionAvatarUrl(widget.session)
                      : null,
                  authToken: widget.session.token,
                  radius: spotlight ? 40 : 28,
                ),
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        if (item.isSpeaking)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.graphic_eq_rounded,
                              size: 16,
                              color: TurnaColors.success,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            item.isLocal ? '${item.displayName} (Sen)' : item.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildParticipantsLayout(List<_GroupCallParticipantViewData> items) {
    final spotlight = _spotlightParticipant(items);
    final others = spotlight == null
        ? items
        : items.where((item) => item.id != spotlight.id).toList();
    final useSpotlight = spotlight != null && items.length > 2;
    final columns = items.length > 8 ? 3 : 2;

    if (!useSpotlight) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: items.length <= 2 ? items.length : columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: widget.connect.type == TurnaCallType.video ? 0.78 : 1.05,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => _buildParticipantTile(items[index]),
      );
    }

    return Column(
      children: [
        if (spotlight != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              height: useSpotlight ? 240 : 180,
              child: _buildParticipantTile(
                spotlight,
                spotlight: true,
              ),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: widget.connect.type == TurnaCallType.video ? 0.78 : 1.05,
            ),
            itemCount: others.length,
            itemBuilder: (context, index) {
              return _buildParticipantTile(others[index]);
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final participants = _participantViews();
    final statusText = _adapter.connecting
        ? 'Bağlanıyor...'
        : (_adapter.connected
              ? '${participants.length} kişi · ${_formatDuration()}'
              : (_adapter.error ?? 'Çağrı hazırlanıyor'));

    return PopScope(
      canPop: !_leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_leaveCall());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1115),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D1115),
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.chat.name),
              Text(
                statusText,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFFB7BCB9),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            if (_canModerateCall)
              IconButton(
                tooltip: 'Çağrı moderasyonu',
                onPressed: _savingModeration ? null : _openModerationSheet,
                icon: _savingModeration
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.admin_panel_settings_outlined),
              ),
          ],
        ),
        body: Column(
          children: [
            if ((_adapter.mediaError ?? '').isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1E6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _adapter.mediaError!,
                  style: const TextStyle(color: Color(0xFF7A4B00)),
                ),
              ),
            if ((_restrictionText() ?? '').isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: TurnaColors.primary50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: TurnaColors.primary200),
                ),
                child: Text(
                  _restrictionText()!,
                  style: const TextStyle(color: TurnaColors.primary800),
                ),
              ),
            Expanded(
              child: participants.isEmpty
                  ? Center(
                      child: Text(
                        _adapter.connecting
                            ? 'Katılımcılar bağlanıyor...'
                            : 'Henüz kimse katılmadı.',
                        style: const TextStyle(color: Color(0xFFB7BCB9)),
                      ),
                    )
                  : _buildParticipantsLayout(participants),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: _AudioCallControlDock(
                children: [
                  if (widget.connect.type == TurnaCallType.video)
                    _AudioCallControlButton(
                      onTap: _adapter.connecting || !_canEnableCamera
                          ? null
                          : () => _adapter.toggleCamera(),
                      icon: Icon(
                        _adapter.cameraEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                      ),
                      active: _adapter.cameraEnabled,
                    ),
                  _AudioCallControlButton(
                    onTap: _adapter.connecting
                        ? null
                        : () => _adapter.toggleSpeaker(),
                    icon: Icon(
                      _adapter.speakerEnabled
                          ? Icons.volume_up_rounded
                          : Icons.hearing_rounded,
                    ),
                    active: _adapter.speakerEnabled,
                  ),
                  _AudioCallControlButton(
                    onTap: _adapter.connecting || !_canSpeak
                        ? null
                        : () => _adapter.toggleMicrophone(),
                    icon: Icon(
                      _adapter.microphoneEnabled
                          ? Icons.mic_none_rounded
                          : Icons.mic_off_rounded,
                    ),
                    active: !_adapter.microphoneEnabled,
                  ),
                  _AudioCallControlButton(
                    onTap: _leaving ? null : _leaveCall,
                    icon: const Icon(Icons.call_end_rounded),
                    destructive: true,
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

class _GroupCallParticipantViewData {
  const _GroupCallParticipantViewData({
    required this.id,
    required this.displayName,
    required this.isLocal,
    required this.isSpeaking,
    required this.audioLevel,
    required this.videoTrack,
  });

  final String id;
  final String displayName;
  final bool isLocal;
  final bool isSpeaking;
  final double audioLevel;
  final lk.VideoTrack? videoTrack;
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
