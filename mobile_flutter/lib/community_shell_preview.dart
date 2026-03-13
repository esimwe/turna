import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CommunityShellPreviewPage extends StatefulWidget {
  const CommunityShellPreviewPage({
    super.key,
    required this.authToken,
    required this.backendBaseUrl,
    this.onTurnaTap,
  });

  final String authToken;
  final String backendBaseUrl;
  final VoidCallback? onTurnaTap;

  @override
  State<CommunityShellPreviewPage> createState() =>
      _CommunityShellPreviewPageState();
}

class _CommunityShellPreviewPageState extends State<CommunityShellPreviewPage> {
  int _selectedIndex = 0;

  late _CommunityApiClient _api;

  @override
  void initState() {
    super.initState();
    _api = _CommunityApiClient(
      authToken: widget.authToken,
      backendBaseUrl: widget.backendBaseUrl,
    );
  }

  @override
  void didUpdateWidget(covariant CommunityShellPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authToken != widget.authToken ||
        oldWidget.backendBaseUrl != widget.backendBaseUrl) {
      _api = _CommunityApiClient(
        authToken: widget.authToken,
        backendBaseUrl: widget.backendBaseUrl,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _CommunityHomePage(api: _api, onTurnaTap: widget.onTurnaTap),
      _CommunityExplorePage(api: _api, onTurnaTap: widget.onTurnaTap),
      _CommunityTurnaReturnPage(onTap: widget.onTurnaTap),
      const _CommunityNotificationsPage(),
      _CommunityMyCommunitiesPage(api: _api, onTurnaTap: widget.onTurnaTap),
    ];

    return Scaffold(
      backgroundColor: _CommunityUiTokens.background,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInOut,
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedIndex),
          child: pages[_selectedIndex],
        ),
      ),
      bottomNavigationBar: _CommunityBottomBar(
        selectedIndex: _selectedIndex,
        onSelect: (index) {
          if (index == 2 && widget.onTurnaTap != null) {
            widget.onTurnaTap!.call();
            return;
          }
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}

class _CommunityApiClient {
  _CommunityApiClient({required this.authToken, required this.backendBaseUrl});

  final String authToken;
  final String backendBaseUrl;

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer $authToken',
    'Content-Type': 'application/json',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = backendBaseUrl.endsWith('/')
        ? backendBaseUrl.substring(0, backendBaseUrl.length - 1)
        : backendBaseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<List<_CommunitySummary>> fetchExplore() async {
    final res = await http.get(
      _uri('/api/communities/explore'),
      headers: _headers,
    );
    return _decodeCommunityList(res, fallbackError: 'Topluluklar yuklenemedi.');
  }

  Future<List<_CommunitySummary>> fetchMine() async {
    final res = await http.get(
      _uri('/api/communities/mine'),
      headers: _headers,
    );
    return _decodeCommunityList(
      res,
      fallbackError: 'Topluluklarin yuklenemedi.',
    );
  }

  Future<_CommunityDashboardData> fetchDashboard() async {
    final results = await Future.wait<List<_CommunitySummary>>([
      fetchExplore(),
      fetchMine(),
    ]);
    return _CommunityDashboardData(explore: results[0], mine: results[1]);
  }

  Future<_CommunityProfileGate> fetchProfileGate() async {
    final res = await http.get(_uri('/api/profile/me'), headers: _headers);
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Community profili yuklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    return _CommunityProfileGate.fromProfileMap(data);
  }

  Future<_CommunityHomeData> fetchHomeData() async {
    final results = await Future.wait<Object>([
      fetchDashboard(),
      fetchProfileGate(),
    ]);
    return _CommunityHomeData(
      dashboard: results[0] as _CommunityDashboardData,
      profileGate: results[1] as _CommunityProfileGate,
    );
  }

  Future<_CommunitySummary> fetchCommunity(String communityIdOrSlug) async {
    final res = await http.get(
      _uri('/api/communities/$communityIdOrSlug'),
      headers: _headers,
    );
    return _decodeCommunityItem(
      res,
      fallbackError: 'Topluluk detayi yuklenemedi.',
    );
  }

  Future<_CommunityDetailData> fetchDetailData(String communityIdOrSlug) async {
    final results = await Future.wait<Object>([
      fetchCommunity(communityIdOrSlug),
      fetchProfileGate(),
    ]);
    return _CommunityDetailData(
      community: results[0] as _CommunitySummary,
      profileGate: results[1] as _CommunityProfileGate,
    );
  }

  Future<_CommunitySummary> join(String communityId) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/join'),
      headers: _headers,
    );
    return _decodeCommunityItem(res, fallbackError: 'Topluluga katilinamadi.');
  }

  Future<void> leave(String communityId) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/leave'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Topluluktan ayrilinamadi.'),
      );
    }
  }

  List<_CommunitySummary> _decodeCommunityList(
    http.Response res, {
    required String fallbackError,
  }) {
    if (res.statusCode >= 400) {
      throw _CommunityApiException(_decodeError(res, fallbackError));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => _CommunitySummary.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  _CommunitySummary _decodeCommunityItem(
    http.Response res, {
    required String fallbackError,
  }) {
    if (res.statusCode >= 400) {
      throw _CommunityApiException(_decodeError(res, fallbackError));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map);
    return _CommunitySummary.fromMap(data);
  }

  String _decodeError(http.Response res, String fallbackError) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final message = body['error']?.toString().trim();
      if (message != null && message.isNotEmpty) {
        switch (message) {
          case 'community_join_request_required':
            return 'Bu topluluk icin onay gerekli.';
          case 'community_owner_cannot_leave':
            return 'Kurucu rolu ile topluluktan ayrilamazsin.';
          default:
            return message;
        }
      }
    } catch (_) {}
    return fallbackError;
  }
}

