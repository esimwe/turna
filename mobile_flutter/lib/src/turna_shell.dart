part of '../main.dart';

enum TurnaShellMode { turna, community }

final LocalAuthentication _turnaChatLocalAuth = LocalAuthentication();
const String _kTurnaAppLockEnabledPrefKey = 'turna_app_lock_enabled';
final ValueNotifier<bool> kTurnaAppLockEnabledNotifier = ValueNotifier<bool>(
  false,
);

Future<bool> loadTurnaAppLockEnabledPreference() async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(_kTurnaAppLockEnabledPrefKey) ?? false;
  if (kTurnaAppLockEnabledNotifier.value != enabled) {
    kTurnaAppLockEnabledNotifier.value = enabled;
  }
  return enabled;
}

Future<void> setTurnaAppLockEnabledPreference(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kTurnaAppLockEnabledPrefKey, enabled);
  if (kTurnaAppLockEnabledNotifier.value != enabled) {
    kTurnaAppLockEnabledNotifier.value = enabled;
  }
}

String _turnaDeviceUnlockMethodLabel() {
  if (Platform.isIOS) {
    return 'Face ID veya cihaz şifresi';
  }
  if (Platform.isAndroid) {
    return 'parmak izi veya ekran kilidi';
  }
  return 'cihaz doğrulaması';
}

Future<bool> _authenticateTurnaDeviceAccess(
  BuildContext context, {
  required String localizedReason,
  required String unsupportedMessage,
}) async {
  try {
    final supported = await _turnaChatLocalAuth.isDeviceSupported();
    if (!supported) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(unsupportedMessage)));
      }
      return false;
    }

    return await _turnaChatLocalAuth.authenticate(
      localizedReason: localizedReason,
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
        sensitiveTransaction: true,
      ),
    );
  } on PlatformException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message?.trim().isNotEmpty == true
                ? error.message!.trim()
                : 'Cihaz doğrulaması başarısız oldu.',
          ),
        ),
      );
    }
    return false;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cihaz doğrulaması şu anda yapılamıyor.')),
      );
    }
    return false;
  }
}

List<ChatPreview> _prioritizeFavoritedChats(Iterable<ChatPreview> chats) {
  final favorited = <ChatPreview>[];
  final regular = <ChatPreview>[];
  for (final chat in chats) {
    if (chat.isFavorited) {
      favorited.add(chat);
    } else {
      regular.add(chat);
    }
  }
  return [...favorited, ...regular];
}

Future<bool> _authenticateLockedChatAccess(
  BuildContext context, {
  required String chatName,
  required String actionLabel,
}) async {
  return _authenticateTurnaDeviceAccess(
    context,
    localizedReason:
        '"$chatName" sohbetini $actionLabel cihaz doğrulaması gerekiyor.',
    unsupportedMessage: 'Bu cihazda sohbet kilidi desteklenmiyor.',
  );
}

class TurnaShellHost extends StatefulWidget {
  const TurnaShellHost({
    super.key,
    required this.session,
    required this.onSessionUpdated,
    required this.onLogout,
  });

  final AuthSession session;
  final void Function(AuthSession session) onSessionUpdated;
  final VoidCallback onLogout;

  @override
  State<TurnaShellHost> createState() => _TurnaShellHostState();
}

