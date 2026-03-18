part of turna_app;

Widget buildTurnaSessionExpiredRedirect(VoidCallback onSessionExpired) {
  WidgetsBinding.instance.addPostFrameCallback((_) => onSessionExpired());
  return const Center(child: CircularProgressIndicator());
}

class TurnaDisplayWakeLock {
  static const MethodChannel _channel = MethodChannel('turna/display');
  static final Set<String> _holders = <String>{};

  static Future<void> acquire(String reason) async {
    final wasEmpty = _holders.isEmpty;
    _holders.add(reason);
    if (!wasEmpty) return;
    await _setEnabled(true);
  }

  static Future<void> release(String reason) async {
    final removed = _holders.remove(reason);
    if (!removed || _holders.isNotEmpty) return;
    await _setEnabled(false);
  }

  static Future<void> _setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setKeepScreenOn', {'enabled': enabled});
    } catch (error) {
      turnaLog('display wake lock update skipped', error);
    }
  }
}

class TurnaProximityScreenLock {
  static const MethodChannel _channel = MethodChannel('turna/display');
  static final Set<String> _holders = <String>{};

  static Future<void> acquire(String reason) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final wasEmpty = _holders.isEmpty;
    _holders.add(reason);
    if (!wasEmpty) return;
    await _setEnabled(true);
  }

  static Future<void> release(String reason) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final removed = _holders.remove(reason);
    if (!removed || _holders.isNotEmpty) return;
    await _setEnabled(false);
  }

  static Future<void> _setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setProximityScreenLockEnabled', {
        'enabled': enabled,
      });
    } catch (error) {
      turnaLog('proximity screen lock update skipped', error);
    }
  }
}

class TurnaAppBadge {
  static const MethodChannel _channel = MethodChannel('turna/display');

  static Future<void> setCount(int count) async {
    final normalized = math.max(0, count);
    try {
      await _channel.invokeMethod('setAppBadgeCount', {'count': normalized});
    } catch (error) {
      turnaLog('app badge update skipped', error);
    }
  }
}
