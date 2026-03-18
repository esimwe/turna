import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'turna_theme.dart';

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

String turnaDeviceUnlockMethodLabel() {
  if (Platform.isIOS) {
    return 'Face ID veya cihaz şifresi';
  }
  if (Platform.isAndroid) {
    return 'parmak izi veya ekran kilidi';
  }
  return 'cihaz doğrulaması';
}

Future<bool> authenticateTurnaDeviceAccess(
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

Future<bool> authenticateLockedChatAccess(
  BuildContext context, {
  required String chatName,
  required String actionLabel,
}) async {
  return authenticateTurnaDeviceAccess(
    context,
    localizedReason:
        '"$chatName" sohbetini $actionLabel cihaz doğrulaması gerekiyor.',
    unsupportedMessage: 'Bu cihazda sohbet kilidi desteklenmiyor.',
  );
}

class TurnaAppLockOverlay extends StatelessWidget {
  const TurnaAppLockOverlay({
    super.key,
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
