part of turna_app;

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
    final authenticated = await authenticateTurnaDeviceAccess(
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
              child: TurnaAppLockOverlay(
                busy: _appLockBusy,
                unlockMethodLabel: turnaDeviceUnlockMethodLabel(),
                onUnlock: _promptAppUnlock,
              ),
            ),
        ],
      ),
    );
  }
}