class _CommunityApiException implements Exception {
  _CommunityApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CommunityDashboardData {
  const _CommunityDashboardData({required this.explore, required this.mine});

  final List<_CommunitySummary> explore;
  final List<_CommunitySummary> mine;
}

class _CommunityHomeData {
  const _CommunityHomeData({
    required this.dashboard,
    required this.profileGate,
  });

  final _CommunityDashboardData dashboard;
  final _CommunityProfileGate profileGate;
}

class _CommunityDetailData {
  const _CommunityDetailData({
    required this.community,
    required this.profileGate,
  });

  final _CommunitySummary community;
  final _CommunityProfileGate profileGate;
}

class _CommunityProfileGate {
  const _CommunityProfileGate({
    required this.missingItems,
    required this.completedCount,
    required this.requiredCount,
  });

  final List<String> missingItems;
  final int completedCount;
  final int requiredCount;

  bool get isComplete => missingItems.isEmpty;

  double get progress => requiredCount <= 0
      ? 1
      : (completedCount / requiredCount).clamp(0, 1).toDouble();

  String get progressLabel => '%${(progress * 100).round()}';

  factory _CommunityProfileGate.fromProfileMap(Map<String, dynamic> map) {
    final missingItems = <String>[];
    final checks = <String, bool>{
      'Ad': _hasContent(map['displayName']),
      'Kullanici adi': _hasContent(map['username']),
      'Kisa bio': _hasContent(map['about']),
      'Profil fotografi': _hasContent(map['avatarUrl']),
    };
    checks.forEach((label, complete) {
      if (!complete) missingItems.add(label);
    });
    return _CommunityProfileGate(
      missingItems: missingItems,
      completedCount: checks.length - missingItems.length,
      requiredCount: checks.length,
    );
  }

  static bool _hasContent(Object? value) {
    final text = value?.toString().trim();
    return text != null && text.isNotEmpty;
  }
}

class _CommunityChannelSummary {
  const _CommunityChannelSummary({
    required this.id,
    required this.slug,
    required this.name,
    required this.type,
    required this.isDefault,
  });

  final String id;
  final String slug;
  final String name;
  final String type;
  final bool isDefault;

  factory _CommunityChannelSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityChannelSummary(
      id: (map['id'] ?? '').toString(),
      slug: (map['slug'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      type: (map['type'] ?? 'chat').toString(),
      isDefault: map['isDefault'] == true,
    );
  }
}

class _CommunitySummary {
  const _CommunitySummary({
    required this.id,
    required this.slug,
    required this.name,
    required this.memberCount,
    required this.isMember,
    required this.visibility,
    this.tagline,
    this.description,
    this.emoji,
    this.role,
    this.joinedAt,
    this.coverGradientFrom,
    this.coverGradientTo,
    this.welcomeTitle,
    this.welcomeDescription,
    this.entryChecklist = const <String>[],
    this.rules = const <String>[],
    this.channels = const <_CommunityChannelSummary>[],
  });

  final String id;
  final String slug;
  final String name;
  final String? tagline;
  final String? description;
  final String? emoji;
  final String visibility;
  final int memberCount;
  final bool isMember;
  final String? role;
  final String? joinedAt;
  final String? coverGradientFrom;
  final String? coverGradientTo;
  final String? welcomeTitle;
  final String? welcomeDescription;
  final List<String> entryChecklist;
  final List<String> rules;
  final List<_CommunityChannelSummary> channels;