class _TurnaShellHostState extends State<TurnaShellHost>
    with WidgetsBindingObserver {
  static const Duration _communityReturnLock = Duration(milliseconds: 420);

  final GlobalKey<_MainTabsState> _mainTabsKey = GlobalKey<_MainTabsState>();
  TurnaShellMode _mode = TurnaShellMode.turna;
  DateTime? _communityTapLockedUntil;
  TurnaUserProfile? _communityAccessProfile;
  bool _communityAccessRefreshBusy = false;
  bool _appLockEnabled = false;
  bool _appLockReady = false;
  bool _appLockBusy = false;
  bool _appUnlocked = true;
  bool _needsAppRelock = false;
  bool _communityPreviewModalOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    kTurnaAppLockEnabledNotifier.addListener(_handleAppLockPreferenceChanged);
    _communityAccessProfile = TurnaProfileLocalCache.peekSelfProfile(
      widget.session,
    );
    unawaited(_loadAppLockPreference());
    unawaited(_loadCommunityAccessProfile());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    kTurnaAppLockEnabledNotifier.removeListener(
      _handleAppLockPreferenceChanged,
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TurnaShellHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.userId != widget.session.userId ||
        oldWidget.session.username != widget.session.username) {
      _communityAccessProfile = TurnaProfileLocalCache.peekSelfProfile(
        widget.session,
      );
      unawaited(_loadCommunityAccessProfile());
    }
  }

  Future<void> _loadAppLockPreference() async {
    final enabled = await loadTurnaAppLockEnabledPreference();
    if (!mounted) return;
    setState(() {
      _appLockEnabled = enabled;
      _appLockReady = true;
      _appUnlocked = !enabled;
      _needsAppRelock = enabled;
    });
    if (enabled) {
      unawaited(_promptAppUnlock());
    }
  }

  Future<void> _loadCommunityAccessProfile() async {
    final profile = await TurnaProfileLocalCache.loadSelfProfile(
      widget.session,
    );
    if (!mounted || profile == null) return;
    setState(() {
      _communityAccessProfile = profile;
    });
  }

  TurnaUserProfile? get _communityEntryProfile {
    return TurnaProfileLocalCache.peekSelfProfile(widget.session) ??
        _communityAccessProfile;
  }

  bool get _canEnterCommunity {
    return hasTurnaCommunityInternalAccess(profile: _communityEntryProfile);
  }

  Future<bool> _refreshCommunityAccessFromBackend() async {
    if (_communityAccessRefreshBusy) {
      return _canEnterCommunity;
    }
    _communityAccessRefreshBusy = true;
    try {
      final profile = await ProfileApi.fetchMe(widget.session);
      if (!mounted) {
        return hasTurnaCommunityInternalAccess(profile: profile);
      }
      setState(() {
        _communityAccessProfile = profile;
      });
      return hasTurnaCommunityInternalAccess(profile: profile);
    } on TurnaUnauthorizedException {
      if (mounted) {
        widget.onLogout();
      }
      return false;
    } catch (_) {
      return _canEnterCommunity;
    } finally {
      _communityAccessRefreshBusy = false;
    }
  }

  Future<void> _showCommunityPreviewModal() async {
    if (!mounted || _communityPreviewModalOpen) return;
    _communityPreviewModalOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: const Color(0xFFF6EBDD),
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBD9C2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🌿', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Community hazırlanıyor',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2A241C),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Community şu an düzenleme ve test aşamasında. Çok yakında kullanıma sunulacak.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xFF5F5446),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E261F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Tamam'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _communityPreviewModalOpen = false;
    if (!mounted) return;
    _mainTabsKey.currentState?.focusChatsTab();
    _openTurna();
  }

  void _handleAppLockPreferenceChanged() {
    final enabled = kTurnaAppLockEnabledNotifier.value;
    if (!mounted) return;
    setState(() {
      _appLockEnabled = enabled;
      _appLockReady = true;
      if (!enabled) {
        _appUnlocked = true;
        _appLockBusy = false;
        _needsAppRelock = false;
      } else {
        _appUnlocked = true;
        _needsAppRelock = false;
      }
    });
  }

  Future<void> _promptAppUnlock() async {
    if (!_appLockEnabled || _appLockBusy || _appUnlocked || !_appLockReady) {
      return;
    }
    setState(() => _appLockBusy = true);
    final authenticated = await _authenticateTurnaDeviceAccess(
      context,
      localizedReason:
          'Turna uygulamasını açmak için cihaz doğrulaması gerekiyor.',
      unsupportedMessage: 'Bu cihazda uygulama kilidi desteklenmiyor.',
    );
    if (!mounted) return;
    setState(() {
      _appLockBusy = false;
      if (authenticated) {
        _appUnlocked = true;
        _needsAppRelock = false;
      } else {
        _appUnlocked = false;
        _needsAppRelock = true;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_appLockEnabled || !_appLockReady) return;

    if (state == AppLifecycleState.resumed) {
      if (_needsAppRelock || !_appUnlocked) {
        unawaited(_promptAppUnlock());
      }
      return;
    }

    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        !_appLockBusy) {
      setState(() {
        _appUnlocked = false;
        _needsAppRelock = true;
      });
    }
  }

  Future<void> _openCommunity() async {
    final now = DateTime.now();
    final lockedUntil = _communityTapLockedUntil;
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      turnaLog('shell community blocked', {
        'mode': _mode.name,
        'lockedUntil': lockedUntil.toIso8601String(),
        'remainingMs': lockedUntil.difference(now).inMilliseconds,
      });
      return;
    }
    if (_mode == TurnaShellMode.community) {
      turnaLog('shell community ignored', {'reason': 'already_community'});
      return;
    }
    if (!_canEnterCommunity) {
      final refreshedAccess = await _refreshCommunityAccessFromBackend();
      if (!mounted) return;
      if (!refreshedAccess) {
        turnaLog('shell community blocked by preview gate', {
          'from': _mode.name,
          'communityRole': _communityEntryProfile?.communityRole,
        });
        setState(() => _mode = TurnaShellMode.community);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_showCommunityPreviewModal());
        });
        return;
      }
    }
    turnaLog('shell open community', {
      'from': _mode.name,
      'hasPreviewAccess': _canEnterCommunity,
      'communityRole': _communityEntryProfile?.communityRole,
    });
    setState(() => _mode = TurnaShellMode.community);
  }

  void _openTurna() {
    final lockedUntil = DateTime.now().add(_communityReturnLock);
    turnaLog('shell open turna', {
      'from': _mode.name,
      'lockMs': _communityReturnLock.inMilliseconds,
      'lockedUntil': lockedUntil.toIso8601String(),
    });
    if (_mode == TurnaShellMode.turna) {
      _communityTapLockedUntil = lockedUntil;
      return;
    }
    setState(() {
      _mode = TurnaShellMode.turna;
      _communityTapLockedUntil = lockedUntil;
    });
  }

  void _openTurnaProfile() {
    turnaLog('shell open turna profile', {'from': _mode.name});
    _openTurna();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainTabsKey.currentState?.openProfileEditorFromCommunity();
    });
  }

  void _handlePopAttempt() {
    if (_mode == TurnaShellMode.community) {
      turnaLog('shell pop returning to turna');
      _openTurna();
    }
  }

  @override
  Widget build(BuildContext context) {
    turnaLog('shell build', {'mode': _mode.name});
    return PopScope(
      canPop: _mode == TurnaShellMode.turna,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handlePopAttempt();
        }
      },
      child: Stack(
        children: [
          IndexedStack(
            index: _mode == TurnaShellMode.turna ? 0 : 1,
            children: [
              TickerMode(
                enabled: _mode == TurnaShellMode.turna,
                child: MainTabs(
                  key: _mainTabsKey,
                  session: widget.session,
                  onSessionUpdated: widget.onSessionUpdated,
                  onLogout: widget.onLogout,
                  onCommunitySelected: _openCommunity,
                ),
              ),
              TickerMode(
                enabled: _mode == TurnaShellMode.community,
                child: CommunityShellPreviewPage(
                  authToken: widget.session.token,
                  backendBaseUrl: kBackendBaseUrl,
                  currentUserId: widget.session.userId,
                  onTurnaTap: _openTurna,
                  onProfileTap: _openTurnaProfile,
                ),
              ),
            ],
          ),
          if (_appLockReady && _appLockEnabled && !_appUnlocked)
            Positioned.fill(
              child: _TurnaAppLockOverlay(
                busy: _appLockBusy,
                unlockMethodLabel: _turnaDeviceUnlockMethodLabel(),
                onUnlock: _promptAppUnlock,
              ),
            ),
        ],
      ),
    );
  }
}

