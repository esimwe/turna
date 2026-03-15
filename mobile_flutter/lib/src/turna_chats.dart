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

class ChatsPage extends StatefulWidget {
  const ChatsPage({
    super.key,
    required this.session,
    required this.onSessionExpired,
    required this.callCoordinator,
    this.inboxUpdateNotifier,
    this.onUnreadChanged,
  });

  final AuthSession session;
  final VoidCallback onSessionExpired;
  final TurnaCallCoordinator callCoordinator;
  final ValueNotifier<int>? inboxUpdateNotifier;
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

enum _ChatsMenuAction { select, markAllRead }

class _ChatsPageState extends State<ChatsPage> {
  static const String _allChatsFilterId = '__all__';

  int _refreshTick = 0;
  bool _selectionMode = false;
  bool _bulkActionBusy = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedChatIds = <String>{};
  late Future<ChatInboxData> _inboxFuture;
  ChatInboxData? _cachedInbox;
  String _selectedFilterId = _allChatsFilterId;

  @override
  void initState() {
    super.initState();
    _cachedInbox = TurnaChatInboxLocalCache.peek(widget.session.userId);
    _inboxFuture = _fetchInbox();
    unawaited(_loadCachedInbox());
    widget.inboxUpdateNotifier?.addListener(_onInboxUpdate);
    _searchController.addListener(_onSearchChanged);
    TurnaContactsDirectory.revision.addListener(_onContactsChanged);
    unawaited(TurnaContactsDirectory.ensureLoaded());
  }

  @override
  void didUpdateWidget(covariant ChatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.session.userId != widget.session.userId) {
      _refreshTick = 0;
      _cachedInbox = null;
      _inboxFuture = _fetchInbox();
    }
  }

  Future<ChatInboxData> _fetchInbox() {
    return ChatApi.fetchChats(widget.session, refreshTick: _refreshTick);
  }

  Future<void> _loadCachedInbox() async {
    final cached = await TurnaChatInboxLocalCache.load(widget.session.userId);
    if (!mounted || cached == null) return;
    setState(() {
      _cachedInbox = cached;
    });
  }

  void _scheduleInboxReload() {
    _refreshTick++;
    _inboxFuture = _fetchInbox();
  }

  Future<void> _reloadInbox() async {
    if (!mounted) return;
    setState(_scheduleInboxReload);
    try {
      await _inboxFuture;
    } catch (_) {}
  }

