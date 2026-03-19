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

class TurnaLinkedDeviceSession {
  const TurnaLinkedDeviceSession({
    required this.id,
    required this.deviceLabel,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    this.deviceModel,
    this.osVersion,
    this.appVersion,
    this.localeTag,
    this.regionCode,
    this.connectionType,
    this.countryIso,
    this.ipCountryIso,
    this.ipAddress,
    this.userAgent,
  });

  final String id;
  final String deviceLabel;
  final String platform;
  final String createdAt;
  final String lastSeenAt;
  final String? deviceModel;
  final String? osVersion;
  final String? appVersion;
  final String? localeTag;
  final String? regionCode;
  final String? connectionType;
  final String? countryIso;
  final String? ipCountryIso;
  final String? ipAddress;
  final String? userAgent;

  factory TurnaLinkedDeviceSession.fromMap(Map<String, dynamic> map) {
    return TurnaLinkedDeviceSession(
      id: (map['id'] ?? '').toString(),
      deviceLabel: (map['deviceLabel'] ?? 'Turna Web').toString(),
      platform: (map['platform'] ?? 'web').toString(),
      createdAt: (map['createdAt'] ?? '').toString(),
      lastSeenAt: (map['lastSeenAt'] ?? '').toString(),
      deviceModel: turnaProfileNullableString(map['deviceModel']),
      osVersion: turnaProfileNullableString(map['osVersion']),
      appVersion: turnaProfileNullableString(map['appVersion']),
      localeTag: turnaProfileNullableString(map['localeTag']),
      regionCode: turnaProfileNullableString(map['regionCode']),
      connectionType: turnaProfileNullableString(map['connectionType']),
      countryIso: turnaProfileNullableString(map['countryIso']),
      ipCountryIso: turnaProfileNullableString(map['ipCountryIso']),
      ipAddress: turnaProfileNullableString(map['ipAddress']),
      userAgent: turnaProfileNullableString(map['userAgent']),
    );
  }
}

class TurnaLinkedWebLoginConfirmResult {
  const TurnaLinkedWebLoginConfirmResult({
    required this.linked,
    required this.sessionId,
    required this.deviceLabel,
    this.expiresAt,
  });

  final bool linked;
  final String sessionId;
  final String deviceLabel;
  final String? expiresAt;
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

  static Future<List<TurnaLinkedDeviceSession>> fetchLinkedDevices(
    AuthSession session,
  ) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      authToken: session.token,
    );
    final res = await http.get(
      Uri.parse('$kBackendBaseUrl/api/auth/linked-devices'),
      headers: headers,
    );
    if (res.statusCode >= 400) {
      turnaThrowApiError(res.body, res.statusCode);
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as List? ?? const [];
    return data
        .whereType<Map>()
        .map(
          (item) =>
              TurnaLinkedDeviceSession.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  static Future<TurnaLinkedWebLoginConfirmResult> confirmWebLogin(
    AuthSession session, {
    required String requestId,
    required String secret,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      authToken: session.token,
      includeJsonContentType: true,
    );
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/auth/web-login/confirm'),
      headers: headers,
      body: jsonEncode({'requestId': requestId, 'secret': secret}),
    );
    if (res.statusCode >= 400) {
      turnaThrowApiError(res.body, res.statusCode);
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    final sessionId = data['sessionId']?.toString();
    final deviceLabel = data['deviceLabel']?.toString();
    if (sessionId == null || deviceLabel == null) {
      throw TurnaApiException('Sunucu yaniti gecersiz.');
    }
    return TurnaLinkedWebLoginConfirmResult(
      linked: data['linked'] == true,
      sessionId: sessionId,
      deviceLabel: deviceLabel,
      expiresAt: turnaProfileNullableString(data['expiresAt']),
    );
  }

  static Future<void> revokeLinkedDevice(
    AuthSession session, {
    required String sessionId,
  }) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      authToken: session.token,
      includeJsonContentType: true,
    );
    final res = await http.delete(
      Uri.parse('$kBackendBaseUrl/api/auth/linked-devices/$sessionId'),
      headers: headers,
    );
    if (res.statusCode >= 400) {
      turnaThrowApiError(res.body, res.statusCode);
    }
  }
}