class _TurnaAppLockOverlay extends StatelessWidget {
  const _TurnaAppLockOverlay({
    required this.busy,
    required this.unlockMethodLabel,
    required this.onUnlock,
  });

  final bool busy;
  final String unlockMethodLabel;
  final Future<void> Function() onUnlock;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TurnaColors.backgroundSoft,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [TurnaColors.shadowSoft],
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 34,
                    color: TurnaColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Uygulama kilitli',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: TurnaColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Turna\'yi acmak icin $unlockMethodLabel kullan.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: TurnaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : onUnlock,
                    style: FilledButton.styleFrom(
                      backgroundColor: TurnaColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Turna\'yi ac'),
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

class _MainTabsState extends State<MainTabs> with WidgetsBindingObserver {
  int _index = 3;
  int _totalUnreadChats = 0;
  late final PresenceSocketClient _presenceClient;
  final _inboxUpdateNotifier = ValueNotifier<int>(0);
  final _callCoordinator = TurnaCallCoordinator();
  final Set<int> _visitedTabs = <int>{3};
  final Object _pushChatOpenBinding = Object();
  final Object _shareTargetBinding = Object();
  String? _activeIncomingCallId;
  String? _lastPushOpenedChatId;
  bool _endingSession = false;
  bool _openingProfileFromCommunity = false;
  bool _openingPushChat = false;

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