  void _onInboxUpdate() {
    if (!mounted) return;
    setState(_scheduleInboxReload);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onContactsChanged() {
    if (!mounted) return;
    setState(_scheduleInboxReload);
  }

  @override
  void dispose() {
    widget.inboxUpdateNotifier?.removeListener(_onInboxUpdate);
    _searchController.removeListener(_onSearchChanged);
    TurnaContactsDirectory.revision.removeListener(_onContactsChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openNewChatPage() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewChatPage(
          session: widget.session,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (created == true && mounted) {
      setState(_scheduleInboxReload);
    }
  }

  Future<void> _openArchivedChatsPage() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ArchivedChatsPage(
          session: widget.session,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted) return;
    setState(_scheduleInboxReload);
  }

  void _enterSelectionMode([String? initialChatId]) {
    setState(() {
      _selectionMode = true;
      _selectedChatIds
        ..clear()
        ..addAll(initialChatId == null ? const <String>[] : [initialChatId]);
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode && _selectedChatIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedChatIds.clear();
    });
  }

  void _toggleChatSelection(String chatId) {
    setState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  void _selectFilter(String filterId) {
    if (_selectedFilterId == filterId) return;
    setState(() => _selectedFilterId = filterId);
  }

  void _handleActionError(Object error) {
    if (error is TurnaUnauthorizedException) {
      widget.onSessionExpired();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _handleChatsMenuAction(_ChatsMenuAction action) async {
    switch (action) {
      case _ChatsMenuAction.select:
        _enterSelectionMode();
        break;
      case _ChatsMenuAction.markAllRead:
        await _markAllChatsRead();
        break;
    }
  }

  Future<void> _markAllChatsRead() async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);

    try {
      final updatedCount = await ChatApi.markAllChatsRead(widget.session);
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatedCount > 0
                ? '$updatedCount sohbet okundu olarak isaretlendi.'
                : 'Okunmamis sohbet yok.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _deleteSelectedChats() async {
    if (_selectedChatIds.isEmpty || _bulkActionBusy) return;

    final selectedCount = _selectedChatIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sohbetleri sil'),
          content: Text(
            selectedCount == 1
                ? 'Secili sohbet listeden kaldirilsin mi? Yeni mesaj gelirse yeniden gorunur.'
                : '$selectedCount secili sohbet listeden kaldirilsin mi? Yeni mesaj gelirse yeniden gorunur.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      final deletedCount = await ChatApi.deleteChats(
        widget.session,
        _selectedChatIds.toList(),
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _selectionMode = false;
        _selectedChatIds.clear();
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedCount > 0
                ? '$deletedCount sohbet silindi.'
                : 'Secili sohbetler silinemedi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _markChatRead(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);
    try {
      final updatedCount = await ChatApi.markChatRead(
        widget.session,
        chat.chatId,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatedCount > 0
                ? '"${chat.name}" okundu olarak isaretlendi.'
                : 'Okunmamis mesaj yok.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleChatMute(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);
    try {
      final muted = await ChatApi.setChatMuted(
        widget.session,
        chatId: chat.chatId,
        muted: !chat.isMuted,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            muted
                ? '"${chat.name}" sessize alindi.'
                : '"${chat.name}" icin bildirimler yeniden acildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleArchiveChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);
    try {
      final archived = await ChatApi.setChatArchived(
        widget.session,
        chatId: chat.chatId,
        archived: !chat.isArchived,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            archived
                ? '"${chat.name}" arşive taşındı.'
                : '"${chat.name}" arşivden çıkarıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleFavoriteChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    setState(() => _bulkActionBusy = true);
    try {
      final favorited = await ChatApi.setChatFavorited(
        widget.session,
        chatId: chat.chatId,
        favorited: !chat.isFavorited,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            favorited
                ? '"${chat.name}" favorilere eklendi.'
                : '"${chat.name}" favorilerden cikarildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleLockChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    final authenticated = await _authenticateLockedChatAccess(
      context,
      chatName: chat.name,
      actionLabel: chat.isLocked
          ? 'kilidini kaldirmak icin'
          : 'kilitlemek icin',
    );
    if (!mounted || !authenticated) return;

    setState(() => _bulkActionBusy = true);
    try {
      final locked = await ChatApi.setChatLocked(
        widget.session,
        chatId: chat.chatId,
        locked: !chat.isLocked,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locked
                ? '"${chat.name}" kilitlendi.'
                : '"${chat.name}" kilidi kaldirildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<String?> _promptFolderName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategori oluştur'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            hintText: 'Kategori adı',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> _deleteFolder(ChatFolder folder) async {
    if (_bulkActionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategori sil'),
        content: Text(
          '"${folder.name}" kategorisi silinsin mi? Kategoriye atanmış sohbetler Tümü içinde kalmaya devam edecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      await ChatApi.deleteFolder(widget.session, folder.id);
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        if (_selectedFilterId == folder.id) {
          _selectedFilterId = _allChatsFilterId;
        }
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${folder.name}" silindi.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _assignChatFolder(
    ChatPreview chat,
    List<ChatFolder> folders,
  ) async {
    if (_bulkActionBusy) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chat.folderId != null)
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: const Text('Kategoriden çıkar'),
                  onTap: () => Navigator.pop(sheetContext, '__clear__'),
                ),
              for (final folder in folders)
                ListTile(
                  leading: Icon(
                    chat.folderId == folder.id
                        ? Icons.check_circle_rounded
                        : Icons.folder_open_outlined,
                  ),
                  title: Text(folder.name),
                  onTap: () => Navigator.pop(sheetContext, folder.id),
                ),
              if (folders.length < 3)
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('Yeni kategori oluştur'),
                  onTap: () => Navigator.pop(sheetContext, '__create__'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    String? nextFolderId;
    if (action == '__create__') {
      final name = await _promptFolderName();
      if (!mounted || name == null) return;
      setState(() => _bulkActionBusy = true);
      try {
        final folder = await ChatApi.createFolder(widget.session, name: name);
        nextFolderId = folder.id;
      } catch (error) {
        if (!mounted) return;
        setState(() => _bulkActionBusy = false);
        _handleActionError(error);
        return;
      }
    } else if (action == '__clear__') {
      nextFolderId = null;
    } else {
      nextFolderId = action;
    }

    setState(() => _bulkActionBusy = true);
    try {
      await ChatApi.setChatFolder(
        widget.session,
        chatId: chat.chatId,
        folderId: nextFolderId,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextFolderId == null
                ? '"${chat.name}" kategoriden çıkarıldı.'
                : '"${chat.name}" kategoriye atandı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _clearChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sohbeti temizle'),
          content: Text(
            '"${chat.name}" sohbetinin içeriği bu cihazda temizlenecek. Karşı tarafta kalmaya devam edecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Temizle'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      await ChatApi.clearChat(widget.session, chat.chatId);
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${chat.name}" temizlendi.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleBlockChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;

    final willBlock = !chat.isBlockedByMe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(willBlock ? 'Kişiyi engelle' : 'Engeli kaldır'),
          content: Text(
            willBlock
                ? '"${chat.name}" artık sana mesaj gönderemez ve seni arayamaz.'
                : '"${chat.name}" ile iletişim yeniden açılsın mı?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(willBlock ? 'Engelle' : 'Kaldır'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      final blocked = await ChatApi.setChatBlocked(
        widget.session,
        chatId: chat.chatId,
        blocked: willBlock,
      );
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? '"${chat.name}" engellendi.'
                : '"${chat.name}" engeli kaldırıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteSingleChat(ChatPreview chat) async {
    if (_bulkActionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sohbeti sil'),
          content: Text(
            '"${chat.name}" sohbeti sadece senden silinecek. Karsi tarafta kalmaya devam edecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _bulkActionBusy = true);
    try {
      final deletedCount = await ChatApi.deleteChats(widget.session, [
        chat.chatId,
      ]);
      if (!mounted) return;
      setState(() {
        _bulkActionBusy = false;
        _scheduleInboxReload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedCount > 0 ? '"${chat.name}" silindi.' : 'Sohbet silinemedi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _bulkActionBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showChatActions(
    ChatPreview chat,
    List<ChatFolder> folders,
  ) async {
    if (_bulkActionBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ChatListActionTile(
                    icon: Icons.mark_chat_read_outlined,
                    title: 'Okundu olarak işaretle',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _markChatRead(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: chat.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    title: chat.isArchived ? 'Arşivden çıkar' : 'Arşive at',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleArchiveChat(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: chat.isLocked
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline,
                    title: chat.isLocked
                        ? 'Sohbet kilidini kaldır'
                        : 'Sohbeti kilitle',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleLockChat(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: chat.isFavorited
                        ? Icons.star_border_rounded
                        : Icons.star_outline_rounded,
                    title: chat.isFavorited
                        ? 'Favorilerden çıkar'
                        : 'Favorilere ekle',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleFavoriteChat(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: chat.isMuted
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    title: chat.isMuted ? 'Sessizden çıkar' : 'Sessize al',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleChatMute(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: Icons.folder_open_outlined,
                    title: 'Kategori ata',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _assignChatFolder(chat, folders);
                    },
                  ),
                  if (chat.peerId != null)
                    _ChatListActionTile(
                      icon: chat.isBlockedByMe
                          ? Icons.person_add_alt_1_outlined
                          : Icons.block_outlined,
                      title: chat.isBlockedByMe
                          ? 'Engeli kaldır'
                          : 'Kişiyi engelle',
                      destructive: !chat.isBlockedByMe,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _toggleBlockChat(chat);
                      },
                    ),
                  _ChatListActionTile(
                    icon: Icons.layers_clear_outlined,
                    title: 'Sohbeti temizle',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _clearChat(chat);
                    },
                  ),
                  _ChatListActionTile(
                    icon: Icons.delete_outline,
                    title: 'Sohbeti sil',
                    destructive: true,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _deleteSingleChat(chat);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: _selectionMode
            ? IconButton(
                onPressed: _bulkActionBusy ? null : _exitSelectionMode,
                icon: const Icon(Icons.close),
              )
            : PopupMenuButton<_ChatsMenuAction>(
                onSelected: _handleChatsMenuAction,
                position: PopupMenuPosition.under,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _ChatsMenuAction.select,
                    child: Text('Sec'),
                  ),
                  PopupMenuItem(
                    value: _ChatsMenuAction.markAllRead,
                    child: Text('Tumu okundu'),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 6,
                    top: 8,
                    bottom: 8,
                  ),
                  child: _ChatsMenuAnchorIcon(),
                ),
              ),
        title: Text(
          _selectionMode
              ? (_selectedChatIds.isEmpty
                    ? 'Sohbet sec'
                    : '${_selectedChatIds.length} secildi')
              : 'Sohbetler',
          style: const TextStyle(
            color: TurnaColors.text,
            fontSize: 18.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  onPressed: _selectedChatIds.isEmpty || _bulkActionBusy
                      ? null
                      : _deleteSelectedChats,
                  icon: _bulkActionBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                ),
                const SizedBox(width: 4),
              ]
            : [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.camera_alt_outlined, size: 21),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 12),
                  child: _ChatsNewChatActionButton(onTap: _openNewChatPage),
                ),
              ],
      ),
      body: FutureBuilder<ChatInboxData>(
        future: _inboxFuture,
        initialData: _cachedInbox,
        builder: (context, snapshot) {
          final error = snapshot.error;
          if (snapshot.hasData) {
            _cachedInbox = snapshot.data;
          }
          if (error is TurnaUnauthorizedException) {
            return buildTurnaSessionExpiredRedirect(widget.onSessionExpired);
          }

          final inbox = snapshot.data ?? _cachedInbox;
          if (snapshot.connectionState == ConnectionState.waiting &&
              inbox == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (error != null && inbox == null) {
            return _CenteredState(
              icon: Icons.cloud_off_outlined,
              title: 'Sohbetler yüklenemedi',
              message: error.toString(),
              primaryLabel: 'Tekrar dene',
              onPrimary: _reloadInbox,
            );
          }

          final resolvedInbox =
              inbox ?? ChatInboxData(chats: const [], folders: const []);
          final chats = resolvedInbox.chats;
          final folders = resolvedInbox.folders;
          final hasSelectedFolder =
              _selectedFilterId == _allChatsFilterId ||
              folders.any((folder) => folder.id == _selectedFilterId);
          if (!hasSelectedFolder) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _selectedFilterId = _allChatsFilterId);
            });
          }
          final unreadTotal = chats.fold<int>(
            0,
            (sum, chat) => sum + chat.unreadCount,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onUnreadChanged?.call(unreadTotal);
          });

          final archivedChats = _prioritizeFavoritedChats(
            chats.where((chat) => chat.isArchived),
          );
          final activeChats = _prioritizeFavoritedChats(
            chats.where((chat) => !chat.isArchived),
          );
          final scopedChats = switch (_selectedFilterId) {
            _allChatsFilterId => activeChats,
            _ =>
              activeChats
                  .where((chat) => chat.folderId == _selectedFilterId)
                  .toList(),
          };
          final query = _searchController.text.trim().toLowerCase();
          final filteredChats = scopedChats.where((chat) {
            if (query.isEmpty) return true;
            final searchableMessage = chat.isLocked
                ? ''
                : chat.message.toLowerCase();
            return chat.name.toLowerCase().contains(query) ||
                searchableMessage.contains(query);
          }).toList();
          final archivedTopVisible = archivedChats.isNotEmpty;
          final filtersVisible = folders.isNotEmpty;
          final headerSlots =
              1 + (archivedTopVisible ? 1 : 0) + (filtersVisible ? 1 : 0);

          return RefreshIndicator(
            onRefresh: _reloadInbox,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filteredChats.isEmpty
                  ? headerSlots + 1
                  : filteredChats.length + headerSlots,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Sohbetlerde ara',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () => _searchController.clear(),
                                icon: const Icon(Icons.close),
                              ),
                        filled: true,
                        fillColor: TurnaColors.backgroundMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  );
                }

                var cursor = 1;
                if (archivedTopVisible && index == cursor) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: _ArchivedChatsBanner(
                      archivedCount: archivedChats.length,
                      onTap: _openArchivedChatsPage,
                    ),
                  );
                }
                if (archivedTopVisible) {
                  cursor += 1;
                }

                if (filtersVisible && index == cursor) {
                  return SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      children: [
                        _ChatFilterChip(
                          label: 'Tümü',
                          selected: _selectedFilterId == _allChatsFilterId,
                          onTap: () => _selectFilter(_allChatsFilterId),
                        ),
                        for (final folder in folders)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _ChatFilterChip(
                              label: folder.name,
                              selected: _selectedFilterId == folder.id,
                              onTap: () => _selectFilter(folder.id),
                              onLongPress: () => _deleteFolder(folder),
                            ),
                          ),
                      ],
                    ),
                  );
                }
                if (filtersVisible) {
                  cursor += 1;
                }

                if (filteredChats.isEmpty) {
                  if (activeChats.isEmpty && archivedChats.isEmpty) {
                    return const _CenteredListState(
                      icon: Icons.chat_bubble_outline,
                      title: 'Henüz sohbet yok',
                      message:
                          'İlk konuşmayı başlatmak için sağ üstteki artıdan kişi seç.',
                    );
                  }
                  return _CenteredListState(
                    icon: Icons.search_off,
                    title: 'Sonuç bulunamadı',
                    message:
                        '"${_searchController.text.trim()}" için eşleşen sohbet yok.',
                  );
                }

                final chat = filteredChats[index - headerSlots];
                final isLastItem =
                    index == filteredChats.length + headerSlots - 1;
                final isSelected = _selectedChatIds.contains(chat.chatId);
                return _ChatPreviewListTile(
                  chat: chat,
                  authToken: widget.session.token,
                  isSelected: isSelected,
                  showDivider: !isLastItem,
                  onTap: () {
                    if (_selectionMode) {
                      _toggleChatSelection(chat.chatId);
                      return;
                    }
                    Navigator.push(
                      context,
                      buildChatRoomRoute(
                        chat: chat,
                        session: widget.session,
                        callCoordinator: widget.callCoordinator,
                        onSessionExpired: widget.onSessionExpired,
                      ),
                    );
                  },
                  onLongPress: () {
                    if (_selectionMode) return;
                    _showChatActions(chat, folders);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ChatsMenuAnchorIcon extends StatelessWidget {
  const _ChatsMenuAnchorIcon();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: TurnaColors.border.withValues(alpha: 0.9),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset('assets/turna-icon.png', fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: TurnaColors.border.withValues(alpha: 0.9),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x120F172A),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              '...',
              style: TextStyle(
                color: TurnaColors.textMuted,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatListActionTile extends StatelessWidget {
  const _ChatListActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? TurnaColors.error : TurnaColors.text;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ChatsNewChatActionButton extends StatelessWidget {
  const _ChatsNewChatActionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TurnaColors.primary,
      borderRadius: BorderRadius.circular(999),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.add, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class ArchivedChatsPage extends StatefulWidget {
  const ArchivedChatsPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<ArchivedChatsPage> createState() => _ArchivedChatsPageState();
}

class _ArchivedChatsPageState extends State<ArchivedChatsPage> {
  int _refreshTick = 0;
  bool _actionBusy = false;
  ChatInboxData? _cachedInbox;

  @override
  void initState() {
    super.initState();
    _cachedInbox = TurnaChatInboxLocalCache.peek(widget.session.userId);
    unawaited(_loadCachedInbox());
    TurnaContactsDirectory.revision.addListener(_onContactsChanged);
    unawaited(TurnaContactsDirectory.ensureLoaded());
  }

  @override
  void dispose() {
    TurnaContactsDirectory.revision.removeListener(_onContactsChanged);
    super.dispose();
  }

  void _onContactsChanged() {
    if (!mounted) return;
    setState(() => _refreshTick++);
  }

  void _scheduleRefresh() {
    _refreshTick++;
  }

  Future<void> _loadCachedInbox() async {
    final cached = await TurnaChatInboxLocalCache.load(widget.session.userId);
    if (!mounted || cached == null) return;
    setState(() => _cachedInbox = cached);
  }

  void _handleActionError(Object error) {
    if (error is TurnaUnauthorizedException) {
      widget.onSessionExpired();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _toggleArchiveChat(ChatPreview chat) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final archived = await ChatApi.setChatArchived(
        widget.session,
        chatId: chat.chatId,
        archived: !chat.isArchived,
      );
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            archived
                ? '"${chat.name}" arşive taşındı.'
                : '"${chat.name}" arşivden çıkarıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleFavoriteChat(ChatPreview chat) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final favorited = await ChatApi.setChatFavorited(
        widget.session,
        chatId: chat.chatId,
        favorited: !chat.isFavorited,
      );
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            favorited
                ? '"${chat.name}" favorilere eklendi.'
                : '"${chat.name}" favorilerden cikarildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleLockChat(ChatPreview chat) async {
    if (_actionBusy) return;
    final authenticated = await _authenticateLockedChatAccess(
      context,
      chatName: chat.name,
      actionLabel: chat.isLocked
          ? 'kilidini kaldirmak icin'
          : 'kilitlemek icin',
    );
    if (!mounted || !authenticated) return;

    setState(() => _actionBusy = true);
    try {
      final locked = await ChatApi.setChatLocked(
        widget.session,
        chatId: chat.chatId,
        locked: !chat.isLocked,
      );
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locked
                ? '"${chat.name}" kilitlendi.'
                : '"${chat.name}" kilidi kaldirildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _toggleBlockChat(ChatPreview chat) async {
    if (_actionBusy || chat.peerId == null) return;

    final willBlock = !chat.isBlockedByMe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(willBlock ? 'Kişiyi engelle' : 'Engeli kaldır'),
        content: Text(
          willBlock
              ? '"${chat.name}" artık sana mesaj gönderemez ve seni arayamaz.'
              : '"${chat.name}" ile iletişim yeniden açılsın mı?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(willBlock ? 'Engelle' : 'Kaldır'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      final blocked = await ChatApi.setChatBlocked(
        widget.session,
        chatId: chat.chatId,
        blocked: willBlock,
      );
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? '"${chat.name}" engellendi.'
                : '"${chat.name}" engeli kaldırıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _clearChat(ChatPreview chat) async {
    if (_actionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sohbeti temizle'),
        content: Text(
          '"${chat.name}" sohbetinin içeriği bu cihazda temizlenecek. Karşı tarafta kalmaya devam edecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      await ChatApi.clearChat(widget.session, chat.chatId);
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${chat.name}" temizlendi.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _deleteSingleChat(ChatPreview chat) async {
    if (_actionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sohbeti sil'),
        content: Text(
          '"${chat.name}" sohbeti sadece senden silinecek. Karsi tarafta kalmaya devam edecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      final deletedCount = await ChatApi.deleteChats(widget.session, [
        chat.chatId,
      ]);
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _scheduleRefresh();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedCount > 0 ? '"${chat.name}" silindi.' : 'Sohbet silinemedi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      _handleActionError(error);
    }
  }

  Future<void> _showChatActions(ChatPreview chat) async {
    if (_actionBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChatListActionTile(
                  icon: Icons.unarchive_outlined,
                  title: 'Arşivden çıkar',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _toggleArchiveChat(chat);
                  },
                ),
                _ChatListActionTile(
                  icon: chat.isLocked
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                  title: chat.isLocked
                      ? 'Sohbet kilidini kaldır'
                      : 'Sohbeti kilitle',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _toggleLockChat(chat);
                  },
                ),
                _ChatListActionTile(
                  icon: chat.isFavorited
                      ? Icons.star_border_rounded
                      : Icons.star_outline_rounded,
                  title: chat.isFavorited
                      ? 'Favorilerden çıkar'
                      : 'Favorilere ekle',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _toggleFavoriteChat(chat);
                  },
                ),
                if (chat.peerId != null)
                  _ChatListActionTile(
                    icon: chat.isBlockedByMe
                        ? Icons.person_add_alt_1_outlined
                        : Icons.block_outlined,
                    title: chat.isBlockedByMe
                        ? 'Engeli kaldır'
                        : 'Kişiyi engelle',
                    destructive: !chat.isBlockedByMe,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _toggleBlockChat(chat);
                    },
                  ),
                _ChatListActionTile(
                  icon: Icons.layers_clear_outlined,
                  title: 'Sohbeti temizle',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _clearChat(chat);
                  },
                ),
                _ChatListActionTile(
                  icon: Icons.delete_outline,
                  title: 'Sohbeti sil',
                  destructive: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _deleteSingleChat(chat);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Arşiv Sohbetleri',
          style: TextStyle(
            color: TurnaColors.text,
            fontSize: 18.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: FutureBuilder<ChatInboxData>(
        future: ChatApi.fetchChats(widget.session, refreshTick: _refreshTick),
        initialData: _cachedInbox,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _cachedInbox = snapshot.data;
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null &&
              _cachedInbox == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            if (error is TurnaUnauthorizedException) {
              return buildTurnaSessionExpiredRedirect(widget.onSessionExpired);
            }
            return _CenteredState(
              icon: Icons.archive_outlined,
              title: 'Arşiv yüklenemedi',
              message: error.toString(),
              primaryLabel: 'Tekrar dene',
              onPrimary: () => setState(() => _refreshTick++),
            );
          }

          final inbox =
              snapshot.data ??
              _cachedInbox ??
              ChatInboxData(chats: const [], folders: const []);
          final archivedChats = _prioritizeFavoritedChats(
            inbox.chats.where((chat) => chat.isArchived),
          );

          return RefreshIndicator(
            onRefresh: () async => setState(() => _refreshTick++),
            child: archivedChats.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      _CenteredListState(
                        icon: Icons.archive_outlined,
                        title: 'Arşiv boş',
                        message:
                            'Arşive attığın sohbetler burada listelenecek.',
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: archivedChats.length,
                    itemBuilder: (context, index) {
                      final chat = archivedChats[index];
                      final isLastItem = index == archivedChats.length - 1;
                      return _ChatPreviewListTile(
                        chat: chat,
                        authToken: widget.session.token,
                        showDivider: !isLastItem,
                        onTap: () {
                          Navigator.push(
                            context,
                            buildChatRoomRoute(
                              chat: chat,
                              session: widget.session,
                              callCoordinator: widget.callCoordinator,
                              onSessionExpired: widget.onSessionExpired,
                            ),
                          );
                        },
                        onLongPress: () => _showChatActions(chat),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class _ChatPreviewListTile extends StatelessWidget {
  const _ChatPreviewListTile({
    required this.chat,
    required this.authToken,
    required this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.showDivider = true,
  });

  final ChatPreview chat;
  final String authToken;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tileColor = isSelected
        ? TurnaColors.primary.withValues(alpha: 0.08)
        : chat.unreadCount > 0
        ? TurnaColors.chatUnreadBg
        : Colors.transparent;
    final groupPreview = chat.memberPreviewNames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final groupMetaText = () {
      if (chat.chatType != TurnaChatType.group) return null;
      final parts = <String>[];
      if (groupPreview.isNotEmpty) {
        parts.add(groupPreview.join(', '));
      }
      if (chat.memberCount > 0) {
        parts.add('${chat.memberCount} üye');
      }
      return parts.isEmpty ? null : parts.join(' · ');
    }();
    final subtitleText = chat.isLocked
        ? 'Sohbet kilitli'
        : (groupMetaText != null && chat.message.trim() == 'Grup oluşturuldu'
              ? groupMetaText
              : chat.message);
    return Material(
      color: tileColor,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _ProfileAvatar(
                          label: chat.name,
                          avatarUrl: chat.avatarUrl,
                          authToken: authToken,
                          radius: 23,
                        ),
                        if (isSelected)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: TurnaColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.6,
                                ),
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      chat.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: TurnaColors.text,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  if (chat.chatType == TurnaChatType.group) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.group_outlined,
                                      size: 15,
                                      color: TurnaColors.textSoft,
                                    ),
                                  ],
                                  if (chat.isFavorited) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: Color(0xFFDAA520),
                                    ),
                                  ],
                                  if (chat.isLocked) ...[
                                    const SizedBox(width: 5),
                                    const Icon(
                                      Icons.lock_outline,
                                      size: 13,
                                      color: TurnaColors.textSoft,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ChatPreviewMeta(chat: chat),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _ChatPreviewSubtitle(text: subtitleText),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              const Divider(
                height: 1,
                thickness: 0.8,
                indent: 74,
                endIndent: 16,
                color: TurnaColors.divider,
              ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedChatsBanner extends StatelessWidget {
  const _ArchivedChatsBanner({
    required this.archivedCount,
    required this.onTap,
  });

  final int archivedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.archive_outlined, color: TurnaColors.textMuted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Arşiv Sohbetleri',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: TurnaColors.text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: TurnaColors.backgroundMuted,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$archivedCount',
                  style: TextStyle(
                    color: TurnaColors.textSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
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

class _ChatFilterChip extends StatelessWidget {
  const _ChatFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: TurnaColors.primary.withValues(alpha: 0.16),
        labelStyle: TextStyle(
          color: selected ? TurnaColors.primaryDeep : TurnaColors.textSoft,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(
          color: selected ? TurnaColors.primary : TurnaColors.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        backgroundColor: Colors.white,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _ChatPreviewMeta extends StatelessWidget {
  const _ChatPreviewMeta({required this.chat});

  final ChatPreview chat;

  @override
  Widget build(BuildContext context) {
    final hasUnread = chat.unreadCount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          chat.time,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w400,
            color: hasUnread ? TurnaColors.primary : const Color(0xFF8C959F),
            height: 1.1,
          ),
        ),
        if (hasUnread) ...[
          const SizedBox(height: 7),
          Container(
            constraints: const BoxConstraints(minWidth: 19),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: const BoxDecoration(
              color: TurnaColors.primary,
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
            child: Text(
              chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChatPreviewSubtitleParts {
  const _ChatPreviewSubtitleParts({this.sender, required this.message});

  final String? sender;
  final String message;
}

class _ChatPreviewSubtitle extends StatelessWidget {
  const _ChatPreviewSubtitle({required this.text});

  final String text;

  static _ChatPreviewSubtitleParts _parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const _ChatPreviewSubtitleParts(message: 'Sohbet başlat');
    }

    final dividerIndex = trimmed.indexOf(':');
    if (dividerIndex <= 0 || dividerIndex >= 32) {
      return _ChatPreviewSubtitleParts(message: trimmed);
    }

    final sender = trimmed.substring(0, dividerIndex).trim();
    final message = trimmed.substring(dividerIndex + 1).trim();
    if (sender.isEmpty ||
        message.isEmpty ||
        sender.contains('://') ||
        sender.contains('@')) {
      return _ChatPreviewSubtitleParts(message: trimmed);
    }

    return _ChatPreviewSubtitleParts(sender: sender, message: message);
  }

  @override
  Widget build(BuildContext context) {
    final parts = _parse(text);
    final baseStyle = const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w400,
      color: TurnaColors.textMuted,
      height: 1.2,
    );

    if (parts.sender == null) {
      return Text(
        parts.message,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${parts.sender}: ',
            style: baseStyle.copyWith(
              color: TurnaColors.textSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(text: parts.message, style: baseStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _ComposerEditDraft {
  const _ComposerEditDraft({
    required this.messageId,
    required this.reply,
    required this.originalText,
  });

  final String messageId;
  final TurnaReplyPayload? reply;
  final String originalText;
}

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.chat,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final ChatPreview chat;
  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

PageRoute<void> buildChatRoomRoute({
  required ChatPreview chat,
  required AuthSession session,
  required TurnaCallCoordinator callCoordinator,
  required VoidCallback onSessionExpired,
}) {
  return MaterialPageRoute(
    settings: RouteSettings(
      name: kChatRoomRouteName,
      arguments: {'chatId': chat.chatId},
    ),
    builder: (_) => _LockedChatAccessGate(
      chat: chat,
      child: ChatRoomPage(
        chat: chat,
        session: session,
        callCoordinator: callCoordinator,
        onSessionExpired: onSessionExpired,
      ),
    ),
  );
}

class _LockedChatAccessGate extends StatefulWidget {
  const _LockedChatAccessGate({required this.chat, required this.child});

  final ChatPreview chat;
  final Widget child;

  @override
  State<_LockedChatAccessGate> createState() => _LockedChatAccessGateState();
}

class _LockedChatAccessGateState extends State<_LockedChatAccessGate> {
  bool _authorized = false;
  bool _authStarted = false;

  @override
  void initState() {
    super.initState();
    _authorized = !widget.chat.isLocked;
    if (!_authorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _authenticate();
      });
    }
  }

  Future<void> _authenticate() async {
    if (_authStarted || !mounted || _authorized) return;
    _authStarted = true;
    final authenticated = await _authenticateLockedChatAccess(
      context,
      chatName: widget.chat.name,
      actionLabel: 'acmak icin',
    );
    if (!mounted) return;
    if (authenticated) {
      setState(() => _authorized = true);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (_authorized) {
      return widget.child;
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

ChatPreview buildDirectChatPreviewForCall(
  AuthSession session,
  TurnaCallSummary call,
) {
  return ChatPreview(
    chatId: ChatApi.buildDirectChatId(session.userId, call.peer.id),
    name: call.peer.displayName,
    message: '',
    time: '',
    avatarUrl: call.peer.avatarUrl,
  );
}

class _ChatTimelineEntry {
  const _ChatTimelineEntry._({
    required this.id,
    required this.createdAt,
    this.message,
    this.call,
  });

  factory _ChatTimelineEntry.message(ChatMessage message) {
    return _ChatTimelineEntry._(
      id: 'message:${message.id}',
      createdAt: message.createdAt,
      message: message,
    );
  }

  factory _ChatTimelineEntry.call(TurnaCallHistoryItem call) {
    return _ChatTimelineEntry._(
      id: 'call:${call.id}',
      createdAt: call.createdAt ?? '',
      call: call,
    );
  }

  final String id;
  final String createdAt;
  final ChatMessage? message;
  final TurnaCallHistoryItem? call;

  bool get isMessage => message != null;
}

class _ChatRoomPageState extends State<ChatRoomPage>
    with WidgetsBindingObserver, RouteAware {
  static const Duration _voiceRecordTick = Duration(milliseconds: 140);
  static const Duration _voiceMinDuration = Duration(milliseconds: 600);
  static const double _voiceCancelThreshold = 112;
  static const double _voiceLockThreshold = 84;

  late final TurnaSocketClient _client;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _mediaPicker = ImagePicker();
  final FocusNode _composerFocusNode = FocusNode();
  final rec.AudioRecorder _voiceRecorder = rec.AudioRecorder();
  final Stopwatch _voiceStopwatch = Stopwatch();
  bool _showScrollToBottom = false;
  bool _attachmentBusy = false;
  bool _hasComposerText = false;
  bool _loadingPeerCalls = false;
  bool _voiceRecording = false;
  bool _voiceRecordingLocked = false;
  bool _voiceRecordingPaused = false;
  bool _voiceRecorderBusy = false;
  bool _voiceSlideCancelArmed = false;
  bool _showSecurityBanner = false;
  TurnaReplyPayload? _replyDraft;
  _ComposerEditDraft? _editingDraft;
  List<TurnaGroupMember> _mentionCandidates = const [];
  List<TurnaGroupMember> _mentionSuggestions = const [];
  String? _activeMentionQuery;
  List<TurnaCallHistoryItem> _peerCalls = const [];
  Set<String> _starredMessageIds = <String>{};
  Set<String> _softDeletedMessageIds = <String>{};
  Set<String> _deletedMessageIds = <String>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  int _lastRenderedTimelineCount = 0;
  Timer? _messageHighlightTimer;
  String? _highlightedMessageId;
  PageRoute<dynamic>? _route;
  Timer? _voiceRecordTimer;
  String? _voiceRecordingPath;
  double _voiceSlideProgress = 0;
  final GlobalKey _voiceMicKey = GlobalKey();
  int? _voicePointerId;
  Offset? _voicePointerOriginGlobal;

  bool get _isGroupChat => widget.chat.chatType == TurnaChatType.group;
  TurnaChatDetail? get _cachedGroupDetail => _isGroupChat
      ? TurnaChatDetailLocalCache.peek(
          widget.session.userId,
          widget.chat.chatId,
        )
      : null;
  String? get _peerUserId =>
      ChatApi.extractPeerUserId(widget.chat.chatId, widget.session.userId);
  String? get _groupAvatarUrl =>
      _cachedGroupDetail?.avatarUrl ?? widget.chat.avatarUrl;
  int get _groupMemberCount =>
      _cachedGroupDetail?.memberCount ?? widget.chat.memberCount;
  String get _chatDisplayName => _isGroupChat
      ? ((_cachedGroupDetail?.title.trim().isNotEmpty ?? false)
            ? _cachedGroupDetail!.title.trim()
            : widget.chat.name)
      : TurnaContactsDirectory.resolveDisplayLabel(
          phone: widget.chat.phone,
          fallbackName: widget.chat.name,
        );
  TurnaPinnedMessageSummary? get _activePinnedMessage =>
      _client.pinnedMessages.isEmpty ? null : _client.pinnedMessages.first;
  bool get _canManagePinnedMessages {
    if (!_isGroupChat) return false;
    final detail = _cachedGroupDetail;
    if (detail == null) return true;
    return _policyAllowsForCurrentUser(
      detail.whoCanEditInfo,
      detail.myRole ?? '',
    );
  }

  String get _securityBannerSeenKey =>
      'turna_security_banner_seen_${widget.session.userId}_${widget.chat.chatId}';
  String get _starredMessagesKey =>
      'turna_starred_messages_${widget.chat.chatId}';
  String get _softDeletedMessagesKey =>
      'turna_soft_deleted_messages_${widget.chat.chatId}';
  String get _deletedMessagesKey =>
      'turna_deleted_messages_${widget.chat.chatId}';

  bool _policyAllowsForCurrentUser(String policy, String role) {
    final normalizedPolicy = policy.trim().toUpperCase();
    final normalizedRole = role.trim().toUpperCase();
    if (normalizedRole == 'OWNER') return true;
    switch (normalizedPolicy) {
      case 'EVERYONE':
        return true;
      case 'EDITOR_ONLY':
        return normalizedRole == 'ADMIN' || normalizedRole == 'EDITOR';
      case 'ADMIN_ONLY':
        return normalizedRole == 'ADMIN';
      default:
        return false;
    }
  }

  bool get _canCurrentUserSendInGroup {
    if (!_isGroupChat) return true;
    final detail = _cachedGroupDetail;
    if (detail == null) return true;
    if (detail.myIsMuted) return false;
    if (detail.myCanSend != true) return false;
    return _policyAllowsForCurrentUser(detail.whoCanSend, detail.myRole ?? '');
  }

  String? get _groupSendRestrictionText {
    if (!_isGroupChat) return null;
    final detail = _cachedGroupDetail;
    if (detail == null || _canCurrentUserSendInGroup) return null;
    if (detail.myIsMuted) {
      if ((detail.myMutedUntil ?? '').trim().isNotEmpty) {
        final until = parseTurnaLocalDateTime(detail.myMutedUntil!);
        if (until != null) {
          final hh = until.hour.toString().padLeft(2, '0');
          final mm = until.minute.toString().padLeft(2, '0');
          return 'Sessize alındın. ${until.day.toString().padLeft(2, '0')}.${until.month.toString().padLeft(2, '0')} $hh:$mm sonrasına kadar yazamazsın.';
        }
      }
      return (detail.myMuteReason ?? '').trim().isNotEmpty
          ? 'Sessize alındın. ${detail.myMuteReason!.trim()}'
          : 'Sessize alındın. Bu grupta şu an mesaj gönderemezsin.';
    }
    switch ((detail.whoCanSend).trim().toUpperCase()) {
      case 'OWNER_ONLY':
        return 'Bu grupta şu an sadece sahip mesaj gönderebilir.';
      case 'ADMIN_ONLY':
        return 'Bu grupta şu an sadece adminler mesaj gönderebilir.';
      case 'EDITOR_ONLY':
        return 'Bu grupta şu an sadece editör ve üstü mesaj gönderebilir.';
      default:
        return 'Bu grupta mesaj gönderme iznin kapalı.';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    turnaLog('chat room init', {
      'chatId': widget.chat.chatId,
      'senderId': widget.session.userId,
    });
    TurnaAnalytics.logEvent('chat_opened', {'chat_id': widget.chat.chatId});
    _client = TurnaSocketClient(
      chatId: widget.chat.chatId,
      senderId: widget.session.userId,
      peerUserId: _peerUserId,
      chatType: widget.chat.chatType,
      token: widget.session.token,
      onSessionExpired: widget.onSessionExpired,
    )..connect();
    _client.addListener(_refresh);
    widget.callCoordinator.addListener(_handleCallCoordinatorChanged);
    _controller.addListener(_handleComposerChanged);
    _composerFocusNode.addListener(_handleComposerFocusChanged);
    _scrollController.addListener(_handleScroll);
    TurnaContactsDirectory.revision.addListener(_refresh);
    _loadLocalMessageState();
    unawaited(_loadSecurityBannerState());
    if (_isGroupChat) {
      unawaited(_loadPinnedMessages());
      unawaited(_loadGroupDetail());
      unawaited(_loadMentionCandidates());
    }
    if (!_isGroupChat) {
      _restorePeerCallHistoryFromWarmCache();
    }
    unawaited(TurnaContactsDirectory.ensureLoaded());
    if (!_isGroupChat) {
      unawaited(_restorePeerCallHistoryFromDiskCache());
      unawaited(_loadPeerCallHistory());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || identical(route, _route)) return;
    if (_route != null) {
      kTurnaRouteObserver.unsubscribe(this);
    }
    _route = route;
    kTurnaRouteObserver.subscribe(this, route);
  }

  @override
  void didPush() {
    kTurnaActiveChatRegistry.setCurrent(widget.chat);
    if (!_isGroupChat) {
      unawaited(_loadPeerCallHistory());
    }
  }

  @override
  void didPopNext() {
    kTurnaActiveChatRegistry.setCurrent(widget.chat);
    if (!_isGroupChat) {
      unawaited(_loadPeerCallHistory());
    }
  }

  @override
  void didPushNext() {
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
  }

  @override
  void didPop() {
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
  }

  void _refresh() {
    final shouldSnapToBottom =
        !_scrollController.hasClients || _scrollController.offset < 120;
    if (mounted) {
      setState(() {});
    }
    final timelineCount = _buildTimelineEntries().length;
    if (timelineCount != _lastRenderedTimelineCount) {
      _lastRenderedTimelineCount = timelineCount;
      if (shouldSnapToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    }
  }

  void _handleCallCoordinatorChanged() {
    if (_isGroupChat) return;
    unawaited(_loadPeerCallHistory());
  }

  void _handleComposerChanged() {
    final text = _controller.text;
    _client.updateComposerText(text);
    _updateMentionSuggestions(text);
    final hasComposerText = text.trim().isNotEmpty;
    if (hasComposerText != _hasComposerText && mounted) {
      setState(() => _hasComposerText = hasComposerText);
    }
  }

  void _handleComposerFocusChanged() {
    _refresh();
    _updateMentionSuggestions(_controller.text);
  }

  String? _buildPeerStatusText() {
    if (_isGroupChat) {
      final typingSummary = _client.groupTypingSummary;
      if (typingSummary != null) return typingSummary;
      final previewNames = (_cachedGroupDetail?.memberPreviewNames ??
              widget.chat.memberPreviewNames)
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (previewNames.isNotEmpty) {
        return '${previewNames.join(', ')} · $_groupMemberCount üye';
      }
      if (_groupMemberCount > 0) {
        return '$_groupMemberCount üye';
      }
      return 'Grup sohbeti';
    }
    if (_peerUserId == null) return null;
    if (_client.peerTyping) return 'yazıyor...';
    if (_client.peerOnline) return 'online';
    final lastSeenAt = _client.peerLastSeenAt;
    if (lastSeenAt == null || lastSeenAt.trim().isEmpty) return null;
    return 'son görülme ${_formatPresenceTime(lastSeenAt)}';
  }

  String _formatPresenceTime(String iso) {
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return iso;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final seenDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(seenDay).inDays;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (diffDays == 0) return 'bugün $hh:$mm';
    if (diffDays == 1) return 'dün $hh:$mm';

    final dd = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    if (dt.year == now.year) return '$dd.$month $hh:$mm';
    return '$dd.$month.${dt.year} $hh:$mm';
  }

  Future<void> _openPeerProfile() async {
    final peerUserId = _peerUserId;
    if (peerUserId == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          session: widget.session,
          userId: peerUserId,
          fallbackName: _chatDisplayName,
          fallbackAvatarUrl: widget.chat.avatarUrl,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _openGroupInfo() async {
    if (!_isGroupChat) return;

    final shouldCloseRoom = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaGroupInfoPage(
          session: widget.session,
          chat: widget.chat,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
    if (mounted && _isGroupChat) {
      unawaited(_loadGroupDetail());
    }
    if (!mounted || shouldCloseRoom != true) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _loadGroupDetail() async {
    if (!_isGroupChat) return;
    try {
      await ChatApi.fetchChatDetail(widget.session, widget.chat.chatId);
      if (!mounted) return;
      setState(() {});
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (_) {}
  }

  Future<void> _startCall(TurnaCallType type) async {
    final peerUserId = _peerUserId;
    if (peerUserId == null) return;

    try {
      final started = await CallApi.startCall(
        widget.session,
        calleeId: peerUserId,
        type: type,
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
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 180;
    if (shouldShow != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = shouldShow);
    }

    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 220) {
      _client.loadOlderMessages();
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  String _formatMessageTime(String iso) {
    return formatTurnaLocalClock(iso);
  }

  String _formatDayLabel(String iso) {
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(messageDay).inDays;
    if (diffDays == 0) return 'Bugun';
    if (diffDays == 1) return 'Dun';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd.$mm.${dt.year}';
  }

  String _formatViewerDateTime(String iso) {
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return '';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${dt.year} $hh:$min';
  }

  Future<void> _openSharedUri(
    Uri uri, {
    String errorMessage = 'Bağlantı açılamadı.',
  }) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  String _stripLinksFromText(String text) {
    return text
        .replaceAll(_kTurnaSharedUrlPattern, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Widget _buildLinkifiedMessageText(String text, {required bool mine}) {
    final baseStyle = TextStyle(
      fontSize: 16,
      height: 1.28,
      color: mine ? TurnaColors.chatOutgoingText : TurnaColors.chatIncomingText,
    );
    final matches = _kTurnaSharedUrlPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final raw = match.group(0) ?? '';
      final uri = parseTurnaSharedUrl(raw);
      if (uri == null) {
        spans.add(TextSpan(text: raw));
      } else {
        spans.add(
          TextSpan(
            text: raw,
            style: baseStyle.copyWith(
              color: mine ? TurnaColors.primary800 : TurnaColors.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openSharedUri(uri),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  String _timelineCreatedAt(_ChatTimelineEntry entry) {
    if (entry.message != null) return entry.message!.createdAt;
    final call = entry.call;
    return call?.createdAt ?? call?.endedAt ?? call?.acceptedAt ?? '';
  }

  bool _shouldShowDayChip(List<_ChatTimelineEntry> entries, int index) {
    if (index == entries.length - 1) return true;
    final current = parseTurnaLocalDateTime(_timelineCreatedAt(entries[index]));
    final older = parseTurnaLocalDateTime(
      _timelineCreatedAt(entries[index + 1]),
    );
    if (current == null || older == null) return false;
    return current.year != older.year ||
        current.month != older.month ||
        current.day != older.day;
  }

  String _formatFileSize(int bytes) => formatBytesLabel(bytes);

  List<TurnaCallHistoryItem> _filterPeerCalls(
    Iterable<TurnaCallHistoryItem> calls,
  ) {
    final peerUserId = _peerUserId;
    if (peerUserId == null) return const <TurnaCallHistoryItem>[];

    final filtered = calls.where((item) => item.peer.id == peerUserId).toList()
      ..sort((a, b) {
        final aTime = a.createdAt ?? a.endedAt ?? a.acceptedAt ?? '';
        final bTime = b.createdAt ?? b.endedAt ?? b.acceptedAt ?? '';
        return compareTurnaTimestamps(aTime, bTime);
      });
    return filtered;
  }

  bool _sameCallHistory(
    List<TurnaCallHistoryItem> a,
    List<TurnaCallHistoryItem> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id) return false;
      if (a[index].status != b[index].status) return false;
      if (a[index].createdAt != b[index].createdAt) return false;
      if (a[index].acceptedAt != b[index].acceptedAt) return false;
      if (a[index].endedAt != b[index].endedAt) return false;
      if (a[index].durationSeconds != b[index].durationSeconds) return false;
    }
    return true;
  }

  void _restorePeerCallHistoryFromWarmCache() {
    final cached = TurnaCallHistoryLocalCache.peek(widget.session.userId);
    if (cached == null || cached.isEmpty) return;
    _peerCalls = _filterPeerCalls(cached);
  }

  Future<void> _restorePeerCallHistoryFromDiskCache() async {
    final cached = await TurnaCallHistoryLocalCache.load(widget.session.userId);
    if (!mounted || cached.isEmpty) return;
    final filtered = _filterPeerCalls(cached);
    if (filtered.isEmpty || _sameCallHistory(filtered, _peerCalls)) return;
    setState(() => _peerCalls = filtered);
  }

  Future<void> _loadPeerCallHistory() async {
    final peerUserId = _peerUserId;
    if (peerUserId == null || _loadingPeerCalls) return;

    _loadingPeerCalls = true;
    final shouldSnapToBottom =
        !_scrollController.hasClients || _scrollController.offset < 120;
    final previousCount = _buildTimelineEntries().length;
    try {
      final calls = await CallApi.fetchCalls(widget.session);
      if (!mounted) return;
      final filtered = _filterPeerCalls(calls);
      setState(() => _peerCalls = filtered);
      final nextCount = _buildTimelineEntries().length;
      _lastRenderedTimelineCount = nextCount;
      if (shouldSnapToBottom && nextCount != previousCount) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      turnaLog('chat call history load failed', error);
    } finally {
      _loadingPeerCalls = false;
    }
  }

  void _showVoiceMessageHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ses kaydı için mikrofona basılı tut.')),
    );
  }

  Future<void> _pickLocation() async {
    if (_attachmentBusy) return;
    final selection = await Navigator.of(context).push<TurnaLocationSelection>(
      MaterialPageRoute<TurnaLocationSelection>(
        builder: (_) => const LocationPickerPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || selection == null) return;
    await _sendLocationSelection(selection);
  }

  Future<void> _sendLocationSelection(TurnaLocationSelection selection) async {
    if (_attachmentBusy) return;
    final replyDraft = _replyDraft;
    final outboundText = buildTurnaLocationEncodedText(
      location: selection.payload,
    );
    final encodedText = replyDraft == null
        ? outboundText
        : buildTurnaReplyEncodedText(reply: replyDraft, text: outboundText);
    setState(() => _attachmentBusy = true);

    try {
      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: widget.chat.chatId,
        text: encodedText,
      );
      if (!mounted) return;
      _client.mergeServerMessage(message);
      if (selection.mode == TurnaLocationShareMode.live) {
        await TurnaLiveLocationManager.instance.startShare(
          session: widget.session,
          chatId: widget.chat.chatId,
          message: message,
          payload: selection.payload,
        );
      }
      setState(() => _replyDraft = null);
      _jumpToBottom();
      await TurnaAnalytics.logEvent('location_sent', {
        'chat_id': widget.chat.chatId,
        'mode': selection.mode.name,
        'live_minutes': selection.liveDuration?.inMinutes ?? 0,
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Konum gönderilemedi: $error')));
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Future<void> _pickSharedContact() async {
    if (_attachmentBusy) return;
    final payload = await Navigator.of(context).push<TurnaSharedContactPayload>(
      MaterialPageRoute<TurnaSharedContactPayload>(
        builder: (_) => const ContactSharePickerPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || payload == null) return;
    await _sendSharedContact(payload);
  }

  Future<void> _sendSharedContact(TurnaSharedContactPayload payload) async {
    if (_attachmentBusy) return;
    final replyDraft = _replyDraft;
    final outboundText = buildTurnaContactEncodedText(contact: payload);
    final encodedText = replyDraft == null
        ? outboundText
        : buildTurnaReplyEncodedText(reply: replyDraft, text: outboundText);
    setState(() => _attachmentBusy = true);

    try {
      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: widget.chat.chatId,
        text: encodedText,
      );
      if (!mounted) return;
      _client.mergeServerMessage(message);
      setState(() => _replyDraft = null);
      _jumpToBottom();
      await TurnaAnalytics.logEvent('contact_sent', {
        'chat_id': widget.chat.chatId,
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kişi gönderilemedi: $error')));
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Future<void> _stopLiveLocation(
    ChatMessage msg,
    TurnaLocationPayload payload,
  ) async {
    if (_attachmentBusy) return;
    if (!payload.isLiveActive || (payload.liveId?.trim().isEmpty ?? true)) {
      return;
    }
    setState(() => _attachmentBusy = true);
    try {
      await TurnaLiveLocationManager.instance.stopShare(msg.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Canlı konum durduruldu.')));
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  String _formatVoiceDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Duration get _voiceDuration => _voiceStopwatch.elapsed;

  void _tickVoiceRecording() {
    if (!mounted || !_voiceRecording || _voiceRecordingPaused) return;
    setState(() {});
  }

  void _resetVoiceRecordingState() {
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;
    _voiceStopwatch
      ..stop()
      ..reset();
    _voiceRecording = false;
    _voiceRecordingLocked = false;
    _voiceRecordingPaused = false;
    _voiceSlideCancelArmed = false;
    _voiceSlideProgress = 0;
    _voiceRecordingPath = null;
  }

  Future<void> _startVoiceRecording() async {
    if (_attachmentBusy ||
        _voiceRecorderBusy ||
        _voiceRecording ||
        _hasComposerText ||
        _editingDraft != null) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _voiceRecorderBusy = true);

    try {
      final hasPermission = await _voiceRecorder.hasPermission();
      if (!hasPermission) {
        throw TurnaApiException(
          'Ses kaydı için mikrofon izni vermen gerekiyor.',
        );
      }

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'turna-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${tempDir.path}/$fileName';

      await _voiceRecorder.start(
        const rec.RecordConfig(
          encoder: rec.AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _voiceRecordTimer?.cancel();
      _voiceStopwatch
        ..reset()
        ..start();
      _voiceRecordTimer = Timer.periodic(
        _voiceRecordTick,
        (_) => _tickVoiceRecording(),
      );

      if (!mounted) return;
      setState(() {
        _voiceRecording = true;
        _voiceRecordingLocked = false;
        _voiceRecordingPaused = false;
        _voiceSlideCancelArmed = false;
        _voiceSlideProgress = 0;
        _voiceRecordingPath = path;
        _voiceRecorderBusy = false;
      });
    } on TurnaApiException catch (error) {
      if (!mounted) return;
      setState(() => _voiceRecorderBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _voiceRecorderBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ses kaydı başlatılamadı.')));
      turnaLog('voice record start failed', error);
    }
  }

  void _updateVoiceRecordingGesture(Offset delta) {
    if (!_voiceRecording || _voiceRecordingLocked) return;
    final slideProgress = ((-delta.dx) / _voiceCancelThreshold).clamp(0.0, 1.0);
    final lockProgress = ((-delta.dy) / _voiceLockThreshold).clamp(0.0, 1.0);
    if (lockProgress >= 1) {
      setState(() {
        _voiceRecordingLocked = true;
        _voiceSlideCancelArmed = false;
        _voiceSlideProgress = 0;
      });
      return;
    }
    setState(() {
      _voiceSlideProgress = slideProgress;
      _voiceSlideCancelArmed = slideProgress >= 1;
    });
  }

  bool _isVoiceMicHit(Offset globalPosition) {
    final context = _voiceMicKey.currentContext;
    if (context == null) return false;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return false;
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;
    return rect.contains(globalPosition);
  }

  void _handleComposerPointerDown(PointerDownEvent event) {
    if (_attachmentBusy ||
        _voiceRecorderBusy ||
        _hasComposerText ||
        _editingDraft != null) {
      return;
    }
    if (!_isVoiceMicHit(event.position)) return;
    _voicePointerId = event.pointer;
    _voicePointerOriginGlobal = event.position;
  }

  void _handleComposerPointerMove(PointerMoveEvent event) {
    if (_voicePointerId != event.pointer) return;
    final origin = _voicePointerOriginGlobal;
    if (origin == null) return;
    _updateVoiceRecordingGesture(event.position - origin);
  }

  Future<void> _handleComposerPointerUp(PointerUpEvent event) async {
    if (_voicePointerId != event.pointer) return;
    _voicePointerId = null;
    _voicePointerOriginGlobal = null;
    if (!_voiceRecording || _voiceRecordingLocked) return;
    await _handleVoiceRecordingRelease();
  }

  Future<void> _handleComposerPointerCancel(PointerCancelEvent event) async {
    if (_voicePointerId != event.pointer) return;
    _voicePointerId = null;
    _voicePointerOriginGlobal = null;
    if (!_voiceRecording || _voiceRecordingLocked) return;
    await _cancelVoiceRecording();
  }

  Future<void> _handleVoiceRecordingRelease() async {
    if (!_voiceRecording) return;
    if (_voiceRecordingLocked) return;
    if (_voiceSlideCancelArmed) {
      await _cancelVoiceRecording();
      return;
    }
    await _finishVoiceRecording(send: true);
  }

  Future<void> _toggleLockedVoicePause() async {
    if (!_voiceRecording || !_voiceRecordingLocked || _voiceRecorderBusy) {
      return;
    }
    setState(() => _voiceRecorderBusy = true);
    try {
      if (_voiceRecordingPaused) {
        await _voiceRecorder.resume();
        _voiceStopwatch.start();
      } else {
        await _voiceRecorder.pause();
        _voiceStopwatch.stop();
      }
      if (!mounted) return;
      setState(() {
        _voiceRecordingPaused = !_voiceRecordingPaused;
        _voiceRecorderBusy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _voiceRecorderBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ses kaydı güncellenemedi.')),
      );
      turnaLog('voice record pause toggle failed', error);
    }
  }

  Future<void> _cancelVoiceRecording({bool showFeedback = false}) async {
    final path = _voiceRecordingPath;
    _voiceRecordTimer?.cancel();
    _voiceStopwatch.stop();
    try {
      await _voiceRecorder.cancel();
    } catch (error) {
      turnaLog('voice record cancel failed', error);
    }
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _voiceRecorderBusy = false;
      _resetVoiceRecordingState();
    });
    if (showFeedback) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ses kaydı silindi.')));
    }
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    if (_voiceRecorderBusy) return;
    if (mounted) {
      setState(() => _voiceRecorderBusy = true);
    } else {
      _voiceRecorderBusy = true;
    }
    final capturedDuration = _voiceDuration;
    final fallbackPath = _voiceRecordingPath;
    _voiceRecordTimer?.cancel();
    _voiceStopwatch.stop();

    String? resolvedPath;
    try {
      resolvedPath = send ? await _voiceRecorder.stop() : null;
    } catch (error) {
      turnaLog('voice record stop failed', error);
    }

    if (mounted) {
      setState(() {
        _voiceRecorderBusy = false;
        _resetVoiceRecordingState();
      });
    } else {
      _resetVoiceRecordingState();
    }

    final path = resolvedPath ?? fallbackPath;
    if (!send || path == null || path.trim().isEmpty) return;

    if (capturedDuration < _voiceMinDuration) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ses kaydı çok kısa.')));
      }
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ses kaydı bulunamadı.')));
      }
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ses kaydı boş geldi.')));
      }
      return;
    }

    await _sendPickedAttachment(
      kind: ChatAttachmentKind.file,
      fileName: 'sesli-mesaj-${DateTime.now().millisecondsSinceEpoch}.m4a',
      contentType: 'audio/mp4',
      readBytes: () async => bytes,
      sizeBytes: bytes.length,
      durationSeconds: math.max(1, capturedDuration.inSeconds),
    );

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _loadPinnedMessages() async {
    if (!_isGroupChat) return;
    try {
      final items = await ChatApi.fetchPinnedMessages(
        widget.session,
        chatId: widget.chat.chatId,
      );
      if (!mounted) return;
      _client.setPinnedMessages(items);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      turnaLog('chat pinned messages load failed', error);
    }
  }

  Future<void> _refreshPinnedMessagesIfAffected(String messageId) async {
    if (!_isGroupChat) return;
    if (!_client.pinnedMessages.any((item) => item.messageId == messageId)) {
      return;
    }
    await _loadPinnedMessages();
  }

  Future<void> _loadMentionCandidates() async {
    if (!_isGroupChat) return;
    try {
      final page = await ChatApi.fetchGroupMembers(
        widget.session,
        chatId: widget.chat.chatId,
        limit: 120,
      );
      if (!mounted) return;
      setState(() {
        _mentionCandidates = page.items
            .where((item) => item.userId != widget.session.userId)
            .toList();
      });
      _updateMentionSuggestions(_controller.text);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      turnaLog('chat mention candidates load failed', error);
    }
  }

  Future<void> _loadSecurityBannerState() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadySeen = prefs.getBool(_securityBannerSeenKey) == true;
    if (!mounted || alreadySeen) return;
    setState(() => _showSecurityBanner = true);
    await prefs.setBool(_securityBannerSeenKey, true);
  }

  Future<void> _loadLocalMessageState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final starred = prefs.getStringList(_starredMessagesKey) ?? const [];
      final softDeleted =
          prefs.getStringList(_softDeletedMessagesKey) ?? const [];
      final deleted = prefs.getStringList(_deletedMessagesKey) ?? const [];
      if (!mounted) return;
      setState(() {
        _starredMessageIds = starred.toSet();
        _softDeletedMessageIds = softDeleted.toSet();
        _deletedMessageIds = deleted.toSet();
      });
    } catch (error) {
      turnaLog('chat local message state load failed', error);
    }
  }

  Future<void> _persistStarredMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_starredMessagesKey, _starredMessageIds.toList());
  }

  Future<void> _persistSoftDeletedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _softDeletedMessagesKey,
      _softDeletedMessageIds.toList(),
    );
  }

  Future<void> _persistDeletedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_deletedMessagesKey, _deletedMessageIds.toList());
  }

  bool _isMessageDeletedForMe(ChatMessage msg) =>
      _softDeletedMessageIds.contains(msg.id);

  bool _isMessageDeletedPlaceholder(
    ChatMessage msg, {
    ParsedTurnaMessageText? parsed,
  }) => _isMessageDeletedForMe(msg) || (parsed?.deletedForEveryone ?? false);

  bool _canDeleteForEveryone(
    ChatMessage msg, {
    ParsedTurnaMessageText? parsed,
  }) {
    if (msg.senderId != widget.session.userId) return false;
    if (msg.id.startsWith('local_')) return false;
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) return false;
    final createdAt = DateTime.tryParse(msg.createdAt)?.toLocal();
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt) <= const Duration(minutes: 10);
  }

  Future<bool> _showDestructiveConfirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: TurnaColors.error,
                foregroundColor: Colors.white,
              ),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return approved == true;
  }

  void _updateMentionSuggestions(String text) {
    if (!_isGroupChat || !_composerFocusNode.hasFocus) {
      if (_activeMentionQuery != null || _mentionSuggestions.isNotEmpty) {
        setState(() {
          _activeMentionQuery = null;
          _mentionSuggestions = const [];
        });
      }
      return;
    }

    final selection = _controller.selection;
    final safeCursor = selection.isValid
        ? selection.baseOffset.clamp(0, text.length).toInt()
        : text.length;
    final prefix = text.substring(0, safeCursor);
    final match = RegExp(
      r'(?:^|\s)@([a-z0-9._]{0,24})$',
      caseSensitive: false,
    ).firstMatch(prefix);

    if (match == null) {
      if (_activeMentionQuery != null || _mentionSuggestions.isNotEmpty) {
        setState(() {
          _activeMentionQuery = null;
          _mentionSuggestions = const [];
        });
      }
      return;
    }

    final query = (match.group(1) ?? '').trim().toLowerCase();
    final suggestions = _mentionCandidates.where((member) {
      final username = (member.username ?? '').trim().toLowerCase();
      final displayName = member.displayName.trim().toLowerCase();
      if (query.isEmpty) return true;
      return username.startsWith(query) ||
          displayName.startsWith(query) ||
          displayName.contains(query);
    }).take(6).toList();

    final sameQuery = _activeMentionQuery == query;
    final sameSuggestions =
        _mentionSuggestions.length == suggestions.length &&
        _mentionSuggestions.asMap().entries.every(
          (entry) => entry.value.userId == suggestions[entry.key].userId,
        );
    if (sameQuery && sameSuggestions) return;
    if (!mounted) return;
    setState(() {
      _activeMentionQuery = query;
      _mentionSuggestions = suggestions;
    });
  }

  String _mentionInsertTextFor(TurnaGroupMember member) {
    final username = member.username?.trim();
    if (username != null && username.isNotEmpty) {
      return '@$username ';
    }
    final fallback = member.displayName.trim().split(RegExp(r'\s+')).first;
    return '@$fallback ';
  }

  void _insertMentionCandidate(TurnaGroupMember member) {
    final text = _controller.text;
    final selection = _controller.selection;
    final safeCursor = selection.isValid
        ? selection.baseOffset.clamp(0, text.length).toInt()
        : text.length;

    var tokenStart = safeCursor - 1;
    while (tokenStart >= 0 &&
        !RegExp(r'\s').hasMatch(text[tokenStart])) {
      tokenStart -= 1;
    }
    tokenStart += 1;
    if (tokenStart >= text.length || text[tokenStart] != '@') return;

    final replacement = _mentionInsertTextFor(member);
    final nextText =
        '${text.substring(0, tokenStart)}$replacement${text.substring(safeCursor)}';
    final nextCursor = tokenStart + replacement.length;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
    _composerFocusNode.requestFocus();
    _updateMentionSuggestions(nextText);
  }

  String _previewSnippetForMessage(ChatMessage msg) {
    if (_isSystemMessage(msg)) {
      return _systemMessageText(msg);
    }
    final parsed = parseTurnaMessageText(msg.text);
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      return 'Silindi.';
    }
    if (parsed.location != null) {
      return parsed.location!.previewLabel;
    }
    if (parsed.contact != null) {
      return parsed.contact!.previewLabel;
    }
    final text = parsed.text.trim();
    if (text.isNotEmpty) {
      return text.length > 72 ? '${text.substring(0, 72)}...' : text;
    }
    if (msg.attachments.isEmpty) return 'Mesaj';
    final first = msg.attachments.first;
    if (_isAudioAttachment(first)) return 'Ses kaydı';
    if (_isImageAttachment(first)) return 'Fotoğraf';
    if (_isVideoAttachment(first)) return 'Video';
    return 'Dosya';
  }

  TurnaReplyPayload _replyPayloadForMessage(ChatMessage msg) {
    final mine = msg.senderId == widget.session.userId;
    return TurnaReplyPayload(
      messageId: msg.id,
      senderLabel: mine ? 'Siz' : _displaySenderNameFor(msg),
      previewText: _previewSnippetForMessage(msg),
    );
  }

  ChatMessage? _findReplyTargetMessage(String messageId) {
    for (final message in _client.messages) {
      if (message.id == messageId && !_deletedMessageIds.contains(message.id)) {
        return message;
      }
    }
    return null;
  }

  ChatMessage _messageForPinnedSummary(TurnaPinnedMessageSummary summary) {
    return _client.messages.firstWhere(
      (message) => message.id == summary.messageId,
      orElse: () => ChatMessage(
        id: summary.messageId,
        senderId: summary.senderId,
        text: summary.previewText,
        status: ChatMessageStatus.sent,
        createdAt: summary.messageCreatedAt,
        senderDisplayName: summary.senderDisplayName,
        isPinned: true,
      ),
    );
  }

  ChatAttachment? _replyVisualAttachmentForMessage(ChatMessage? message) {
    if (message == null) return null;
    for (final attachment in message.attachments) {
      if (_isImageAttachment(attachment) || _isVideoAttachment(attachment)) {
        return attachment;
      }
    }
    return null;
  }

  String _replySenderLabel(
    TurnaReplyPayload reply, {
    ChatMessage? targetMessage,
  }) {
    if (targetMessage != null) {
      return targetMessage.senderId == widget.session.userId
          ? 'Siz'
          : _displaySenderNameFor(targetMessage);
    }
    final label = reply.senderLabel.trim();
    return label == 'Sen' ? 'Siz' : label;
  }

  bool _isSystemMessage(ChatMessage msg) {
    final systemType = msg.systemType?.trim() ?? '';
    return systemType.isNotEmpty;
  }

  bool _isAdminNoticeMessage(ChatMessage msg) {
    final systemType = (msg.systemType ?? '').trim();
    return systemType == 'admin_notice' || systemType == 'admin_notice_silent';
  }

  String _systemMessageText(ChatMessage msg) {
    switch ((msg.systemType ?? '').trim()) {
      case 'admin_notice':
      case 'admin_notice_silent':
        final payload = msg.systemPayload ?? const <String, dynamic>{};
        final title = (payload['title'] ?? '').toString().trim();
        final text = (payload['text'] ?? msg.text).toString().trim();
        return title.isNotEmpty
            ? title
            : (text.isNotEmpty ? text : 'Bilgi notu');
      case 'group_created':
        final creator = (msg.systemPayload?['createdByDisplayName'] ?? '')
            .toString()
            .trim();
        return creator.isEmpty
            ? 'Grup oluşturuldu'
            : 'Grup oluşturuldu - $creator tarafından';
      case 'group_members_added':
        final raw = msg.systemPayload?['memberNames'];
        final names = raw is List
            ? raw
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty)
                  .toList()
            : const <String>[];
        if (names.isEmpty) return 'Yeni üyeler eklendi';
        if (names.length == 1) return '${names.first} gruba eklendi';
        if (names.length == 2) {
          return '${names.first} ve ${names.last} gruba eklendi';
        }
        return '${names.first} ve ${names.length - 1} kişi daha gruba eklendi';
      case 'group_member_left':
        final member = (msg.systemPayload?['leftByDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Bir üye gruptan ayrıldı'
            : '$member gruptan ayrıldı';
      case 'group_member_removed':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Bir üye gruptan çıkarıldı'
            : '$member gruptan çıkarıldı';
      case 'group_info_updated':
        return 'Grup bilgileri güncellendi';
      case 'group_settings_updated':
        return 'Grup ayarları güncellendi';
      case 'group_role_updated':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        final role = (msg.systemPayload?['roleLabel'] ?? '').toString().trim();
        if (member.isEmpty && role.isEmpty) {
          return 'Üye rolü güncellendi';
        }
        if (member.isEmpty) {
          return 'Rol $role olarak güncellendi';
        }
        if (role.isEmpty) {
          return '$member rolü güncellendi';
        }
        return '$member artık $role';
      case 'group_owner_transferred':
        final member = (msg.systemPayload?['newOwnerDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Grup sahipliği devredildi'
            : 'Grup sahipliği $member kişisine devredildi';
      case 'group_join_request_created':
        return 'Katılım isteği gönderildi';
      case 'group_join_request_approved':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Katılım isteği onaylandı'
            : '$member gruba kabul edildi';
      case 'group_member_muted':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Bir üye sessize alındı'
            : '$member sessize alındı';
      case 'group_member_unmuted':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Sessiz kullanıcı kaldırıldı'
            : '$member tekrar konuşabilir';
      case 'group_member_banned':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Bir üye gruptan yasaklandı'
            : '$member gruptan yasaklandı';
      case 'group_member_unbanned':
        final member = (msg.systemPayload?['memberDisplayName'] ?? '')
            .toString()
            .trim();
        return member.isEmpty
            ? 'Yasak kaldırıldı'
            : '$member yasağı kaldırıldı';
      default:
        return msg.text.trim().isEmpty ? 'Sistem mesajı' : msg.text.trim();
    }
  }

  IconData _adminNoticeIcon(ChatMessage msg) {
    final icon = (msg.systemPayload?['icon'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    switch (icon) {
      case 'lock':
        return Icons.lock_rounded;
      case 'megaphone':
        return Icons.campaign_rounded;
      case 'shield':
        return Icons.shield_moon_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'sparkles':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  ({Color background, Color border, Color foreground}) _adminNoticeColors(
    ChatMessage msg,
  ) {
    final icon = (msg.systemPayload?['icon'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    switch (icon) {
      case 'lock':
        return (
          background: const Color(0xFFFFF3D6),
          border: const Color(0xFFF1D493),
          foreground: const Color(0xFF6E5617),
        );
      case 'megaphone':
        return (
          background: const Color(0xFFEAF4FF),
          border: const Color(0xFFB9D8FF),
          foreground: const Color(0xFF245E9C),
        );
      case 'shield':
        return (
          background: const Color(0xFFEAF5EF),
          border: const Color(0xFFB9DEC8),
          foreground: const Color(0xFF2A6B47),
        );
      case 'warning':
        return (
          background: const Color(0xFFFFEFE5),
          border: const Color(0xFFF5C9AF),
          foreground: const Color(0xFF9B4A19),
        );
      case 'sparkles':
        return (
          background: const Color(0xFFF6EEFF),
          border: const Color(0xFFD8C5F4),
          foreground: const Color(0xFF69469D),
        );
      default:
        return (
          background: const Color(0xFFF1F4F8),
          border: const Color(0xFFD6DEE8),
          foreground: const Color(0xFF526271),
        );
    }
  }

  Widget _buildAdminNoticeBubble(ChatMessage msg) {
    final payload = msg.systemPayload ?? const <String, dynamic>{};
    final title = (payload['title'] ?? '').toString().trim();
    final text = (payload['text'] ?? msg.text).toString().trim();
    final colors = _adminNoticeColors(msg);
    final hasTitle = title.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 304),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              crossAxisAlignment: hasTitle
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: colors.foreground.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _adminNoticeIcon(msg),
                    size: 14,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: hasTitle
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.foreground,
                              ),
                            ),
                            if (text.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                text,
                                style: TextStyle(
                                  fontSize: 12.35,
                                  height: 1.3,
                                  fontWeight: FontWeight.w500,
                                  color: colors.foreground,
                                ),
                              ),
                            ],
                          ],
                        )
                      : Text(
                          text.isNotEmpty ? text : 'Bilgi notu',
                          style: TextStyle(
                            fontSize: 12.35,
                            height: 1.28,
                            fontWeight: FontWeight.w600,
                            color: colors.foreground,
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

  String _displaySenderNameFor(ChatMessage msg) {
    final raw = (msg.senderDisplayName ?? '').trim();
    if (raw.isNotEmpty) return raw;
    if (msg.senderId == widget.session.userId) return 'Siz';
    return _chatDisplayName;
  }

  bool _canEditMessage(ChatMessage msg, {ParsedTurnaMessageText? parsed}) {
    final resolved = parsed ?? parseTurnaMessageText(msg.text);
    if (msg.senderId != widget.session.userId) return false;
    if (_isMessageDeletedPlaceholder(msg, parsed: resolved)) return false;
    if (resolved.text.trim().isEmpty) return false;
    final createdAt = parseTurnaLocalDateTime(msg.createdAt);
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt).inMinutes < 10;
  }

  void _startEditingMessage(ChatMessage msg, ParsedTurnaMessageText parsed) {
    final visibleText = parsed.text.trim();
    setState(() {
      _replyDraft = null;
      _editingDraft = _ComposerEditDraft(
        messageId: msg.id,
        reply: parsed.reply,
        originalText: visibleText,
      );
      _controller.value = TextEditingValue(
        text: visibleText,
        selection: TextSelection.collapsed(offset: visibleText.length),
      );
    });
    _composerFocusNode.requestFocus();
  }

  void _cancelEditingMessage() {
    if (_editingDraft == null) return;
    setState(() {
      _editingDraft = null;
      _controller.clear();
    });
  }

  Future<File> _downloadAttachmentFile(ChatAttachment attachment) async {
    final url = attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      throw TurnaApiException('Ek için link bulunamadı.');
    }

    final cachedFile = await TurnaLocalMediaCache.getOrDownloadFile(
      cacheKey: 'attachment:${attachment.objectKey}',
      url: url,
      authToken: widget.session.token,
    );
    if (cachedFile != null) {
      return cachedFile;
    }

    throw TurnaApiException('Ek indirilemedi.');
  }

  Future<List<int>> _downloadAttachmentBytes(ChatAttachment attachment) async {
    final file = await _downloadAttachmentFile(attachment);
    return file.readAsBytes();
  }

  Future<void> _saveAttachmentToDevice(ChatAttachment attachment) async {
    try {
      final file = await _downloadAttachmentFile(attachment);
      await TurnaMediaBridge.saveToGallery(
        path: file.path,
        mimeType: attachment.contentType,
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

  List<ChatGalleryMediaItem> _buildMediaGalleryItems() {
    final items = <ChatGalleryMediaItem>[];
    for (final message in _currentDisplayMessages()) {
      final parsed = parseTurnaMessageText(message.text);
      if (_isMessageDeletedPlaceholder(message, parsed: parsed)) continue;
      for (final attachment in message.attachments) {
        if (!_isImageAttachment(attachment) &&
            !_isVideoAttachment(attachment)) {
          continue;
        }
        final url = attachment.url?.trim() ?? '';
        if (url.isEmpty) continue;
        items.add(
          ChatGalleryMediaItem(
            message: message,
            attachment: attachment,
            senderLabel: message.senderId == widget.session.userId
                ? 'Siz'
                : _displaySenderNameFor(message),
            cacheKey: 'attachment:${attachment.objectKey}',
            url: url,
          ),
        );
      }
    }
    return items;
  }

  Future<void> _forwardMessage(ChatMessage msg) async {
    final targetChat = await Navigator.push<ChatPreview>(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardMessagePickerPage(
          session: widget.session,
          currentChatId: widget.chat.chatId,
        ),
      ),
    );
    if (!mounted || targetChat == null) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('${targetChat.name} sohbetine iletiliyor...')),
    );

    try {
      final parsed = parseTurnaMessageText(msg.text);
      final drafts = <OutgoingAttachmentDraft>[];
      for (final attachment in msg.attachments) {
        final bytes = await _downloadAttachmentBytes(attachment);
        final upload = await ChatApi.createAttachmentUpload(
          widget.session,
          chatId: targetChat.chatId,
          kind: attachment.kind,
          contentType: attachment.contentType,
          fileName: attachment.fileName ?? 'dosya',
        );
        final uploadRes = await http.put(
          Uri.parse(upload.uploadUrl),
          headers: upload.headers,
          body: bytes,
        );
        if (uploadRes.statusCode >= 400) {
          throw TurnaApiException('İletilecek ek yüklenemedi.');
        }
        drafts.add(
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: attachment.kind,
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            sizeBytes: attachment.sizeBytes > 0
                ? attachment.sizeBytes
                : bytes.length,
            width: attachment.width,
            height: attachment.height,
            durationSeconds: attachment.durationSeconds,
          ),
        );
      }

      await ChatApi.sendMessage(
        widget.session,
        chatId: targetChat.chatId,
        text: parsed.text.trim().isEmpty ? null : parsed.text.trim(),
        attachments: drafts,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${targetChat.name} sohbetine iletildi.')),
        );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleStarMessage(ChatMessage msg) async {
    final next = Set<String>.from(_starredMessageIds);
    final nowStarred = !next.contains(msg.id);
    if (nowStarred) {
      next.add(msg.id);
    } else {
      next.remove(msg.id);
    }
    setState(() => _starredMessageIds = next);
    await _persistStarredMessages();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nowStarred ? 'Mesaja yıldız eklendi.' : 'Yıldız kaldırıldı.',
        ),
      ),
    );
  }

  Future<void> _deleteMessageLocally(ChatMessage msg) async {
    final next = Set<String>.from(_deletedMessageIds)..add(msg.id);
    final nextStarred = Set<String>.from(_starredMessageIds)..remove(msg.id);
    final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
      ..remove(msg.id);
    setState(() {
      _deletedMessageIds = next;
      _starredMessageIds = nextStarred;
      _softDeletedMessageIds = nextSoftDeleted;
      if (_editingDraft?.messageId == msg.id) {
        _editingDraft = null;
        _controller.clear();
      }
    });
    await _persistSoftDeletedMessages();
    await _persistDeletedMessages();
    await _persistStarredMessages();
    await _refreshPinnedMessagesIfAffected(msg.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mesaj bu cihazdan silindi.')));
  }

  Future<void> _deleteMessageForMe(ChatMessage msg) async {
    final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
      ..add(msg.id);
    final nextStarred = Set<String>.from(_starredMessageIds)..remove(msg.id);
    setState(() {
      _softDeletedMessageIds = nextSoftDeleted;
      _starredMessageIds = nextStarred;
      if (_editingDraft?.messageId == msg.id) {
        _editingDraft = null;
        _controller.clear();
      }
    });
    await _persistSoftDeletedMessages();
    await _persistStarredMessages();
    await _refreshPinnedMessagesIfAffected(msg.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mesaj sende Silindi. olarak gösteriliyor.'),
      ),
    );
  }

  Future<void> _deleteMessageForEveryone(ChatMessage msg) async {
    try {
      final updated = await ChatApi.deleteMessageForEveryone(
        widget.session,
        messageId: msg.id,
      );
      final nextSoftDeleted = Set<String>.from(_softDeletedMessageIds)
        ..remove(msg.id);
      if (mounted) {
        setState(() {
          _softDeletedMessageIds = nextSoftDeleted;
          if (_editingDraft?.messageId == msg.id) {
            _editingDraft = null;
            _controller.clear();
          }
        });
      }
      await _persistSoftDeletedMessages();
      await _refreshPinnedMessagesIfAffected(msg.id);
      _client.mergeServerMessage(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mesaj herkesten silindi.')));
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _confirmRemoveDeletedPlaceholder(ChatMessage msg) async {
    final confirmed = await _showDestructiveConfirm(
      title: 'Mesajı kaldır',
      message: 'Bu Silindi. mesajı cihazından tamamen kaldırılsın mı?',
      confirmLabel: 'Kaldır',
    );
    if (!confirmed) return;
    await _deleteMessageLocally(msg);
  }

  Future<void> _showDeleteMessageOptions(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    final canDeleteForEveryone = _canDeleteForEveryone(msg, parsed: parsed);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Benden sil'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final confirmed = await _showDestructiveConfirm(
                    title: 'Mesajı senden sil',
                    message:
                        'Bu mesaj sadece senin tarafında Silindi. olarak gösterilecek.',
                    confirmLabel: 'Benden sil',
                  );
                  if (!confirmed) return;
                  await _deleteMessageForMe(msg);
                },
              ),
              if (canDeleteForEveryone)
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Herkesten sil'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirmed = await _showDestructiveConfirm(
                      title: 'Mesajı herkesten sil',
                      message:
                          'Bu mesaj iki taraf için de Silindi. olarak değişecek.',
                      confirmLabel: 'Herkesten sil',
                    );
                    if (!confirmed) return;
                    await _deleteMessageForEveryone(msg);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _translateMessage(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    final text = parsed.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çevrilecek metin bulunamadı.')),
      );
      return;
    }

    final uri = Uri.parse(
      'https://translate.google.com/?sl=auto&tl=tr&text=${Uri.encodeComponent(text)}&op=translate',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Çeviri açılamadı.')));
    }
  }

  Future<void> _reportMessage(ChatMessage msg) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        const reasons = ['Spam', 'Taciz', 'Uygunsuz içerik', 'Sahte hesap'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final reason in reasons)
                ListTile(
                  title: Text(reason),
                  onTap: () => Navigator.pop(sheetContext, reason),
                ),
            ],
          ),
        );
      },
    );

    if (reason == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Şikayet kaydedildi: $reason')));
  }

  String _messageStatusLabel(ChatMessageStatus status) {
    return switch (status) {
      ChatMessageStatus.sending => 'Gönderiliyor',
      ChatMessageStatus.queued => 'Kuyrukta',
      ChatMessageStatus.failed => 'Hatalı',
      ChatMessageStatus.sent => 'Gönderildi',
      ChatMessageStatus.delivered => 'Teslim edildi',
      ChatMessageStatus.read => 'Okundu',
    };
  }

  String _messageTypeLabel(ChatMessage msg, ParsedTurnaMessageText parsed) {
    if (parsed.location != null) {
      return parsed.location!.live ? 'Canlı konum' : 'Konum';
    }
    if (parsed.contact != null) return 'Kişi';
    if (msg.attachments.isNotEmpty) {
      final first = msg.attachments.first;
      if (_isAudioAttachment(first)) return 'Ses kaydı';
      if (_isImageAttachment(first)) return 'Fotoğraf';
      if (_isVideoAttachment(first)) return 'Video';
      return 'Belge';
    }
    return 'Mesaj';
  }

  Future<void> _showMessageInfo(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    final totalBytes = msg.attachments.fold<int>(
      0,
      (total, item) => total + math.max(0, item.sizeBytes),
    );
    final detailRows = <MapEntry<String, String>>[
      MapEntry('Tür', _messageTypeLabel(msg, parsed)),
      MapEntry(
        'Tarih',
        '${_formatDayLabel(msg.createdAt)} ${_formatMessageTime(msg.createdAt)}',
      ),
      MapEntry('Durum', _messageStatusLabel(msg.status)),
      if (msg.attachments.isNotEmpty)
        MapEntry('Ek sayısı', '${msg.attachments.length}'),
      if (totalBytes > 0) MapEntry('Boyut', _formatFileSize(totalBytes)),
      if (msg.attachments.length == 1 &&
          _isAudioAttachment(msg.attachments.first) &&
          (msg.attachments.first.durationSeconds ?? 0) > 0)
        MapEntry(
          'Süre',
          _formatVoiceDuration(
            Duration(seconds: msg.attachments.first.durationSeconds!),
          ),
        ),
      if (msg.isEdited && (msg.editedAt?.trim().isNotEmpty ?? false))
        MapEntry(
          'Düzenlendi',
          '${_formatDayLabel(msg.editedAt!)} ${_formatMessageTime(msg.editedAt!)}',
        ),
    ];

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mesaj bilgisi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final row in detailRows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 88,
                          child: Text(
                            row.key,
                            style: const TextStyle(
                              color: TurnaColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.value,
                            style: const TextStyle(
                              color: TurnaColors.text,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const List<String> _reactionOptions = <String>[
    '👍',
    '❤️',
    '😂',
    '🔥',
    '👏',
    '😮',
    '😢',
    '🙏',
  ];

  bool _messageHasMyReaction(ChatMessage msg, String emoji) {
    return msg.reactions.any(
      (reaction) =>
          reaction.emoji == emoji &&
          reaction.userIds.contains(widget.session.userId),
    );
  }

  Future<void> _toggleReaction(ChatMessage msg, String emoji) async {
    try {
      final updated = _messageHasMyReaction(msg, emoji)
          ? await ChatApi.removeReaction(
              widget.session,
              messageId: msg.id,
              emoji: emoji,
            )
          : await ChatApi.addReaction(
              widget.session,
              messageId: msg.id,
              emoji: emoji,
            );
      _client.mergeServerMessage(updated);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showReactionPicker(ChatMessage msg) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tepki sec',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _reactionOptions.map((emoji) {
                    final selected = _messageHasMyReaction(msg, emoji);
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _toggleReaction(msg, emoji);
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? TurnaColors.primary50
                              : TurnaColors.backgroundMuted,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : TurnaColors.border,
                          ),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _togglePinnedMessage(ChatMessage msg) async {
    if (!_isGroupChat) return;
    final isPinned = msg.isPinned ||
        _client.pinnedMessages.any((item) => item.messageId == msg.id);
    try {
      if (isPinned) {
        await ChatApi.unpinMessage(widget.session, messageId: msg.id);
      } else {
        await ChatApi.pinMessage(widget.session, messageId: msg.id);
      }
      await _loadPinnedMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPinned ? 'Sabit mesaj kaldırıldı.' : 'Mesaj sabitlendi.',
          ),
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
    }
  }

  Future<void> _openPinnedMessagesSheet() async {
    final pinnedMessages = _client.pinnedMessages;
    if (pinnedMessages.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sabit mesajlar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: math.min(
                    MediaQuery.of(sheetContext).size.height * 0.48,
                    math.max(88, pinnedMessages.length * 78).toDouble(),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: pinnedMessages.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: TurnaColors.divider),
                    itemBuilder: (context, index) {
                      final item = pinnedMessages[index];
                      final pinnedBy =
                          (item.pinnedByDisplayName ?? '').trim().isNotEmpty
                          ? item.pinnedByDisplayName!.trim()
                          : 'Birisi';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.push_pin_rounded,
                          color: TurnaColors.primary,
                        ),
                        title: Text(
                          item.previewText.trim().isEmpty
                              ? 'Sabit mesaj'
                              : item.previewText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$pinnedBy · ${_formatMessageTime(item.pinnedAt)}',
                        ),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _scrollToReplyTarget(item.messageId);
                        },
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
  }

  Future<void> _showMoreMessageActions(ChatMessage msg) async {
    final parsed = parseTurnaMessageText(msg.text);
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      await _confirmRemoveDeletedPlaceholder(msg);
      return;
    }
    final isPinned = msg.isPinned ||
        _client.pinnedMessages.any((item) => item.messageId == msg.id);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isGroupChat)
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  ),
                  title: Text(isPinned ? 'Sabitlemeyi kaldır' : 'Sabitle'),
                  onTap: !_canManagePinnedMessages
                      ? null
                      : () async {
                          Navigator.pop(sheetContext);
                          await _togglePinnedMessage(msg);
                        },
                ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('Tepki ver'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReactionPicker(msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.translate_rounded),
                title: const Text('Cevir'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _translateMessage(msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Şikayet Et'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _reportMessage(msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Sil'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteMessageOptions(msg);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleMessageLongPress(
    ChatMessage msg, {
    ChatAttachment? attachment,
  }) async {
    final parsed = parseTurnaMessageText(msg.text);
    if (_isMessageDeletedPlaceholder(msg, parsed: parsed)) {
      await _confirmRemoveDeletedPlaceholder(msg);
      return;
    }
    final replyPayload = _replyPayloadForMessage(msg);
    final isStarred = _starredMessageIds.contains(msg.id);
    final textOnly = parsed.text.trim();
    final canEdit = _canEditMessage(msg, parsed: parsed);
    final visualAttachment =
        attachment != null &&
            (_isImageAttachment(attachment) || _isVideoAttachment(attachment))
        ? attachment
        : msg.attachments.cast<ChatAttachment?>().firstWhere(
            (item) =>
                item != null &&
                (_isImageAttachment(item) || _isVideoAttachment(item)),
            orElse: () => null,
          );
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    _MessageQuickAction(
                      icon: Icons.emoji_emotions_outlined,
                      label: 'Tepki',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showReactionPicker(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.reply_rounded,
                      label: 'Cevapla',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() {
                          _editingDraft = null;
                          _replyDraft = replyPayload;
                        });
                        _composerFocusNode.requestFocus();
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.forward_rounded,
                      label: 'Ilet',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _forwardMessage(msg);
                      },
                    ),
                    if (canEdit)
                      _MessageQuickAction(
                        icon: Icons.edit_outlined,
                        label: 'Duzenle',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _startEditingMessage(msg, parsed);
                        },
                      ),
                    _MessageQuickAction(
                      icon: Icons.copy_all_outlined,
                      label: 'Kopyala',
                      enabled: textOnly.isNotEmpty,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await Clipboard.setData(ClipboardData(text: textOnly));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Mesaj kopyalandi.')),
                        );
                      },
                    ),
                    _MessageQuickAction(
                      icon: isStarred
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      label: isStarred ? 'Yıldızı kaldır' : 'Yıldız ekle',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _toggleStarMessage(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.info_outline_rounded,
                      label: 'Bilgi',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showMessageInfo(msg);
                      },
                    ),
                    if (visualAttachment != null)
                      _MessageQuickAction(
                        icon: Icons.download_rounded,
                        label: 'Kaydet',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _saveAttachmentToDevice(visualAttachment);
                        },
                      ),
                    _MessageQuickAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Sil',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showDeleteMessageOptions(msg);
                      },
                    ),
                    _MessageQuickAction(
                      icon: Icons.more_horiz_rounded,
                      label: 'Daha fazla',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showMoreMessageActions(msg);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isSameMessageGroup(
    List<_ChatTimelineEntry> displayEntries,
    int currentIndex,
    int neighborIndex,
  ) {
    if (neighborIndex < 0 || neighborIndex >= displayEntries.length) {
      return false;
    }
    final currentEntry = displayEntries[currentIndex];
    final neighborEntry = displayEntries[neighborIndex];
    final current = currentEntry.message;
    final neighbor = neighborEntry.message;
    if (current == null || neighbor == null) return false;
    if (current.senderId != neighbor.senderId) return false;
    final currentDate = parseTurnaLocalDateTime(current.createdAt);
    final neighborDate = parseTurnaLocalDateTime(neighbor.createdAt);
    if (currentDate == null || neighborDate == null) return false;
    return currentDate.year == neighborDate.year &&
        currentDate.month == neighborDate.month &&
        currentDate.day == neighborDate.day;
  }

  EdgeInsets _bubbleMarginFor(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    bool mine,
  ) {
    final joinsOlder = _isSameMessageGroup(displayEntries, index, index + 1);
    final joinsNewer = _isSameMessageGroup(displayEntries, index, index - 1);
    return EdgeInsets.only(
      left: mine ? 56 : 8,
      right: mine ? 8 : 56,
      top: joinsOlder ? TurnaChatTokens.stackGap / 2 : TurnaChatTokens.groupGap,
      bottom: joinsNewer
          ? TurnaChatTokens.stackGap / 2
          : TurnaChatTokens.groupGap / 2,
    );
  }

  List<ChatMessage> _currentDisplayMessages() => _client.messages.reversed
      .where((message) => !_deletedMessageIds.contains(message.id))
      .toList();

  List<_ChatTimelineEntry> _buildTimelineEntries() {
    final entries = <_ChatTimelineEntry>[
      ..._currentDisplayMessages().map(_ChatTimelineEntry.message),
      ..._peerCalls.map(_ChatTimelineEntry.call),
    ];
    entries.sort(
      (a, b) =>
          compareTurnaTimestamps(_timelineCreatedAt(b), _timelineCreatedAt(a)),
    );
    return entries;
  }

  GlobalKey _messageKeyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, GlobalKey.new);

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    return completer.future;
  }

  void _highlightMessage(String messageId) {
    _messageHighlightTimer?.cancel();
    if (mounted) {
      setState(() => _highlightedMessageId = messageId);
    }
    _messageHighlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || _highlightedMessageId != messageId) return;
      setState(() => _highlightedMessageId = null);
    });
  }

  Future<void> _scrollToReplyTarget(String messageId) async {
    var displayMessages = _currentDisplayMessages();
    var targetIndex = displayMessages.indexWhere(
      (message) => message.id == messageId,
    );

    var loadAttempt = 0;
    while (targetIndex == -1 && _client.hasMore && loadAttempt < 8) {
      await _client.loadOlderMessages();
      loadAttempt += 1;
      await _waitForNextFrame();
      displayMessages = _currentDisplayMessages();
      targetIndex = displayMessages.indexWhere(
        (message) => message.id == messageId,
      );
    }

    if (targetIndex == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yanıtlanan mesaj bulunamadı.')),
      );
      return;
    }

    _highlightMessage(messageId);
    await _waitForNextFrame();
    if (!mounted) return;

    var targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext != null) {
      if (!targetContext.mounted) return;
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.34,
      );
      return;
    }

    if (!_scrollController.hasClients) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final ratio = displayMessages.length <= 1
        ? 0.0
        : targetIndex / (displayMessages.length - 1);
    final viewport = _scrollController.position.viewportDimension;
    final offsets = <double>[
      (maxExtent * ratio).clamp(0.0, maxExtent).toDouble(),
      (maxExtent * ratio + viewport * 0.5).clamp(0.0, maxExtent).toDouble(),
    ];

    for (final offset in offsets) {
      await _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      await _waitForNextFrame();
      if (!mounted) return;
      targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null) {
        if (!targetContext.mounted) return;
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.34,
        );
        return;
      }
    }
  }

  Future<void> _handleSendPressed() async {
    if (_attachmentBusy) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final editingDraft = _editingDraft;
    if (editingDraft != null) {
      final outboundText = editingDraft.reply == null
          ? text
          : buildTurnaReplyEncodedText(reply: editingDraft.reply!, text: text);
      try {
        final updated = await ChatApi.editMessage(
          widget.session,
          messageId: editingDraft.messageId,
          text: outboundText,
        );
        _client.mergeServerMessage(updated);
        await _refreshPinnedMessagesIfAffected(updated.id);
        if (!mounted) return;
        setState(() => _editingDraft = null);
        _controller.clear();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Mesaj duzenlendi.')));
        return;
      } on TurnaUnauthorizedException {
        if (!mounted) return;
        widget.onSessionExpired();
        return;
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        return;
      }
    }

    final outboundText = _replyDraft == null
        ? text
        : buildTurnaReplyEncodedText(reply: _replyDraft!, text: text);
    _client.send(outboundText);
    TurnaAnalytics.logEvent('message_sent', {
      'chat_id': widget.chat.chatId,
      'kind': 'text',
    });
    _controller.clear();
    if (mounted) {
      setState(() => _replyDraft = null);
    }
    _jumpToBottom();
  }

  String _formatCallTimelineSubtitle(TurnaCallHistoryItem item) {
    final duration = item.durationSeconds;
    if (duration != null && duration > 0) {
      final hours = duration ~/ 3600;
      final minutes = (duration % 3600) ~/ 60;
      final seconds = duration % 60;
      if (hours > 0) {
        return minutes > 0 ? '$hours sa $minutes dk' : '$hours sa';
      }
      if (minutes > 0) return '$minutes dk';
      return '$seconds sn';
    }

    switch (item.status) {
      case TurnaCallStatus.declined:
        return 'Reddedildi';
      case TurnaCallStatus.missed:
        return 'Cevapsız';
      case TurnaCallStatus.cancelled:
        return 'İptal edildi';
      case TurnaCallStatus.ringing:
        return 'Caliyor';
      case TurnaCallStatus.accepted:
      case TurnaCallStatus.ended:
        return 'Baglandi';
    }
  }

  Widget _buildCallBubble(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    TurnaCallHistoryItem item,
  ) {
    final mine = item.direction == 'outgoing';
    final bubbleColor = mine
        ? TurnaColors.chatOutgoing.withValues(alpha: 0.14)
        : TurnaColors.chatIncoming;
    final iconBackground = mine
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white;
    final iconColor = item.status == TurnaCallStatus.missed
        ? TurnaColors.error
        : mine
        ? TurnaColors.chatOutgoingText
        : TurnaColors.primary;
    final textColor = mine ? TurnaColors.text : TurnaColors.chatIncomingText;
    final title = item.type == TurnaCallType.video
        ? 'Goruntulu arama'
        : 'Sesli arama';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
              TurnaChatTokens.messageMaxWidthFactor,
        ),
        margin: _bubbleMarginFor(displayEntries, index, mine),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(TurnaChatTokens.bubbleRadius),
            topRight: const Radius.circular(TurnaChatTokens.bubbleRadius),
            bottomLeft: Radius.circular(
              mine
                  ? TurnaChatTokens.bubbleRadiusTail
                  : TurnaChatTokens.bubbleRadius,
            ),
            bottomRight: Radius.circular(
              mine
                  ? TurnaChatTokens.bubbleRadius
                  : TurnaChatTokens.bubbleRadiusTail,
            ),
          ),
          boxShadow: const [TurnaColors.shadowBubble],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                item.type == TurnaCallType.video
                    ? Icons.videocam_rounded
                    : Icons.call_rounded,
                color: iconColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 44),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          _formatCallTimelineSubtitle(item),
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.82),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatMessageTime(
                          item.createdAt ??
                              item.endedAt ??
                              item.acceptedAt ??
                              '',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: textColor.withValues(alpha: 0.68),
                        ),
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

  Widget _buildSystemMessageBubble(ChatMessage msg) {
    if (_isAdminNoticeMessage(msg)) {
      return _buildAdminNoticeBubble(msg);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: TurnaColors.backgroundMuted,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: TurnaColors.divider),
          ),
          child: Text(
            _systemMessageText(msg),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: TurnaColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityBanner() {
    final message = _isGroupChat
        ? 'Mesajlar ve aramalar uçtan uca şifrelidir. Yalnızca bu gruptaki kişiler bu içerikleri okuyabilir, dinleyebilir veya paylaşabilir.'
        : 'Mesajlar ve aramalar uçtan uca şifrelidir. Yalnızca bu sohbetteki kişiler bu içerikleri okuyabilir, dinleyebilir veya paylaşabilir.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1D493)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_rounded, size: 16, color: Color(0xFF6E5617)),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Color(0xFF6E5617),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    List<_ChatTimelineEntry> displayEntries,
    int index,
    ChatMessage msg,
    bool mine,
  ) {
    if (_isSystemMessage(msg)) {
      return _buildSystemMessageBubble(msg);
    }
    final parsed = parseTurnaMessageText(msg.text);
    final isDeletedPlaceholder = _isMessageDeletedPlaceholder(
      msg,
      parsed: parsed,
    );
    final isPinnedMessage = msg.isPinned ||
        _client.pinnedMessages.any((item) => item.messageId == msg.id);
    final displayText = isDeletedPlaceholder ? 'Silindi.' : parsed.text.trim();
    final locationPayload = isDeletedPlaceholder ? null : parsed.location;
    final contactPayload = isDeletedPlaceholder ? null : parsed.contact;
    final visibleAttachments = isDeletedPlaceholder
        ? const <ChatAttachment>[]
        : msg.attachments;
    final hasText = displayText.isNotEmpty;
    final hasLocation = locationPayload != null;
    final hasContact = contactPayload != null;
    final hasSingleAudioAttachment =
        visibleAttachments.length == 1 &&
        _isAudioAttachment(visibleAttachments.first);
    final hasSingleVisualAttachment =
        visibleAttachments.length == 1 &&
        !_isAudioAttachment(visibleAttachments.first) &&
        visibleAttachments.first.kind != ChatAttachmentKind.file;
    final hasError =
        !isDeletedPlaceholder &&
        msg.errorText != null &&
        msg.errorText!.trim().isNotEmpty;
    final sharedLinks = hasText ? extractTurnaUrls(displayText) : const <Uri>[];
    final primaryLinkUri = sharedLinks.isEmpty ? null : sharedLinks.first;
    final linkCaptionText = primaryLinkUri == null
        ? displayText
        : _stripLinksFromText(displayText);
    final showLinkPreview =
        primaryLinkUri != null &&
        !hasLocation &&
        !hasContact &&
        visibleAttachments.isEmpty &&
        !hasError;
    final previewUri = showLinkPreview ? primaryLinkUri : null;
    final showTextBlock =
        hasText && (!showLinkPreview || linkCaptionText.isNotEmpty);
    final useEmbeddedMediaBubble =
        !hasText &&
        !hasError &&
        parsed.reply == null &&
        (locationPayload != null ||
            contactPayload != null ||
            hasSingleVisualAttachment ||
            hasSingleAudioAttachment);
    final isHighlighted = _highlightedMessageId == msg.id;
    final footer = _MessageMetaFooter(
      timeLabel: _formatMessageTime(msg.createdAt),
      mine: mine,
      status: msg.status,
      edited: msg.isEdited,
      starred: _starredMessageIds.contains(msg.id),
    );
    final embeddedFooter = _MessageMetaFooter(
      timeLabel: _formatMessageTime(msg.createdAt),
      mine: mine,
      status: msg.status,
      edited: msg.isEdited,
      starred: _starredMessageIds.contains(msg.id),
      overlay: true,
    );
    final embeddedFooterPlain = _MessageMetaFooter(
      timeLabel: _formatMessageTime(msg.createdAt),
      mine: mine,
      status: msg.status,
      edited: msg.isEdited,
      starred: _starredMessageIds.contains(msg.id),
      overlay: true,
      showOverlayBackground: false,
    );
    final bubbleColor = mine
        ? (_isGroupChat ? const Color(0xFFD7F3E0) : TurnaColors.chatOutgoing)
        : TurnaColors.chatIncoming;
    final resolvedBubbleColor = isHighlighted
        ? Color.alphaBlend(
            TurnaColors.accent.withValues(alpha: mine ? 0.18 : 0.12),
            bubbleColor,
          )
        : bubbleColor;
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(TurnaChatTokens.bubbleRadius),
      topRight: const Radius.circular(TurnaChatTokens.bubbleRadius),
      bottomLeft: Radius.circular(
        mine ? TurnaChatTokens.bubbleRadiusTail : TurnaChatTokens.bubbleRadius,
      ),
      bottomRight: Radius.circular(
        mine ? TurnaChatTokens.bubbleRadius : TurnaChatTokens.bubbleRadiusTail,
      ),
    );
    final bubbleBorder = msg.status == ChatMessageStatus.failed
        ? Border.all(color: Colors.red.shade200)
        : isHighlighted
        ? Border.all(
            color: TurnaColors.accentStrong.withValues(alpha: 0.72),
            width: 1.2,
          )
        : null;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _handleMessageLongPress(msg),
        onTap: isDeletedPlaceholder
            ? () => _confirmRemoveDeletedPlaceholder(msg)
            : mine &&
                  (msg.status == ChatMessageStatus.failed ||
                      msg.status == ChatMessageStatus.queued)
            ? () => _client.retryMessage(msg)
            : null,
        child: AnimatedContainer(
          key: _messageKeyFor(msg.id),
          duration: const Duration(milliseconds: 180),
          constraints: BoxConstraints(
            maxWidth:
                MediaQuery.of(context).size.width *
                TurnaChatTokens.messageMaxWidthFactor,
          ),
          margin: _bubbleMarginFor(displayEntries, index, mine),
          padding: useEmbeddedMediaBubble
              ? EdgeInsets.zero
              : EdgeInsets.fromLTRB(
                  12,
                  9,
                  12,
                  msg.attachments.isEmpty && !hasError ? 8 : 10,
                ),
          decoration: BoxDecoration(
            color: useEmbeddedMediaBubble
                ? Colors.transparent
                : resolvedBubbleColor,
            borderRadius: bubbleRadius,
            border: useEmbeddedMediaBubble ? null : bubbleBorder,
            boxShadow: [
              if (!useEmbeddedMediaBubble)
                mine
                    ? TurnaColors.shadowBubble
                    : const BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, 1),
                      ),
              if (isHighlighted)
                BoxShadow(
                  color: TurnaColors.accent.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 0),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isGroupChat && !mine) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _displaySenderNameFor(msg),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: TurnaColors.primary,
                    ),
                  ),
                ),
              ],
              if (isPinnedMessage)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.push_pin_rounded,
                        size: 12,
                        color: TurnaColors.primary,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Sabitlendi',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: TurnaColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              if (hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    msg.errorText!,
                    style: TextStyle(
                      fontSize: 11,
                      color: msg.status == ChatMessageStatus.failed
                          ? TurnaColors.error
                          : TurnaColors.textMuted,
                    ),
                  ),
                ),
              if (parsed.reply != null && !isDeletedPlaceholder) ...[
                Builder(
                  builder: (context) {
                    final replyTarget = _findReplyTargetMessage(
                      parsed.reply!.messageId,
                    );
                    return _ReplySnippetCard(
                      reply: parsed.reply!,
                      mine: mine,
                      senderLabel: _replySenderLabel(
                        parsed.reply!,
                        targetMessage: replyTarget,
                      ),
                      repliedToCurrentUser: replyTarget != null
                          ? replyTarget.senderId == widget.session.userId
                          : parsed.reply!.senderLabel.trim() == 'Sen' ||
                                parsed.reply!.senderLabel.trim() == 'Siz',
                      previewAttachment: _replyVisualAttachmentForMessage(
                        replyTarget,
                      ),
                      authToken: widget.session.token,
                      onTap: () =>
                          _scrollToReplyTarget(parsed.reply!.messageId),
                    );
                  },
                ),
                if (hasText ||
                    hasLocation ||
                    hasContact ||
                    visibleAttachments.isNotEmpty)
                  const SizedBox(height: 8),
              ],
              if (visibleAttachments.isNotEmpty) ...[
                _ChatAttachmentList(
                  attachments: visibleAttachments,
                  mine: mine,
                  onTap: (attachment) {
                    if (_isImageAttachment(attachment) ||
                        _isVideoAttachment(attachment)) {
                      return _openMediaAttachment(msg, attachment);
                    }
                    return _openAttachment(attachment);
                  },
                  formatFileSize: _formatFileSize,
                  authToken: widget.session.token,
                  onLongPress: (attachment) =>
                      _handleMessageLongPress(msg, attachment: attachment),
                  overlayFooter: useEmbeddedMediaBubble ? embeddedFooter : null,
                  audioOverlayFooter: useEmbeddedMediaBubble
                      ? embeddedFooterPlain
                      : null,
                ),
                if (hasText || hasLocation || hasContact)
                  const SizedBox(height: 8),
              ],
              if (locationPayload != null) ...[
                _TurnaLocationMessageCard(
                  payload: locationPayload,
                  mine: mine,
                  messageId: msg.id,
                  liveClient: _client,
                  overlayFooter: useEmbeddedMediaBubble ? embeddedFooter : null,
                  onStopShare: mine && locationPayload.isLiveActive
                      ? () => _stopLiveLocation(msg, locationPayload)
                      : null,
                ),
                if (hasText || hasContact) const SizedBox(height: 8),
              ],
              if (contactPayload != null) ...[
                _TurnaSharedContactMessageCard(
                  payload: contactPayload,
                  mine: mine,
                  session: widget.session,
                  callCoordinator: widget.callCoordinator,
                  onSessionExpired: widget.onSessionExpired,
                  overlayFooter: useEmbeddedMediaBubble
                      ? embeddedFooterPlain
                      : null,
                ),
                if (hasText) const SizedBox(height: 8),
              ],
              if (previewUri != null) ...[
                _TurnaMessageLinkPreviewCard(
                  uri: previewUri,
                  mine: mine,
                  onTap: () => _openSharedUri(previewUri),
                ),
                if (showTextBlock) const SizedBox(height: 8),
              ],
              if (showTextBlock)
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        right: mine ? 64 : 54,
                        bottom: 4,
                      ),
                      child: _buildLinkifiedMessageText(
                        showLinkPreview ? linkCaptionText : displayText,
                        mine: mine,
                      ),
                    ),
                    footer,
                  ],
                )
              else if (showLinkPreview)
                Align(alignment: Alignment.bottomRight, child: footer)
              else if (!useEmbeddedMediaBubble &&
                  (hasLocation ||
                      hasContact ||
                      visibleAttachments.isNotEmpty ||
                      hasError))
                Align(alignment: Alignment.bottomRight, child: footer),
              if (msg.reactions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: msg.reactions.map((reaction) {
                    final selected = reaction.userIds.contains(
                      widget.session.userId,
                    );
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _toggleReaction(msg, reaction.emoji),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? TurnaColors.primary50
                              : Colors.white.withValues(alpha: mine ? 0.54 : 0.9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? TurnaColors.primary
                                : TurnaColors.border,
                          ),
                        ),
                        child: Text(
                          '${reaction.emoji} ${reaction.count}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? TurnaColors.primaryStrong
                                : TurnaColors.text,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final focused = _composerFocusNode.hasFocus;
    final child = _voiceRecording
        ? SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _voiceSlideCancelArmed
                        ? TurnaColors.error.withValues(alpha: 0.32)
                        : TurnaColors.border,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: _voiceRecordingLocked
                    ? _buildLockedVoiceRecorderComposer()
                    : _buildHoldVoiceRecorderComposer(),
              ),
            ),
          )
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_editingDraft != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 48,
                        right: 54,
                        bottom: 8,
                      ),
                      child: _ComposerEditBanner(
                        draft: _editingDraft!,
                        onClose: _cancelEditingMessage,
                      ),
                    ),
                  if (_replyDraft != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 48,
                        right: 54,
                        bottom: 8,
                      ),
                      child: _ComposerReplyBanner(
                        reply: _replyDraft!,
                        onClose: () => setState(() => _replyDraft = null),
                      ),
                    ),
                  if (_mentionSuggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(
                        left: 48,
                        right: 54,
                        bottom: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: TurnaColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _mentionSuggestions.map((member) {
                          final username = (member.username ?? '').trim();
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: TurnaColors.primary50,
                              backgroundImage:
                                  (member.avatarUrl ?? '').trim().isNotEmpty
                                  ? NetworkImage(member.avatarUrl!.trim())
                                  : null,
                              child: (member.avatarUrl ?? '').trim().isEmpty
                                  ? Text(
                                      member.displayName.trim().isEmpty
                                          ? '?'
                                          : member.displayName.trim()[0]
                                                .toUpperCase(),
                                      style: const TextStyle(
                                        color: TurnaColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              member.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              username.isEmpty ? 'Uye' : '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _insertMentionCandidate(member),
                          );
                        }).toList(),
                      ),
                    ),
                  if (_groupSendRestrictionText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: TurnaColors.backgroundMuted,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: TurnaColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            color: TurnaColors.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _groupSendRestrictionText!,
                              style: const TextStyle(
                                color: TurnaColors.textSoft,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: _attachmentBusy
                              ? null
                              : _showAttachmentSheet,
                          icon: _attachmentBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add, size: 28),
                          color: TurnaColors.textSoft,
                        ),
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: TurnaColors.backgroundSoft,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: focused
                                    ? TurnaColors.primary
                                    : TurnaColors.border,
                                width: focused ? 1.4 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: TurnaColors.primary.withValues(
                                    alpha: focused ? 0.08 : 0.03,
                                  ),
                                  blurRadius: focused ? 16 : 8,
                                  offset: const Offset(0, 1.5),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _composerFocusNode,
                                    minLines: 1,
                                    maxLines: 5,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      hintText: _editingDraft == null
                                          ? 'Mesaj'
                                          : 'Duzenlenmis mesaji yaz',
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 14,
                                          ),
                                    ),
                                  ),
                                ),
                                if (!_hasComposerText && _editingDraft == null)
                                  IconButton(
                                    onPressed: _attachmentBusy
                                        ? null
                                        : _pickCameraImage,
                                    icon: const Icon(Icons.camera_alt_outlined),
                                    color: TurnaColors.textSoft,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: _hasComposerText
                              ? Container(
                                  key: const ValueKey('send'),
                                  width: 46,
                                  height: 46,
                                  decoration: const BoxDecoration(
                                    color: TurnaColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    onPressed: _attachmentBusy
                                        ? null
                                        : _handleSendPressed,
                                    icon: const Icon(Icons.send_rounded),
                                    color: TurnaColors.surface,
                                  ),
                                )
                              : SizedBox(
                                  key: const ValueKey('mic'),
                                  width: 46,
                                  height: 46,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _attachmentBusy
                                        ? null
                                        : _showVoiceMessageHint,
                                    onLongPressStart: _attachmentBusy
                                        ? null
                                        : (_) =>
                                              unawaited(_startVoiceRecording()),
                                    child: Container(
                                      key: _voiceMicKey,
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.mic_none_rounded,
                                        color: _voiceRecorderBusy
                                            ? TurnaColors.textMuted
                                            : TurnaColors.textSoft,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleComposerPointerDown,
      onPointerMove: _handleComposerPointerMove,
      onPointerUp: (event) => unawaited(_handleComposerPointerUp(event)),
      onPointerCancel: (event) =>
          unawaited(_handleComposerPointerCancel(event)),
      child: child,
    );
  }

  Widget _buildHoldVoiceRecorderComposer() {
    final danger = _voiceSlideCancelArmed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: danger
                    ? TurnaColors.error.withValues(alpha: 0.14)
                    : TurnaColors.primary50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic_rounded,
                color: danger ? TurnaColors.error : TurnaColors.primary,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatVoiceDuration(_voiceDuration),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: TurnaColors.text,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: 1 - (_voiceSlideProgress * 0.45),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chevron_left_rounded,
                      size: 20,
                      color: danger ? TurnaColors.error : TurnaColors.textMuted,
                    ),
                    Text(
                      danger ? 'Bırakınca silinecek' : 'iptal için kaydır',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: danger
                            ? TurnaColors.error
                            : TurnaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: TurnaColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 46),
            Expanded(
              child: _VoiceWaveformStrip(
                color: danger ? TurnaColors.error : TurnaColors.primary,
                activeBars: math.min(
                  _VoiceWaveformStrip.barCount,
                  ((_voiceDuration.inMilliseconds / 180).floor() %
                          _VoiceWaveformStrip.barCount) +
                      4,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'yukarı kaydırıp kilitle',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: TurnaColors.textMuted.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLockedVoiceRecorderComposer() {
    final paused = _voiceRecordingPaused;
    return Row(
      children: [
        _VoiceComposerAction(
          icon: Icons.delete_outline_rounded,
          backgroundColor: TurnaColors.error.withValues(alpha: 0.12),
          foregroundColor: TurnaColors.error,
          onTap: _voiceRecorderBusy
              ? null
              : () => unawaited(_cancelVoiceRecording(showFeedback: true)),
        ),
        const SizedBox(width: 12),
        Text(
          _formatVoiceDuration(_voiceDuration),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: TurnaColors.text,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _VoiceWaveformStrip(
            color: paused ? TurnaColors.textMuted : TurnaColors.primary,
            activeBars: paused
                ? 4
                : math.min(
                    _VoiceWaveformStrip.barCount,
                    ((_voiceDuration.inMilliseconds / 180).floor() %
                            _VoiceWaveformStrip.barCount) +
                        4,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        _VoiceComposerAction(
          icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          backgroundColor: TurnaColors.primary50,
          foregroundColor: TurnaColors.primary,
          onTap: _voiceRecorderBusy
              ? null
              : () => unawaited(_toggleLockedVoicePause()),
        ),
        const SizedBox(width: 10),
        _VoiceComposerAction(
          icon: Icons.send_rounded,
          backgroundColor: const Color(0xFF111827),
          foregroundColor: Colors.white,
          onTap: _voiceRecorderBusy
              ? null
              : () => unawaited(_finishVoiceRecording(send: true)),
        ),
      ],
    );
  }

  Future<void> _sendPickedAttachment({
    required ChatAttachmentKind kind,
    required String fileName,
    required String contentType,
    required Future<List<int>> Function() readBytes,
    int? sizeBytes,
    int? durationSeconds,
  }) async {
    setState(() => _attachmentBusy = true);

    try {
      final upload = await ChatApi.createAttachmentUpload(
        widget.session,
        chatId: widget.chat.chatId,
        kind: kind,
        contentType: contentType,
        fileName: fileName,
      );

      final bytes = await readBytes();
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Dosya yüklenemedi.');
      }

      final message = await ChatApi.sendMessage(
        widget.session,
        chatId: widget.chat.chatId,
        text: _controller.text.trim().isEmpty
            ? null
            : (_replyDraft == null
                  ? _controller.text.trim()
                  : buildTurnaReplyEncodedText(
                      reply: _replyDraft!,
                      text: _controller.text.trim(),
                    )),
        attachments: [
          OutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: kind,
            fileName: fileName,
            contentType: contentType,
            sizeBytes: sizeBytes ?? bytes.length,
            durationSeconds: durationSeconds,
          ),
        ],
      );

      if (!mounted) return;
      _client.mergeServerMessage(message);
      _controller.clear();
      setState(() => _replyDraft = null);
      _jumpToBottom();
      await TurnaAnalytics.logEvent('attachment_sent', {
        'chat_id': widget.chat.chatId,
        'kind': kind.name,
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Future<void> _openMediaComposerFromFiles(List<XFile> files) async {
    final seeds = await buildTurnaMediaComposerSeeds(context, files);
    if (seeds.isEmpty || !mounted) return;

    final message = await Navigator.push<ChatMessage>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaMediaComposerPage(
          session: widget.session,
          chat: widget.chat,
          items: seeds,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );

    if (!mounted || message == null) return;
    _client.mergeServerMessage(message);
    _jumpToBottom();
  }

  Future<void> _pickGalleryPhotos() async {
    final files = await _mediaPicker.pickMultiImage(
      limit: kComposerMediaLimit,
      imageQuality: kInlineImagePickerQuality,
      maxWidth: kInlineImagePickerMaxDimension,
      maxHeight: kInlineImagePickerMaxDimension,
    );
    if (files.isEmpty) return;
    await _openMediaComposerFromFiles(files);
  }

  Future<void> _pickGalleryVideo() async {
    final file = await _mediaPicker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    await _openMediaComposerFromFiles([file]);
  }

  Future<void> _pickCameraImage() async {
    final file = await _mediaPicker.pickImage(
      source: ImageSource.camera,
      imageQuality: kInlineImagePickerQuality,
      maxWidth: kInlineImagePickerMaxDimension,
      maxHeight: kInlineImagePickerMaxDimension,
    );
    if (file == null) return;
    await _openMediaComposerFromFiles([file]);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final filePath = file.path;
    if (filePath == null || filePath.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Secilen dosya okunamadi.')));
      return;
    }

    final fileName = file.name.trim().isEmpty
        ? filePath.split('/').last
        : file.name.trim();
    await _sendPickedAttachment(
      kind: ChatAttachmentKind.file,
      fileName: fileName,
      contentType:
          guessContentTypeForFileName(fileName) ?? 'application/octet-stream',
      readBytes: () => File(filePath).readAsBytes(),
      sizeBytes: file.size,
    );
  }

  Future<void> _showPaymentPlaceholderModal() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF27D06F),
                        Color(0xFF00B8FF),
                        Color(0xFFFFC23A),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.payments_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Ödeme Yap',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hazırlanıyor...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: TurnaColors.textMuted),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7F9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Çok yakında Turna ödemeleri burada olacak.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: TurnaColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAttachmentSheet() async {
    if (_attachmentBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            decoration: BoxDecoration(
              color: TurnaColors.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paylaş',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: TurnaColors.text,
                  ),
                ),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                  children: [
                    _AttachmentQuickAction(
                      icon: Icons.photo_library_outlined,
                      label: 'Fotoğraflar',
                      backgroundColor: TurnaColors.accent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickGalleryPhotos();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.video_library_outlined,
                      label: 'Videolar',
                      backgroundColor: TurnaColors.primaryStrong,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickGalleryVideo();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.photo_camera_outlined,
                      label: 'Kamera',
                      backgroundColor: TurnaColors.primary,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickCameraImage();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.payments_rounded,
                      label: 'Ödeme Yap',
                      backgroundColor: const Color(0xFF1FCB76),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF2BD56F),
                          Color(0xFF00B7FF),
                          Color(0xFFFFC93D),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showPaymentPlaceholderModal();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.insert_drive_file_outlined,
                      label: 'Belge',
                      backgroundColor: TurnaColors.primaryDeep,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickFile();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.perm_contact_calendar_outlined,
                      label: 'Kişi',
                      backgroundColor: TurnaColors.accentStrong,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickSharedContact();
                      },
                    ),
                    _AttachmentQuickAction(
                      icon: Icons.location_on_outlined,
                      label: 'Konum',
                      backgroundColor: TurnaColors.primary400,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickLocation();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAttachment(ChatAttachment attachment) async {
    final url = attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya linki hazır değil.')));
      return;
    }

    if (_isImageAttachment(attachment) || _isVideoAttachment(attachment)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatAttachmentViewerPage(
            session: widget.session,
            items: [
              ChatGalleryMediaItem(
                attachment: attachment,
                senderLabel: attachment.fileName ?? 'Medya',
                cacheKey: 'attachment:${attachment.objectKey}',
                url: url,
              ),
            ],
            initialIndex: 0,
            autoOpenInitialVideoFullscreen: _isVideoAttachment(attachment),
          ),
        ),
      );
      return;
    }

    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya açılamadı.')));
    }
  }

  Future<void> _openMediaAttachment(
    ChatMessage sourceMessage,
    ChatAttachment attachment,
  ) async {
    final url = attachment.url?.trim() ?? '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya linki hazır değil.')));
      return;
    }
    final galleryItems = _buildMediaGalleryItems();
    final initialIndex = galleryItems.indexWhere(
      (item) =>
          item.message?.id == sourceMessage.id &&
          item.attachment.objectKey == attachment.objectKey,
    );
    final itemsToOpen = initialIndex < 0
        ? [
            ChatGalleryMediaItem(
              message: sourceMessage,
              attachment: attachment,
              senderLabel: sourceMessage.senderId == widget.session.userId
                  ? 'Siz'
                  : _displaySenderNameFor(sourceMessage),
              cacheKey: 'attachment:${attachment.objectKey}',
              url: url,
            ),
          ]
        : galleryItems;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatAttachmentViewerPage(
          session: widget.session,
          items: itemsToOpen,
          initialIndex: initialIndex < 0 ? 0 : initialIndex,
          autoOpenInitialVideoFullscreen: _isVideoAttachment(attachment),
          formatTimestamp: _formatViewerDateTime,
          isStarred: (message) => _starredMessageIds.contains(message.id),
          onReply: (message) async {
            final replyPayload = _replyPayloadForMessage(message);
            setState(() {
              _editingDraft = null;
              _replyDraft = replyPayload;
            });
            _composerFocusNode.requestFocus();
          },
          onForward: _forwardMessage,
          onToggleStar: _toggleStarMessage,
          onDeleteForMe: (message) async {
            await _deleteMessageForMe(message);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    turnaLog('chat room dispose', {'chatId': widget.chat.chatId});
    if (_route != null) {
      kTurnaRouteObserver.unsubscribe(this);
    }
    kTurnaActiveChatRegistry.clearCurrent(widget.chat.chatId);
    _client.removeListener(_refresh);
    TurnaContactsDirectory.revision.removeListener(_refresh);
    _client.dispose();
    widget.callCoordinator.removeListener(_handleCallCoordinatorChanged);
    _controller.removeListener(_handleComposerChanged);
    _controller.dispose();
    _composerFocusNode.removeListener(_handleComposerFocusChanged);
    _composerFocusNode.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _voiceRecordTimer?.cancel();
    unawaited(_voiceRecorder.cancel());
    unawaited(_voiceRecorder.dispose());
    _messageHighlightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _client.refreshConnection();
      unawaited(_loadPeerCallHistory());
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_voiceRecording) {
        unawaited(_cancelVoiceRecording());
      }
      _client.disconnectForBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final timelineEntries = _buildTimelineEntries();
    final peerStatusText = _buildPeerStatusText();

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        title: GestureDetector(
          onTap: _isGroupChat
              ? _openGroupInfo
              : (_peerUserId == null ? null : _openPeerProfile),
          child: Row(
            children: [
              _ProfileAvatar(
                label: _chatDisplayName,
                avatarUrl: _isGroupChat
                    ? _groupAvatarUrl
                    : widget.chat.avatarUrl,
                authToken: widget.session.token,
                radius: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _chatDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (peerStatusText != null)
                      Text(
                        peerStatusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _client.peerTyping
                              ? TurnaColors.primary
                              : TurnaColors.textMuted,
                          fontWeight: _client.peerTyping
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_isGroupChat)
            IconButton(
              tooltip: 'Grup bilgisi',
              onPressed: _openGroupInfo,
              icon: const Icon(Icons.info_outline_rounded),
            ),
          if (!_isGroupChat) ...[
            IconButton(
              tooltip: 'Görüntülü ara',
              onPressed: _peerUserId == null
                  ? null
                  : () => _startCall(TurnaCallType.video),
              icon: const Icon(Icons.videocam_outlined),
            ),
            IconButton(
              tooltip: 'Sesli ara',
              onPressed: _peerUserId == null
                  ? null
                  : () => _startCall(TurnaCallType.audio),
              icon: const Icon(Icons.call_outlined),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_client.error != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF1E6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _client.error!,
                style: const TextStyle(color: Color(0xFF7A4B00)),
              ),
            ),
          if (_attachmentBusy)
            Container(
              width: double.infinity,
              color: TurnaColors.primary50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Medya yükleniyor. Mesaj hazırlanıyor...',
                style: TextStyle(color: TurnaColors.primaryStrong),
              ),
            ),
          if (_activePinnedMessage != null)
            _PinnedMessageBar(
              pinned: _activePinnedMessage!,
              onTap: _openPinnedMessagesSheet,
              onClear: _canManagePinnedMessages
                  ? () =>
                        _togglePinnedMessage(
                          _messageForPinnedSummary(_activePinnedMessage!),
                        )
                  : null,
            ),
          if (_showSecurityBanner) _buildSecurityBanner(),
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: _ChatWallpaper()),
                if (timelineEntries.isEmpty && _client.loadingInitial)
                  const SizedBox.expand()
                else if (timelineEntries.isEmpty)
                  const _CenteredState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Henüz mesaj yok',
                    message: 'İlk mesajı göndererek sohbeti başlat.',
                  )
                else
                  ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 18),
                    itemCount: timelineEntries.length + 1,
                    itemBuilder: (context, index) {
                      if (index == timelineEntries.length) {
                        if (_client.loadingMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                'Eski mesajlar ekleniyor...',
                                style: TextStyle(color: Color(0xFF777C79)),
                              ),
                            ),
                          );
                        }
                        if (_client.hasMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                'Eski mesajlar yükleniyor...',
                                style: TextStyle(color: Color(0xFF777C79)),
                              ),
                            ),
                          );
                        }
                        return const SizedBox(height: 24);
                      }

                      final entry = timelineEntries[index];
                      final msg = entry.message;
                      final call = entry.call;
                      return Column(
                        children: [
                          if (_shouldShowDayChip(timelineEntries, index))
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: TurnaChatTokens.dateGap / 2,
                              ),
                              child: _DateSeparatorChip(
                                label: _formatDayLabel(
                                  _timelineCreatedAt(entry),
                                ),
                              ),
                            ),
                          if (msg != null)
                            _buildMessageBubble(
                              timelineEntries,
                              index,
                              msg,
                              msg.senderId == widget.session.userId,
                            )
                          else if (call != null)
                            _buildCallBubble(timelineEntries, index, call),
                        ],
                      );
                    },
                  ),
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.white,
                      foregroundColor: TurnaColors.primary,
                      onPressed: _jumpToBottom,
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
              ],
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }
}

class _MessageMetaFooter extends StatelessWidget {
  const _MessageMetaFooter({
    required this.timeLabel,
    required this.mine,
    required this.status,
    this.edited = false,
    this.starred = false,
    this.overlay = false,
    this.showOverlayBackground = true,
  });

  final String timeLabel;
  final bool mine;
  final ChatMessageStatus status;
  final bool edited;
  final bool starred;
  final bool overlay;
  final bool showOverlayBackground;

  @override
  Widget build(BuildContext context) {
    final textColor = overlay
        ? (showOverlayBackground
              ? Colors.white.withValues(alpha: 0.94)
              : (mine
                    ? TurnaColors.chatOutgoingText.withValues(alpha: 0.54)
                    : TurnaColors.textMuted))
        : (mine ? TurnaColors.chatOutgoingMeta : TurnaColors.textMuted);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (starred) ...[
          Icon(
            Icons.star_rounded,
            size: 13,
            color: overlay && showOverlayBackground
                ? Colors.white.withValues(alpha: 0.96)
                : (mine ? TurnaColors.chatOutgoingMeta : TurnaColors.warning),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          edited ? 'düzenlendi $timeLabel' : timeLabel,
          style: TextStyle(fontSize: 11, color: textColor),
        ),
        if (mine) ...[
          const SizedBox(width: 6),
          _StatusTick(
            status: status,
            mine: mine,
            overlay: overlay,
            showOverlayBackground: showOverlayBackground,
          ),
        ],
      ],
    );
    if (!overlay || !showOverlayBackground) return content;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(999),
      ),
      child: content,
    );
  }
}

class _StatusTick extends StatelessWidget {
  const _StatusTick({
    required this.status,
    this.mine = false,
    this.overlay = false,
    this.showOverlayBackground = true,
  });