  String get summaryText {
    final channelCount = channels.length;
    final memberText = memberCount == 1 ? '1 uye' : '$memberCount uye';
    if (channelCount <= 0) return memberText;
    final channelText = channelCount == 1 ? '1 oda' : '$channelCount oda';
    return '$memberText  •  $channelText';
  }

  String get roleLabel {
    switch ((role ?? '').toLowerCase()) {
      case 'owner':
        return 'Kurucu';
      case 'admin':
        return 'Admin';
      case 'moderator':
        return 'Mod';
      case 'mentor':
        return 'Mentor';
      default:
        return 'Uye';
    }
  }

  String get cardSubtitle => tagline?.trim().isNotEmpty == true
      ? tagline!.trim()
      : (description?.trim().isNotEmpty == true
            ? description!.trim()
            : 'Topluluk alani');

  factory _CommunitySummary.fromMap(Map<String, dynamic> map) {
    return _CommunitySummary(
      id: (map['id'] ?? '').toString(),
      slug: (map['slug'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      tagline: _nullableString(map['tagline']),
      description: _nullableString(map['description']),
      emoji: _nullableString(map['emoji']),
      visibility: (map['visibility'] ?? 'public').toString(),
      memberCount: (map['memberCount'] as num?)?.toInt() ?? 0,
      isMember: map['isMember'] == true,
      role: _nullableString(map['role']),
      joinedAt: _nullableString(map['joinedAt']),
      coverGradientFrom: _nullableString(map['coverGradientFrom']),
      coverGradientTo: _nullableString(map['coverGradientTo']),
      welcomeTitle: _nullableString(map['welcomeTitle']),
      welcomeDescription: _nullableString(map['welcomeDescription']),
      entryChecklist: _stringList(map['entryChecklist']),
      rules: _stringList(map['rules']),
      channels: (map['channels'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityChannelSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

class _CommunityUiTokens {
  static const background = Color(0xFFF7F8F4);
  static const surface = Colors.white;
  static const surfaceSoft = Color(0xFFF1F4EC);
  static const border = Color(0xFFE2E7DA);
  static const text = Color(0xFF182018);
  static const textMuted = Color(0xFF6C756B);

  static const mint = Color(0xFF7BC6A4);
  static const sky = Color(0xFF7EC8F8);
  static const sun = Color(0xFFF6D36E);
  static const coral = Color(0xFFF39A82);
  static const lavender = Color(0xFFB8B4F8);

  static const success = Color(0xFF39B97A);

  static const pagePadding = 20.0;
  static const sectionGap = 24.0;
  static const cardRadius = 24.0;
  static const chipRadius = 999.0;

  static List<BoxShadow> get softShadow => const [
    BoxShadow(color: Color(0x12000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

class _CommunityHomePage extends StatefulWidget {
  const _CommunityHomePage({required this.api, this.onTurnaTap});

  final _CommunityApiClient api;
  final VoidCallback? onTurnaTap;

  @override
  State<_CommunityHomePage> createState() => _CommunityHomePageState();
}

class _CommunityHomePageState extends State<_CommunityHomePage> {
  late Future<_CommunityHomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchHomeData();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.api.fetchHomeData();
    });
    await _future;
  }

  Future<void> _openCommunity(_CommunitySummary community) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommunityDetailPage(
          api: widget.api,
          initialCommunity: community,
          onTurnaTap: widget.onTurnaTap,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<_CommunityHomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CommunityErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final homeData = snapshot.data!;
          final data = homeData.dashboard;
          final profileGate = homeData.profileGate;
          final featured = data.explore.take(4).toList();
          final mine = data.mine.take(3).toList();

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                _CommunityUiTokens.pagePadding,
                12,
                _CommunityUiTokens.pagePadding,
                140,
              ),
              children: [
                const _CommunityHeroCard(),
                const SizedBox(height: 18),
                _CommunityProfileCompletionCard(
                  gate: profileGate,
                  onTurnaTap: widget.onTurnaTap,
                ),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '✨',
                  title: 'Sana uygun topluluklar',
                  actionLabel: 'Kesfet',
                ),
                const SizedBox(height: 12),
                if (featured.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '🌿',
                    title: 'Henuz listelenen topluluk yok',
                    subtitle:
                        'Seed script calistiginda burada onerilen topluluklar gorunecek.',
                  )
                else
                  SizedBox(
                    height: 194,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: featured.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final community = featured[index];
                        return _CommunityCard(
                          emoji: community.emoji ?? _emojiForIndex(index),
                          title: community.name,
                          subtitle: community.cardSubtitle,
                          accent: _accentForCommunity(community, index),
                          onTap: () => _openCommunity(community),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '🌿',
                  title: 'Topluluklarin',
                ),
                const SizedBox(height: 12),
                if (mine.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '🫶',
                    title: 'Henüz bir topluluğa katılmadın',
                    subtitle:
                        'Kesfet alanindan topluluklara katildiginda burada gormeye baslayacaksin.',
                  )
                else
                  ...List<Widget>.generate(mine.length, (index) {
                    final community = mine[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == mine.length - 1 ? 0 : 12,
                      ),
                      child: _WideCommunityCard(
                        emoji: community.emoji ?? _emojiForIndex(index + 2),
                        title: community.name,
                        subtitle: community.cardSubtitle,
                        stats:
                            'Rolun: ${community.roleLabel}  •  ${community.summaryText}',
                        accent: _accentForCommunity(community, index + 3),
                        onTap: () => _openCommunity(community),
                      ),
                    );
                  }),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '📅',
                  title: 'Yaklasan etkinlikler',
                ),
                const SizedBox(height: 12),
                const _CommunityEventCard(),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '🤝',
                  title: 'Yeni kisiler',
                  actionLabel: 'Dizine git',
                ),
                const SizedBox(height: 12),
                const _CommunityMemberTile(
                  emoji: '🪄',
                  name: 'Selin T.',
                  role: 'Urun tasarimcisi',
                  subtitle: 'Istanbul  •  Tasarim, AI, growth',
                ),
                const SizedBox(height: 10),
                const _CommunityMemberTile(
                  emoji: '🚀',
                  name: 'Emir K.',
                  role: 'Startup kurucusu',
                  subtitle: 'Ankara  •  SaaS, satis, ekip kurma',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommunityExplorePage extends StatefulWidget {
  const _CommunityExplorePage({required this.api, this.onTurnaTap});

  final _CommunityApiClient api;
  final VoidCallback? onTurnaTap;

  @override
  State<_CommunityExplorePage> createState() => _CommunityExplorePageState();
}

class _CommunityExplorePageState extends State<_CommunityExplorePage> {
  late Future<List<_CommunitySummary>> _future;
  final Set<String> _joiningIds = <String>{};

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchExplore();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.api.fetchExplore();
    });
    await _future;
  }

  Future<void> _openCommunity(_CommunitySummary community) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommunityDetailPage(
          api: widget.api,
          initialCommunity: community,
          onTurnaTap: widget.onTurnaTap,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<bool> _ensureProfileReady() async {
    final gate = await widget.api.fetchProfileGate();
    if (gate.isComplete) return true;
    if (!mounted) return false;
    await _showCommunityProfileGateSheet(
      context,
      gate: gate,
      onTurnaTap: widget.onTurnaTap,
    );
    return false;
  }

  Future<void> _join(_CommunitySummary community) async {
    if (_joiningIds.contains(community.id)) return;
    final ready = await _ensureProfileReady();
    if (!ready) return;
    setState(() => _joiningIds.add(community.id));
    try {
      await widget.api.join(community.id);
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${community.name} topluluguna katildin.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _joiningIds.remove(community.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<List<_CommunitySummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CommunityErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final communities = snapshot.data ?? const <_CommunitySummary>[];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                _CommunityUiTokens.pagePadding,
                12,
                _CommunityUiTokens.pagePadding,
                140,
              ),
              children: [
                const _CommunityPageTitle(
                  title: 'Kesfet',
                  subtitle: 'Ilgi alanina gore topluluk bul',
                ),
                const SizedBox(height: 18),
                const _CommunitySearchField(),
                const SizedBox(height: 16),
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _CommunityChip(label: '🚀 Girisim'),
                    _CommunityChip(label: '🎨 Tasarim'),
                    _CommunityChip(label: '🧠 AI'),
                    _CommunityChip(label: '💼 Kariyer'),
                    _CommunityChip(label: '🌍 Networking'),
                    _CommunityChip(label: '📚 Egitim'),
                  ],
                ),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '🌟',
                  title: 'One cikan topluluklar',
                ),
                const SizedBox(height: 12),
                if (communities.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '🌱',
                    title: 'Topluluk bulunamadi',
                    subtitle:
                        'Seed script calistiginda burada listelenen topluluklar gorunecek.',
                  )
                else
                  ...List<Widget>.generate(communities.length, (index) {
                    final community = communities[index];
                    final busy = _joiningIds.contains(community.id);
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == communities.length - 1 ? 0 : 12,
                      ),
                      child: _WideCommunityCard(
                        emoji: community.emoji ?? _emojiForIndex(index),
                        title: community.name,
                        subtitle: community.cardSubtitle,
                        stats: community.summaryText,
                        accent: _accentForCommunity(community, index),
                        onTap: () => _openCommunity(community),
                        actionLabel: community.isMember
                            ? 'Katildin'
                            : (busy ? 'Bekle...' : 'Katil'),
                        onAction: community.isMember || busy
                            ? null
                            : () => _join(community),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommunityNotificationsPage extends StatelessWidget {
  const _CommunityNotificationsPage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          _CommunityUiTokens.pagePadding,
          12,
          _CommunityUiTokens.pagePadding,
          140,
        ),
        children: const [
          _CommunityPageTitle(
            title: 'Bildirimler',
            subtitle: 'Topluluk hareketleri burada',
          ),
          SizedBox(height: 18),
          _NotificationTile(
            emoji: '🔥',
            title: 'Threadine 8 yeni cevap geldi',
            subtitle: 'AI Circle  •  5 dk once',
          ),
          SizedBox(height: 12),
          _NotificationTile(
            emoji: '🤝',
            title: 'Yeni mesaj istegi',
            subtitle: 'Girisim Kulubu icinden Selin sana ulasti',
          ),
          SizedBox(height: 12),
          _NotificationTile(
            emoji: '📅',
            title: 'Etkinlik yarin basliyor',
            subtitle: 'Creator Lounge  •  Canli yayin oturumu',
          ),
          SizedBox(height: 12),
          _NotificationTile(
            emoji: '📌',
            title: 'Yeni yonetici duyurusu',
            subtitle: 'Tasarim Evi  •  Haftalik ozet paylasildi',
          ),
        ],
      ),
    );
  }
}

class _CommunityMyCommunitiesPage extends StatefulWidget {
  const _CommunityMyCommunitiesPage({required this.api, this.onTurnaTap});

  final _CommunityApiClient api;
  final VoidCallback? onTurnaTap;

  @override
  State<_CommunityMyCommunitiesPage> createState() =>
      _CommunityMyCommunitiesPageState();
}

class _CommunityMyCommunitiesPageState
    extends State<_CommunityMyCommunitiesPage> {
  late Future<List<_CommunitySummary>> _future;
  final Set<String> _leavingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchMine();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.api.fetchMine();
    });
    await _future;
  }

  Future<void> _openCommunity(_CommunitySummary community) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommunityDetailPage(
          api: widget.api,
          initialCommunity: community,
          onTurnaTap: widget.onTurnaTap,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _leave(_CommunitySummary community) async {
    if (_leavingIds.contains(community.id)) return;
    setState(() => _leavingIds.add(community.id));
    try {
      await widget.api.leave(community.id);
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${community.name} toplulugundan ayrildin.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _leavingIds.remove(community.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<List<_CommunitySummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CommunityErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final communities = snapshot.data ?? const <_CommunitySummary>[];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                _CommunityUiTokens.pagePadding,
                12,
                _CommunityUiTokens.pagePadding,
                140,
              ),
              children: [
                const _CommunityPageTitle(
                  title: 'Topluluklarim',
                  subtitle: 'Dahil oldugun alanlar',
                ),
                const SizedBox(height: 18),
                if (communities.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '🫶',
                    title: 'Henüz bir topluluga katilmadin',
                    subtitle:
                        'Kesfet ekranindan topluluklara katildiginda burada gormeye baslayacaksin.',
                  )
                else
                  ...List<Widget>.generate(communities.length, (index) {
                    final community = communities[index];
                    final busy = _leavingIds.contains(community.id);
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == communities.length - 1 ? 0 : 12,
                      ),
                      child: _WideCommunityCard(
                        emoji: community.emoji ?? _emojiForIndex(index),
                        title: community.name,
                        subtitle: community.cardSubtitle,
                        stats:
                            'Rolun: ${community.roleLabel}  •  ${community.summaryText}',
                        accent: _accentForCommunity(community, index),
                        onTap: () => _openCommunity(community),
                        actionLabel: busy ? 'Bekle...' : 'Ayril',
                        onAction: busy ? null : () => _leave(community),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommunityTurnaReturnPage extends StatelessWidget {
  const _CommunityTurnaReturnPage({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(_CommunityUiTokens.pagePadding),
          child: _SurfaceCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: _CommunityUiTokens.surfaceSoft,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('💬', style: TextStyle(fontSize: 34)),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Turna moduna don',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Community icindeki baglantilar kabul olunca birebir sohbetler burada devam eder.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: _CommunityUiTokens.text,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Turna moduna gec'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityDetailPage extends StatefulWidget {
  const _CommunityDetailPage({
    required this.api,
    required this.initialCommunity,
    this.onTurnaTap,
  });

  final _CommunityApiClient api;
  final _CommunitySummary initialCommunity;
  final VoidCallback? onTurnaTap;

  @override
  State<_CommunityDetailPage> createState() => _CommunityDetailPageState();
}

class _CommunityDetailPageState extends State<_CommunityDetailPage> {
  late Future<_CommunityDetailData> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchDetailData(widget.initialCommunity.id);
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.api.fetchDetailData(widget.initialCommunity.id);
    });
    await _future;
  }

  Future<void> _handleJoin(_CommunityDetailData data) async {
    if (_busy) return;
    if (!data.profileGate.isComplete) {
      await _showCommunityProfileGateSheet(
        context,
        gate: data.profileGate,
        onTurnaTap: widget.onTurnaTap,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.join(data.community.id);
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${data.community.name} topluluguna katildin.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _handleLeave(_CommunityDetailData data) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.leave(data.community.id);
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${data.community.name} toplulugundan ayrildin.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CommunityUiTokens.background,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_CommunityDetailData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _CommunityErrorState(
                message: snapshot.error.toString(),
                onRetry: _reload,
              );
            }

            final data = snapshot.data!;
            final community = data.community;
            final accent = _accentForCommunity(community, 0);
            final ruleItems = community.rules.isEmpty
                ? const <String>[
                    'Saygili kal ve baglamsiz promosyon yapma.',
                    'Once kanalda etkileşim kur, sonra DM istegi gonder.',
                    'Kaynak veya iddia paylasirken net baglam ver.',
                  ]
                : community.rules;
            final entryItems = community.entryChecklist.isEmpty
                ? const <String>[
                    'Kendini tanit.',
                    'Ilgili odayi takip et.',
                    'Bir sohbete katilarak gorunur olmaya basla.',
                  ]
                : community.entryChecklist;

            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  _CommunityUiTokens.pagePadding,
                  12,
                  _CommunityUiTokens.pagePadding,
                  40,
                ),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _CommunityUiTokens.text,
                        ),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Topluluk detayi',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _CommunityUiTokens.textMuted,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Dashboard + sohbet + kurallar',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _CommunityUiTokens.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: 0.22),
                          _colorWithMix(accent, Colors.white, 0.78),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: _CommunityUiTokens.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  community.emoji ?? '🌿',
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      community.name,
                                      style: const TextStyle(
                                        fontSize: 25,
                                        height: 1.05,
                                        fontWeight: FontWeight.w700,
                                        color: _CommunityUiTokens.text,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      community.cardSubtitle,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                        color: _CommunityUiTokens.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _CommunityMetricPill(
                                label: '👥 ${community.memberCount} uye',
                              ),
                              _CommunityMetricPill(
                                label: '🗂️ ${community.channels.length} oda',
                              ),
                              _CommunityMetricPill(
                                label: community.isMember
                                    ? '✅ Uyesin'
                                    : '🔓 Acik katilim',
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          if (community.isMember)
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _handleLeave(data),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _CommunityUiTokens.text,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: Text(
                                      _busy ? 'Bekle...' : 'Topluluktan ayril',
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _handleJoin(data),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _CommunityUiTokens.text,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: Text(
                                      _busy
                                          ? 'Bekle...'
                                          : (data.profileGate.isComplete
                                                ? 'Topluluga katil'
                                                : 'Profili tamamla'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!data.profileGate.isComplete && !community.isMember)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _CommunityProfileCompletionCard(
                        gate: data.profileGate,
                        onTurnaTap: widget.onTurnaTap,
                        compact: true,
                      ),
                    ),
                  _SurfaceCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _CommunitySectionHeader(
                          emoji: '🪄',
                          title: 'Nereden baslamali?',
                        ),
                        const SizedBox(height: 12),
                        if ((community.welcomeTitle ?? '').trim().isNotEmpty)
                          Text(
                            community.welcomeTitle!,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: _CommunityUiTokens.text,
                            ),
                          ),
                        if ((community.welcomeDescription ?? '')
                            .trim()
                            .isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              community.welcomeDescription!,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: _CommunityUiTokens.textMuted,
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        ...List<Widget>.generate(entryItems.length, (index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == entryItems.length - 1 ? 0 : 10,
                            ),
                            child: _ChecklistTile(
                              index: index + 1,
                              text: entryItems[index],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SurfaceCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _CommunitySectionHeader(
                          emoji: '💬',
                          title: 'Odalar',
                        ),
                        const SizedBox(height: 12),
                        ...List<Widget>.generate(community.channels.length, (
                          index,
                        ) {
                          final channel = community.channels[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == community.channels.length - 1
                                  ? 0
                                  : 10,
                            ),
                            child: _ChannelTile(channel: channel),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SurfaceCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _CommunitySectionHeader(
                          emoji: '🛡️',
                          title: 'Topluluk kurallari',
                        ),
                        const SizedBox(height: 12),
                        ...List<Widget>.generate(ruleItems.length, (index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == ruleItems.length - 1 ? 0 : 10,
                            ),
                            child: _RuleTile(text: ruleItems[index]),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _SurfaceCard(
                    padding: EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CommunitySectionHeader(
                          emoji: '🤝',
                          title: 'Networking mantigi',
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Birebir baglanti kurmak isteyen uyeler once istek gonderir. Kabul edilen baglantilar Turna birebir sohbetine duser.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: _CommunityUiTokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CommunityHeroCard extends StatelessWidget {
  const _CommunityHeroCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF8F2), Color(0xFFF8F2E7)],
        ),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('🌿', style: TextStyle(fontSize: 18)),
                SizedBox(width: 8),
                Text(
                  'Community',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Bugun hangi toplulukta gorunmek istiyorsun?',
              style: TextStyle(
                fontSize: 29,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.text,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Canli sohbet, sorular, kaynaklar ve guvenli networking ayni akista.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _CommunityMetricPill(label: '🌿 Curated topluluklar'),
                _CommunityMetricPill(label: '📅 Etkinlikler'),
                _CommunityMetricPill(label: '🤝 Guvenli baglanti'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityProfileCompletionCard extends StatelessWidget {
  const _CommunityProfileCompletionCard({
    required this.gate,
    this.onTurnaTap,
    this.compact = false,
  });

  final _CommunityProfileGate gate;
  final VoidCallback? onTurnaTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🧩', style: TextStyle(fontSize: 18)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Community profiline son dokunus',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
              ),
              Text(
                gate.progressLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _CommunityUiTokens.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: gate.progress,
              minHeight: 8,
              backgroundColor: _CommunityUiTokens.surfaceSoft,
              color: gate.isComplete
                  ? _CommunityUiTokens.success
                  : _CommunityUiTokens.sun,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            gate.isComplete
                ? 'Mevcut profilin community katilimi icin yeterli. Artik topluluklara katilip mesaj istekleri gonderebilirsin.'
                : 'Topluluk katilimi icin su alanlari tamamla: ${gate.missingItems.join(', ')}.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
          if (!gate.isComplete && onTurnaTap != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onTurnaTap,
                style: TextButton.styleFrom(
                  foregroundColor: _CommunityUiTokens.text,
                  backgroundColor: _CommunityUiTokens.surfaceSoft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  compact ? 'Siz bolumune don' : 'Profili tamamlamak icin don',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommunityPageTitle extends StatelessWidget {
  const _CommunityPageTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w700,
            color: _CommunityUiTokens.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            color: _CommunityUiTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class _CommunitySectionHeader extends StatelessWidget {
  const _CommunitySectionHeader({
    required this.emoji,
    required this.title,
    this.actionLabel,
  });

  final String emoji;
  final String title;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.text,
            ),
          ),
        ),
        if (actionLabel != null)
          Text(
            actionLabel!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
      ],
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 222,
      child: GestureDetector(
        onTap: onTap,
        child: _SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _CommunityUiTokens.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: _CommunityUiTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideCommunityCard extends StatelessWidget {
  const _WideCommunityCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.stats,
    required this.accent,
    this.actionLabel,
    this.onAction,
    this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final String stats;
  final Color accent;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _SurfaceCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _CommunityUiTokens.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stats,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: 12),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: _CommunityUiTokens.text,
                  backgroundColor: _CommunityUiTokens.surfaceSoft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommunityEventCard extends StatelessWidget {
  const _CommunityEventCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6EFD9), Color(0xFFF4F8EA)],
        ),
        borderRadius: BorderRadius.circular(_CommunityUiTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '🎙️ Canli oturum',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Topluluk onboarding deneyimi nasil tasarlanir?',
              style: TextStyle(
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.text,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Yarin 20:30  •  148 kisi katiliyor',
              style: TextStyle(
                fontSize: 13,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityMemberTile extends StatelessWidget {
  const _CommunityMemberTile({
    required this.emoji,
    required this.name,
    required this.role,
    required this.subtitle,
  });

  final String emoji;
  final String name;
  final String role;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _CommunityUiTokens.surfaceSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: _CommunityUiTokens.textMuted,
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  final String emoji;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _CommunityUiTokens.surfaceSoft,
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: _CommunityUiTokens.surfaceSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.text,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _CommunityUiTokens.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel});

  final _CommunityChannelSummary channel;

  @override
  Widget build(BuildContext context) {
    final descriptor = _communityChannelDescriptor(channel.type);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _CommunityUiTokens.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                descriptor.emoji,
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _CommunityUiTokens.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descriptor.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (channel.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Baslangic',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _CommunityUiTokens.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('•', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: _CommunityUiTokens.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunitySearchField extends StatelessWidget {
  const _CommunitySearchField();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _CommunityUiTokens.border),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: _CommunityUiTokens.textMuted),
            SizedBox(width: 10),
            Text(
              'Topluluk, konu veya kisi ara',
              style: TextStyle(
                fontSize: 14,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityMetricPill extends StatelessWidget {
  const _CommunityMetricPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _CommunityUiTokens.text,
          ),
        ),
      ),
    );
  }
}

class _CommunityChip extends StatelessWidget {
  const _CommunityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _CommunityUiTokens.surfaceSoft,
        borderRadius: BorderRadius.circular(_CommunityUiTokens.chipRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _CommunityUiTokens.text,
          ),
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _CommunityUiTokens.surface,
        borderRadius: BorderRadius.circular(_CommunityUiTokens.cardRadius),
        border: Border.all(color: _CommunityUiTokens.border),
        boxShadow: _CommunityUiTokens.softShadow,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _CommunityEmptyState extends StatelessWidget {
  const _CommunityEmptyState({
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  final String emoji;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityErrorState extends StatelessWidget {
  const _CommunityErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_CommunityUiTokens.pagePadding),
        child: _SurfaceCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 28)),
              const SizedBox(height: 10),
              const Text(
                'Community verisi yuklenemedi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _CommunityUiTokens.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: _CommunityUiTokens.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: _CommunityUiTokens.text,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityBottomBar extends StatelessWidget {
  const _CommunityBottomBar({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = <({String emoji, String label})>[
      (emoji: '🏡', label: 'Ana Sayfa'),
      (emoji: '🧭', label: 'Kesfet'),
      (emoji: '💬', label: 'Turna'),
      (emoji: '🔔', label: 'Bildirimler'),
      (emoji: '🌿', label: 'Topluluklarim'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _CommunityUiTokens.border),
            boxShadow: _CommunityUiTokens.softShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: List<Widget>.generate(items.length, (index) {
                final item = items[index];
                final selected = index == selectedIndex;
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onSelect(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? _CommunityUiTokens.surfaceSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: _CommunityUiTokens.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showCommunityProfileGateSheet(
  BuildContext context, {
  required _CommunityProfileGate gate,
  VoidCallback? onTurnaTap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _SurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profili tamamla',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Topluluklara katilmak ve mesaj istegi gonderebilmek icin su alanlar eksik: ${gate.missingItems.join(', ')}.',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: gate.missingItems
                      .map((item) => _CommunityChip(label: '🧩 $item'))
                      .toList(),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          onTurnaTap?.call();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _CommunityUiTokens.text,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('Siz bolumune don'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

({String emoji, String label}) _communityChannelDescriptor(String type) {
  switch (type.toLowerCase()) {
    case 'announcement':
      return (emoji: '📣', label: 'Duyuru kanali');
    case 'question':
      return (emoji: '❓', label: 'Soru-cevap alani');
    case 'resource':
      return (emoji: '📚', label: 'Kaynak kutuphanesi');
    case 'event':
      return (emoji: '📅', label: 'Etkinlik alani');
    default:
      return (emoji: '💬', label: 'Canli sohbet odasi');
  }
}

Color _accentForCommunity(_CommunitySummary community, int index) {
  final from = _parseHexColor(community.coverGradientFrom);
  if (from != null) return from;

  const palette = <Color>[
    _CommunityUiTokens.sky,
    _CommunityUiTokens.coral,
    _CommunityUiTokens.lavender,
    _CommunityUiTokens.sun,
    _CommunityUiTokens.mint,
  ];
  return palette[index % palette.length];
}

String _emojiForIndex(int index) {
  const emojis = <String>['🚀', '🎨', '🧠', '📚', '🌍', '💼'];
  return emojis[index % emojis.length];
}

Color? _parseHexColor(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  final normalized = text.replaceFirst('#', '');
  if (normalized.length != 6) return null;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return null;
  return Color(0xFF000000 | parsed);
}

Color _colorWithMix(Color color, Color other, double ratio) {
  final clamped = ratio.clamp(0, 1).toDouble();
  return Color.lerp(color, other, clamped) ?? color;
}