  void focusChatsTab() {
    if (!mounted) return;
    if (_index == 3 && _visitedTabs.contains(3)) return;
    setState(() {
      _index = 3;
      _visitedTabs.add(3);
    });
  }

  ChatPreview? _findChatPreview(ChatInboxData? inbox, String chatId) {
    if (inbox == null) return null;
    for (final chat in inbox.chats) {
      if (chat.chatId == chatId) return chat;
    }
    return null;
  }

  ChatPreview _previewFromDetail(TurnaChatDetail detail) {
    final title = detail.title.trim();
    return ChatPreview(
      chatId: detail.chatId,
      chatType: detail.chatType,
      name: title.isEmpty ? 'Sohbet' : title,
      message: '',
      time: '',
      avatarUrl: detail.avatarUrl,
      memberPreviewNames: detail.memberPreviewNames,
      memberCount: detail.memberCount,
      myRole: detail.myRole,
      description: detail.description,
      isPublic: detail.isPublic,
    );
  }

  Future<ChatPreview?> _resolvePushChatPreview(String chatId) async {
    final userId = widget.session.userId;
    final cachedInbox =
        TurnaChatInboxLocalCache.peek(userId) ??
        await TurnaChatInboxLocalCache.load(userId);
    final cachedMatch = _findChatPreview(cachedInbox, chatId);
    if (cachedMatch != null) return cachedMatch;

    try {
      final freshInbox = await ChatApi.fetchChats(widget.session);
      final freshMatch = _findChatPreview(freshInbox, chatId);
      if (freshMatch != null) return freshMatch;
    } catch (error) {
      turnaLog('push chat inbox refresh skipped', {
        'chatId': chatId,
        'error': error.toString(),
      });
    }

    try {
      final detail = await ChatApi.fetchChatDetail(widget.session, chatId);
      return _previewFromDetail(detail);
    } catch (error) {
      turnaLog('push chat detail load failed', {
        'chatId': chatId,
        'error': error.toString(),
      });
      return null;
    }
  }

  Future<void> _handlePushChatOpen(String chatId) async {
    final normalizedChatId = chatId.trim();
    if (!mounted || normalizedChatId.isEmpty) return;
    if (_openingPushChat && _lastPushOpenedChatId == normalizedChatId) return;
    if (kTurnaActiveChatRegistry.isChatActive(normalizedChatId)) {
      focusChatsTab();
      _inboxUpdateNotifier.value++;
      return;
    }

    _openingPushChat = true;
    _lastPushOpenedChatId = normalizedChatId;
    try {
      focusChatsTab();
      _inboxUpdateNotifier.value++;
      final chat = await _resolvePushChatPreview(normalizedChatId);
      if (!mounted || chat == null) return;
      if (kTurnaActiveChatRegistry.isChatActive(chat.chatId)) return;
      final navigator = kTurnaNavigatorKey.currentState;
      if (navigator == null) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      await navigator.push(
        buildChatRoomRoute(
          chat: chat,
          session: widget.session,
          callCoordinator: _callCoordinator,
          onSessionExpired: _handleSessionExpired,
        ),
      );
    } finally {
      _openingPushChat = false;
    }
  }

  ChatAttachmentKind _attachmentKindForSharedItem(
    TurnaIncomingSharedItem item,
  ) {
    final mimeType = item.mimeType.toLowerCase();
    if (mimeType.startsWith('image/')) {
      return ChatAttachmentKind.image;
    }
    if (mimeType.startsWith('video/')) {
      return ChatAttachmentKind.video;
    }
    final guessed =
        guessContentTypeForFileName(item.fileName)?.toLowerCase() ?? '';
    if (guessed.startsWith('image/')) {
      return ChatAttachmentKind.image;
    }
    if (guessed.startsWith('video/')) {
      return ChatAttachmentKind.video;
    }
    return ChatAttachmentKind.file;
  }

