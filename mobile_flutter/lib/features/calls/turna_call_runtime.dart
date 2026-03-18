part of '../../app/turna_app.dart';

class _TurnaPendingNativeAction {
  const _TurnaPendingNativeAction({required this.action, required this.body});

  final String action;
  final Map<String, dynamic> body;

  Map<String, dynamic> toMap() => {'action': action, 'body': body};

  factory _TurnaPendingNativeAction.fromMap(Map<String, dynamic> map) {
    return _TurnaPendingNativeAction(
      action: (map['action'] ?? '').toString(),
      body: Map<String, dynamic>.from(map['body'] as Map? ?? const {}),
    );
  }
}

class TurnaNativeCallManager {
  static const _pendingActionKey = 'turna_pending_native_call_action';
  static const _lastVoipPushTokenKey = 'turna_last_voip_push_token';
  static bool _initialized = false;
  static bool _androidPermissionsRequested = false;
  static AuthSession? _session;
  static TurnaCallCoordinator? _coordinator;
  static VoidCallback? _onSessionExpired;
  static final Set<String> _handledActionKeys = <String>{};
  static final Set<String> _suppressedEndEvents = <String>{};
  static final Set<String> _shownIncomingCalls = <String>{};
  static String? _activeCallId;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      Future<void>(() async {
        await _handleCallkitEvent(event);
      });
    });

    if (Platform.isAndroid) {
      await _requestAndroidPermissions();
    }
  }

  static Future<void> bindSession({
    required AuthSession session,
    required TurnaCallCoordinator coordinator,
    required VoidCallback onSessionExpired,
  }) async {
    _session = session;
    _coordinator = coordinator;
    _onSessionExpired = onSessionExpired;
    if (Platform.isAndroid) {
      await _requestAndroidPermissions();
    }
    await syncVoipToken(session);
    await _reconcileStaleCalls(session);
    await _consumePendingAction();
    await _recoverAcceptedNativeCall();
  }

  static void unbindSession(String userId) {
    if (_session?.userId != userId) return;
    _session = null;
    _coordinator = null;
    _onSessionExpired = null;
  }

  static Future<void> handleAppResumed() async {
    final session = _session;
    if (session != null) {
      await _reconcileStaleCalls(session);
    }
    await _consumePendingAction();
    await _recoverAcceptedNativeCall();
  }

  static Future<void> clearSessionArtifacts() async {
    _session = null;
    _coordinator = null;
    _onSessionExpired = null;
    _handledActionKeys.clear();
    _suppressedEndEvents.clear();
    _shownIncomingCalls.clear();
    _activeCallId = null;
    await TurnaSecureStateStore.delete(_lastVoipPushTokenKey);
    await TurnaSecureStateStore.delete(_pendingActionKey);
  }

  static Future<void> _reconcileStaleCalls(AuthSession session) async {
    try {
      final reconciledCallIds = await CallApi.reconcileCalls(session);
      for (final callId in reconciledCallIds) {
        await endCallUi(callId);
      }
    } catch (error) {
      turnaLog('call reconcile skipped', error);
    }
  }

  static Future<void> handleBackgroundRemoteMessage(
    Map<String, dynamic> data,
  ) async {
    await initialize();
    final type = (data['type'] ?? '').toString();
    if (type == 'incoming_call') {
      await _showIncomingCallkitIfNeeded(data);
      return;
    }
    if (type == 'call_ended') {
      final callId = _readCallId(data);
      if (callId != null) {
        await endCallUi(callId);
      }
    }
  }

  static Future<void> handleForegroundRemoteMessage(
    Map<String, dynamic> data,
  ) async {
    final type = (data['type'] ?? '').toString();
    if (type == 'call_ended') {
      final callId = _readCallId(data);
      if (callId != null) {
        await endCallUi(callId);
      }
    }
  }

  static Future<void> syncVoipToken(AuthSession session) async {
    if (!Platform.isIOS) return;
    try {
      final token = (await FlutterCallkitIncoming.getDevicePushTokenVoIP())
          ?.toString()
          .trim();
      if (token == null || token.isEmpty) return;
      final previous = await TurnaSecureStateStore.readString(
        _lastVoipPushTokenKey,
      );
      if (previous == token) return;
      await PushApi.registerDevice(
        session,
        token: token,
        platform: 'ios',
        tokenKind: 'voip',
        deviceLabel: 'ios-voip',
      );
      await TurnaSecureStateStore.writeString(_lastVoipPushTokenKey, token);
      turnaLog('voip token synced');
    } catch (error) {
      turnaLog('voip token sync skipped', error);
    }
  }

  static Future<void> setCallConnected(String callId) async {
    _activeCallId = callId;
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (error) {
      turnaLog('native call connected skipped', error);
    }
  }

  static Future<void> endCallUi(String callId) async {
    _shownIncomingCalls.remove(callId);
    if (_activeCallId == callId) {
      _activeCallId = null;
    }
    _suppressedEndEvents.add(callId);
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (error) {
      turnaLog('native call end skipped', error);
      _suppressedEndEvents.remove(callId);
    }
  }

  static Future<void> _requestAndroidPermissions() async {
    if (!Platform.isAndroid || _androidPermissionsRequested) return;
    _androidPermissionsRequested = true;
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Bildirim izni',
        'rationaleMessagePermission':
            'Gelen aramaları gösterebilmek için bildirim izni gerekiyor.',
        'postNotificationMessageRequired':
            'Gelen aramaları gösterebilmek için bildirim izni ver.',
      });
    } catch (error) {
      turnaLog('android notification permission skipped', error);
    }
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (error) {
      turnaLog('android full intent permission skipped', error);
    }
  }

  static Future<void> _handleCallkitEvent(CallEvent event) async {
    final body = _normalizeBody(event.body);
    final callId = _readCallId(body);
    switch (event.event) {
      case Event.actionDidUpdateDevicePushTokenVoip:
        final session = _session;
        if (session != null) {
          await syncVoipToken(session);
        }
        return;
      case Event.actionCallIncoming:
        if (callId != null) {
          _shownIncomingCalls.add(callId);
        }
        return;
      case Event.actionCallAccept:
        await _queueOrHandleAction('accept', body);
        return;
      case Event.actionCallDecline:
        await _queueOrHandleAction('decline', body);
        return;
      case Event.actionCallEnded:
        if (callId != null && _suppressedEndEvents.remove(callId)) {
          return;
        }
        await _queueOrHandleAction('end', body);
        return;
      case Event.actionCallTimeout:
        await _queueOrHandleAction('timeout', body);
        return;
      default:
        return;
    }
  }

  static Future<void> _queueOrHandleAction(
    String action,
    Map<String, dynamic> body,
  ) async {
    final handled = await _handleAction(action, body);
    if (handled) {
      await _clearPendingAction();
      return;
    }
    await _persistPendingAction(
      _TurnaPendingNativeAction(action: action, body: body),
    );
  }

  static Future<bool> _handleAction(
    String action,
    Map<String, dynamic> body,
  ) async {
    final session = _session;
    final coordinator = _coordinator;
    if (session == null || coordinator == null) return false;

    final callId = _readCallId(body);
    if (callId == null || callId.isEmpty) return false;
    final actionKey = '$action:$callId';
    if (_handledActionKeys.contains(actionKey)) {
      return true;
    }

    try {
      switch (action) {
        case 'accept':
          final accepted = await CallApi.acceptCall(session, callId: callId);
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          _shownIncomingCalls.remove(callId);
          await _openAcceptedCall(session, coordinator, accepted);
          return true;
        case 'decline':
          await CallApi.declineCall(session, callId: callId);
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          await endCallUi(callId);
          return true;
        case 'end':
          await CallApi.endCall(session, callId: callId);
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          await endCallUi(callId);
          return true;
        case 'timeout':
          coordinator.clearCall(callId);
          _handledActionKeys.add(actionKey);
          await endCallUi(callId);
          return true;
        default:
          return false;
      }
    } on TurnaUnauthorizedException {
      _onSessionExpired?.call();
      return true;
    } catch (error) {
      turnaLog('native call action failed', {
        'action': action,
        'callId': callId,
        'error': error.toString(),
      });
      return false;
    }
  }

  static Future<void> _openAcceptedCall(
    AuthSession session,
    TurnaCallCoordinator coordinator,
    TurnaAcceptedCallEvent accepted,
  ) async {
    if (_activeCallId == accepted.call.id) return;
    await Future<void>.delayed(Duration.zero);
    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    _activeCallId = accepted.call.id;
    final returnChat = buildDirectChatPreviewForCall(session, accepted.call);
    final callSession = kTurnaCallUiController.obtainSession(
      session: session,
      coordinator: coordinator,
      call: accepted.call,
      connect: accepted.connect,
      onSessionExpired: _onSessionExpired ?? () {},
      returnChatOnExit: returnChat,
    );
    await navigator.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'active-call'),
        builder: (_) => ActiveCallPage(callSession: callSession),
      ),
    );
  }

  static Future<void> _recoverAcceptedNativeCall() async {
    final session = _session;
    if (session == null) return;
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls is! List || activeCalls.isEmpty) return;
      for (final item in activeCalls) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final accepted = map['accepted'] == true || map['isAccepted'] == true;
        if (!accepted) continue;
        final callId = _readCallId(map);
        if (callId == null || callId.isEmpty) continue;
        await _handleAction('accept', map);
        break;
      }
    } catch (error) {
      turnaLog('active native call recovery skipped', error);
    }
  }

  static Future<void> _persistPendingAction(
    _TurnaPendingNativeAction action,
  ) async {
    await TurnaSecureStateStore.writeString(
      _pendingActionKey,
      jsonEncode(action.toMap()),
    );
  }

  static Future<void> _clearPendingAction() async {
    await TurnaSecureStateStore.delete(_pendingActionKey);
  }

  static Future<void> _consumePendingAction() async {
    final raw = await TurnaSecureStateStore.readString(_pendingActionKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final pending = _TurnaPendingNativeAction.fromMap(map);
      final handled = await _handleAction(pending.action, pending.body);
      if (handled) {
        await TurnaSecureStateStore.delete(_pendingActionKey);
      }
    } catch (error) {
      turnaLog('pending native call action parse failed', error);
      await TurnaSecureStateStore.delete(_pendingActionKey);
    }
  }

  static Map<String, dynamic> _normalizeBody(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  static String? _readCallId(Map<String, dynamic> map) {
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : const <String, dynamic>{};
    final id = map['id'] ?? map['callId'] ?? extra['callId'] ?? extra['id'];
    final value = id?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static String _readCallerName(Map<String, dynamic> map) {
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : const <String, dynamic>{};
    return (map['callerDisplayName'] ??
                map['nameCaller'] ??
                extra['callerDisplayName'] ??
                map['handle'] ??
                'Turna')
            .toString()
            .trim()
            .isEmpty
        ? 'Turna'
        : (map['callerDisplayName'] ??
                  map['nameCaller'] ??
                  extra['callerDisplayName'] ??
                  map['handle'] ??
                  'Turna')
              .toString();
  }

  static bool _readIsVideo(Map<String, dynamic> map) {
    final extra = map['extra'] is Map
        ? Map<String, dynamic>.from(map['extra'] as Map)
        : const <String, dynamic>{};
    final raw =
        map['isVideo'] ??
        map['callType'] ??
        extra['callType'] ??
        extra['isVideo'];
    if (raw is bool) return raw;
    final text = raw?.toString().toLowerCase();
    return text == 'video' || text == 'true' || text == '1';
  }

  static Future<void> _showIncomingCallkitIfNeeded(
    Map<String, dynamic> payload,
  ) async {
    final callId = _readCallId(payload);
    if (callId == null || callId.isEmpty) return;
    if (_shownIncomingCalls.contains(callId)) return;
    if (Platform.isIOS) {
      return;
    }

    _shownIncomingCalls.add(callId);
    final isVideo = _readIsVideo(payload);
    final callerName = _readCallerName(payload);
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Turna',
      handle: callerName,
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'Ac',
      textDecline: 'Reddet',
      extra: <String, dynamic>{
        'callId': callId,
        'callerId': (payload['callerId'] ?? '').toString(),
        'callerDisplayName': callerName,
        'callType': isVideo ? 'video' : 'audio',
      },
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Cevapsız arama',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#101314',
        actionColor: '#2F80ED',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Turna Arama',
        missedCallNotificationChannelName: 'Turna Cevapsız',
        isShowCallID: false,
        isShowFullLockedScreen: true,
        isImportant: true,
      ),
      ios: IOSParams(
        handleType: 'generic',
        supportsVideo: isVideo,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (error) {
      _shownIncomingCalls.remove(callId);
      turnaLog('native incoming call show failed', error);
    }
  }
}

abstract class CallProviderAdapter {
  Future<void> connect();
  Future<void> disconnect();
}

enum _AdaptiveCallVideoProfile { low, medium, standard, high }

extension _AdaptiveCallVideoProfileX on _AdaptiveCallVideoProfile {
  String get label => switch (this) {
    _AdaptiveCallVideoProfile.low => '360p',
    _AdaptiveCallVideoProfile.medium => '540p',
    _AdaptiveCallVideoProfile.standard => '720p',
    _AdaptiveCallVideoProfile.high => '1080p',
  };

  lk.VideoParameters get parameters => switch (this) {
    _AdaptiveCallVideoProfile.low => lk.VideoParametersPresets.h360_169,
    _AdaptiveCallVideoProfile.medium => lk.VideoParametersPresets.h540_169,
    _AdaptiveCallVideoProfile.standard => lk.VideoParametersPresets.h720_169,
    _AdaptiveCallVideoProfile.high => lk.VideoParametersPresets.h1080_169,
  };
}

class LiveKitCallAdapter extends ChangeNotifier implements CallProviderAdapter {
  static const _initialVideoProfile = _AdaptiveCallVideoProfile.standard;

  LiveKitCallAdapter({
    required this.connectPayload,
    required this.videoEnabled,
  });

  final TurnaCallConnectPayload connectPayload;
  bool videoEnabled;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  bool connecting = false;
  bool connected = false;
  bool microphoneEnabled = true;
  bool cameraEnabled = false;
  bool speakerEnabled = false;
  lk.CameraPosition cameraPosition = lk.CameraPosition.front;
  _AdaptiveCallVideoProfile _videoProfile = _initialVideoProfile;
  bool _cameraRetryScheduled = false;
  bool _videoProfileUpdateInFlight = false;
  int _excellentQualityStreak = 0;
  int _goodQualityStreak = 0;
  int _poorQualityStreak = 0;
  String? error;
  String? mediaError;

  lk.Room get room {
    final current = _room;
    if (current == null) {
      throw StateError('livekit_room_not_initialized');
    }
    return current;
  }

  String get videoQualityLabel => _videoProfile.label;

  Iterable<lk.RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[];
  lk.LocalParticipant? get localParticipant => _room?.localParticipant;

  List<lk.Participant> get activeSpeakers => List<lk.Participant>.from(
    _room?.activeSpeakers ?? const <lk.Participant>[],
  );

  lk.VideoTrack? get primaryRemoteVideoTrack {
    final currentRoom = _room;
    if (currentRoom == null) return null;
    for (final participant in currentRoom.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track is lk.VideoTrack &&
            publication.subscribed &&
            !publication.muted &&
            publication.streamState == lk.StreamState.active) {
          return track;
        }
      }
    }
    return null;
  }

  lk.VideoTrack? videoTrackForParticipant(lk.Participant participant) {
    final publications = participant.videoTrackPublications;
    for (final publication in publications) {
      final track = publication.track;
      final hasActiveStream =
          publication is lk.RemoteTrackPublication<lk.RemoteVideoTrack>
          ? publication.streamState == lk.StreamState.active
          : true;
      if (track is lk.VideoTrack &&
          publication.subscribed &&
          !publication.muted &&
          hasActiveStream) {
        return track;
      }
    }
    return null;
  }

  lk.VideoTrack? get localVideoTrack {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return null;
    for (final publication in localParticipant.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.VideoTrack) {
        return track;
      }
    }
    return null;
  }

  lk.LocalVideoTrack? get localCameraTrack {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return null;
    for (final publication in localParticipant.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.LocalVideoTrack) {
        return track;
      }
    }
    return null;
  }

  Future<lk.Room> _buildRoom() async {
    return lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: true,
        dynacast: false,
        defaultCameraCaptureOptions: lk.CameraCaptureOptions(
          params: _initialVideoProfile.parameters,
        ),
        defaultAudioCaptureOptions: const lk.AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        ),
        defaultAudioPublishOptions: const lk.AudioPublishOptions(
          encoding: lk.AudioEncoding(
            maxBitrate: 24000,
            bitratePriority: lk.Priority.high,
            networkPriority: lk.Priority.high,
          ),
          dtx: true,
          red: true,
        ),
        defaultAudioOutputOptions: lk.AudioOutputOptions(speakerOn: false),
      ),
    );
  }

  Future<bool> _enableCameraWithFallback(
    lk.LocalParticipant localParticipant, {
    required String origin,
  }) async {
    if (Platform.isIOS && origin == 'initial_connect') {
      turnaLog('livekit camera waiting for active lifecycle', {
        'lifecycle': kTurnaLifecycleState.value.name,
      });
      await _waitForActiveLifecycle();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    final attempts =
        <
          ({
            String label,
            _AdaptiveCallVideoProfile? profile,
            lk.CameraCaptureOptions? options,
          })
        >[
          (
            label: 'safe_default',
            profile: _videoProfile,
            options: lk.CameraCaptureOptions(
              cameraPosition: cameraPosition,
              params: _videoProfile.parameters,
            ),
          ),
          (label: 'default', profile: null, options: null),
        ];

    Object? lastError;
    for (final attempt in attempts) {
      try {
        await localParticipant.setCameraEnabled(
          true,
          cameraCaptureOptions: attempt.options,
        );
        cameraEnabled = true;
        if (attempt.profile != null) {
          _videoProfile = attempt.profile!;
        }
        turnaLog('livekit camera enabled', {
          'origin': origin,
          'attempt': attempt.label,
          'profile': _videoProfile.label,
        });
        return true;
      } catch (err) {
        lastError = err;
        turnaLog('livekit camera enable failed', {
          'origin': origin,
          'attempt': attempt.label,
          'error': '$err',
        });
      }
    }

    cameraEnabled = false;
    turnaLog('livekit camera enable exhausted', {
      'origin': origin,
      'error': '$lastError',
    });
    if (Platform.isIOS &&
        origin == 'initial_connect' &&
        connected &&
        !_cameraRetryScheduled) {
      _cameraRetryScheduled = true;
      unawaited(_retryCameraAfterDelay(localParticipant));
    }
    return false;
  }

  Future<void> _waitForActiveLifecycle() async {
    if (kTurnaLifecycleState.value == AppLifecycleState.resumed) {
      return;
    }

    final completer = Completer<void>();
    late VoidCallback listener;
    Timer? timeout;
    listener = () {
      if (kTurnaLifecycleState.value == AppLifecycleState.resumed) {
        timeout?.cancel();
        kTurnaLifecycleState.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    };

    timeout = Timer(const Duration(seconds: 3), () {
      kTurnaLifecycleState.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    kTurnaLifecycleState.addListener(listener);
    await completer.future;
  }

  Future<void> _retryCameraAfterDelay(
    lk.LocalParticipant localParticipant,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!connected || cameraEnabled) {
      _cameraRetryScheduled = false;
      return;
    }
    await _waitForActiveLifecycle();
    await _enableCameraWithFallback(localParticipant, origin: 'initial_retry');
    _cameraRetryScheduled = false;
    notifyListeners();
  }

  void _resetConnectionQualityState() {
    _excellentQualityStreak = 0;
    _goodQualityStreak = 0;
    _poorQualityStreak = 0;
  }

  Future<void> _applyVideoProfile(
    _AdaptiveCallVideoProfile nextProfile, {
    required String reason,
  }) async {
    if (_videoProfileUpdateInFlight || _videoProfile == nextProfile) return;
    final track = localCameraTrack;
    if (track == null) return;

    _videoProfileUpdateInFlight = true;
    try {
      await track.restartTrack(
        lk.CameraCaptureOptions(
          cameraPosition: cameraPosition,
          params: nextProfile.parameters,
        ),
      );
      _videoProfile = nextProfile;
      turnaLog('livekit video profile changed', {
        'reason': reason,
        'profile': nextProfile.label,
      });
      notifyListeners();
    } catch (err) {
      turnaLog('livekit video profile change failed', {
        'reason': reason,
        'profile': nextProfile.label,
        'error': '$err',
      });
    } finally {
      _videoProfileUpdateInFlight = false;
    }
  }

  @override
  Future<void> connect() async {
    if (connecting || connected) return;

    connecting = true;
    error = null;
    mediaError = null;
    notifyListeners();

    try {
      _room ??= await _buildRoom();

      _listener?.dispose();
      _listener = room.createListener()
        ..on<lk.RoomDisconnectedEvent>((_) {
          connected = false;
          connecting = false;
          notifyListeners();
        })
        ..on<lk.ParticipantConnectedEvent>((_) => notifyListeners())
        ..on<lk.ParticipantDisconnectedEvent>((_) => notifyListeners())
        ..on<lk.TrackSubscribedEvent>((_) => notifyListeners())
        ..on<lk.TrackUnsubscribedEvent>((_) => notifyListeners())
        ..on<lk.TrackMutedEvent>((_) => notifyListeners())
        ..on<lk.TrackUnmutedEvent>((_) => notifyListeners())
        ..on<lk.TrackStreamStateUpdatedEvent>((_) => notifyListeners())
        ..on<lk.LocalTrackPublishedEvent>((_) => notifyListeners())
        ..on<lk.LocalTrackUnpublishedEvent>((_) => notifyListeners())
        ..on<lk.ActiveSpeakersChangedEvent>((_) => notifyListeners())
        ..on<lk.ParticipantConnectionQualityUpdatedEvent>(
          _handleConnectionQualityUpdated,
        );

      await room.prepareConnection(connectPayload.url, connectPayload.token);
      await room.connect(connectPayload.url, connectPayload.token);
      connected = true;
      connecting = false;
      error = null;
      _cameraRetryScheduled = false;
      _resetConnectionQualityState();
      notifyListeners();

      final localParticipant = room.localParticipant;
      if (localParticipant == null) {
        throw StateError('local_participant_missing');
      }

      try {
        await localParticipant.setMicrophoneEnabled(true);
        microphoneEnabled = true;
      } catch (err) {
        mediaError = 'Mikrofon acilamadi.';
        turnaLog('livekit microphone enable failed', err);
      }

      try {
        speakerEnabled = false;
        await room.setSpeakerOn(false);
      } catch (err) {
        turnaLog('livekit speaker configure failed', err);
      }

      notifyListeners();

      if (videoEnabled) {
        final cameraReady = await _enableCameraWithFallback(
          localParticipant,
          origin: 'initial_connect',
        );
        if (!cameraReady) {
          mediaError = 'Kamera acilamadi.';
        } else if (mediaError == 'Kamera acilamadi.') {
          mediaError = null;
        }
        notifyListeners();
      }
    } catch (err) {
      connected = false;
      connecting = false;
      error = 'Cagri baglantisi kurulamadi.';
      turnaLog('livekit connect failed', err);
      notifyListeners();
    }
  }

  Future<void> toggleMicrophone() async {
    final next = !microphoneEnabled;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    await localParticipant.setMicrophoneEnabled(next);
    microphoneEnabled = next;
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    if (!videoEnabled) return;
    final next = !cameraEnabled;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    if (next) {
      final enabled = await _enableCameraWithFallback(
        localParticipant,
        origin: 'toggle_camera',
      );
      cameraEnabled = enabled;
      if (enabled) {
        if (mediaError == 'Kamera acilamadi.') {
          mediaError = null;
        }
      } else {
        mediaError = 'Kamera acilamadi.';
      }
    } else {
      await localParticipant.setCameraEnabled(false);
      cameraEnabled = false;
    }
    notifyListeners();
  }

  Future<void> enableVideoMode({bool enableCamera = true}) async {
    if (videoEnabled) {
      if (enableCamera && connected && !cameraEnabled) {
        await toggleCamera();
      }
      return;
    }

    videoEnabled = true;
    notifyListeners();

    if (!connected || !enableCamera) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null || cameraEnabled) return;

    final enabled = await _enableCameraWithFallback(
      localParticipant,
      origin: 'video_upgrade_accept',
    );
    cameraEnabled = enabled;
    if (enabled) {
      if (mediaError == 'Kamera acilamadi.') {
        mediaError = null;
      }
    } else {
      mediaError = 'Kamera acilamadi.';
    }
    notifyListeners();
  }

  Future<void> flipCamera() async {
    final track = localCameraTrack;
    if (track == null) return;
    final previousPosition = cameraPosition;
    final nextPosition = previousPosition.switched();
    cameraPosition = nextPosition;
    notifyListeners();
    try {
      await track.setCameraPosition(nextPosition);
    } catch (err) {
      cameraPosition = previousPosition;
      notifyListeners();
      turnaLog('livekit flip camera failed', err);
    }
  }

  Future<void> toggleSpeaker() async {
    if (_room == null) return;
    final next = !speakerEnabled;
    await room.setSpeakerOn(next);
    speakerEnabled = next;
    notifyListeners();
  }

  void _handleConnectionQualityUpdated(
    lk.ParticipantConnectionQualityUpdatedEvent event,
  ) {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return;
    if (event.participant.identity != localParticipant.identity) return;
    if (!videoEnabled || !cameraEnabled) return;

    switch (event.connectionQuality) {
      case lk.ConnectionQuality.excellent:
        _excellentQualityStreak += 1;
        _goodQualityStreak += 1;
        _poorQualityStreak = 0;
        if (_videoProfile != _AdaptiveCallVideoProfile.high &&
            _excellentQualityStreak >= 3) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.high,
              reason: 'excellent_stable',
            ),
          );
        }
        break;
      case lk.ConnectionQuality.good:
        _excellentQualityStreak = 0;
        _goodQualityStreak += 1;
        _poorQualityStreak = 0;
        if (_videoProfile == _AdaptiveCallVideoProfile.low &&
            _goodQualityStreak >= 2) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.medium,
              reason: 'recover_from_low',
            ),
          );
        } else if (_videoProfile == _AdaptiveCallVideoProfile.medium &&
            _goodQualityStreak >= 3) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.standard,
              reason: 'recover_to_standard',
            ),
          );
        }
        break;
      case lk.ConnectionQuality.poor:
      case lk.ConnectionQuality.lost:
        _excellentQualityStreak = 0;
        _goodQualityStreak = 0;
        _poorQualityStreak += 1;
        if (_videoProfile == _AdaptiveCallVideoProfile.high) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.standard,
              reason: 'drop_from_high',
            ),
          );
        } else if (_videoProfile == _AdaptiveCallVideoProfile.standard &&
            _poorQualityStreak >= 2) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.medium,
              reason: 'degrade_to_medium',
            ),
          );
        } else if (_videoProfile == _AdaptiveCallVideoProfile.medium &&
            _poorQualityStreak >= 3) {
          unawaited(
            _applyVideoProfile(
              _AdaptiveCallVideoProfile.low,
              reason: 'degrade_to_low',
            ),
          );
        }
        break;
      case lk.ConnectionQuality.unknown:
        break;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _room?.disconnect();
    } catch (_) {}
    connected = false;
    connecting = false;
    _cameraRetryScheduled = false;
    _resetConnectionQualityState();
    notifyListeners();
  }

  @override
  void dispose() {
    _listener?.dispose();
    _room?.disconnect();
    super.dispose();
  }
}

