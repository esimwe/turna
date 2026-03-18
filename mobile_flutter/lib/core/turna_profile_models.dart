String? turnaProfileNullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

List<String> turnaProfileStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

class TurnaRegisteredContact {
  TurnaRegisteredContact({
    required this.id,
    required this.displayName,
    required this.contactName,
    this.username,
    this.phone,
    this.about,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String contactName;
  final String? username;
  final String? phone;
  final String? about;
  final String? avatarUrl;

  String get resolvedTitle =>
      contactName.trim().isEmpty ? displayName : contactName;

  factory TurnaRegisteredContact.fromMap(Map<String, dynamic> map) {
    return TurnaRegisteredContact(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      contactName: (map['contactName'] ?? '').toString(),
      username: turnaProfileNullableString(map['username']),
      phone: turnaProfileNullableString(map['phone']),
      about: turnaProfileNullableString(map['about']),
      avatarUrl: turnaProfileNullableString(map['avatarUrl']),
    );
  }

  TurnaUserProfile toUserProfile() {
    return TurnaUserProfile(
      id: id,
      displayName: resolvedTitle,
      username: username,
      phone: phone,
      about: about,
      avatarUrl: avatarUrl,
    );
  }
}

class TurnaUserProfile {
  TurnaUserProfile({
    required this.id,
    required this.displayName,
    this.username,
    this.phone,
    this.email,
    this.about,
    this.avatarUrl,
    this.city,
    this.country,
    this.expertise,
    this.communityRole,
    this.interests = const <String>[],
    this.socialLinks = const <String>[],
    this.onboardingCompletedAt,
    this.createdAt,
  });

  final String id;
  final String displayName;
  final String? username;
  final String? phone;
  final String? email;
  final String? about;
  final String? avatarUrl;
  final String? city;
  final String? country;
  final String? expertise;
  final String? communityRole;
  final List<String> interests;
  final List<String> socialLinks;
  final String? onboardingCompletedAt;
  final String? createdAt;

  factory TurnaUserProfile.fromMap(Map<String, dynamic> map) {
    return TurnaUserProfile(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      username: turnaProfileNullableString(map['username']),
      phone: turnaProfileNullableString(map['phone']),
      email: turnaProfileNullableString(map['email']),
      about: turnaProfileNullableString(map['about']),
      avatarUrl: turnaProfileNullableString(map['avatarUrl']),
      city: turnaProfileNullableString(map['city']),
      country: turnaProfileNullableString(map['country']),
      expertise: turnaProfileNullableString(map['expertise']),
      communityRole: turnaProfileNullableString(map['communityRole']),
      interests: turnaProfileStringList(map['interests']),
      socialLinks: turnaProfileStringList(map['socialLinks']),
      onboardingCompletedAt: turnaProfileNullableString(
        map['onboardingCompletedAt'],
      ),
      createdAt: turnaProfileNullableString(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'username': username,
      'phone': phone,
      'email': email,
      'about': about,
      'avatarUrl': avatarUrl,
      'city': city,
      'country': country,
      'expertise': expertise,
      'communityRole': communityRole,
      'interests': interests,
      'socialLinks': socialLinks,
      'onboardingCompletedAt': onboardingCompletedAt,
      'createdAt': createdAt,
    };
  }
}

enum TurnaPrivacyAudience {
  everyone,
  myContacts,
  excludedContacts,
  nobody,
  onlySharedWith,
}

extension TurnaPrivacyAudienceX on TurnaPrivacyAudience {
  static TurnaPrivacyAudience fromWire(String value) {
    switch (value.trim().toLowerCase()) {
      case 'my_contacts':
        return TurnaPrivacyAudience.myContacts;
      case 'excluded_contacts':
        return TurnaPrivacyAudience.excludedContacts;
      case 'nobody':
        return TurnaPrivacyAudience.nobody;
      case 'only_shared_with':
        return TurnaPrivacyAudience.onlySharedWith;
      default:
        return TurnaPrivacyAudience.everyone;
    }
  }

  String get wireValue {
    switch (this) {
      case TurnaPrivacyAudience.myContacts:
        return 'my_contacts';
      case TurnaPrivacyAudience.excludedContacts:
        return 'excluded_contacts';
      case TurnaPrivacyAudience.nobody:
        return 'nobody';
      case TurnaPrivacyAudience.onlySharedWith:
        return 'only_shared_with';
      case TurnaPrivacyAudience.everyone:
        return 'everyone';
    }
  }

  String get label {
    switch (this) {
      case TurnaPrivacyAudience.myContacts:
        return 'Kişilerim';
      case TurnaPrivacyAudience.excludedContacts:
        return 'Şunlar hariç kişilerim...';
      case TurnaPrivacyAudience.nobody:
        return 'Hiç kimse';
      case TurnaPrivacyAudience.onlySharedWith:
        return 'Sadece şu kişilerle paylaş';
      case TurnaPrivacyAudience.everyone:
        return 'Herkes';
    }
  }

  bool get needsTargetSelection =>
      this == TurnaPrivacyAudience.excludedContacts ||
      this == TurnaPrivacyAudience.onlySharedWith;
}

enum TurnaOnlineVisibility { everyone, sameAsLastSeen }

extension TurnaOnlineVisibilityX on TurnaOnlineVisibility {
  static TurnaOnlineVisibility fromWire(String value) {
    switch (value.trim().toLowerCase()) {
      case 'same_as_last_seen':
        return TurnaOnlineVisibility.sameAsLastSeen;
      default:
        return TurnaOnlineVisibility.everyone;
    }
  }

  String get wireValue {
    switch (this) {
      case TurnaOnlineVisibility.sameAsLastSeen:
        return 'same_as_last_seen';
      case TurnaOnlineVisibility.everyone:
        return 'everyone';
    }
  }

  String get label {
    switch (this) {
      case TurnaOnlineVisibility.sameAsLastSeen:
        return 'Son görülme bilgisiyle aynı';
      case TurnaOnlineVisibility.everyone:
        return 'Herkes';
    }
  }
}

class TurnaPrivacyAudienceSetting {
  TurnaPrivacyAudienceSetting({
    required this.mode,
    this.targetUserIds = const <String>[],
  });

  final TurnaPrivacyAudience mode;
  final List<String> targetUserIds;

  factory TurnaPrivacyAudienceSetting.fromMap(Map<String, dynamic> map) {
    return TurnaPrivacyAudienceSetting(
      mode: TurnaPrivacyAudienceX.fromWire(
        (map['mode'] ?? 'everyone').toString(),
      ),
      targetUserIds: turnaProfileStringList(map['targetUserIds']),
    );
  }

  TurnaPrivacyAudienceSetting copyWith({
    TurnaPrivacyAudience? mode,
    List<String>? targetUserIds,
  }) {
    return TurnaPrivacyAudienceSetting(
      mode: mode ?? this.mode,
      targetUserIds: targetUserIds ?? this.targetUserIds,
    );
  }

  Map<String, dynamic> toMap() => {
    'mode': mode.wireValue,
    'targetUserIds': targetUserIds,
  };
}

class TurnaPrivacySettings {
  TurnaPrivacySettings({
    required this.lastSeen,
    required this.online,
    required this.profilePhoto,
    required this.about,
    required this.links,
    required this.groups,
    required this.defaultMessageExpirationSeconds,
    required this.statusAllowReshare,
  });

  final TurnaPrivacyAudienceSetting lastSeen;
  final TurnaOnlineVisibility online;
  final TurnaPrivacyAudienceSetting profilePhoto;
  final TurnaPrivacyAudienceSetting about;
  final TurnaPrivacyAudienceSetting links;
  final TurnaPrivacyAudienceSetting groups;
  final int? defaultMessageExpirationSeconds;
  final bool statusAllowReshare;

  factory TurnaPrivacySettings.defaults() {
    return TurnaPrivacySettings(
      lastSeen: TurnaPrivacyAudienceSetting(
        mode: TurnaPrivacyAudience.everyone,
      ),
      online: TurnaOnlineVisibility.everyone,
      profilePhoto: TurnaPrivacyAudienceSetting(
        mode: TurnaPrivacyAudience.everyone,
      ),
      about: TurnaPrivacyAudienceSetting(mode: TurnaPrivacyAudience.myContacts),
      links: TurnaPrivacyAudienceSetting(mode: TurnaPrivacyAudience.myContacts),
      groups: TurnaPrivacyAudienceSetting(mode: TurnaPrivacyAudience.everyone),
      defaultMessageExpirationSeconds: null,
      statusAllowReshare: false,
    );
  }

  factory TurnaPrivacySettings.fromMap(Map<String, dynamic> map) {
    final defaults = TurnaPrivacySettings.defaults();
    final lastSeenMap = Map<String, dynamic>.from(
      map['lastSeen'] as Map? ?? const {},
    );
    final profilePhotoMap = Map<String, dynamic>.from(
      map['profilePhoto'] as Map? ?? const {},
    );
    final aboutMap = Map<String, dynamic>.from(
      map['about'] as Map? ?? const {},
    );
    final linksMap = Map<String, dynamic>.from(
      map['links'] as Map? ?? const {},
    );
    final groupsMap = Map<String, dynamic>.from(
      map['groups'] as Map? ?? const {},
    );
    return TurnaPrivacySettings(
      lastSeen: lastSeenMap.isEmpty
          ? defaults.lastSeen
          : TurnaPrivacyAudienceSetting.fromMap(lastSeenMap),
      online: TurnaOnlineVisibilityX.fromWire(
        ((map['online'] as Map?)?['mode'] ?? defaults.online.wireValue)
            .toString(),
      ),
      profilePhoto: profilePhotoMap.isEmpty
          ? defaults.profilePhoto
          : TurnaPrivacyAudienceSetting.fromMap(profilePhotoMap),
      about: aboutMap.isEmpty
          ? defaults.about
          : TurnaPrivacyAudienceSetting.fromMap(aboutMap),
      links: linksMap.isEmpty
          ? defaults.links
          : TurnaPrivacyAudienceSetting.fromMap(linksMap),
      groups: groupsMap.isEmpty
          ? defaults.groups
          : TurnaPrivacyAudienceSetting.fromMap(groupsMap),
      defaultMessageExpirationSeconds:
          (map['defaultMessageExpirationSeconds'] as num?)?.toInt(),
      statusAllowReshare: map['statusAllowReshare'] == true,
    );
  }

  TurnaPrivacySettings copyWith({
    TurnaPrivacyAudienceSetting? lastSeen,
    TurnaOnlineVisibility? online,
    TurnaPrivacyAudienceSetting? profilePhoto,
    TurnaPrivacyAudienceSetting? about,
    TurnaPrivacyAudienceSetting? links,
    TurnaPrivacyAudienceSetting? groups,
    int? defaultMessageExpirationSeconds,
    bool clearDefaultMessageExpirationSeconds = false,
    bool? statusAllowReshare,
  }) {
    return TurnaPrivacySettings(
      lastSeen: lastSeen ?? this.lastSeen,
      online: online ?? this.online,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      about: about ?? this.about,
      links: links ?? this.links,
      groups: groups ?? this.groups,
      defaultMessageExpirationSeconds: clearDefaultMessageExpirationSeconds
          ? null
          : (defaultMessageExpirationSeconds ??
                this.defaultMessageExpirationSeconds),
      statusAllowReshare: statusAllowReshare ?? this.statusAllowReshare,
    );
  }

  Map<String, dynamic> toMap() => {
    'lastSeen': lastSeen.toMap(),
    'online': {'mode': online.wireValue},
    'profilePhoto': profilePhoto.toMap(),
    'about': about.toMap(),
    'links': links.toMap(),
    'groups': groups.toMap(),
    'defaultMessageExpirationSeconds': defaultMessageExpirationSeconds,
    'statusAllowReshare': statusAllowReshare,
  };
}

String? normalizeTurnaCommunityAccessRole(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

bool hasTurnaCommunityInternalAccess({TurnaUserProfile? profile}) {
  return normalizeTurnaCommunityAccessRole(profile?.communityRole) != null;
}