  final ChatMessageStatus status;
  final bool mine;
  final bool overlay;
  final bool showOverlayBackground;

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.done;
    Color color = overlay && showOverlayBackground
        ? Colors.white.withValues(alpha: 0.94)
        : (mine ? TurnaColors.chatOutgoingMeta : TurnaColors.textMuted);

    if (status == ChatMessageStatus.sending) {
      icon = Icons.schedule;
    } else if (status == ChatMessageStatus.queued) {
      icon = Icons.cloud_off_outlined;
    } else if (status == ChatMessageStatus.failed) {
      icon = Icons.error_outline;
      color = TurnaColors.error;
    } else if (status == ChatMessageStatus.delivered) {
      icon = Icons.done_all;
    } else if (status == ChatMessageStatus.read) {
      icon = Icons.done_all;
      color = mine ? TurnaColors.chatOutgoingRead : TurnaColors.info;
    }

    return Icon(icon, size: 16, color: color);
  }
}

class _DateSeparatorChip extends StatelessWidget {
  const _DateSeparatorChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TurnaColors.surfaceHover,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TurnaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: TurnaColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ChatWallpaper extends StatelessWidget {
  const _ChatWallpaper();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ChatWallpaperPainter());
  }
}

class _ChatWallpaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = TurnaColors.border.withValues(alpha: 0.45);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = TurnaColors.primary50.withValues(alpha: 0.22);

    const stepX = 72.0;
    const stepY = 78.0;
    for (double y = -10; y < size.height + stepY; y += stepY) {
      final row = (y / stepY).round();
      for (double x = 0; x < size.width + stepX; x += stepX) {
        final offsetX = row.isEven ? 10.0 : 36.0;
        final origin = Offset(x + offsetX, y + 16);

        canvas.drawCircle(origin, 6, stroke);
        canvas.drawCircle(origin, 3, fill);

        final rounded = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: origin + const Offset(22, 18),
            width: 18,
            height: 13,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(rounded, stroke);

        final path = Path()
          ..moveTo(origin.dx - 4, origin.dy + 26)
          ..quadraticBezierTo(
            origin.dx + 2,
            origin.dy + 18,
            origin.dx + 8,
            origin.dy + 26,
          )
          ..quadraticBezierTo(
            origin.dx + 14,
            origin.dy + 34,
            origin.dx + 20,
            origin.dy + 26,
          );
        canvas.drawPath(path, stroke);

        canvas.drawArc(
          Rect.fromCircle(center: origin + const Offset(44, 42), radius: 7),
          -math.pi / 6,
          math.pi * 1.2,
          false,
          stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AttachmentQuickAction extends StatelessWidget {
  const _AttachmentQuickAction({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onTap,
    this.gradient,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: backgroundColor,
                gradient: gradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: Colors.white, size: 25),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: TurnaColors.textSoft,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageQuickAction extends StatelessWidget {
  const _MessageQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? TurnaColors.text : TurnaColors.textMuted;
    return SizedBox(
      width: 82,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: TurnaColors.backgroundMuted,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: iconColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplySnippetCard extends StatelessWidget {
  const _ReplySnippetCard({
    required this.reply,
    required this.mine,
    required this.senderLabel,
    required this.repliedToCurrentUser,
    required this.authToken,
    this.previewAttachment,
    this.onTap,
  });

  final TurnaReplyPayload reply;
  final bool mine;
  final String senderLabel;
  final bool repliedToCurrentUser;
  final String authToken;
  final ChatAttachment? previewAttachment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = repliedToCurrentUser
        ? const Color(0xFF1976D2)
        : const Color(0xFFD35F49);
    final background = mine ? const Color(0xFFD8EDC7) : const Color(0xFFF4F5F7);
    final textColor = TurnaColors.text;
    final attachment = previewAttachment;
    final hasThumbnail = attachment != null;
    final mediaLabel = reply.previewText.trim().isEmpty
        ? 'Medya'
        : reply.previewText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      senderLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          reply.previewText == 'Video'
                              ? Icons.videocam_rounded
                              : reply.previewText == 'Fotoğraf'
                              ? Icons.photo_camera_rounded
                              : Icons.subtitles_rounded,
                          size: 18,
                          color: textColor.withValues(alpha: 0.76),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            mediaLabel,
                            maxLines: hasThumbnail ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.92),
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasThumbnail) ...[
                const SizedBox(width: 8),
                _ReplySnippetThumbnail(
                  attachment: attachment,
                  authToken: authToken,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplySnippetThumbnail extends StatelessWidget {
  const _ReplySnippetThumbnail({
    required this.attachment,
    required this.authToken,
  });

  final ChatAttachment attachment;
  final String authToken;

  @override
  Widget build(BuildContext context) {
    final cacheKey = 'attachment:${attachment.objectKey}';
    final url = attachment.url?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 52,
        height: 52,
        child: _isVideoAttachment(attachment)
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _TurnaVideoThumbnail(
                    cacheKey: cacheKey,
                    url: url,
                    authToken: authToken,
                    contentType: attachment.contentType,
                    fileName: attachment.fileName,
                    fit: BoxFit.cover,
                    loading: const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xFFBEC5C8)),
                    ),
                    error: const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xFFBEC5C8)),
                    ),
                  ),
                  Container(color: Colors.black.withValues(alpha: 0.16)),
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              )
            : _TurnaCachedImage(
                cacheKey: cacheKey,
                imageUrl: url,
                authToken: authToken,
                fit: BoxFit.cover,
                loading: const ColoredBox(color: Color(0xFFBEC5C8)),
                error: const ColoredBox(color: Color(0xFFBEC5C8)),
              ),
      ),
    );
  }
}