  Future<OutgoingAttachmentDraft> _uploadIncomingSharedItem(
    ChatPreview targetChat,
    TurnaIncomingSharedItem item,
  ) async {
    final file = File(item.filePath);
    if (!await file.exists()) {
      throw TurnaApiException('Paylasilan dosya bulunamadi.');
    }

    final fileName = item.fileName.trim().isNotEmpty
        ? item.fileName.trim()
        : file.uri.pathSegments.last;
    final contentType = item.mimeType.trim().isNotEmpty
        ? item.mimeType.trim()
        : (guessContentTypeForFileName(fileName) ?? 'application/octet-stream');
    final kind = _attachmentKindForSharedItem(item);
    final sizeBytes = item.sizeBytes > 0 ? item.sizeBytes : await file.length();

    if (kind != ChatAttachmentKind.file) {
      final prepared = await prepareTurnaInlineMediaAttachment(
        MediaComposerSeed(
          kind: kind,
          file: XFile(file.path, name: fileName, mimeType: contentType),
          fileName: fileName,
          contentType: contentType,
          sizeBytes: sizeBytes,
        ),
      );
      final upload = await ChatApi.createAttachmentUpload(
        widget.session,
        chatId: targetChat.chatId,
        kind: prepared.kind,
        contentType: prepared.contentType,
        fileName: prepared.fileName,
      );
      await _uploadPreparedIncomingSharedAttachment(upload, prepared);
      turnaLog('share target media uploaded', {
        'chatId': targetChat.chatId,
        'kind': prepared.kind.name,
        'transferMode': MediaComposerQuality.standard.transferMode.name,
      });
      return OutgoingAttachmentDraft(
        objectKey: upload.objectKey,
        kind: prepared.kind,
        transferMode: MediaComposerQuality.standard.transferMode,
        fileName: prepared.fileName,
        contentType: prepared.contentType,
        sizeBytes: prepared.sizeBytes,
        width: prepared.width,
        height: prepared.height,
        durationSeconds: prepared.durationSeconds,
      );
    }

    final upload = await ChatApi.createAttachmentUpload(
      widget.session,
      chatId: targetChat.chatId,
      kind: kind,
      contentType: contentType,
      fileName: fileName,
    );

    final request = http.StreamedRequest('PUT', Uri.parse(upload.uploadUrl));
    request.headers.addAll(upload.headers);
    request.contentLength = sizeBytes;
    final responseFuture = request.send();
    await file.openRead().pipe(request.sink);
    final uploadRes = await responseFuture;
    if (uploadRes.statusCode >= 400) {
      throw TurnaApiException('Paylasilan dosya yuklenemedi.');
    }

    return OutgoingAttachmentDraft(
      objectKey: upload.objectKey,
      kind: kind,
      transferMode: ChatAttachmentTransferMode.document,
      fileName: fileName,
      contentType: contentType,
      sizeBytes: sizeBytes,
    );
  }

  Future<void> _uploadPreparedIncomingSharedAttachment(
    ChatAttachmentUploadTicket upload,
    _PreparedComposerAttachment prepared,
  ) async {
    if (prepared.filePath != null && prepared.filePath!.trim().isNotEmpty) {
      final file = File(prepared.filePath!);
      if (!await file.exists()) {
        throw TurnaApiException('Hazirlanan dosya bulunamadi.');
      }
      final request = http.StreamedRequest('PUT', Uri.parse(upload.uploadUrl));
      request.headers.addAll(upload.headers);
      request.contentLength = prepared.sizeBytes;
      final responseFuture = request.send();
      await file.openRead().pipe(request.sink);
      final uploadRes = await responseFuture;
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Paylasilan dosya yuklenemedi.');
      }
      return;
    }

    final bytes = prepared.bytes;
    if (bytes == null) {
      throw TurnaApiException('Hazirlanan dosya okunamadi.');
    }
    final uploadRes = await http.put(
      Uri.parse(upload.uploadUrl),
      headers: upload.headers,
      body: bytes,
    );
    if (uploadRes.statusCode >= 400) {
      throw TurnaApiException('Paylasilan dosya yuklenemedi.');
    }
  }

  TurnaStatusType? _statusTypeForSharedItem(TurnaIncomingSharedItem item) {
    final mimeType = item.mimeType.toLowerCase();
    if (mimeType.startsWith('image/')) {
      return TurnaStatusType.image;
    }
    if (mimeType.startsWith('video/')) {
      return TurnaStatusType.video;
    }
    final guessed =
        guessContentTypeForFileName(item.fileName)?.toLowerCase() ?? '';
    if (guessed.startsWith('image/')) {
      return TurnaStatusType.image;
    }
    if (guessed.startsWith('video/')) {
      return TurnaStatusType.video;
    }
    return null;
  }

