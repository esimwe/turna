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
  String? _activeIncomingCallId;
  bool _endingSession = false;
  bool _openingProfileFromCommunity = false;

  void _handleSessionExpired() {
    if (_endingSession) return;
    _endingSession = true;
    widget.onLogout();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