class _TurnaMessageLinkPreviewCard extends StatelessWidget {
  const _TurnaMessageLinkPreviewCard({
    required this.uri,
    required this.mine,
    required this.onTap,
  });

  final Uri uri;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surfaceColor = mine
        ? Colors.white.withValues(alpha: 0.44)
        : const Color(0xFFF6F8FB);
    final borderColor = mine
        ? Colors.white.withValues(alpha: 0.22)
        : TurnaColors.border;

    return FutureBuilder<TurnaLinkPreviewMetadata>(
      future: TurnaLinkPreviewCache.resolve(uri),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final host = preview?.host.isNotEmpty == true
            ? preview!.host
            : uri.host.replaceFirst(
                RegExp(r'^www\.', caseSensitive: false),
                '',
              );
        final title = (preview?.title.trim().isNotEmpty ?? false)
            ? preview!.title.trim()
            : (host.isEmpty ? uri.toString() : host);
        final displayUrl = preview?.displayUrl ?? uri.toString();

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 250,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: mine
                          ? Colors.white.withValues(alpha: 0.5)
                          : TurnaColors.backgroundMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.link_rounded,
                      color: mine
                          ? TurnaColors.primary800
                          : TurnaColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.22,
                            fontWeight: FontWeight.w700,
                            color: mine
                                ? TurnaColors.chatOutgoingText
                                : TurnaColors.chatIncomingText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: mine
                                ? TurnaColors.chatOutgoingText.withValues(
                                    alpha: 0.72,
                                  )
                                : TurnaColors.textMuted,
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
      },
    );
  }
}

