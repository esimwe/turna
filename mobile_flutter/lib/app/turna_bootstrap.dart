part of turna_app;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await TurnaFirebase.ensureInitialized();
  await TurnaNativeCallManager.handleBackgroundRemoteMessage(message.data);
}

Future<void> runTurnaMobileApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TurnaAppConfig.load();
  await TurnaFirebase.ensureInitialized();
  await TurnaDeviceContext.ensureLoaded();
  await TurnaLocalStore.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const TurnaApp());
}

class TurnaApp extends StatefulWidget {
  const TurnaApp({super.key});

  @override
  State<TurnaApp> createState() => _TurnaAppState();
}

class _TurnaAppState extends State<TurnaApp> with WidgetsBindingObserver {
  AuthSession? _session;
  bool _bootstrapping = true;
  bool _requestedContactsOnLaunch = false;
  static const Duration _minimumSplashDuration = Duration(milliseconds: 750);
  static const Duration _maximumBootstrapWait = Duration(seconds: 6);

  void _updateSession(AuthSession? session) {
    setState(() => _session = session);
    unawaited(TurnaLiveLocationManager.instance.bindSession(session));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    kTurnaLifecycleState.value = state;
    turnaLog('app lifecycle', state.name);
  }

  Future<void> _bootstrap() async {
    final startedAt = DateTime.now();
    final sessionFuture = _loadStoredSession();
    AuthSession? session;
    var timedOut = false;

    try {
      session = await sessionFuture.timeout(_maximumBootstrapWait);
    } catch (error) {
      if (error is TimeoutException) {
        timedOut = true;
        turnaLog('auth session load timeout', {
          'timeoutMs': _maximumBootstrapWait.inMilliseconds,
        });
      } else {
        turnaLog('auth session load skipped', error);
      }
    }

    final elapsed = DateTime.now().difference(startedAt);
    final remaining = _minimumSplashDuration - elapsed;
    if (!remaining.isNegative) {
      await Future<void>.delayed(remaining);
    }

    if (mounted) {
      setState(() {
        _session = session;
        _bootstrapping = false;
      });
      unawaited(TurnaLiveLocationManager.instance.bindSession(session));
      _requestContactsOnLaunch();
      turnaLog('app init', {
        'hasSession': _session != null,
        'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
        'timedOut': timedOut,
      });
    }

    if (session == null) {
      unawaited(TurnaAppBadge.setCount(0));
    }

    if (timedOut) {
      unawaited(
        sessionFuture
            .then((lateSession) {
              if (!mounted || lateSession == null) return;
              if (_session?.userId == lateSession.userId &&
                  _session?.token == lateSession.token) {
                return;
              }
              _updateSession(lateSession);
              turnaLog('auth session restored after timeout', {
                'hasSession': true,
              });
            })
            .catchError((Object error) {
              turnaLog('late auth session load skipped', error);
            }),
      );
    }

    unawaited(_initializeServices());
  }

  Future<AuthSession?> _loadStoredSession() async {
    return TurnaAuthSessionStore.load();
  }

  Future<void> _initializeServices() async {
    try {
      await TurnaFirebase.ensureInitialized();
    } catch (error) {
      turnaLog('firebase boot init skipped', error);
    }

    try {
      await TurnaNativeCallManager.initialize();
    } catch (error) {
      turnaLog('native call init skipped', error);
    }

    try {
      await TurnaLaunchBridge.initialize();
    } catch (error) {
      turnaLog('launch bridge init skipped', error);
    }

    try {
      await TurnaShareTargetBridge.initialize();
    } catch (error) {
      turnaLog('share target bridge init skipped', error);
    }
  }

  void _requestContactsOnLaunch() {
    if (_requestedContactsOnLaunch) {
      return;
    }
    _requestedContactsOnLaunch = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(TurnaContactsDirectory.ensureLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Turna',
      debugShowCheckedModeBanner: false,
      navigatorKey: kTurnaNavigatorKey,
      navigatorObservers: [kTurnaRouteObserver],
      theme: buildTurnaAppTheme(),
      home: _bootstrapping
          ? const TurnaLaunchPage()
          : _session == null
          ? TurnaPhoneAuthPage(onAuthenticated: _updateSession)
          : _session!.needsOnboarding
          ? TurnaProfileOnboardingPage(
              session: _session!,
              onCompleted: (session) {
                _updateSession(session);
              },
            )
          : TurnaShellHost(
              session: _session!,
              onSessionUpdated: (session) {
                _updateSession(session);
              },
              onLogout: () async {
                final activeSession = _session;
                if (activeSession != null) {
                  try {
                    await AuthApi.logout(activeSession);
                  } catch (_) {}
                }
                await TurnaAuthSessionStore.clear();
                await TurnaAppBadge.setCount(0);
                _updateSession(null);
              },
            ),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.onAuthenticated});

  final void Function(AuthSession session) onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _isRegisterMode = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty) {
      setState(() => _error = 'Username gir.');
      return;
    }
    if (password.length < 4) {
      setState(() => _error = 'Şifre en az 4 karakter olmalı.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final endpoint = _isRegisterMode ? 'register' : 'login';
      turnaLog('auth submit', {'mode': endpoint, 'username': username});
      final payload = <String, dynamic>{
        'username': username,
        'password': password,
      };

      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/auth/$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 400) {
        turnaLog('auth failed', {
          'statusCode': res.statusCode,
          'body': res.body,
        });
        final body = jsonDecode(res.body);
        setState(
          () => _error = 'İşlem başarısız: ${body['error'] ?? res.statusCode}',
        );
        return;
      }
      turnaLog('auth success', {'statusCode': res.statusCode});

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final token = map['accessToken']?.toString();
      final user = map['user'] as Map<String, dynamic>?;
      final userId = user?['id']?.toString();
      final displayName = user?['displayName']?.toString() ?? username;
      final avatarUrl = user?['avatarUrl']?.toString();
      if (token == null || userId == null) {
        setState(() => _error = 'Sunucu yanıtı geçersiz.');
        return;
      }

      final session = AuthSession(
        token: token,
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
      await TurnaAuthSessionStore.save(session);
      widget.onAuthenticated(session);
    } catch (_) {
      turnaLog('auth exception');
      setState(() => _error = 'Sunucuya bağlanılamadı.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turna Giriş')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _isRegisterMode
                ? 'Username ve şifre ile kayıt ol.'
                : 'Username ve şifre ile giriş yap.',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Şifre',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Text(
              _loading
                  ? 'Bekleyin...'
                  : (_isRegisterMode ? 'Kayıt Ol' : 'Giriş Yap'),
            ),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _error = null;
                      _isRegisterMode = !_isRegisterMode;
                    });
                  },
            child: Text(
              _isRegisterMode
                  ? 'Hesabım var, giriş yap'
                  : 'Hesabım yok, kayıt ol',
            ),
          ),
        ],
      ),
    );
  }
}
