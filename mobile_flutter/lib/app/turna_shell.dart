part of 'turna_app.dart';

class MainTabs extends StatefulWidget {
  const MainTabs({
    super.key,
    required this.session,
    required this.onSessionUpdated,
    required this.onLogout,
    required this.onCommunitySelected,
  });

  final AuthSession session;
  final void Function(AuthSession session) onSessionUpdated;
  final VoidCallback onLogout;
  final VoidCallback onCommunitySelected;

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs>
    with WidgetsBindingObserver, _TurnaMainTabsRuntime {
  int _index = 3;
  int _totalUnreadChats = 0;
  late final PresenceSocketClient _presenceClient;
  @override
  final _inboxUpdateNotifier = ValueNotifier<int>(0);
  @override
  final _callCoordinator = TurnaCallCoordinator();
  final Set<int> _visitedTabs = <int>{3};
  final Object _pushChatOpenBinding = Object();
  final Object _shareTargetBinding = Object();
  String? _activeIncomingCallId;
  @override
  String? _lastPushOpenedChatId;
  bool _endingSession = false;
  bool _openingProfileFromCommunity = false;
  @override
  bool _openingPushChat = false;

  @override
  void _handleSessionExpired() {
    if (_endingSession) return;
    _endingSession = true;
    widget.onLogout();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    kTurnaPushChatOpenCoordinator.bind(
      _pushChatOpenBinding,
      _handlePushChatOpen,
    );
    kTurnaShareTargetCoordinator.bind(
      _shareTargetBinding,
      _handleIncomingSharePayload,
    );
    TurnaPushManager.syncSession(widget.session);
    TurnaNativeCallManager.bindSession(
      session: widget.session,
      coordinator: _callCoordinator,
      onSessionExpired: _handleSessionExpired,
    );
    TurnaAnalytics.logEvent('app_session_started', {
      'user_id': widget.session.userId,
    });
    _presenceClient = PresenceSocketClient(
      token: widget.session.token,
      onSessionExpired: _handleSessionExpired,
      onInboxUpdate: () {
        _inboxUpdateNotifier.value++;
      },
      onIncomingCall: _callCoordinator.handleIncoming,
      onCallAccepted: _callCoordinator.handleAccepted,
      onCallDeclined: _callCoordinator.handleDeclined,
      onCallMissed: _callCoordinator.handleMissed,
      onCallEnded: _callCoordinator.handleEnded,
      onCallVideoUpgradeRequested: _callCoordinator.handleVideoUpgradeRequested,
      onCallVideoUpgradeAccepted: _callCoordinator.handleVideoUpgradeAccepted,
      onCallVideoUpgradeDeclined: _callCoordinator.handleVideoUpgradeDeclined,
    )..connect();
    _callCoordinator.addListener(_handleCallCoordinator);
  }

  @override
  void didUpdateWidget(covariant MainTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.session.userId != widget.session.userId) {
      _endingSession = false;
      TurnaPushManager.syncSession(widget.session);
      TurnaNativeCallManager.bindSession(
        session: widget.session,
        coordinator: _callCoordinator,
        onSessionExpired: _handleSessionExpired,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    kTurnaPushChatOpenCoordinator.unbind(_pushChatOpenBinding);
    kTurnaShareTargetCoordinator.unbind(_shareTargetBinding);
    _callCoordinator.removeListener(_handleCallCoordinator);
    _presenceClient.dispose();
    TurnaNativeCallManager.unbindSession(widget.session.userId);
    _callCoordinator.dispose();
    _inboxUpdateNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _presenceClient.refreshConnection();
      TurnaNativeCallManager.handleAppResumed();
      _inboxUpdateNotifier.value++;
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _presenceClient.disconnectForBackground();
    }
  }

  void _handleCallCoordinator() {
    final incoming = _callCoordinator.takeIncomingCall();
    if (incoming == null) return;
    if (_activeIncomingCallId == incoming.call.id) return;

    _activeIncomingCallId = incoming.call.id;
    final returnChat = buildDirectChatPreviewForCall(
      widget.session,
      incoming.call,
    );
    final shouldOpenChatOnExit = !kTurnaActiveChatRegistry.isChatActive(
      returnChat.chatId,
    );
    Future<void>(() async {
      if (await shouldTurnaSilenceIncomingCaller(
        activeUserId: widget.session.userId,
        callerUserId: incoming.call.callerId,
      )) {
        turnaLog('incoming call silenced', {
          'callId': incoming.call.id,
          'callerId': incoming.call.callerId,
        });
        if (mounted) {
          _activeIncomingCallId = null;
        }
        return;
      }
      final navigator = kTurnaNavigatorKey.currentState;
      if (!mounted || navigator == null) return;
      try {
        await navigator.push(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'incoming-call'),
            builder: (_) => IncomingCallPage(
              session: widget.session,
              coordinator: _callCoordinator,
              incoming: incoming,
              onSessionExpired: _handleSessionExpired,
              returnChatOnExit: shouldOpenChatOnExit ? returnChat : null,
            ),
          ),
        );
      } finally {
        if (mounted) {
          _activeIncomingCallId = null;
        }
      }
    });
  }

  Widget _buildTabPage(int index) {
    return switch (index) {
      0 => StatusesPage(
        session: widget.session,
        onSessionExpired: _handleSessionExpired,
      ),
      1 => CallsPage(
        session: widget.session,
        callCoordinator: _callCoordinator,
        onSessionExpired: _handleSessionExpired,
      ),
      2 => const SizedBox.shrink(),
      3 => ChatsPage(
        session: widget.session,
        inboxUpdateNotifier: _inboxUpdateNotifier,
        callCoordinator: _callCoordinator,
        onSessionExpired: _handleSessionExpired,
        onUnreadChanged: (count) {
          if (_totalUnreadChats == count || !mounted) return;
          setState(() => _totalUnreadChats = count);
          unawaited(TurnaAppBadge.setCount(count));
        },
      ),
      _ => SettingsPage(
        session: widget.session,
        onSessionUpdated: widget.onSessionUpdated,
        onLogout: _handleSessionExpired,
      ),
    };
  }

  void _selectTab(int index) {
    if (index == 2) {
      turnaLog('main tabs community tapped', {
        'currentIndex': _index,
        'visitedTabs': _visitedTabs.length,
      });
      widget.onCommunitySelected();
      return;
    }
    if (_index == index && _visitedTabs.contains(index)) return;
    setState(() {
      _index = index;
      _visitedTabs.add(index);
    });
  }

  Future<void> openProfileEditorFromCommunity() async {
    if (!mounted || _openingProfileFromCommunity) return;
    turnaLog('main tabs open profile from community', {'currentIndex': _index});
    if (_index != 4 || !_visitedTabs.contains(4)) {
      setState(() {
        _index = 4;
        _visitedTabs.add(4);
      });
    }
    _openingProfileFromCommunity = true;
    try {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfilePage(
            session: widget.session,
            onProfileUpdated: widget.onSessionUpdated,
            onSessionExpired: _handleSessionExpired,
          ),
        ),
      );
    } finally {
      _openingProfileFromCommunity = false;
    }
  }

  @override
  void focusChatsTab() {
    if (!mounted) return;
    if (_index == 3 && _visitedTabs.contains(3)) return;
    setState(() {
      _index = 3;
      _visitedTabs.add(3);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(
          5,
          (index) => _visitedTabs.contains(index)
              ? _buildTabPage(index)
              : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: _TurnaBottomBar(
        selectedIndex: _index,
        unreadChats: _totalUnreadChats,
        session: widget.session,
        onSelect: _selectTab,
      ),
    );
  }
}