class _ComposerReplyBanner extends StatelessWidget {
  const _ComposerReplyBanner({required this.reply, required this.onClose});

  final TurnaReplyPayload reply;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final senderLabel = reply.senderLabel.trim() == 'Sen'
        ? 'Siz'
        : reply.senderLabel;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: TurnaColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TurnaColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: TurnaColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yanıtlanıyor: $senderLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: TurnaColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _ComposerEditBanner extends StatelessWidget {
  const _ComposerEditBanner({required this.draft, required this.onClose});

  final _ComposerEditDraft draft;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TurnaColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: TurnaColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mesaj duzenleniyor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: TurnaColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  draft.originalText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TurnaColors.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: TurnaColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _PinnedMessageBar extends StatelessWidget {
  const _PinnedMessageBar({
    required this.pinned,
    required this.onTap,
    this.onClear,
  });

  final TurnaPinnedMessageSummary pinned;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final senderLabel =
        (pinned.senderDisplayName ?? '').trim().isNotEmpty
        ? pinned.senderDisplayName!.trim()
        : 'Mesaj';
    return Material(
      color: TurnaColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: TurnaColors.divider)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.push_pin_rounded,
                size: 17,
                color: TurnaColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sabitlenen mesaj',
                      style: TextStyle(
                        color: TurnaColors.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$senderLabel: ${pinned.previewText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TurnaColors.textSoft,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onTap,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
                color: TurnaColors.textMuted,
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: TurnaColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class ForwardMessagePickerPage extends StatefulWidget {
  const ForwardMessagePickerPage({
    super.key,
    required this.session,
    required this.currentChatId,
  });

  final AuthSession session;
  final String currentChatId;

  @override
  State<ForwardMessagePickerPage> createState() =>
      _ForwardMessagePickerPageState();
}

class _ForwardMessagePickerPageState extends State<ForwardMessagePickerPage> {
  final TextEditingController _searchController = TextEditingController();
  late Future<ChatInboxData> _chatsFuture;
  ChatInboxData? _cachedInbox;

  @override
  void initState() {
    super.initState();
    _cachedInbox = TurnaChatInboxLocalCache.peek(widget.session.userId);
    _chatsFuture = ChatApi.fetchChats(widget.session);
    unawaited(_loadCachedInbox());
    _searchController.addListener(_refresh);
  }

  Future<void> _loadCachedInbox() async {
    final cached = await TurnaChatInboxLocalCache.load(widget.session.userId);
    if (!mounted || cached == null) return;
    setState(() => _cachedInbox = cached);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Ilet')),
      body: FutureBuilder<ChatInboxData>(
        future: _chatsFuture,
        initialData: _cachedInbox,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _cachedInbox = snapshot.data;
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null &&
              _cachedInbox == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CenteredState(
              icon: Icons.forward_to_inbox_outlined,
              title: 'Sohbetler yüklenemedi',
              message: snapshot.error.toString(),
            );
          }

          final chats =
              ((snapshot.data ?? _cachedInbox)?.chats ?? const <ChatPreview>[])
                  .where((chat) => !chat.isArchived)
                  .where((chat) => chat.chatId != widget.currentChatId)
                  .where((chat) {
                    if (query.isEmpty) return true;
                    return chat.name.toLowerCase().contains(query) ||
                        chat.message.toLowerCase().contains(query);
                  })
                  .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Sohbet ara',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: TurnaColors.backgroundMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: chats.isEmpty
                    ? const _CenteredState(
                        icon: Icons.chat_bubble_outline,
                        title: 'Sohbet bulunamadı',
                        message: 'İletilecek başka sohbet bulunmuyor.',
                      )
                    : ListView.builder(
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          return ListTile(
                            leading: _ProfileAvatar(
                              label: chat.name,
                              avatarUrl: chat.avatarUrl,
                              authToken: widget.session.token,
                              radius: 22,
                            ),
                            title: Text(
                              chat.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: chat.message.trim().isEmpty
                                ? null
                                : Text(
                                    chat.message,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => Navigator.pop(context, chat),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChatAttachmentList extends StatelessWidget {
  const _ChatAttachmentList({
    required this.attachments,
    required this.mine,
    required this.onTap,
    required this.formatFileSize,
    required this.authToken,
    this.onLongPress,
    this.overlayFooter,
    this.audioOverlayFooter,
  });

  final List<ChatAttachment> attachments;
  final bool mine;
  final Future<void> Function(ChatAttachment attachment) onTap;
  final String Function(int bytes) formatFileSize;
  final String authToken;
  final ValueChanged<ChatAttachment>? onLongPress;
  final Widget? overlayFooter;
  final Widget? audioOverlayFooter;

  @override
  Widget build(BuildContext context) {
    final showOverlay = overlayFooter != null && attachments.length == 1;
    return Column(
      children: attachments.map<Widget>((attachment) {
        if (_isAudioAttachment(attachment)) {
          return _VoiceMessageBubble(
            attachment: attachment,
            mine: mine,
            authToken: authToken,
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(attachment),
            overlayFooter: showOverlay
                ? (audioOverlayFooter ?? overlayFooter)
                : null,
          );
        }

        if (_isImageAttachment(attachment)) {
          final imageUrl = attachment.url?.trim() ?? '';
          return Padding(
            padding: EdgeInsets.only(bottom: showOverlay ? 0 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onTap(attachment),
              onLongPress: onLongPress == null
                  ? null
                  : () => onLongPress!(attachment),
              child: SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        width: 220,
                        height: 220,
                        color: TurnaColors.backgroundMuted,
                        child: imageUrl.isEmpty
                            ? const Center(
                                child: Icon(Icons.image_not_supported_outlined),
                              )
                            : _TurnaCachedImage(
                                cacheKey: 'attachment:${attachment.objectKey}',
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                loading: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                error: const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                      ),
                    ),
                    if (showOverlay)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Container(
                            height: 70,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(22),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.22),
                                  Colors.black.withValues(alpha: 0.34),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showOverlay)
                      Positioned(right: 8, bottom: 8, child: overlayFooter!),
                  ],
                ),
              ),
            ),
          );
        }

        final isVideo = _isVideoAttachment(attachment);
        if (isVideo) {
          return Padding(
            padding: EdgeInsets.only(bottom: showOverlay ? 0 : 8),
            child: InkWell(
              onTap: () => onTap(attachment),
              onLongPress: onLongPress == null
                  ? null
                  : () => onLongPress!(attachment),
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 220,
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: _TurnaVideoThumbnail(
                          cacheKey: 'attachment:${attachment.objectKey}',
                          url: attachment.url?.trim() ?? '',
                          authToken: authToken,
                          contentType: attachment.contentType,
                          fileName: attachment.fileName,
                          fit: BoxFit.cover,
                          loading: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF31424A),
                                  Color(0xFF1E2A30),
                                  Color(0xFF11181D),
                                ],
                              ),
                            ),
                          ),
                          error: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF31424A),
                                  Color(0xFF1E2A30),
                                  Color(0xFF11181D),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.34),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        right: showOverlay ? 82 : 14,
                        bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              attachment.fileName ?? 'Video',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Video • ${formatFileSize(attachment.sizeBytes)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showOverlay)
                        Positioned(right: 8, bottom: 8, child: overlayFooter!),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onTap(attachment),
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(attachment),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TurnaColors.backgroundMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: TurnaColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.insert_drive_file_outlined,
                      color: TurnaColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName ?? 'Dosya',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dosya • ${formatFileSize(attachment.sizeBytes)}',
                          style: const TextStyle(
                            fontSize: 12,
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
      }).toList(),
    );
  }
}

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

class NewChatPage extends StatefulWidget {
  const NewChatPage({
    super.key,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  static const List<String> _alphabetIndex = <String>[
    'A',
    'B',
    'C',
    'Ç',
    'D',
    'E',
    'F',
    'G',
    'Ğ',
    'H',
    'I',
    'İ',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'Ö',
    'P',
    'R',
    'S',
    'Ş',
    'T',
    'U',
    'Ü',
    'V',
    'Y',
    'Z',
  ];
  static const double _sectionHeaderHeight = 28;
  static const double _contactRowHeight = 74;
  final TextEditingController _lookupController = TextEditingController();
  final ScrollController _contactsScrollController = ScrollController();
  TurnaUserProfile? _foundUser;
  List<TurnaRegisteredContact> _registeredContacts =
      const <TurnaRegisteredContact>[];
  Timer? _lookupDebounce;
  bool _loading = false;
  bool _syncingContacts = false;
  String? _lookupError;
  String? _directoryError;

  @override
  void initState() {
    super.initState();
    _lookupController.addListener(_handleLookupChanged);
    TurnaContactsDirectory.revision.addListener(_handleContactsChanged);
    unawaited(_refreshRegisteredContacts());
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    TurnaContactsDirectory.revision.removeListener(_handleContactsChanged);
    _lookupController.removeListener(_handleLookupChanged);
    _lookupController.dispose();
    _contactsScrollController.dispose();
    super.dispose();
  }

  void _handleLookupChanged() {
    _lookupDebounce?.cancel();
    if (!mounted) return;
    setState(() {
      if (_lookupError != null) {
        _lookupError = null;
      }
      if (_foundUser != null) {
        _foundUser = null;
      }
    });

    final query = _lookupController.text.trim();
    if (!_shouldTriggerExactLookup(query)) {
      return;
    }

    _lookupDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      unawaited(_searchUser(overrideQuery: query));
    });
  }

  void _handleContactsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshRegisteredContacts({
    bool forceContactReload = false,
  }) async {
    if (_syncingContacts) return;
    setState(() {
      _syncingContacts = true;
      _directoryError = null;
    });

    try {
      await TurnaContactsDirectory.ensureLoaded(force: forceContactReload);
      if (!mounted) return;

      if (!TurnaContactsDirectory.permissionGranted) {
        setState(() => _syncingContacts = false);
        return;
      }

      final contacts = TurnaContactsDirectory.snapshotForSync();
      await ProfileApi.syncContacts(widget.session, contacts);
      final registered = await ChatApi.fetchRegisteredContacts(widget.session);
      if (!mounted) return;
      setState(() {
        _registeredContacts = registered;
        _syncingContacts = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      setState(() => _syncingContacts = false);
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _syncingContacts = false;
        _directoryError = error.toString();
      });
    }
  }

  List<TurnaRegisteredContact> get _filteredRegisteredContacts {
    final rawQuery = _lookupController.text.trim();
    final query = rawQuery.toLowerCase();
    if (query.isEmpty) return _registeredContacts;
    final exactUsername = _normalizeUsernameLookup(rawQuery);
    if (exactUsername != null) {
      return _registeredContacts.where((contact) {
        return ((contact.username ?? '').trim().toLowerCase() == exactUsername);
      }).toList();
    }

    final exactPhone = _normalizeLookupPhoneQuery(rawQuery);
    if (exactPhone != null) {
      final exactDigits = exactPhone.replaceAll(RegExp(r'\D+'), '');
      return _registeredContacts.where((contact) {
        final phoneDigits = (contact.phone ?? '').replaceAll(
          RegExp(r'\D+'),
          '',
        );
        return phoneDigits == exactDigits;
      }).toList();
    }

    final digitsQuery = query.replaceAll(RegExp(r'\D+'), '');
    return _registeredContacts.where((contact) {
      final title = contact.resolvedTitle.toLowerCase();
      final username = (contact.username ?? '').toLowerCase();
      final phone = (contact.phone ?? '').toLowerCase();
      final phoneDigits = phone.replaceAll(RegExp(r'\D+'), '');
      return title.contains(query) ||
          username.contains(query.replaceAll('@', '')) ||
          phone.contains(query) ||
          (digitsQuery.isNotEmpty && phoneDigits.contains(digitsQuery));
    }).toList();
  }

  String? _normalizeUsernameLookup(String query) {
    final trimmed = query.trim();
    if (!trimmed.startsWith('@')) return null;
    final normalized = trimmed
        .replaceFirst(RegExp(r'^@+'), '')
        .trim()
        .toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeLookupPhoneQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    final digits = trimmed.replaceAll(RegExp(r'\D+'), '');
    if (trimmed.startsWith('+')) {
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }
    if (RegExp(r'^05\d{9}$').hasMatch(digits)) {
      return '+90${digits.substring(1)}';
    }
    if (RegExp(r'^5\d{9}$').hasMatch(digits)) {
      return '+90$digits';
    }
    return null;
  }

  bool _shouldTriggerExactLookup(String query) {
    if (_normalizeUsernameLookup(query) != null) return true;
    return _normalizeLookupPhoneQuery(query) != null;
  }

  Future<void> _searchUser({String? overrideQuery}) async {
    final rawQuery = (overrideQuery ?? _lookupController.text).trim();
    final query =
        _normalizeLookupPhoneQuery(rawQuery) ??
        (_normalizeUsernameLookup(rawQuery) != null
            ? '@${_normalizeUsernameLookup(rawQuery)!}'
            : rawQuery);
    if (query.isEmpty) {
      setState(() {
        _lookupError = 'Telefon numarası veya kullanıcı adı gir.';
        _foundUser = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _lookupError = null;
      _foundUser = null;
    });

    try {
      final user = await ChatApi.lookupUser(widget.session, query);
      if (!mounted) return;
      setState(() {
        _foundUser = user;
        _loading = false;
        _lookupError = user == null
            ? 'Bu sorguyla kayıtlı bir Turna hesabı bulunamadı.'
            : null;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lookupError = error.toString();
      });
    }
  }

  Future<void> _openCreateContact() async {
    try {
      final queryPhone = _normalizeLookupPhoneQuery(_lookupController.text);
      final contact = Contact(
        displayName: '',
        phones: queryPhone == null
            ? const <Phone>[]
            : <Phone>[Phone(queryPhone)],
      );
      await FlutterContacts.openExternalInsert(contact);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kişi kartı açılamadı: $error')));
    }
  }

  Future<void> _openCreateGroup() async {
    final navigator = Navigator.of(context);
    final createdChat = await Navigator.push<ChatPreview>(
      context,
      MaterialPageRoute(
        builder: (_) => _CreateGroupPage(
          session: widget.session,
          registeredContacts: _registeredContacts,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || createdChat == null) return;
    await navigator.push(
      buildChatRoomRoute(
        chat: createdChat,
        session: widget.session,
        callCoordinator: widget.callCoordinator,
        onSessionExpired: widget.onSessionExpired,
      ),
    );
    if (!mounted) return;
    navigator.pop(true);
  }

  Future<void> _openChat(TurnaUserProfile user) async {
    final phone = user.phone;
    final fallbackName = phone == null || phone.trim().isEmpty
        ? user.displayName
        : formatTurnaDisplayPhone(phone);
    final chat = ChatPreview(
      chatId: ChatApi.buildDirectChatId(widget.session.userId, user.id),
      name: TurnaContactsDirectory.resolveDisplayLabel(
        phone: phone,
        fallbackName: fallbackName,
      ),
      message: '',
      time: '',
      phone: phone,
      avatarUrl: user.avatarUrl,
      peerId: user.id,
    );
    await Navigator.push(
      context,
      buildChatRoomRoute(
        chat: chat,
        session: widget.session,
        callCoordinator: widget.callCoordinator,
        onSessionExpired: widget.onSessionExpired,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _buildRegisteredContactsSection() {
    if (!TurnaContactsDirectory.permissionGranted &&
        _registeredContacts.isEmpty) {
      return _CenteredState(
        icon: Icons.perm_contact_calendar_outlined,
        title: 'Rehber izni gerekli',
        message:
            'Rehberinde kayıtlı ve Turna kullanan kişileri görmek için rehber izni ver.',
        primaryLabel: 'Rehber iznini iste',
        onPrimary: () => _refreshRegisteredContacts(forceContactReload: true),
      );
    }

    if (_directoryError != null) {
      return _CenteredState(
        icon: Icons.sync_problem_outlined,
        title: 'Rehber senkronize edilemedi',
        message: _directoryError!,
        primaryLabel: 'Kişileri yenile',
        onPrimary: () => _refreshRegisteredContacts(forceContactReload: true),
      );
    }

    if (_syncingContacts && _registeredContacts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final contacts = _filteredRegisteredContacts;
    if (contacts.isEmpty) {
      return _CenteredState(
        icon: Icons.perm_contact_calendar_outlined,
        title: 'Kayıtlı rehber kişisi bulunamadı',
        message: _lookupController.text.trim().isEmpty
            ? 'Rehberinde kayıtlı ve Turna kullanan kişiler burada listelenecek.'
            : 'Arama metnine uyan rehber kişisi bulunamadı.',
        primaryLabel: _lookupController.text.trim().isEmpty
            ? 'Kişileri yenile'
            : 'Kişiyi bul',
        onPrimary: _lookupController.text.trim().isEmpty
            ? () => _refreshRegisteredContacts(forceContactReload: true)
            : _searchUser,
      );
    }

    final grouped = <String, List<TurnaRegisteredContact>>{};
    for (final contact in contacts) {
      final letter = _sectionLetter(contact.resolvedTitle);
      grouped
          .putIfAbsent(letter, () => <TurnaRegisteredContact>[])
          .add(contact);
    }
    final visibleLetters = _alphabetIndex
        .where((letter) => grouped.containsKey(letter))
        .toList(growable: false);
    final offsets = <String, double>{};
    var runningOffset = 0.0;
    for (final letter in visibleLetters) {
      offsets[letter] = runningOffset;
      runningOffset +=
          _sectionHeaderHeight + (grouped[letter]!.length * _contactRowHeight);
    }

    return Stack(
      children: [
        ListView(
          controller: _contactsScrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 30, 24),
          children: [
            for (final letter in visibleLetters) ...[
              SizedBox(
                height: _sectionHeaderHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    letter,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: TurnaColors.textMuted,
                    ),
                  ),
                ),
              ),
              ...grouped[letter]!.map((contact) {
                final subtitleParts = <String>[
                  if ((contact.username ?? '').trim().isNotEmpty)
                    '@${contact.username!.trim()}',
                  if ((contact.phone ?? '').trim().isNotEmpty)
                    formatTurnaDisplayPhone(contact.phone!),
                ];
                return SizedBox(
                  height: _contactRowHeight,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          leading: _ProfileAvatar(
                            label: contact.resolvedTitle,
                            avatarUrl: contact.avatarUrl,
                            authToken: widget.session.token,
                            radius: 24,
                          ),
                          title: Text(
                            contact.resolvedTitle,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: subtitleParts.isEmpty
                              ? null
                              : Text(
                                  subtitleParts.join('  •  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => _openChat(contact.toUserProfile()),
                          onLongPress: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfilePage(
                                  session: widget.session,
                                  userId: contact.id,
                                  fallbackName: contact.resolvedTitle,
                                  fallbackAvatarUrl: contact.avatarUrl,
                                  callCoordinator: widget.callCoordinator,
                                  onSessionExpired: widget.onSessionExpired,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
        Positioned(
          top: 6,
          right: 4,
          bottom: 10,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _alphabetIndex.map((letter) {
              final enabled = offsets.containsKey(letter);
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: !enabled
                      ? null
                      : () {
                          _contactsScrollController.animateTo(
                            offsets[letter]!,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                          );
                        },
                  child: SizedBox(
                    width: 20,
                    child: Center(
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? TurnaColors.primary
                              : TurnaColors.textMuted.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _sectionLetter(String value) {
    final trimmed = value.trimLeft();
    if (trimmed.isEmpty) return '#';
    final first = trimmed.substring(0, 1);
    switch (first.toLowerCase()) {
      case 'ç':
        return 'Ç';
      case 'ğ':
        return 'Ğ';
      case 'ı':
        return 'I';
      case 'i':
        return 'İ';
      case 'ö':
        return 'Ö';
      case 'ş':
        return 'Ş';
      case 'ü':
        return 'Ü';
      default:
        final upper = first.toUpperCase();
        return _alphabetIndex.contains(upper) ? upper : '#';
    }
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: TurnaColors.primary50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: TurnaColors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: TurnaColors.textMuted,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      minLeadingWidth: 0,
    );
  }

  Widget _buildLookupResultCard(String? foundUserName) {
    if (_foundUser == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: TurnaColors.divider),
        ),
        child: Row(
          children: [
            _ProfileAvatar(
              label: foundUserName ?? _foundUser!.displayName,
              avatarUrl: _foundUser!.avatarUrl,
              authToken: widget.session.token,
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    foundUserName ?? _foundUser!.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (_foundUser!.username ?? '').trim().isNotEmpty
                        ? '@${_foundUser!.username!.trim()}'
                        : formatTurnaDisplayPhone(_foundUser!.phone ?? ''),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: TurnaColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _openChat(_foundUser!),
              child: const Text('Sohbet'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lookupInput = _lookupController.text.trim();
    final foundUserName = _foundUser == null
        ? null
        : TurnaContactsDirectory.resolveDisplayLabel(
            phone: _foundUser!.phone,
            fallbackName: _foundUser!.displayName,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni sohbet')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _lookupController,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    hintText: 'Bir ad, numara veya kullanıcı adı aratın',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: lookupInput.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _lookupController.clear();
                              setState(() {
                                _foundUser = null;
                                _lookupError = null;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: TurnaColors.backgroundMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _searchUser(),
                ),
                if (_lookupError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _lookupError!,
                    style: const TextStyle(
                      color: TurnaColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading && _foundUser == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: TurnaColors.divider),
                          ),
                          child: Column(
                            children: [
                              _buildQuickActionTile(
                                icon: Icons.groups_rounded,
                                title: 'Yeni grup',
                                onTap: _openCreateGroup,
                              ),
                              const Divider(height: 1),
                              _buildQuickActionTile(
                                icon: Icons.person_add_alt_1_rounded,
                                title: 'Yeni kişi',
                                onTap: _openCreateContact,
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildLookupResultCard(foundUserName),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                        child: Row(
                          children: [
                            const Text(
                              'Turna\'daki kişiler',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (_syncingContacts)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              TextButton(
                                onPressed: () => _refreshRegisteredContacts(
                                  forceContactReload: true,
                                ),
                                child: const Text('Yenile'),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.62,
                        child: _buildRegisteredContactsSection(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreateGroupPage extends StatefulWidget {
  const _CreateGroupPage({
    required this.session,
    required this.registeredContacts,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final List<TurnaRegisteredContact> registeredContacts;
  final VoidCallback onSessionExpired;

  @override
  State<_CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<_CreateGroupPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  bool _creating = false;

  List<TurnaRegisteredContact> get _filteredContacts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.registeredContacts;
    return widget.registeredContacts.where((contact) {
      final title = contact.resolvedTitle.toLowerCase();
      final username = (contact.username ?? '').toLowerCase();
      final phone = (contact.phone ?? '').toLowerCase();
      return title.contains(query) ||
          username.contains(query.replaceAll('@', '')) ||
          phone.contains(query);
    }).toList();
  }

  Future<void> _createGroup() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Grup adı gerekli.')));
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir kişi daha seçmelisin.')),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final detail = await ChatApi.createGroup(
        widget.session,
        title: title,
        memberUserIds: _selectedIds.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        ChatPreview(
          chatId: detail.chatId,
          name: detail.title,
          message: 'Grup oluşturuldu',
          time: '',
          chatType: TurnaChatType.group,
          memberPreviewNames: detail.memberPreviewNames,
          avatarUrl: detail.avatarUrl,
          memberCount: detail.memberCount,
          myRole: detail.myRole,
          description: detail.description,
          isPublic: detail.isPublic,
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
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _filteredContacts;
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Grup')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: TurnaColors.divider),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: TurnaColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Grup adı',
                          filled: true,
                          fillColor: TurnaColors.backgroundMuted,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Kişi ara',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: TurnaColors.backgroundMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${_selectedIds.length} kişi seçildi',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: TurnaColors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _creating ? null : _createGroup,
                      child: Text(
                        _creating ? 'Oluşturuluyor...' : 'Grubu oluştur',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: contacts.isEmpty
                ? const Center(
                    child: Text(
                      'Seçilebilir kişi bulunamadı.',
                      style: TextStyle(color: TurnaColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: contacts.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      final selected = _selectedIds.contains(contact.id);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selectedIds.remove(contact.id);
                            } else {
                              _selectedIds.add(contact.id);
                            }
                          });
                        },
                        leading: _ProfileAvatar(
                          label: contact.resolvedTitle,
                          avatarUrl: contact.avatarUrl,
                          authToken: widget.session.token,
                          radius: 24,
                        ),
                        title: Text(
                          contact.resolvedTitle,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            if ((contact.username ?? '').trim().isNotEmpty)
                              '@${contact.username!.trim()}',
                            if ((contact.phone ?? '').trim().isNotEmpty)
                              formatTurnaDisplayPhone(contact.phone!),
                          ].join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Checkbox(
                          value: selected,
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedIds.remove(contact.id);
                              } else {
                                _selectedIds.add(contact.id);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TurnaGroupInfoPage extends StatefulWidget {
  const _TurnaGroupInfoPage({
    required this.session,
    required this.chat,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final ChatPreview chat;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupInfoPage> createState() => _TurnaGroupInfoPageState();
}

class _TurnaGroupInfoPageState extends State<_TurnaGroupInfoPage> {
  TurnaChatDetail? _detail;
  List<TurnaGroupMember> _members = const <TurnaGroupMember>[];
  final ImagePicker _avatarPicker = ImagePicker();
  bool _loading = true;
  bool _leaving = false;
  bool _closing = false;
  bool _savingDetail = false;
  bool _loadingMoreMembers = false;
  int _totalMemberCount = 0;
  bool _hasMoreMembers = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detail = TurnaChatDetailLocalCache.peek(
      widget.session.userId,
      widget.chat.chatId,
    );
    unawaited(_load());
  }

  String get _groupTitle => _detail?.title ?? widget.chat.name;
  String? get _groupAvatarUrl => _detail?.avatarUrl ?? widget.chat.avatarUrl;
  int get _groupMemberCount => _detail?.memberCount ?? widget.chat.memberCount;
  String? get _groupDescription =>
      _detail?.description ?? widget.chat.description;
  String get _myRole =>
      (_detail?.myRole ?? widget.chat.myRole ?? '').trim().toUpperCase();
  bool get _isOwner => _myRole == 'OWNER';
  bool get _isAdmin => _myRole == 'ADMIN';
  bool get _isEditor => _myRole == 'EDITOR';
  bool get _canOpenSettings => _isOwner || _isAdmin;
  bool get _canManageRoles => _isOwner || _isAdmin;
  bool get _canEditInfo =>
      _policyAllows(_detail?.whoCanEditInfo ?? 'EDITOR_ONLY', _myRole);
  bool get _canCloseGroup => _isOwner;
  bool get _canAddMembers =>
      _policyAllows(_detail?.whoCanAddMembers ?? 'ADMIN_ONLY', _myRole);

  bool _policyAllows(String policy, String role) {
    final normalizedPolicy = policy.trim().toUpperCase();
    final normalizedRole = role.trim().toUpperCase();
    if (normalizedRole == 'OWNER') return true;
    switch (normalizedPolicy) {
      case 'EVERYONE':
        return true;
      case 'EDITOR_ONLY':
        return normalizedRole == 'ADMIN' || normalizedRole == 'EDITOR';
      case 'ADMIN_ONLY':
        return normalizedRole == 'ADMIN';
      default:
        return false;
    }
  }

  List<String> _availableRoleOptionsFor(TurnaGroupMember member) {
    if (!_canManageRoles) return const <String>[];
    final targetRole = member.role.trim().toUpperCase();
    if (_isOwner) {
      if (targetRole == 'OWNER') return const <String>[];
      return const <String>['ADMIN', 'EDITOR', 'MEMBER'];
    }
    if (_isAdmin) {
      if (targetRole == 'OWNER' || targetRole == 'ADMIN') {
        return const <String>[];
      }
      return const <String>['EDITOR', 'MEMBER'];
    }
    return const <String>[];
  }

  String _formatLastSeen(String? iso) {
    if (iso == null || iso.trim().isEmpty) return 'son görülme bilinmiyor';
    final dt = parseTurnaLocalDateTime(iso);
    if (dt == null) return 'son görülme bilinmiyor';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (diff == 0) return 'bugün $hh:$mm';
    if (diff == 1) return 'dün $hh:$mm';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  String _roleLabel(String? role) {
    switch ((role ?? '').trim().toUpperCase()) {
      case 'OWNER':
        return 'Sahip';
      case 'ADMIN':
        return 'Admin';
      case 'EDITOR':
        return 'Editör';
      default:
        return 'Üye';
    }
  }

  bool _canRemoveMember(TurnaGroupMember member) {
    if (member.userId == widget.session.userId) return false;
    final targetRole = member.role.trim().toUpperCase();
    if (_isOwner) return targetRole != 'OWNER';
    if (_isAdmin) return targetRole == 'EDITOR' || targetRole == 'MEMBER';
    if (_isEditor) return targetRole == 'MEMBER';
    return false;
  }

  bool _canBanMember(TurnaGroupMember member) {
    if (member.userId == widget.session.userId) return false;
    final targetRole = member.role.trim().toUpperCase();
    if (_isOwner) return targetRole != 'OWNER';
    if (_isAdmin) return targetRole == 'EDITOR' || targetRole == 'MEMBER';
    return false;
  }

  String _formatMuteLabel(TurnaGroupMember member) {
    if (!member.isMuted) return 'Sessize al';
    if ((member.mutedUntil ?? '').trim().isEmpty) {
      return 'Kalıcı sessizde';
    }
    final until = parseTurnaLocalDateTime(member.mutedUntil!);
    if (until == null) return 'Sessizde';
    final hh = until.hour.toString().padLeft(2, '0');
    final mm = until.minute.toString().padLeft(2, '0');
    return 'Sessizde • ${until.day.toString().padLeft(2, '0')}.${until.month.toString().padLeft(2, '0')} $hh:$mm';
  }

  Future<String?> _promptForText({
    required String title,
    required String initialValue,
    required String hintText,
    int maxLines = 1,
    int maxLength = 80,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              maxLength: maxLength,
              textCapitalization: maxLines == 1
                  ? TextCapitalization.words
                  : TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hintText),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return value;
  }

  Future<void> _applyGroupDetailUpdate({
    String? title,
    String? description,
    String? avatarObjectKey,
    bool clearAvatar = false,
  }) async {
    if (_savingDetail) return;
    setState(() {
      _savingDetail = true;
      _error = null;
    });
    try {
      final detail = await ChatApi.updateGroupDetail(
        widget.session,
        chatId: widget.chat.chatId,
        title: title,
        description: description,
        avatarObjectKey: avatarObjectKey,
        clearAvatar: clearAvatar,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _savingDetail = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingDetail = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _editGroupTitle() async {
    final value = await _promptForText(
      title: 'Grup adı',
      initialValue: _groupTitle,
      hintText: 'Grup adı',
      maxLength: 80,
    );
    if (value == null || value.trim().isEmpty || value.trim() == _groupTitle) {
      return;
    }
    await _applyGroupDetailUpdate(title: value);
  }

  Future<void> _editGroupDescription() async {
    final value = await _promptForText(
      title: 'Grup açıklaması',
      initialValue: _groupDescription ?? '',
      hintText: 'Bu grup hakkında kısa bir açıklama yaz',
      maxLines: 4,
      maxLength: 240,
    );
    if (value == null) return;
    if (value.trim() == (_groupDescription ?? '').trim()) return;
    await _applyGroupDetailUpdate(description: value);
  }

  Future<void> _changeGroupAvatar() async {
    if (!_canEditInfo || _savingDetail) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeriden seç'),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
              if ((_groupAvatarUrl ?? '').trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Fotoğrafı kaldır'),
                  onTap: () => Navigator.of(context).pop('clear'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == 'clear') {
      await _applyGroupDetailUpdate(clearAvatar: true);
      return;
    }

    final file = await _avatarPicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: kInlineImagePickerQuality,
      maxWidth: kInlineImagePickerMaxDimension,
      maxHeight: kInlineImagePickerMaxDimension,
    );
    if (file == null) return;

    setState(() {
      _savingDetail = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final contentType =
          guessContentTypeForFileName(file.name) ?? 'image/jpeg';
      final upload = await ProfileApi.createAvatarUpload(
        widget.session,
        contentType: contentType,
        fileName: file.name,
      );
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Grup fotoğrafı yüklenemedi.');
      }
      final detail = await ChatApi.updateGroupDetail(
        widget.session,
        chatId: widget.chat.chatId,
        avatarObjectKey: upload.objectKey,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _savingDetail = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingDetail = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Gruptan ayrıl'),
          content: const Text('Gruptan ayrılmak istediğinize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ayrıl'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || _leaving) return;

    setState(() {
      _leaving = true;
      _error = null;
    });
    try {
      await ChatApi.leaveGroup(widget.session, widget.chat.chatId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _leaving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openAddMembers() async {
    if (!_canAddMembers) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TurnaAddGroupMembersPage(
          session: widget.session,
          chatId: widget.chat.chatId,
          existingUserIds: _members.map((item) => item.userId).toSet(),
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || added != true) return;
    await _load(showLoading: false);
  }

  Future<void> _removeMember(TurnaGroupMember member) async {
    if (!_canRemoveMember(member)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Üyeyi çıkar'),
          content: Text(
            '${member.displayName} kişisini bu gruptan çıkarmak istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Çıkar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _error = null);
    try {
      await ChatApi.removeGroupMember(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _changeMemberRole(TurnaGroupMember member) async {
    final options = _availableRoleOptionsFor(member);
    if (options.isEmpty) return;
    final nextRole = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final role in options)
                ListTile(
                  leading: Icon(
                    member.role.trim().toUpperCase() == role
                        ? Icons.check_circle_rounded
                        : Icons.shield_outlined,
                  ),
                  title: Text(_roleLabel(role)),
                  onTap: () => Navigator.of(context).pop(role),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (nextRole == null || nextRole == member.role.trim().toUpperCase()) {
      return;
    }

    setState(() => _error = null);
    try {
      await ChatApi.updateGroupMemberRole(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
        role: nextRole,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _muteMember(TurnaGroupMember member) async {
    if (!_canRemoveMember(member)) return;
    final duration = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Süreli mute seç',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timelapse_rounded),
                title: const Text('1 Saat'),
                onTap: () => Navigator.of(context).pop('1_HOUR'),
              ),
              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: const Text('24 Saat'),
                onTap: () => Navigator.of(context).pop('24_HOURS'),
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Kalıcı'),
                onTap: () => Navigator.of(context).pop('PERMANENT'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (duration == null) return;
    setState(() => _error = null);
    try {
      await ChatApi.muteGroupMember(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
        duration: duration,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _unmuteMember(TurnaGroupMember member) async {
    if (!_canRemoveMember(member)) return;
    setState(() => _error = null);
    try {
      await ChatApi.unmuteGroupMember(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _banMember(TurnaGroupMember member) async {
    if (!_canBanMember(member)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Üyeyi yasakla'),
          content: Text(
            '${member.displayName} kişisini gruptan yasaklamak istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: TurnaColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yasakla'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _error = null);
    try {
      await ChatApi.banGroupMember(
        widget.session,
        chatId: widget.chat.chatId,
        memberUserId: member.userId,
      );
      if (!mounted) return;
      await _load(showLoading: false);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _openMemberModeration(TurnaGroupMember member) async {
    final canRole = _availableRoleOptionsFor(member).isNotEmpty;
    final canMute = _canRemoveMember(member);
    final canBan = _canBanMember(member);
    final canRemove = _canRemoveMember(member);
    if (!canRole && !canMute && !canBan && !canRemove) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canRole)
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Rolü değiştir'),
                  onTap: () => Navigator.of(context).pop('role'),
                ),
              if (canMute)
                ListTile(
                  leading: Icon(
                    member.isMuted
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                  ),
                  title: Text(
                    member.isMuted ? 'Sessizden çıkar' : 'Sessize al',
                  ),
                  subtitle: member.isMuted
                      ? Text(_formatMuteLabel(member))
                      : null,
                  onTap: () => Navigator.of(
                    context,
                  ).pop(member.isMuted ? 'unmute' : 'mute'),
                ),
              if (canBan)
                ListTile(
                  leading: const Icon(Icons.gpp_bad_outlined),
                  title: const Text('Yasakla'),
                  onTap: () => Navigator.of(context).pop('ban'),
                ),
              if (canRemove)
                ListTile(
                  leading: const Icon(Icons.person_remove_alt_1_outlined),
                  title: const Text('Gruptan çıkar'),
                  onTap: () => Navigator.of(context).pop('remove'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'role':
        await _changeMemberRole(member);
        return;
      case 'mute':
        await _muteMember(member);
        return;
      case 'unmute':
        await _unmuteMember(member);
        return;
      case 'ban':
        await _banMember(member);
        return;
      case 'remove':
        await _removeMember(member);
        return;
    }
  }

  Future<void> _openSettings() async {
    if (!_canOpenSettings || _detail == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupSettingsPage(
          session: widget.session,
          chatId: widget.chat.chatId,
          detail: _detail!,
          members: _members,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (!mounted || changed != true) return;
    await _load(showLoading: false);
  }

  Future<void> _closeGroup() async {
    if (!_canCloseGroup || _closing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Grubu kapat'),
          content: const Text(
            'Bu grubu kapatırsanız sohbet ve içerikler tüm üyeler için kapanır. Devam etmek istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: TurnaColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Grubu Kapat'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() {
      _closing = true;
      _error = null;
    });
    try {
      await ChatApi.closeGroup(widget.session, widget.chat.chatId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _closing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final detail = await ChatApi.fetchChatDetail(
        widget.session,
        widget.chat.chatId,
      );
      final members = await ChatApi.fetchGroupMembers(
        widget.session,
        chatId: widget.chat.chatId,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _members = members.items;
        _totalMemberCount = members.totalCount;
        _hasMoreMembers = members.hasMore;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadMoreMembers() async {
    if (_loadingMoreMembers || !_hasMoreMembers) return;
    setState(() => _loadingMoreMembers = true);
    try {
      final page = await ChatApi.fetchGroupMembers(
        widget.session,
        chatId: widget.chat.chatId,
        offset: _members.length,
      );
      if (!mounted) return;
      final existingIds = _members.map((item) => item.userId).toSet();
      setState(() {
        _members = [
          ..._members,
          ...page.items.where((item) => !existingIds.contains(item.userId)),
        ];
        _totalMemberCount = page.totalCount;
        _hasMoreMembers = page.hasMore;
        _loadingMoreMembers = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMoreMembers = false;
        _error = error.toString();
      });
    }
  }

  Widget _buildHeaderCard() {
    final roleText = _myRole.isEmpty ? null : _roleLabel(_myRole);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: TurnaColors.divider),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: _canEditInfo ? _changeGroupAvatar : null,
                child: _ProfileAvatar(
                  label: _groupTitle,
                  avatarUrl: _groupAvatarUrl,
                  authToken: widget.session.token,
                  radius: 36,
                ),
              ),
              if (_canEditInfo)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: _savingDetail ? null : _changeGroupAvatar,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: TurnaColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _groupTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '$_groupMemberCount üye',
            style: const TextStyle(
              color: TurnaColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if ((_groupDescription ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _groupDescription!.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: TurnaColors.textSoft, height: 1.4),
            ),
          ],
          if (roleText != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: TurnaColors.primary50,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Rolün: $roleText',
                style: const TextStyle(
                  color: TurnaColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (_savingDetail) ...[
            const SizedBox(height: 12),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoTab() {
    return RefreshIndicator(
      onRefresh: () => _load(showLoading: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: TurnaColors.error),
              ),
            ),
          if (_canEditInfo)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TurnaColors.divider),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.drive_file_rename_outline_rounded,
                    ),
                    title: const Text('Grup adını düzenle'),
                    subtitle: Text(
                      _groupTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _editGroupTitle,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notes_rounded),
                    title: const Text('Grup açıklamasını düzenle'),
                    subtitle: Text(
                      (_groupDescription ?? '').trim().isEmpty
                          ? 'Henüz açıklama eklenmedi'
                          : _groupDescription!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _editGroupDescription,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (_canAddMembers)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openAddMembers,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Davet Et'),
              ),
            ),
          if (_canAddMembers) const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _leaving ? null : _leaveGroup,
              icon: _leaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: const Text('Gruptan Ayrıl'),
              style: OutlinedButton.styleFrom(
                foregroundColor: TurnaColors.error,
                side: const BorderSide(color: TurnaColors.error),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          if (_canCloseGroup) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _closing ? null : _closeGroup,
                style: FilledButton.styleFrom(
                  backgroundColor: TurnaColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _closing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever_outlined),
                label: const Text('Grubu Kapat'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    return RefreshIndicator(
      onRefresh: () => _load(showLoading: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              const Text(
                'Üyeler',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_members.length}/$_totalMemberCount',
                style: const TextStyle(
                  color: TurnaColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_canAddMembers) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _openAddMembers,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Üye Ekle'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: TurnaColors.error),
              ),
            ),
          ..._members.map(
            (member) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: TurnaColors.divider),
              ),
              child: Row(
                children: [
                  _ProfileAvatar(
                    label: member.displayName,
                    avatarUrl: member.avatarUrl,
                    authToken: widget.session.token,
                    radius: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatLastSeen(member.lastSeenAt),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: TurnaColors.textMuted,
                          ),
                        ),
                        if (member.isMuted) ...[
                          const SizedBox(height: 3),
                          Text(
                            _formatMuteLabel(member),
                            style: const TextStyle(
                              fontSize: 12,
                              color: TurnaColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: _availableRoleOptionsFor(member).isEmpty
                            ? null
                            : () => _changeMemberRole(member),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: TurnaColors.backgroundMuted,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _roleLabel(member.role),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: TurnaColors.textSoft,
                                ),
                              ),
                              if (_availableRoleOptionsFor(
                                member,
                              ).isNotEmpty) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.expand_more_rounded,
                                  size: 14,
                                  color: TurnaColors.textMuted,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_canRemoveMember(member) ||
                          _canBanMember(member)) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _openMemberModeration(member),
                          borderRadius: BorderRadius.circular(999),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              'Yönet',
                              style: TextStyle(
                                color: TurnaColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(
                child: Text(
                  'Bu grupta henüz üye görünmüyor.',
                  style: TextStyle(color: TurnaColors.textMuted),
                ),
              ),
            ),
          if (_hasMoreMembers) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _loadingMoreMembers ? null : _loadMoreMembers,
                child: Text(
                  _loadingMoreMembers
                      ? 'Yükleniyor...'
                      : 'Daha Fazla Üye Yükle',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Bilgisi'),
        actions: [
          if (_canOpenSettings)
            IconButton(
              tooltip: 'Grup ayarları',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: _loading && _detail == null
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildHeaderCard(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TurnaColors.divider),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: TurnaColors.primary50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      labelColor: TurnaColors.primary,
                      unselectedLabelColor: TurnaColors.textMuted,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Bilgiler'),
                        Tab(text: 'Üyeler'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [_buildInfoTab(), _buildMembersTab()],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TurnaGroupSettingsPage extends StatefulWidget {
  const _TurnaGroupSettingsPage({
    required this.session,
    required this.chatId,
    required this.detail,
    required this.members,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final TurnaChatDetail detail;
  final List<TurnaGroupMember> members;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupSettingsPage> createState() =>
      _TurnaGroupSettingsPageState();
}

class _TurnaGroupSettingsPageState extends State<_TurnaGroupSettingsPage> {
  late TurnaChatDetail _detail;
  late List<TurnaGroupMember> _members;
  bool _saving = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
    _members = widget.members;
  }

  String get _myRole => (_detail.myRole ?? '').trim().toUpperCase();
  bool get _isOwner => _myRole == 'OWNER';
  bool get _isAdmin => _myRole == 'ADMIN';
  bool get _canReviewRequests => _isOwner || _isAdmin;
  bool get _canManageModeration => _isOwner || _isAdmin || _myRole == 'EDITOR';

  void _closePage() {
    Navigator.of(context).pop(_changed);
  }

  bool _policyAllows(String policy) {
    switch (policy.trim().toUpperCase()) {
      case 'EVERYONE':
        return true;
      case 'EDITOR_ONLY':
        return _isOwner || _isAdmin || _myRole == 'EDITOR';
      case 'ADMIN_ONLY':
        return _isOwner || _isAdmin;
      default:
        return _isOwner;
    }
  }

  String _policyLabel(String policy) {
    switch (policy.trim().toUpperCase()) {
      case 'OWNER_ONLY':
        return 'Sadece sahip';
      case 'ADMIN_ONLY':
        return 'Sadece adminler';
      case 'EDITOR_ONLY':
        return 'Editör ve üstü';
      default:
        return 'Herkes';
    }
  }

  Future<void> _applySettings({
    bool? isPublic,
    bool? joinApprovalRequired,
    String? whoCanSend,
    String? whoCanEditInfo,
    String? whoCanInvite,
    String? whoCanAddMembers,
    bool? historyVisibleToNewMembers,
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final detail = await ChatApi.updateGroupSettings(
        widget.session,
        chatId: widget.chatId,
        isPublic: isPublic,
        joinApprovalRequired: joinApprovalRequired,
        whoCanSend: whoCanSend,
        whoCanEditInfo: whoCanEditInfo,
        whoCanInvite: whoCanInvite,
        whoCanAddMembers: whoCanAddMembers,
        historyVisibleToNewMembers: historyVisibleToNewMembers,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _saving = false;
        _changed = true;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _pickPrivacyMode() async {
    final value = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  _detail.isPublic
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: const Text('Açık grup'),
                subtitle: const Text('Bağlantı veya katılım isteği ile büyür.'),
                onTap: () => Navigator.of(context).pop(true),
              ),
              ListTile(
                leading: Icon(
                  !_detail.isPublic
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: const Text('Özel grup'),
                subtitle: const Text(
                  'Sadece davet bağlantısı veya doğrudan ekleme ile girilir.',
                ),
                onTap: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (value == null || value == _detail.isPublic) return;
    await _applySettings(
      isPublic: value,
      joinApprovalRequired: value ? _detail.joinApprovalRequired : false,
    );
  }

  Future<void> _openInviteLinks() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupInviteLinksPage(
          session: widget.session,
          chatId: widget.chatId,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() => _changed = true);
    }
  }

  Future<void> _openJoinRequests() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupJoinRequestsPage(
          session: widget.session,
          chatId: widget.chatId,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() => _changed = true);
    }
  }

  Future<void> _openMuteList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupMuteListPage(
          session: widget.session,
          chatId: widget.chatId,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _openBanList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupBanListPage(
          session: widget.session,
          chatId: widget.chatId,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _pickPolicy({
    required String title,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        const options = <String>[
          'OWNER_ONLY',
          'ADMIN_ONLY',
          'EDITOR_ONLY',
          'EVERYONE',
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              for (final option in options)
                ListTile(
                  leading: Icon(
                    currentValue.trim().toUpperCase() == option
                        ? Icons.check_circle_rounded
                        : Icons.tune_rounded,
                  ),
                  title: Text(_policyLabel(option)),
                  onTap: () => Navigator.of(context).pop(option),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null || selected == currentValue.trim().toUpperCase()) {
      return;
    }
    onSelected(selected);
  }

  Future<void> _transferOwnership() async {
    if (!_isOwner || _saving) return;
    final candidates = _members
        .where((member) => member.userId != widget.session.userId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      setState(() => _error = 'Sahiplik devri için başka bir üye gerekli.');
      return;
    }

    final nextOwner = await showModalBottomSheet<TurnaGroupMember>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Text(
                  'Sahipliği devret',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (final member in candidates)
                ListTile(
                  leading: _ProfileAvatar(
                    label: member.displayName,
                    avatarUrl: member.avatarUrl,
                    authToken: widget.session.token,
                    radius: 20,
                  ),
                  title: Text(member.displayName),
                  subtitle: Text(
                    member.role.trim().toUpperCase() == 'ADMIN'
                        ? 'Admin'
                        : member.role.trim().toUpperCase() == 'EDITOR'
                        ? 'Editör'
                        : 'Üye',
                  ),
                  onTap: () => Navigator.of(context).pop(member),
                ),
            ],
          ),
        );
      },
    );
    if (nextOwner == null) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sahipliği devret'),
          content: Text(
            'Grubun sahipliğini ${nextOwner.displayName} kişisine devretmek istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Devret'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ChatApi.transferGroupOwnership(
        widget.session,
        chatId: widget.chatId,
        newOwnerUserId: nextOwner.userId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _closePage,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Grup Ayarları'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: TurnaColors.error),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TurnaColors.divider),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('Grup tipi'),
                  subtitle: Text(_detail.isPublic ? 'Açık grup' : 'Özel grup'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving ? null : _pickPrivacyMode,
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.approval_outlined),
                  title: const Text('Katılım onayı'),
                  subtitle: Text(
                    _detail.isPublic
                        ? 'Açık gruba katılmak isteyenler onay bekler.'
                        : 'Özel gruplarda yalnızca davet bağlantısı çalışır.',
                  ),
                  value: _detail.isPublic && _detail.joinApprovalRequired,
                  onChanged: !_detail.isPublic || _saving
                      ? null
                      : (value) => _applySettings(joinApprovalRequired: value),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded),
                  title: const Text('Kim mesaj gönderebilir?'),
                  subtitle: Text(_policyLabel(_detail.whoCanSend)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving
                      ? null
                      : () => _pickPolicy(
                          title: 'Kim mesaj gönderebilir?',
                          currentValue: _detail.whoCanSend,
                          onSelected: (value) =>
                              _applySettings(whoCanSend: value),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Kim grup bilgisini düzenleyebilir?'),
                  subtitle: Text(_policyLabel(_detail.whoCanEditInfo)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving
                      ? null
                      : () => _pickPolicy(
                          title: 'Kim grup bilgisini düzenleyebilir?',
                          currentValue: _detail.whoCanEditInfo,
                          onSelected: (value) =>
                              _applySettings(whoCanEditInfo: value),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Kim davet edebilir?'),
                  subtitle: Text(_policyLabel(_detail.whoCanInvite)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving
                      ? null
                      : () => _pickPolicy(
                          title: 'Kim davet edebilir?',
                          currentValue: _detail.whoCanInvite,
                          onSelected: (value) =>
                              _applySettings(whoCanInvite: value),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: const Text('Kim üye ekleyebilir?'),
                  subtitle: Text(_policyLabel(_detail.whoCanAddMembers)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving
                      ? null
                      : () => _pickPolicy(
                          title: 'Kim üye ekleyebilir?',
                          currentValue: _detail.whoCanAddMembers,
                          onSelected: (value) =>
                              _applySettings(whoCanAddMembers: value),
                        ),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.history_toggle_off_rounded),
                  title: const Text('Yeni üyeler eski mesajları görsün'),
                  subtitle: Text(
                    _detail.historyVisibleToNewMembers
                        ? 'Yeni katılanlar önceki mesaj geçmişini görebilir.'
                        : 'Yeni katılanlar yalnızca katıldıktan sonraki mesajları görür.',
                  ),
                  value: _detail.historyVisibleToNewMembers,
                  onChanged: _saving
                      ? null
                      : (value) =>
                            _applySettings(historyVisibleToNewMembers: value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TurnaColors.divider),
            ),
            child: Column(
              children: [
                if (_policyAllows(_detail.whoCanInvite))
                  ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: const Text('Davet bağlantıları'),
                    subtitle: const Text(
                      '7 gün, 30 gün veya sınırsız bağlantı oluştur.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openInviteLinks,
                  ),
                if (_policyAllows(_detail.whoCanInvite))
                  const Divider(height: 1),
                if (_canReviewRequests)
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('Katılım istekleri'),
                    subtitle: const Text(
                      'Bekleyen katılım isteklerini onayla veya reddet.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openJoinRequests,
                  ),
                if (_canReviewRequests) const Divider(height: 1),
                if (_canManageModeration)
                  ListTile(
                    leading: const Icon(Icons.volume_off_outlined),
                    title: const Text('Sessize alınanlar'),
                    subtitle: const Text('Aktif mute listesini gör ve yönet.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openMuteList,
                  ),
                if (_canManageModeration) const Divider(height: 1),
                if (_isOwner || _isAdmin)
                  ListTile(
                    leading: const Icon(Icons.gpp_bad_outlined),
                    title: const Text('Yasaklananlar'),
                    subtitle: const Text('Ban listesini gör ve yasak kaldır.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openBanList,
                  ),
              ],
            ),
          ),
          if (_isOwner) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _transferOwnership,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Sahipliği Devret'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TurnaGroupInviteLinksPage extends StatefulWidget {
  const _TurnaGroupInviteLinksPage({
    required this.session,
    required this.chatId,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupInviteLinksPage> createState() =>
      _TurnaGroupInviteLinksPageState();
}

class _TurnaGroupInviteLinksPageState
    extends State<_TurnaGroupInviteLinksPage> {
  List<TurnaGroupInviteLink> _items = const <TurnaGroupInviteLink>[];
  bool _loading = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  void _closePage() => Navigator.of(context).pop(_changed);

  String _formatInviteExpiry(TurnaGroupInviteLink item) {
    if ((item.revokedAt ?? '').trim().isNotEmpty) return 'İptal edildi';
    if ((item.expiresAt ?? '').trim().isEmpty) return 'Sınırsız';
    final dt = parseTurnaLocalDateTime(item.expiresAt!);
    if (dt == null) return 'Süre bilgisi yok';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatApi.fetchGroupInviteLinks(
        widget.session,
        chatId: widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _createInvite() async {
    final duration = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('7 Gün'),
                onTap: () => Navigator.of(context).pop('7_DAYS'),
              ),
              ListTile(
                leading: const Icon(Icons.date_range_outlined),
                title: const Text('30 Gün'),
                onTap: () => Navigator.of(context).pop('30_DAYS'),
              ),
              ListTile(
                leading: const Icon(Icons.all_inclusive_rounded),
                title: const Text('Sınırsız'),
                onTap: () => Navigator.of(context).pop('UNLIMITED'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (duration == null) return;
    try {
      final created = await ChatApi.createGroupInviteLink(
        widget.session,
        chatId: widget.chatId,
        duration: duration,
      );
      if (!mounted) return;
      setState(() {
        _items = [created, ..._items];
        _changed = true;
      });
      await Clipboard.setData(ClipboardData(text: created.inviteUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Davet bağlantısı kopyalandı.')),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _revokeInvite(TurnaGroupInviteLink item) async {
    try {
      await ChatApi.revokeGroupInviteLink(
        widget.session,
        chatId: widget.chatId,
        inviteLinkId: item.id,
      );
      if (!mounted) return;
      setState(() {
        _items = _items
            .map(
              (entry) => entry.id == item.id
                  ? TurnaGroupInviteLink(
                      id: entry.id,
                      token: entry.token,
                      inviteUrl: entry.inviteUrl,
                      expiresAt: entry.expiresAt,
                      revokedAt: DateTime.now().toIso8601String(),
                      createdAt: entry.createdAt,
                    )
                  : entry,
            )
            .toList(growable: false);
        _changed = true;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _closePage,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Davet Bağlantıları'),
        actions: [
          IconButton(
            onPressed: _createInvite,
            icon: const Icon(Icons.add_link_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: TurnaColors.error),
                    ),
                  ),
                ..._items.map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TurnaColors.divider),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.link_rounded),
                      title: Text(
                        item.inviteUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_formatInviteExpiry(item)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          final messenger = ScaffoldMessenger.of(context);
                          if (value == 'copy') {
                            await Clipboard.setData(
                              ClipboardData(text: item.inviteUrl),
                            );
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Bağlantı kopyalandı.'),
                              ),
                            );
                            return;
                          }
                          if (value == 'revoke') {
                            await _revokeInvite(item);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'copy',
                            child: Text('Kopyala'),
                          ),
                          if ((item.revokedAt ?? '').trim().isEmpty)
                            const PopupMenuItem(
                              value: 'revoke',
                              child: Text('İptal et'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'Henüz davet bağlantısı oluşturulmadı.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TurnaGroupJoinRequestsPage extends StatefulWidget {
  const _TurnaGroupJoinRequestsPage({
    required this.session,
    required this.chatId,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupJoinRequestsPage> createState() =>
      _TurnaGroupJoinRequestsPageState();
}

class _TurnaGroupJoinRequestsPageState
    extends State<_TurnaGroupJoinRequestsPage> {
  List<TurnaGroupJoinRequest> _items = const <TurnaGroupJoinRequest>[];
  bool _loading = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  void _closePage() => Navigator.of(context).pop(_changed);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatApi.fetchGroupJoinRequests(
        widget.session,
        chatId: widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _approve(TurnaGroupJoinRequest request) async {
    try {
      await ChatApi.approveGroupJoinRequest(
        widget.session,
        chatId: widget.chatId,
        requestId: request.id,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.where((item) => item.id != request.id).toList();
        _changed = true;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _reject(TurnaGroupJoinRequest request) async {
    try {
      await ChatApi.rejectGroupJoinRequest(
        widget.session,
        chatId: widget.chatId,
        requestId: request.id,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.where((item) => item.id != request.id).toList();
        _changed = true;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _closePage,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Katılım İstekleri'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: TurnaColors.error),
                    ),
                  ),
                ..._items.map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TurnaColors.divider),
                    ),
                    child: Row(
                      children: [
                        _ProfileAvatar(
                          label: item.displayName,
                          avatarUrl: item.avatarUrl,
                          authToken: widget.session.token,
                          radius: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if ((item.username ?? '').trim().isNotEmpty)
                                Text(
                                  '@${item.username!.trim()}',
                                  style: const TextStyle(
                                    color: TurnaColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _reject(item),
                          child: const Text('Reddet'),
                        ),
                        FilledButton(
                          onPressed: () => _approve(item),
                          child: const Text('Onayla'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'Bekleyen katılım isteği yok.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TurnaGroupMuteListPage extends StatefulWidget {
  const _TurnaGroupMuteListPage({
    required this.session,
    required this.chatId,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupMuteListPage> createState() =>
      _TurnaGroupMuteListPageState();
}

class _TurnaGroupMuteListPageState extends State<_TurnaGroupMuteListPage> {
  List<TurnaGroupMuteEntry> _items = const <TurnaGroupMuteEntry>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatApi.fetchGroupMutes(
        widget.session,
        chatId: widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _unmute(TurnaGroupMuteEntry entry) async {
    try {
      await ChatApi.unmuteGroupMember(
        widget.session,
        chatId: widget.chatId,
        memberUserId: entry.userId,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.where((item) => item.id != entry.id).toList();
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessize Alınanlar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: TurnaColors.error),
                    ),
                  ),
                ..._items.map(
                  (item) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 4,
                    ),
                    leading: _ProfileAvatar(
                      label: item.displayName,
                      avatarUrl: item.avatarUrl,
                      authToken: widget.session.token,
                      radius: 22,
                    ),
                    title: Text(item.displayName),
                    subtitle: Text(
                      (item.mutedUntil ?? '').trim().isEmpty
                          ? 'Kalıcı sessizde'
                          : 'Süre: ${item.mutedUntil}',
                    ),
                    trailing: TextButton(
                      onPressed: () => _unmute(item),
                      child: const Text('Kaldır'),
                    ),
                  ),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'Aktif mute kaydı yok.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TurnaGroupBanListPage extends StatefulWidget {
  const _TurnaGroupBanListPage({
    required this.session,
    required this.chatId,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupBanListPage> createState() => _TurnaGroupBanListPageState();
}

class _TurnaGroupBanListPageState extends State<_TurnaGroupBanListPage> {
  List<TurnaGroupBanEntry> _items = const <TurnaGroupBanEntry>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatApi.fetchGroupBans(
        widget.session,
        chatId: widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _unban(TurnaGroupBanEntry entry) async {
    try {
      await ChatApi.unbanGroupMember(
        widget.session,
        chatId: widget.chatId,
        memberUserId: entry.userId,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.where((item) => item.id != entry.id).toList();
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yasaklananlar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: TurnaColors.error),
                    ),
                  ),
                ..._items.map(
                  (item) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 4,
                    ),
                    leading: _ProfileAvatar(
                      label: item.displayName,
                      avatarUrl: item.avatarUrl,
                      authToken: widget.session.token,
                      radius: 22,
                    ),
                    title: Text(item.displayName),
                    subtitle: Text(
                      item.reason?.trim().isNotEmpty == true
                          ? item.reason!.trim()
                          : 'Aktif yasak',
                    ),
                    trailing: TextButton(
                      onPressed: () => _unban(item),
                      child: const Text('Kaldır'),
                    ),
                  ),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'Aktif yasak kaydı yok.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TurnaAddGroupMembersPage extends StatefulWidget {
  const _TurnaAddGroupMembersPage({
    required this.session,
    required this.chatId,
    required this.existingUserIds,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final Set<String> existingUserIds;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaAddGroupMembersPage> createState() =>
      _TurnaAddGroupMembersPageState();
}

class _TurnaAddGroupMembersPageState extends State<_TurnaAddGroupMembersPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedUserIds = <String>{};
  List<TurnaRegisteredContact> _registeredContacts =
      const <TurnaRegisteredContact>[];
  bool _loading = true;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadContacts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TurnaRegisteredContact> get _filteredContacts {
    final query = _searchController.text.trim().toLowerCase();
    final contacts = _registeredContacts
        .where(
          (contact) =>
              contact.id != widget.session.userId &&
              !widget.existingUserIds.contains(contact.id),
        )
        .toList(growable: false);
    if (query.isEmpty) return contacts;
    return contacts
        .where((contact) {
          final title = contact.resolvedTitle.toLowerCase();
          final username = (contact.username ?? '').toLowerCase();
          final phone = (contact.phone ?? '').toLowerCase();
          return title.contains(query) ||
              username.contains(query.replaceAll('@', '')) ||
              phone.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _loadContacts({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await TurnaContactsDirectory.ensureLoaded(force: force);
      if (!mounted) return;
      if (!TurnaContactsDirectory.permissionGranted) {
        setState(() {
          _loading = false;
          _registeredContacts = const <TurnaRegisteredContact>[];
        });
        return;
      }

      final contacts = TurnaContactsDirectory.snapshotForSync();
      await ProfileApi.syncContacts(widget.session, contacts);
      final registered = await ChatApi.fetchRegisteredContacts(widget.session);
      if (!mounted) return;
      setState(() {
        _registeredContacts = registered;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedUserIds.isEmpty || _adding) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await ChatApi.addGroupMembers(
        widget.session,
        chatId: widget.chatId,
        memberUserIds: _selectedUserIds.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _adding = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _filteredContacts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Üye Ekle'),
        actions: [
          TextButton(
            onPressed: _adding || _selectedUserIds.isEmpty ? null : _submit,
            child: Text(_adding ? 'Ekleniyor...' : 'Ekle'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Kişi ara',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: TurnaColors.backgroundMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _error!,
                style: const TextStyle(color: TurnaColors.error),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !TurnaContactsDirectory.permissionGranted &&
                      _registeredContacts.isEmpty
                ? _CenteredState(
                    icon: Icons.perm_contact_calendar_outlined,
                    title: 'Rehber izni gerekli',
                    message:
                        'Turna kullanan rehber kişilerini görmek için rehber izni ver.',
                    primaryLabel: 'Rehber iznini iste',
                    onPrimary: () => _loadContacts(force: true),
                  )
                : contacts.isEmpty
                ? _CenteredState(
                    icon: Icons.group_outlined,
                    title: 'Eklenebilecek kişi bulunamadı',
                    message:
                        'Rehberindeki kayıtlı Turna kullanıcıları burada listelenecek.',
                    primaryLabel: 'Kişileri yenile',
                    onPrimary: () => _loadContacts(force: true),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: contacts.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      final selected = _selectedUserIds.contains(contact.id);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selectedUserIds.remove(contact.id);
                            } else {
                              _selectedUserIds.add(contact.id);
                            }
                          });
                        },
                        leading: _ProfileAvatar(
                          label: contact.resolvedTitle,
                          avatarUrl: contact.avatarUrl,
                          authToken: widget.session.token,
                          radius: 24,
                        ),
                        title: Text(
                          contact.resolvedTitle,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            if ((contact.username ?? '').trim().isNotEmpty)
                              '@${contact.username!.trim()}',
                            if ((contact.phone ?? '').trim().isNotEmpty)
                              formatTurnaDisplayPhone(contact.phone!),
                          ].join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Checkbox(
                          value: selected,
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedUserIds.remove(contact.id);
                              } else {
                                _selectedUserIds.add(contact.id);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
