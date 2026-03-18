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
          await TurnaNativeCallManager.handleForegroundRemoteMessage(
            message.data,
          );
        });
        FirebaseMessaging.onMessageOpenedApp.listen((message) async {
          turnaLog('push opened', message.data);
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