class TurnaManagedCallSession extends ChangeNotifier {
  TurnaManagedCallSession({
    required this.session,
    required this.coordinator,
    required TurnaCallSummary call,
    required this.connect,
    required this.onSessionExpired,
    this.returnChatOnExit,
  }) : _call = call,
       adapter = LiveKitCallAdapter(
         connectPayload: connect,
         videoEnabled: call.type == TurnaCallType.video,
       ) {
    adapter.addListener(_handleAdapterChanged);
    coordinator.addListener(_handleCoordinatorChanged);
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!adapter.connected || _ended) return;
      _durationSeconds++;
      notifyListeners();
    });
  }

  final AuthSession session;
  final TurnaCallCoordinator coordinator;
  final TurnaCallConnectPayload connect;
  final VoidCallback onSessionExpired;
  final ChatPreview? returnChatOnExit;
  final LiveKitCallAdapter adapter;
  TurnaCallSummary _call;

  bool _started = false;
  bool _ended = false;
  bool _reportedConnected = false;
  bool presentingFullScreen = false;
  String? terminalMessage;
  String? noticeMessage;
  int _noticeRevision = 0;
  int _durationSeconds = 0;
  Timer? _durationTicker;
  bool _wakeLockHeld = false;
  bool _proximityLockHeld = false;
  TurnaCallVideoUpgradeRequestEvent? _pendingVideoUpgradeRequest;
  String? _outgoingVideoUpgradeRequestId;

  TurnaCallSummary get call => _call;
  bool get ended => _ended;
  int get durationSeconds => _durationSeconds;
  String get _wakeLockReason => 'active-call:${call.id}';
  String get _proximityReason => 'active-call-proximity:${call.id}';
  int get noticeRevision => _noticeRevision;
  TurnaCallVideoUpgradeRequestEvent? get pendingVideoUpgradeRequest =>
      _pendingVideoUpgradeRequest;
  String? get outgoingVideoUpgradeRequestId => _outgoingVideoUpgradeRequestId;
  bool get isVideoUpgradePending =>
      (_outgoingVideoUpgradeRequestId ?? '').isNotEmpty ||
      _pendingVideoUpgradeRequest != null;
  bool get canRequestVideoUpgrade =>
      !_ended &&
      adapter.connected &&
      call.type == TurnaCallType.audio &&
      !isVideoUpgradePending;

  String formatDuration() {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    _acquireWakeLock();
    await adapter.connect();
    _syncProximityScreenLock();
  }

  void setFullScreenVisible(bool value) {
    if (presentingFullScreen == value) return;
    presentingFullScreen = value;
    notifyListeners();
  }

  Future<void> endCall() async {
    if (_ended) return;
    try {
      await CallApi.endCall(session, callId: call.id);
    } on TurnaUnauthorizedException {
      onSessionExpired();
    } catch (_) {}

    coordinator.clearCall(call.id);
    await adapter.disconnect();
    await TurnaNativeCallManager.endCallUi(call.id);
    _releaseWakeLock();
    _releaseProximityScreenLock();
    _ended = true;
    terminalMessage = null;
    notifyListeners();
    kTurnaCallUiController.clearEndedSession(this);
  }

  Future<void> requestVideoUpgrade() async {
    if (!canRequestVideoUpgrade) return;
    try {
      final request = await CallApi.requestVideoUpgrade(
        session,
        callId: call.id,
      );
      _outgoingVideoUpgradeRequestId = request.requestId;
      _pushNotice('Görüntülü arama isteği gönderildi.');
      notifyListeners();
    } on TurnaUnauthorizedException {
      onSessionExpired();
    } catch (error) {
      _pushNotice(error.toString());
      notifyListeners();
    }
  }

  Future<void> respondVideoUpgrade({required bool accept}) async {
    final request = _pendingVideoUpgradeRequest;
    if (request == null) return;

    try {
      if (accept) {
        final accepted = await CallApi.acceptVideoUpgrade(
          session,
          callId: call.id,
          requestId: request.requestId,
        );
        _pendingVideoUpgradeRequest = null;
        _applyVideoUpgrade(accepted.call);
      } else {
        await CallApi.declineVideoUpgrade(
          session,
          callId: call.id,
          requestId: request.requestId,
        );
        _pendingVideoUpgradeRequest = null;
      }
      notifyListeners();
    } on TurnaUnauthorizedException {
      onSessionExpired();
    } catch (error) {
      _pushNotice(error.toString());
      notifyListeners();
    }
  }

  void _handleAdapterChanged() {
    if (adapter.connected && !_reportedConnected) {
      _reportedConnected = true;
      TurnaNativeCallManager.setCallConnected(call.id);
    }
    _syncProximityScreenLock();
    notifyListeners();
  }

  void _handleCoordinatorChanged() {
    final requested = coordinator.consumeVideoUpgradeRequest(call.id);
    if (requested != null && !_ended) {
      if (requested.requestedByUserId == session.userId) {
        _outgoingVideoUpgradeRequestId = requested.requestId;
      } else {
        _pendingVideoUpgradeRequest = requested;
      }
      notifyListeners();
    }

    final upgradeResolution = coordinator.consumeVideoUpgradeResolution(
      call.id,
    );
    if (upgradeResolution != null && !_ended) {
      _outgoingVideoUpgradeRequestId = null;
      _pendingVideoUpgradeRequest = null;
      if (upgradeResolution.kind == 'accepted') {
        _applyVideoUpgrade(upgradeResolution.call);
        _pushNotice('Görüntülü aramaya geçildi.');
      } else if (upgradeResolution.actedByUserId != session.userId) {
        _pushNotice('Görüntülü arama isteği reddedildi.');
      }
      notifyListeners();
    }

    final terminal = coordinator.consumeTerminal(call.id);
    if (terminal == null || _ended) return;
    coordinator.clearCall(call.id);
    terminalMessage = switch (terminal.kind) {
      'declined' => 'Arama reddedildi.',
      'missed' => 'Cevap yok.',
      _ => 'Arama sonlandı.',
    };
    _releaseWakeLock();
    _releaseProximityScreenLock();
    _ended = true;
    unawaited(adapter.disconnect());
    unawaited(TurnaNativeCallManager.endCallUi(call.id));
    notifyListeners();
    kTurnaCallUiController.clearEndedSession(this);
  }

  void _applyVideoUpgrade(TurnaCallSummary nextCall) {
    _call = _call.copyWith(
      type: nextCall.type,
      status: nextCall.status,
      acceptedAt: nextCall.acceptedAt,
      endedAt: nextCall.endedAt,
      clearAcceptedAt: nextCall.acceptedAt == null,
      clearEndedAt: nextCall.endedAt == null,
    );
    if (nextCall.type == TurnaCallType.video) {
      unawaited(adapter.enableVideoMode());
    }
    _syncProximityScreenLock();
  }

  void _pushNotice(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    noticeMessage = trimmed;
    _noticeRevision++;
  }

  void _acquireWakeLock() {
    if (_wakeLockHeld) return;
    _wakeLockHeld = true;
    unawaited(TurnaDisplayWakeLock.acquire(_wakeLockReason));
  }

  void _releaseWakeLock() {
    if (!_wakeLockHeld) return;
    _wakeLockHeld = false;
    unawaited(TurnaDisplayWakeLock.release(_wakeLockReason));
  }

  void _syncProximityScreenLock() {
    final shouldEnable =
        (Platform.isAndroid || Platform.isIOS) &&
        !_ended &&
        adapter.connected &&
        call.type == TurnaCallType.audio &&
        !adapter.speakerEnabled;
    if (shouldEnable) {
      if (_proximityLockHeld) return;
      _proximityLockHeld = true;
      unawaited(TurnaProximityScreenLock.acquire(_proximityReason));
      return;
    }
    _releaseProximityScreenLock();
  }

  void _releaseProximityScreenLock() {
    if (!_proximityLockHeld) return;
    _proximityLockHeld = false;
    unawaited(TurnaProximityScreenLock.release(_proximityReason));
  }

  @override
  void dispose() {
    adapter.removeListener(_handleAdapterChanged);
    coordinator.removeListener(_handleCoordinatorChanged);
    _durationTicker?.cancel();
    _releaseWakeLock();
    _releaseProximityScreenLock();
    adapter.dispose();
    super.dispose();
  }
}

