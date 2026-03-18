import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

import 'turna_logging.dart';

class TurnaFirebase {
  static bool _attempted = false;
  static bool _enabled = false;
  static FirebaseAnalytics? _analytics;

  static Future<bool> ensureInitialized() async {
    if (_attempted) return _enabled;
    _attempted = true;

    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
      _enabled = true;
    } catch (error) {
      turnaLog('firebase init skipped', error);
      _enabled = false;
    }

    return _enabled;
  }

  static FirebaseAnalytics? get analytics => _enabled ? _analytics : null;
}

class TurnaAnalytics {
  static Future<void> logEvent(
    String name, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final ready = await TurnaFirebase.ensureInitialized();
    if (!ready) return;

    try {
      await TurnaFirebase.analytics?.logEvent(
        name: name,
        parameters: parameters.map(
          (key, value) => MapEntry<String, Object>(
            key,
            value is String || value is num || value is bool
                ? value as Object
                : (value?.toString() ?? ''),
          ),
        ),
      );
    } catch (error) {
      turnaLog('analytics log skipped', error);
    }
  }
}
