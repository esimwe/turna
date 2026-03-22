part of '../app/turna_app.dart';

class TurnaPushManager {
  static const _lastPushTokenKey = 'turna_last_push_token';
  static AuthSession? _session;
  static bool _listenersAttached = false;
  static bool _initialMessageChecked = false;

  static Future<void> _handleChatPushOpen(Map<String, dynamic> data) async {
    if ((data['type'] ?? '').toString() != 'chat_message') return;
    final chatId = (data['chatId'] ?? '').toString().trim();
    if (chatId.isEmpty) return;
    kTurnaPushChatOpenCoordinator.requestOpen(chatId);
  }

  static String _callEndedReasonLabel(String reason) {
    switch (reason.trim().toLowerCase()) {
      case 'missed':
        return 'Cevapsız arama';
      case 'declined':
        return 'Arama reddedildi';
      default:
        return 'Arama sona erdi';
    }
  }

  static TurnaInboxNotificationEntry? _entryFromRemoteMessage(
    RemoteMessage message,
  ) {
    final data = message.data;
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    if (type.isEmpty) return null;
    final createdAt =
        message.sentTime?.toUtc().toIso8601String() ??
        DateTime.now().toUtc().toIso8601String();

    switch (type) {
      case 'chat_message':
        final messageId = (data['messageId'] ?? '').toString().trim();
        final chatId = (data['chatId'] ?? '').toString().trim();
        if (messageId.isEmpty || chatId.isEmpty) return null;
        final sender = (data['senderDisplayName'] ?? '').toString().trim();
        final title = message.notification?.title?.trim().isNotEmpty == true
            ? message.notification!.title!.trim()
            : (sender.isEmpty ? 'Yeni mesaj' : sender);
        final body = message.notification?.body?.trim().isNotEmpty == true
            ? message.notification!.body!.trim()
            : (data['body'] ?? '').toString().trim();
        return TurnaInboxNotificationEntry(
          id: 'push:chat:$messageId',
          source: 'push',
          type: 'chat_message',
          title: title,
          body: body.isEmpty ? null : body,
          createdAt: createdAt,
          chatId: chatId,
          messageId: messageId,
        );
      case 'incoming_call':
        final callId = (data['callId'] ?? data['id'] ?? '').toString().trim();
        if (callId.isEmpty) return null;
        final caller = (data['callerDisplayName'] ?? data['nameCaller'] ?? '')
            .toString()
            .trim();
        final isVideo = (data['isVideo'] ?? '').toString().trim() == 'true';
        return TurnaInboxNotificationEntry(
          id: 'push:incoming_call:$callId',
          source: 'push',
          type: 'incoming_call',
          title: caller.isEmpty ? 'Gelen arama' : caller,
          body: isVideo ? 'Goruntulu arama' : 'Sesli arama',
          createdAt: createdAt,
          callId: callId,
        );
      case 'call_ended':
        final callId = (data['callId'] ?? data['id'] ?? '').toString().trim();
        if (callId.isEmpty) return null;
        return TurnaInboxNotificationEntry(
          id: 'push:call_ended:$callId',
          source: 'push',
          type: 'call_ended',
          title: _callEndedReasonLabel((data['reason'] ?? '').toString()),
          body: null,
          createdAt: createdAt,
          callId: callId,
        );
      default:
        return null;
    }
  }

  static Future<void> _recordRemoteMessage(RemoteMessage message) async {
    final session = _session;
    if (session == null) return;
    final entry = _entryFromRemoteMessage(message);
    if (entry == null) return;
    await TurnaNotificationInboxLocalCache.add(session.userId, entry);
  }

  static Future<void> syncSession(AuthSession session) async {
    _session = session;
    final ready = await TurnaFirebase.ensureInitialized();
    if (!ready) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token == null || token.trim().isEmpty) return;

      final previousToken = await TurnaSecureStateStore.readString(
        _lastPushTokenKey,
      );
      if (previousToken != token) {
        await PushApi.registerDevice(
          session,
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
          tokenKind: 'standard',
          deviceLabel: Platform.isIOS ? 'ios-device' : 'android-device',
        );
        await TurnaSecureStateStore.writeString(_lastPushTokenKey, token);
      }
      await TurnaNativeCallManager.syncVoipToken(session);

      if (!_listenersAttached) {
        _listenersAttached = true;
        FirebaseMessaging.onMessage.listen((message) async {
          turnaLog('push foreground', message.data);
          await _recordRemoteMessage(message);
          await TurnaNativeCallManager.handleForegroundRemoteMessage(
            message.data,
          );
        });
        FirebaseMessaging.onMessageOpenedApp.listen((message) async {
          turnaLog('push opened', message.data);
          await _recordRemoteMessage(message);
          await _handleChatPushOpen(message.data);
          await TurnaNativeCallManager.handleForegroundRemoteMessage(
            message.data,
          );
        });
        messaging.onTokenRefresh.listen((freshToken) async {
          if (freshToken.trim().isEmpty) return;
          final activeSession = _session;
          if (activeSession == null) return;
          try {
            await PushApi.registerDevice(
              activeSession,
              token: freshToken,
              platform: Platform.isIOS ? 'ios' : 'android',
              tokenKind: 'standard',
              deviceLabel: Platform.isIOS ? 'ios-device' : 'android-device',
            );
            await TurnaSecureStateStore.writeString(
              _lastPushTokenKey,
              freshToken,
            );
          } catch (error) {
            turnaLog('push token refresh register failed', error);
          }
        });
      }
      if (!_initialMessageChecked) {
        _initialMessageChecked = true;
        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          turnaLog('push initial', initialMessage.data);
          await _recordRemoteMessage(initialMessage);
          await _handleChatPushOpen(initialMessage.data);
          await TurnaNativeCallManager.handleForegroundRemoteMessage(
            initialMessage.data,
          );
        }
      }
    } catch (error) {
      turnaLog('push sync skipped', error);
    }
  }

  static Future<void> clearSessionArtifacts() async {
    _session = null;
    await TurnaSecureStateStore.delete(_lastPushTokenKey);
  }
}