  Future<void> _shareIncomingPayloadToChat(
    ChatPreview targetChat,
    TurnaIncomingSharePayload payload, {
    String? text,
  }) async {
    final drafts = <OutgoingAttachmentDraft>[];
    for (final item in payload.items) {
      drafts.add(await _uploadIncomingSharedItem(targetChat, item));
    }
    if (drafts.isEmpty) {
      throw TurnaApiException('Paylasilacak dosya bulunamadi.');
    }
    await ChatApi.sendMessage(
      widget.session,
      chatId: targetChat.chatId,
      text: text,
      attachments: drafts,
    );
  }

  Future<void> _shareIncomingPayloadToStatus(
    TurnaIncomingSharePayload payload,
  ) async {
    var sharedAny = false;
    for (final item in payload.items) {
      final type = _statusTypeForSharedItem(item);
      if (type == null) {
        continue;
      }
      final file = File(item.filePath);
      if (!await file.exists()) {
        continue;
      }
      final fileName = item.fileName.trim().isNotEmpty
          ? item.fileName.trim()
          : file.uri.pathSegments.last;
      final contentType = item.mimeType.trim().isNotEmpty
          ? item.mimeType.trim()
          : (guessContentTypeForFileName(fileName) ??
                (type == TurnaStatusType.video ? 'video/mp4' : 'image/jpeg'));
      final sizeBytes = item.sizeBytes > 0
          ? item.sizeBytes
          : await file.length();
      final upload = await TurnaStatusApi.createUpload(
        widget.session,
        type: type,
        contentType: contentType,
        fileName: fileName,
      );

      final request = http.StreamedRequest('PUT', Uri.parse(upload.uploadUrl));
      request.headers.addAll(upload.headers);
      request.contentLength = sizeBytes;
      final responseFuture = request.send();
      await file.openRead().pipe(request.sink);
      final uploadRes = await responseFuture;
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Durum dosyasi yuklenemedi.');
      }

      await TurnaStatusApi.createMediaStatus(
        widget.session,
        type: type,
        objectKey: upload.objectKey,
        contentType: contentType,
        fileName: fileName,
        sizeBytes: sizeBytes,
      );
      sharedAny = true;
    }

    if (!sharedAny) {
      throw TurnaApiException(
        'Bu paylasim durum olarak gonderilebilecek fotograf veya video icermiyor.',
      );
    }
  }

  Future<void> _handleIncomingSharePayload(
    TurnaIncomingSharePayload payload,
  ) async {
    if (!mounted || payload.isEmpty) return;
    turnaLog('share target handling started', {'items': payload.items.length});
    focusChatsTab();
    _inboxUpdateNotifier.value++;

    NavigatorState? navigator = kTurnaNavigatorKey.currentState;
    var attempts = 0;
    while (navigator == null && attempts < 10) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      navigator = kTurnaNavigatorKey.currentState;
      attempts++;
    }
    if (navigator == null) {
      turnaLog('share target navigator unavailable');
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    turnaLog('share target picker presenting');

    final selection = await navigator.push<TurnaShareTargetSelectionResult>(
      MaterialPageRoute(
        builder: (_) => ForwardMessagePickerPage(
          session: widget.session,
          currentChatId: '',
          title: 'Turna\'da paylas',
          sharePayload: payload,
          callCoordinator: _callCoordinator,
          onSessionExpired: _handleSessionExpired,
        ),
      ),
    );
    turnaLog('share target picker dismissed', {
      'hasSelection': selection != null,
      'hasTargets': selection?.hasTargets ?? false,
    });
    if (!mounted || selection == null || !selection.hasTargets) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Paylasim gonderiliyor...')),
    );

    try {
      if (selection.shareToStatus) {
        await _shareIncomingPayloadToStatus(payload);
      }
      for (final chat in selection.chats) {
        await _shareIncomingPayloadToChat(
          chat,
          payload,
          text: selection.caption,
        );
      }
      if (!mounted) return;
      final sentTargetCount =
          selection.chats.length + (selection.shareToStatus ? 1 : 0);
      final sentTargetLabel = sentTargetCount == 1
          ? (selection.shareToStatus && selection.chats.isEmpty
                ? 'Durumum'
                : selection.chats.first.name)
          : '$sentTargetCount hedefe';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$sentTargetLabel gonderildi.')));
      _inboxUpdateNotifier.value++;
      if (!selection.shareToStatus && selection.chats.length == 1) {
        await navigator.push(
          buildChatRoomRoute(
            chat: selection.chats.first,
            session: widget.session,
            callCoordinator: _callCoordinator,
            onSessionExpired: _handleSessionExpired,
          ),
        );
      }
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      _handleSessionExpired();
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
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
