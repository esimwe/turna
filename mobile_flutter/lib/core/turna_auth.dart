import 'dart:convert';

import 'package:http/http.dart' as http;

import 'turna_api_errors.dart';
import 'turna_backend.dart';
import 'turna_device_context.dart';
import 'turna_profile_models.dart';

class AuthSession {
  AuthSession({
    required this.token,
    required this.userId,
    required this.displayName,
    this.username,
    this.phone,
    this.avatarUrl,
    this.needsOnboarding = false,
  });

  final String token;
  final String userId;
  final String displayName;
  final String? username;
  final String? phone;
  final String? avatarUrl;
  final bool needsOnboarding;

  AuthSession copyWith({
    String? token,
    String? userId,
    String? displayName,
    String? username,
    String? phone,
    String? avatarUrl,
    bool? needsOnboarding,
    bool clearPhone = false,
    bool clearAvatarUrl = false,
  }) {
    return AuthSession(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      phone: clearPhone ? null : (phone ?? this.phone),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
    );
  }

  Map<String, dynamic> toLocalSnapshotMap() {
    return <String, dynamic>{
      'userId': userId,
      'displayName': displayName,
      'username': username,
      'phone': phone,
      'avatarUrl': avatarUrl,
      'needsOnboarding': needsOnboarding,
    };
  }
}

String? resolveTurnaSessionAvatarUrl(
  AuthSession session, {
  String? overrideAvatarUrl,
}) {
  final raw = (overrideAvatarUrl ?? session.avatarUrl)?.trim() ?? '';
  if (raw.isEmpty) return null;

  final parsed = Uri.tryParse(raw);
  final isAbsoluteUrl =
      parsed != null &&
      parsed.hasScheme &&
      (parsed.host.isNotEmpty || raw.startsWith('file:'));
  if (isAbsoluteUrl) {
    return normalizeTurnaRemoteUrl(raw);
  }

  return '$kBackendBaseUrl/api/profile/avatar/${Uri.encodeComponent(session.userId)}';
}

class TurnaOtpRequestTicket {
  TurnaOtpRequestTicket({
    required this.phone,
    required this.expiresInSeconds,
    required this.retryAfterSeconds,
  });

  final String phone;
  final int expiresInSeconds;
  final int retryAfterSeconds;
}

class TurnaAuthResult {
  TurnaAuthResult({
    required this.session,
    required this.isNewUser,
    required this.needsOnboarding,
  });

  final AuthSession session;
  final bool isNewUser;
  final bool needsOnboarding;
}

class AuthApi {
  static Future<TurnaOtpRequestTicket> requestOtp({
    required String countryIso,
    required String dialCode,
    required String nationalNumber,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      includeJsonContentType: true,
    );
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/auth/request-otp'),
      headers: headers,
      body: jsonEncode({
        'countryIso': countryIso,
        'dialCode': dialCode,
        'nationalNumber': nationalNumber,
      }),
    );
    if (res.statusCode >= 400) {
      turnaThrowApiError(res.body, res.statusCode);
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaOtpRequestTicket(
      phone: (data['phone'] ?? '').toString(),
      expiresInSeconds: (data['expiresInSeconds'] as num?)?.toInt() ?? 180,
      retryAfterSeconds: (data['retryAfterSeconds'] as num?)?.toInt() ?? 60,
    );
  }

  static Future<TurnaAuthResult> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      includeJsonContentType: true,
    );
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/auth/verify-otp'),
      headers: headers,
      body: jsonEncode({'phone': phone, 'code': code}),
    );
    if (res.statusCode >= 400) {
      turnaThrowApiError(res.body, res.statusCode);
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final user = map['user'] as Map<String, dynamic>? ?? const {};
    final token = map['accessToken']?.toString();
    final userId = user['id']?.toString();
    final displayName = user['displayName']?.toString();
    if (token == null || userId == null || displayName == null) {
      throw TurnaApiException('Sunucu yaniti gecersiz.');
    }

    final needsOnboarding =
        map['needsOnboarding'] == true || map['isNewUser'] == true;
    final session = AuthSession(
      token: token,
      userId: userId,
      displayName: displayName,
      username: turnaProfileNullableString(user['username']),
      phone: turnaProfileNullableString(user['phone']),
      avatarUrl: turnaProfileNullableString(user['avatarUrl']),
      needsOnboarding: needsOnboarding,
    );

    return TurnaAuthResult(
      session: session,
      isNewUser: map['isNewUser'] == true,
      needsOnboarding: needsOnboarding,
    );
  }

  static Future<void> logout(AuthSession session) async {
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/auth/logout'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
    );

    if (res.statusCode >= 400 && res.statusCode != 401) {
      turnaThrowApiError(res.body, res.statusCode);
    }
  }
}
