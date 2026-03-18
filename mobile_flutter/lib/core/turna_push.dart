import 'dart:convert';

import 'package:http/http.dart' as http;

import 'turna_api_errors.dart';
import 'turna_auth.dart';
import 'turna_backend.dart';
import 'turna_device_context.dart';

class PushApi {
  static Future<void> registerDevice(
    AuthSession session, {
    required String token,
    required String platform,
    String tokenKind = 'standard',
    String? deviceLabel,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      authToken: session.token,
      includeJsonContentType: true,
    );
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/push/devices'),
      headers: headers,
      body: jsonEncode({
        'token': token,
        'platform': platform,
        'tokenKind': tokenKind,
        'deviceLabel': deviceLabel,
      }),
    );
    if (res.statusCode >= 400) {
      turnaThrowApiError(res.body, res.statusCode);
    }
  }

  static Future<void> unregisterDevice(
    AuthSession session, {
    required String token,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      authToken: session.token,
      includeJsonContentType: true,
    );
    final res = await http.delete(
      Uri.parse('$kBackendBaseUrl/api/push/devices'),
      headers: headers,
      body: jsonEncode({'token': token}),
    );
    if (res.statusCode >= 400) {
      turnaThrowApiError(res.body, res.statusCode);
    }
  }
}
