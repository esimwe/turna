part of '../app/turna_app.dart';

class ProfileApi {
  static Future<TurnaPrivacySettings> fetchPrivacySettings(
    AuthSession session,
  ) async {
    final res = await http.get(
      Uri.parse('$kBackendBaseUrl/api/profile/privacy'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    _throwIfApiError(res, label: 'fetchPrivacySettings');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaPrivacySettings.fromMap(data);
  }

  static Future<TurnaPrivacySettings> updatePrivacySettings(
    AuthSession session,
    TurnaPrivacySettings settings,
  ) async {
    final res = await http.put(
      Uri.parse('$kBackendBaseUrl/api/profile/privacy'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(settings.toMap()),
    );
    _throwIfApiError(res, label: 'updatePrivacySettings');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaPrivacySettings.fromMap(data);
  }

  static Future<TurnaUserProfile> fetchMe(AuthSession session) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/profile/me'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res, label: 'fetchMe');

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final profile = TurnaUserProfile.fromMap(data);
      await TurnaProfileLocalCache.saveSelfProfile(profile);
      await TurnaUserProfileLocalCache.save(profile);
      return profile;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      final cached = await TurnaProfileLocalCache.loadSelfProfile(session);
      if (cached != null) return cached;
      throw TurnaApiException('Profil yuklenemedi.');
    }
  }

  static Future<TurnaUserProfile> fetchUser(
    AuthSession session,
    String userId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$kBackendBaseUrl/api/profile/users/$userId'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      );
      _throwIfApiError(res, label: 'fetchUser');

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>? ?? const {};
      final profile = TurnaUserProfile.fromMap(data);
      await TurnaUserProfileLocalCache.save(profile);
      return profile;
    } on TurnaApiException {
      rethrow;
    } catch (_) {
      final cached = await TurnaUserProfileLocalCache.load(userId);
      if (cached != null) return cached;
      throw TurnaApiException('Kullanici profili yuklenemedi.');
    }
  }

  static Future<bool> checkUsernameAvailability(
    AuthSession session,
    String username,
  ) async {
    final normalized = username.trim().toLowerCase().replaceAll('@', '');
    final res = await http.get(
      Uri.parse(
        '$kBackendBaseUrl/api/profile/username-availability',
      ).replace(queryParameters: {'username': normalized}),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    _throwIfApiError(res, label: 'checkUsernameAvailability');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return data['available'] == true;
  }

  static Future<TurnaUserProfile> updateMe(
    AuthSession session, {
    required String displayName,
    required String username,
    required String about,
    required String city,
    required String country,
    required String expertise,
    required String communityRole,
    required List<String> interests,
    required List<String> socialLinks,
    required String phone,
    required String email,
  }) async {
    final res = await http.put(
      Uri.parse('$kBackendBaseUrl/api/profile/me'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'displayName': displayName,
        'username': username.trim(),
        'about': about.trim(),
        'city': city.trim(),
        'country': country.trim(),
        'expertise': expertise.trim(),
        'communityRole': communityRole.trim(),
        'interests': interests,
        'socialLinks': socialLinks,
        'phone': phone.trim(),
        'email': email.trim(),
      }),
    );
    _throwIfApiError(res, label: 'updateMe');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<TurnaUserProfile> completeOnboarding(
    AuthSession session, {
    required String displayName,
    required String username,
    required String about,
  }) async {
    final res = await http.put(
      Uri.parse('$kBackendBaseUrl/api/profile/onboarding'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'displayName': displayName,
        'username': username.trim(),
        'about': about.trim(),
      }),
    );
    _throwIfApiError(res, label: 'completeOnboarding');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<AvatarUploadTicket> createAvatarUpload(
    AuthSession session, {
    required String contentType,
    required String fileName,
  }) async {
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/profile/avatar/upload-url'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'contentType': contentType, 'fileName': fileName}),
    );
    _throwIfApiError(res, label: 'createAvatarUpload');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return AvatarUploadTicket.fromMap(data);
  }

  static Future<TurnaUserProfile> completeAvatarUpload(
    AuthSession session, {
    required String objectKey,
  }) async {
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/profile/avatar/complete'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'objectKey': objectKey}),
    );
    _throwIfApiError(res, label: 'completeAvatarUpload');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<TurnaUserProfile> deleteAvatar(AuthSession session) async {
    final res = await http.delete(
      Uri.parse('$kBackendBaseUrl/api/profile/avatar'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    _throwIfApiError(res, label: 'deleteAvatar');

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? const {};
    return TurnaUserProfile.fromMap(data);
  }

  static Future<void> syncContacts(
    AuthSession session,
    List<TurnaContactSyncEntry> contacts,
  ) async {
    final headers = await TurnaDeviceContext.buildHeaders(
      authToken: session.token,
      includeJsonContentType: true,
    );
    final res = await http.post(
      Uri.parse('$kBackendBaseUrl/api/profile/contacts/sync'),
      headers: headers,
      body: jsonEncode({
        'contacts': contacts.map((item) => item.toMap()).toList(),
      }),
    );
    _throwIfApiError(res, label: 'syncContacts');
  }

  static void _throwIfApiError(
    http.Response response, {
    required String label,
  }) {
    if (response.statusCode < 400) return;

    turnaLog('profile api failed', {
      'label': label,
      'statusCode': response.statusCode,
      'body': response.body,
    });
    turnaThrowApiError(response.body, response.statusCode);
  }
}