class TurnaCallUiController {
  TurnaManagedCallSession? _currentSession;
  OverlayEntry? _miniOverlayEntry;
  VoidCallback? _miniListener;

  TurnaManagedCallSession obtainSession({
    required AuthSession session,
    required TurnaCallCoordinator coordinator,
    required TurnaCallSummary call,
    required TurnaCallConnectPayload connect,
    required VoidCallback onSessionExpired,
    ChatPreview? returnChatOnExit,
  }) {
    if (_currentSession?.call.id == call.id) {
      return _currentSession!;
    }
    _disposeCurrentSession();
    _currentSession = TurnaManagedCallSession(
      session: session,
      coordinator: coordinator,
      call: call,
      connect: connect,
      onSessionExpired: onSessionExpired,
      returnChatOnExit: returnChatOnExit,
    );
    return _currentSession!;
  }

  void showMini(TurnaManagedCallSession session) {
    hideMini();
    _currentSession = session;
    final navigator = kTurnaNavigatorKey.currentState;
    final overlay = navigator?.overlay;
    if (overlay == null) return;

    _miniListener = () {
      if (session.ended) {
        clearEndedSession(session);
      } else {
        _miniOverlayEntry?.markNeedsBuild();
      }
    };
    session.addListener(_miniListener!);
    _miniOverlayEntry = OverlayEntry(
      builder: (_) => _MiniCallOverlay(session: session),
    );
    overlay.insert(_miniOverlayEntry!);
  }

  void hideMini() {
    final session = _currentSession;
    final listener = _miniListener;
    if (session != null && listener != null) {
      session.removeListener(listener);
    }
    _miniListener = null;
    _miniOverlayEntry?.remove();
    _miniOverlayEntry = null;
  }

  Future<void> expandMini(TurnaManagedCallSession session) async {
    if (session.presentingFullScreen) return;
    hideMini();
    final navigator = kTurnaNavigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => ActiveCallPage(callSession: session)),
    );
  }

  void clearEndedSession(TurnaManagedCallSession session) {
    if (!identical(_currentSession, session)) return;
    hideMini();
    if (!session.presentingFullScreen) {
      _currentSession = null;
      session.dispose();
    }
  }

  void releaseFullScreenSession(TurnaManagedCallSession session) {
    if (!identical(_currentSession, session)) return;
    if (session.ended) {
      hideMini();
      _currentSession = null;
      session.dispose();
    }
  }

  void _disposeCurrentSession() {
    hideMini();
    _currentSession?.dispose();
    _currentSession = null;
  }
}
