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

String? normalizeTurnaCommunityAccessRole(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

bool hasTurnaCommunityInternalAccess({TurnaUserProfile? profile}) {
  return normalizeTurnaCommunityAccessRole(profile?.communityRole) != null;
}
