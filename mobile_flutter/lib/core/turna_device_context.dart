import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _turnaDeviceLog(String message, [Object? error]) {
  if (!kDebugMode) return;
  final suffix = error == null ? '' : ' | $error';
  debugPrint('[turna-mobile] $message$suffix');
}

class TurnaDeviceContext {
  static const MethodChannel _channel = MethodChannel('turna/device');
  static const String _deviceIdKey = 'turna_app_scoped_device_id';

  static Future<void>? _pendingLoad;
  static String? _deviceId;
  static String? _deviceModel;
  static String? _osVersion;
  static String? _appVersion;
  static String? _localeTag;
  static String? _regionCode;
  static String? _connectionType;
  static String? _countryIso;

  static String? get countryIso => _countryIso;

  static Future<void> ensureLoaded({bool force = false}) async {
    if (!force && _deviceId != null) return;
    if (_pendingLoad != null) {
      await _pendingLoad;
      return;
    }

    final future = _load();
    _pendingLoad = future;
    try {
      await future;
    } finally {
      if (identical(_pendingLoad, future)) {
        _pendingLoad = null;
      }
    }
  }

  static Future<Map<String, String>> buildHeaders({
    String? authToken,
    bool includeJsonContentType = false,
  }) async {
    await ensureLoaded();

    final headers = <String, String>{};
    if (authToken != null && authToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    if (includeJsonContentType) {
      headers['Content-Type'] = 'application/json';
    }

    void putHeader(String key, String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return;
      headers[key] = text;
    }

    putHeader('x-turna-device-id', _deviceId);
    putHeader(
      'x-turna-platform',
      Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
          ? 'android'
          : Platform.operatingSystem,
    );
    putHeader('x-turna-device-model', _deviceModel);
    putHeader('x-turna-os-version', _osVersion);
    putHeader('x-turna-app-version', _appVersion);
    putHeader('x-turna-locale', _localeTag);
    putHeader('x-turna-region', _regionCode);
    putHeader('x-turna-connection-type', _connectionType);
    putHeader('x-turna-country-iso', _countryIso);

    return headers;
  }

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString(_deviceIdKey);
      if (deviceId == null || deviceId.trim().isEmpty) {
        deviceId = _generateDeviceId();
        await prefs.setString(_deviceIdKey, deviceId);
      }

      Map<String, dynamic> native = const <String, dynamic>{};
      try {
        final map = await _channel.invokeMapMethod<String, dynamic>(
          'getContextInfo',
        );
        native = map == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from(map);
      } catch (error) {
        _turnaDeviceLog('device context native skipped', error);
      }

      List<ConnectivityResult> connectivityResults =
          const <ConnectivityResult>[];
      try {
        connectivityResults = await Connectivity().checkConnectivity();
      } catch (error) {
        _turnaDeviceLog('connectivity load skipped', error);
      }

      final locale = ui.PlatformDispatcher.instance.locale;
      final localeTag =
          _readText(native['localeTag']) ?? locale.toLanguageTag();
      final regionCode =
          _normalizeCountryIso(_readText(native['regionCode'])) ??
          _normalizeCountryIso(_readText(native['localeCountryIso'])) ??
          _normalizeCountryIso(locale.countryCode);
      final countryIso =
          _normalizeCountryIso(_readText(native['simCountryIso'])) ??
          _normalizeCountryIso(_readText(native['networkCountryIso'])) ??
          regionCode;

      _deviceId = deviceId;
      _deviceModel = _readText(native['deviceModel']);
      _osVersion = _readText(native['osVersion']);
      _appVersion = _readText(native['appVersion']);
      _localeTag = localeTag;
      _regionCode = regionCode;
      _connectionType = _resolveConnectionType(connectivityResults);
      _countryIso = countryIso;
    } catch (error) {
      _turnaDeviceLog('device context load failed', error);
    }
  }

  static String _generateDeviceId() {
    final random = math.Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  static String? _readText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static String? _normalizeCountryIso(String? value) {
    final text = value?.trim().toUpperCase();
    if (text == null || text.length != 2) return null;
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(text)) return null;
    return text;
  }

  static String _resolveConnectionType(List<ConnectivityResult> results) {
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      return 'none';
    }
    if (results.contains(ConnectivityResult.wifi)) return 'wifi';
    if (results.contains(ConnectivityResult.mobile)) return 'cellular';
    if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
    if (results.contains(ConnectivityResult.vpn)) return 'vpn';
    if (results.contains(ConnectivityResult.bluetooth)) return 'bluetooth';
    if (results.contains(ConnectivityResult.other)) return 'other';
    return results.map((item) => item.name).join(',');
  }
}
