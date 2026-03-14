import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

void _communityLog(String message, [Object? data]) {
  if (data != null) {
    debugPrint('[turna-community] $message | $data');
    return;
  }
  debugPrint('[turna-community] $message');
}

class CommunityShellPreviewPage extends StatefulWidget {
  const CommunityShellPreviewPage({
    super.key,
    required this.authToken,
    required this.backendBaseUrl,
    required this.currentUserId,
    this.onTurnaTap,
    this.onProfileTap,
  });

  final String authToken;
  final String backendBaseUrl;
  final String currentUserId;
  final VoidCallback? onTurnaTap;
  final VoidCallback? onProfileTap;

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

  void _handleTurnaTap() {
    final navigator = Navigator.of(context, rootNavigator: true);
    _communityLog('community turna tapped', {
      'selectedIndex': _selectedIndex,
      'hasCallback': widget.onTurnaTap != null,
      'rootCanPop': navigator.canPop(),
    });
    if (navigator.canPop()) {
      _communityLog('community turna popUntil first');
      navigator.popUntil((route) => route.isFirst);
    }
    widget.onTurnaTap?.call();
  }

  void _handleProfileTap() {
    final navigator = Navigator.of(context, rootNavigator: true);
    _communityLog('community profile tapped', {
      'selectedIndex': _selectedIndex,
      'hasCallback': widget.onProfileTap != null,
      'rootCanPop': navigator.canPop(),
    });
    if (navigator.canPop()) {
      _communityLog('community profile popUntil first');
      navigator.popUntil((route) => route.isFirst);
    }
    widget.onProfileTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _CommunityHomePage(
        api: _api,
        currentUserId: widget.currentUserId,
        onTurnaTap: _handleTurnaTap,
        onProfileTap: _handleProfileTap,
      ),
      _CommunityExplorePage(
        api: _api,
        currentUserId: widget.currentUserId,
        onTurnaTap: _handleTurnaTap,
        onProfileTap: _handleProfileTap,
      ),
      _CommunityTurnaReturnPage(onTap: _handleTurnaTap),
      _CommunityNotificationsPage(api: _api),
      _CommunityMyCommunitiesPage(
        api: _api,
        currentUserId: widget.currentUserId,
        onTurnaTap: _handleTurnaTap,
        onProfileTap: _handleProfileTap,
      ),
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
          if (index == 2) {
            _communityLog('community bottom bar turna selected', {
              'selectedIndex': _selectedIndex,
            });
            _handleTurnaTap();
            return;
          }
          _communityLog('community bottom bar tab selected', {
            'from': _selectedIndex,
            'to': index,
          });
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
    return _decodeCommunityList(res, fallbackError: 'Topluluklar yüklenemedi.');
  }

  Future<List<_CommunitySummary>> fetchMine() async {
    final res = await http.get(
      _uri('/api/communities/mine'),
      headers: _headers,
    );
    return _decodeCommunityList(
      res,
      fallbackError: 'Toplulukların yüklenemedi.',
    );
  }

  Future<_CommunityDashboardData> fetchDashboard() async {
    final res = await http.get(
      _uri('/api/communities/home'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Community ana sayfa verileri yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    return _CommunityDashboardData.fromMap(data);
  }

  Future<_CommunityProfileGate> fetchProfileGate() async {
    final res = await http.get(_uri('/api/profile/me'), headers: _headers);
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Community profili yüklenemedi.'),
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
      fallbackError: 'Topluluk detayı yüklenemedi.',
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

  Future<_CommunityChannelFeed> fetchChannelMessages({
    required String communityId,
    required String channelId,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/channels/$channelId/messages'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Kanal mesajları yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    return _CommunityChannelFeed.fromMap(data);
  }

  Future<_CommunityMessageSummary> sendChannelMessage({
    required String communityId,
    required String channelId,
    required String text,
    String? replyToMessageId,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/channels/$channelId/messages'),
      headers: _headers,
      body: jsonEncode({
        'text': text,
        if ((replyToMessageId ?? '').trim().isNotEmpty)
          'replyToMessageId': replyToMessageId,
      }),
    );
    return _decodeChannelMessage(res, fallbackError: 'Mesaj gönderilemedi.');
  }

  Future<_CommunityThreadFeed> fetchThread({
    required String communityId,
    required String channelId,
    required String messageId,
  }) async {
    final res = await http.get(
      _uri(
        '/api/communities/$communityId/channels/$channelId/messages/$messageId/thread',
      ),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Mesaj threadi yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    return _CommunityThreadFeed.fromMap(data);
  }

  Future<List<_CommunityNotificationSummary>> fetchNotifications({
    int limit = 40,
  }) async {
    final res = await http.get(
      _uri('/api/communities/notifications', {'limit': '$limit'}),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Community bildirimleri yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => _CommunityNotificationSummary.fromMap(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<List<_CommunityTopicSummary>> fetchTopics({
    required String communityId,
    required String type,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/topics', {'type': type}),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Topluluk içerikleri yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              _CommunityTopicSummary.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<List<_CommunityMemberSummary>> fetchMembers({
    required String communityId,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/members'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(_decodeError(res, 'Üyeler yüklenemedi.'));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              _CommunityMemberSummary.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<_CommunitySummary> join(String communityId) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/join'),
      headers: _headers,
    );
    return _decodeCommunityItem(res, fallbackError: 'Topluluğa katılınamadı.');
  }

  Future<void> leave(String communityId) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/leave'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Topluluktan ayrılamadı.'),
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

  _CommunityMessageSummary _decodeChannelMessage(
    http.Response res, {
    required String fallbackError,
  }) {
    if (res.statusCode >= 400) {
      throw _CommunityApiException(_decodeError(res, fallbackError));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map);
    return _CommunityMessageSummary.fromMap(data);
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
  const _CommunityDashboardData({
    required this.explore,
    required this.mine,
    required this.suggestedMembers,
    this.upcomingEvent,
  });

  final List<_CommunitySummary> explore;
  final List<_CommunitySummary> mine;
  final _CommunityTopicSummary? upcomingEvent;
  final List<_CommunityMemberSummary> suggestedMembers;

  factory _CommunityDashboardData.fromMap(Map<String, dynamic> map) {
    return _CommunityDashboardData(
      explore: (map['explore'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                _CommunitySummary.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      mine: (map['mine'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                _CommunitySummary.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      upcomingEvent: (map['upcomingEvent'] as Map?) == null
          ? null
          : _CommunityTopicSummary.fromMap(
              Map<String, dynamic>.from(map['upcomingEvent'] as Map),
            ),
      suggestedMembers: (map['suggestedMembers'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityMemberSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
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

class _CommunityNotificationSummary {
  const _CommunityNotificationSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    this.body,
    this.readAt,
    this.communityId,
    this.channelId,
    this.messageId,
    this.topicId,
  });

  final String id;
  final String type;
  final String title;
  final String createdAt;
  final String? body;
  final String? readAt;
  final String? communityId;
  final String? channelId;
  final String? messageId;
  final String? topicId;

  factory _CommunityNotificationSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityNotificationSummary(
      id: (map['id'] ?? '').toString(),
      type: (map['type'] ?? 'reply').toString(),
      title: (map['title'] ?? '').toString(),
      createdAt: (map['createdAt'] ?? '').toString(),
      body: _CommunitySummary._nullableString(map['body']),
      readAt: _CommunitySummary._nullableString(map['readAt']),
      communityId: _CommunitySummary._nullableString(map['communityId']),
      channelId: _CommunitySummary._nullableString(map['channelId']),
      messageId: _CommunitySummary._nullableString(map['messageId']),
      topicId: _CommunitySummary._nullableString(map['topicId']),
    );
  }
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
      'Profil fotoğrafı': _hasContent(map['avatarUrl']),
      'Kısa bio': _hasContent(map['about']),
      'Uzmanlık alanı': _hasContent(map['expertise']),
      'Şehir / ülke': _hasContent(map['city']) && _hasContent(map['country']),
      'İlgi alanları': _hasList(map['interests']),
      'Sosyal linkler': _hasList(map['socialLinks']),
      'Topluluktaki rol': _hasContent(map['communityRole']),
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

  static bool _hasList(Object? value) {
    if (value is! List) return false;
    return value.any((item) => item.toString().trim().isNotEmpty);
  }
}

class _CommunityChannelSummary {
  const _CommunityChannelSummary({
    required this.id,
    required this.slug,
    required this.name,
    required this.type,
    required this.isDefault,
    this.description,
  });

  final String id;
  final String slug;
  final String name;
  final String type;
  final bool isDefault;
  final String? description;

  factory _CommunityChannelSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityChannelSummary(
      id: (map['id'] ?? '').toString(),
      slug: (map['slug'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      type: (map['type'] ?? 'chat').toString(),
      isDefault: map['isDefault'] == true,
      description: _CommunitySummary._nullableString(map['description']),
    );
  }
}

class _CommunityUserSummary {
  const _CommunityUserSummary({
    required this.id,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.about,
    this.city,
    this.country,
    this.expertise,
    this.communityRole,
  });

  final String id;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String? about;
  final String? city;
  final String? country;
  final String? expertise;
  final String? communityRole;

  String get subtitle {
    final bits = <String>[];
    if ((city ?? '').trim().isNotEmpty) bits.add(city!.trim());
    if ((country ?? '').trim().isNotEmpty) bits.add(country!.trim());
    if ((expertise ?? '').trim().isNotEmpty) bits.add(expertise!.trim());
    if (bits.isEmpty) {
      return about?.trim().isNotEmpty == true
          ? about!.trim()
          : 'Topluluk üyesi';
    }
    return bits.join('  •  ');
  }

  factory _CommunityUserSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityUserSummary(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      username: _CommunitySummary._nullableString(map['username']),
      avatarUrl: _CommunitySummary._nullableString(map['avatarUrl']),
      about: _CommunitySummary._nullableString(map['about']),
      city: _CommunitySummary._nullableString(map['city']),
      country: _CommunitySummary._nullableString(map['country']),
      expertise: _CommunitySummary._nullableString(map['expertise']),
      communityRole: _CommunitySummary._nullableString(map['communityRole']),
    );
  }
}

class _CommunityMessageSummary {
  const _CommunityMessageSummary({
    required this.id,
    required this.author,
    required this.createdAt,
    this.text,
    this.replyCount = 0,
    this.replyToMessageId,
    this.replyAuthorName,
    this.replyPreview,
  });

  final String id;
  final _CommunityUserSummary author;
  final String createdAt;
  final String? text;
  final int replyCount;
  final String? replyToMessageId;
  final String? replyAuthorName;
  final String? replyPreview;

  factory _CommunityMessageSummary.fromMap(Map<String, dynamic> map) {
    final replyTo = map['replyToMessage'] as Map<String, dynamic>?;
    final replyText = replyTo == null
        ? null
        : _CommunitySummary._nullableString(replyTo['text']);
    final replyAuthor = replyTo == null
        ? null
        : Map<String, dynamic>.from(replyTo['author'] as Map? ?? const {});
    return _CommunityMessageSummary(
      id: (map['id'] ?? '').toString(),
      author: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['author'] as Map? ?? const {}),
      ),
      createdAt: (map['createdAt'] ?? '').toString(),
      text: _CommunitySummary._nullableString(map['text']),
      replyCount: (map['replyCount'] as num?)?.toInt() ?? 0,
      replyToMessageId: _CommunitySummary._nullableString(
        map['replyToMessageId'],
      ),
      replyAuthorName: _CommunitySummary._nullableString(
        replyAuthor?['displayName'],
      ),
      replyPreview: replyText,
    );
  }
}

class _CommunityThreadFeed {
  const _CommunityThreadFeed({required this.root, required this.replies});

  final _CommunityMessageSummary root;
  final List<_CommunityMessageSummary> replies;

  factory _CommunityThreadFeed.fromMap(Map<String, dynamic> map) {
    return _CommunityThreadFeed(
      root: _CommunityMessageSummary.fromMap(
        Map<String, dynamic>.from(map['root'] as Map? ?? const {}),
      ),
      replies: (map['replies'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityMessageSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class _CommunityChannelFeed {
  const _CommunityChannelFeed({required this.channel, required this.items});

  final _CommunityChannelSummary channel;
  final List<_CommunityMessageSummary> items;

  factory _CommunityChannelFeed.fromMap(Map<String, dynamic> map) {
    return _CommunityChannelFeed(
      channel: _CommunityChannelSummary.fromMap(
        Map<String, dynamic>.from(map['channel'] as Map? ?? const {}),
      ),
      items: (map['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityMessageSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class _CommunityTopicSummary {
  const _CommunityTopicSummary({
    required this.id,
    required this.title,
    required this.type,
    required this.author,
    required this.replyCount,
    required this.createdAt,
    this.body,
    this.channel,
    this.eventStartsAt,
    this.isPinned = false,
    this.isSolved = false,
    this.tags = const <String>[],
    this.replies = const <_CommunityTopicReplySummary>[],
  });

  final String id;
  final String title;
  final String type;
  final _CommunityUserSummary author;
  final int replyCount;
  final String createdAt;
  final String? body;
  final _CommunityChannelSummary? channel;
  final String? eventStartsAt;
  final bool isPinned;
  final bool isSolved;
  final List<String> tags;
  final List<_CommunityTopicReplySummary> replies;

  factory _CommunityTopicSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityTopicSummary(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      type: (map['type'] ?? 'question').toString(),
      author: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['author'] as Map? ?? const {}),
      ),
      replyCount: (map['replyCount'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] ?? '').toString(),
      body: _CommunitySummary._nullableString(map['body']),
      channel: (map['channel'] as Map?) == null
          ? null
          : _CommunityChannelSummary.fromMap(
              Map<String, dynamic>.from(map['channel'] as Map),
            ),
      eventStartsAt: _CommunitySummary._nullableString(map['eventStartsAt']),
      isPinned: map['isPinned'] == true,
      isSolved: map['isSolved'] == true,
      tags: _CommunitySummary._stringList(map['tags']),
      replies: (map['replies'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityTopicReplySummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class _CommunityTopicReplySummary {
  const _CommunityTopicReplySummary({
    required this.id,
    required this.body,
    required this.author,
    required this.createdAt,
    required this.isAccepted,
  });

  final String id;
  final String body;
  final _CommunityUserSummary author;
  final String createdAt;
  final bool isAccepted;

  factory _CommunityTopicReplySummary.fromMap(Map<String, dynamic> map) {
    return _CommunityTopicReplySummary(
      id: (map['id'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      author: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['author'] as Map? ?? const {}),
      ),
      createdAt: (map['createdAt'] ?? '').toString(),
      isAccepted: map['isAccepted'] == true,
    );
  }
}

class _CommunityMemberSummary {
  const _CommunityMemberSummary({
    required this.role,
    required this.joinedAt,
    required this.user,
  });

  final String? role;
  final String joinedAt;
  final _CommunityUserSummary user;

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
        return user.communityRole?.trim().isNotEmpty == true
            ? user.communityRole!.trim()
            : 'Uye';
    }
  }

  factory _CommunityMemberSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityMemberSummary(
      role: _CommunitySummary._nullableString(map['role']),
      joinedAt: (map['joinedAt'] ?? '').toString(),
      user: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['user'] as Map? ?? const {}),
      ),
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
    final memberText = memberCount == 1 ? '1 üye' : '$memberCount üye';
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
            : 'Topluluk alanı');

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
  const _CommunityHomePage({
    required this.api,
    required this.currentUserId,
    this.onTurnaTap,
    this.onProfileTap,
  });

  final _CommunityApiClient api;
  final String currentUserId;
  final VoidCallback? onTurnaTap;
  final VoidCallback? onProfileTap;

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
          currentUserId: widget.currentUserId,
          onTurnaTap: widget.onTurnaTap,
          onProfileTap: widget.onProfileTap,
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
          final suggestedMembers = data.suggestedMembers.take(3).toList();

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
                  onProfileTap: widget.onProfileTap,
                ),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '✨',
                  title: 'Sana uygun topluluklar',
                  actionLabel: 'Keşfet',
                ),
                const SizedBox(height: 12),
                if (featured.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '🌿',
                    title: 'Henüz listelenen topluluk yok',
                    subtitle:
                        'Seed script çalıştığında burada önerilen topluluklar görünecek.',
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
                  title: 'Toplulukların',
                ),
                const SizedBox(height: 12),
                if (mine.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '🫶',
                    title: 'Henüz bir topluluğa katılmadın',
                    subtitle:
                        'Keşfet alanından topluluklara katıldığında burada görmeye başlayacaksın.',
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
                            'Rolün: ${community.roleLabel}  •  ${community.summaryText}',
                        accent: _accentForCommunity(community, index + 3),
                        onTap: () => _openCommunity(community),
                      ),
                    );
                  }),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '📅',
                  title: 'Yaklaşan etkinlikler',
                ),
                const SizedBox(height: 12),
                if (data.upcomingEvent == null)
                  const _CommunityEmptyState(
                    emoji: '🗓️',
                    title: 'Yaklaşan etkinlik yok',
                    subtitle:
                        'Topluluklarında bir etkinlik planlandığında burada görünecek.',
                  )
                else
                  _CommunityEventCard(topic: data.upcomingEvent!),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '🤝',
                  title: 'Yeni kişiler',
                  actionLabel: 'Dizine git',
                ),
                const SizedBox(height: 12),
                if (suggestedMembers.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '👥',
                    title: 'Öne çıkan üye yok',
                    subtitle:
                        'Topluluklara katıldıkça burada yeni kişiler görünmeye başlayacak.',
                  )
                else
                  ...List<Widget>.generate(suggestedMembers.length, (index) {
                    final member = suggestedMembers[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == suggestedMembers.length - 1 ? 0 : 10,
                      ),
                      child: _CommunityMemberTile(
                        emoji: _emojiForIndex(index + 5),
                        name: member.user.displayName,
                        role: member.roleLabel,
                        subtitle: member.user.subtitle,
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

class _CommunityExplorePage extends StatefulWidget {
  const _CommunityExplorePage({
    required this.api,
    required this.currentUserId,
    this.onTurnaTap,
    this.onProfileTap,
  });

  final _CommunityApiClient api;
  final String currentUserId;
  final VoidCallback? onTurnaTap;
  final VoidCallback? onProfileTap;

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
          currentUserId: widget.currentUserId,
          onTurnaTap: widget.onTurnaTap,
          onProfileTap: widget.onProfileTap,
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
      onProfileTap: widget.onProfileTap,
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
        SnackBar(content: Text('${community.name} topluluğuna katıldın.')),
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
                  title: 'Keşfet',
                  subtitle: 'İlgi alanına göre topluluk bul',
                ),
                const SizedBox(height: 18),
                const _CommunitySearchField(),
                const SizedBox(height: 16),
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _CommunityChip(label: '🚀 Girişim'),
                    _CommunityChip(label: '🎨 Tasarım'),
                    _CommunityChip(label: '🧠 AI'),
                    _CommunityChip(label: '💼 Kariyer'),
                    _CommunityChip(label: '🌍 Networking'),
                    _CommunityChip(label: '📚 Eğitim'),
                  ],
                ),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '🌟',
                  title: 'Öne çıkan topluluklar',
                ),
                const SizedBox(height: 12),
                if (communities.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '🌱',
                    title: 'Topluluk bulunamadı',
                    subtitle:
                        'Seed script çalıştığında burada listelenen topluluklar görünecek.',
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
                            ? 'Katıldın'
                            : (busy ? 'Bekle...' : 'Katıl'),
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

class _CommunityNotificationsPage extends StatefulWidget {
  const _CommunityNotificationsPage({required this.api});

  final _CommunityApiClient api;

  @override
  State<_CommunityNotificationsPage> createState() =>
      _CommunityNotificationsPageState();
}

class _CommunityNotificationsPageState
    extends State<_CommunityNotificationsPage> {
  late Future<List<_CommunityNotificationSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchNotifications();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.api.fetchNotifications();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<List<_CommunityNotificationSummary>>(
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

          final notifications =
              snapshot.data ?? const <_CommunityNotificationSummary>[];
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
                  title: 'Bildirimler',
                  subtitle: 'Topluluk hareketleri burada',
                ),
                const SizedBox(height: 18),
                if (notifications.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '🔔',
                    title: 'Bildirim yok',
                    subtitle:
                        'Community içinde hareket oldukça burada listelenecek.',
                  )
                else
                  ...List<Widget>.generate(notifications.length, (index) {
                    final notification = notifications[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == notifications.length - 1 ? 0 : 12,
                      ),
                      child: _NotificationTile(
                        emoji: _emojiForNotificationType(notification.type),
                        title: notification.title,
                        subtitle: [
                          if ((notification.body ?? '').trim().isNotEmpty)
                            notification.body!.trim(),
                          _formatCommunityDate(notification.createdAt),
                        ].join('  •  '),
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

class _CommunityMyCommunitiesPage extends StatefulWidget {
  const _CommunityMyCommunitiesPage({
    required this.api,
    required this.currentUserId,
    this.onTurnaTap,
    this.onProfileTap,
  });

  final _CommunityApiClient api;
  final String currentUserId;
  final VoidCallback? onTurnaTap;
  final VoidCallback? onProfileTap;

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
          currentUserId: widget.currentUserId,
          onTurnaTap: widget.onTurnaTap,
          onProfileTap: widget.onProfileTap,
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
                  title: 'Topluluklarım',
                  subtitle: 'Dahil olduğun alanlar',
                ),
                const SizedBox(height: 18),
                if (communities.isEmpty)
                  const _CommunityEmptyState(
                    emoji: '🫶',
                    title: 'Henüz bir topluluğa katılmadın',
                    subtitle:
                        'Keşfet ekranından topluluklara katıldığında burada görmeye başlayacaksın.',
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
                            'Rolün: ${community.roleLabel}  •  ${community.summaryText}',
                        accent: _accentForCommunity(community, index),
                        onTap: () => _openCommunity(community),
                        actionLabel: busy ? 'Bekle...' : 'Ayrıl',
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
                  'Turna moduna dön',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Community içindeki bağlantılar kabul olunca birebir sohbetler burada devam eder.',
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
                  child: const Text('Turna moduna geç'),
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
    required this.currentUserId,
    this.onTurnaTap,
    this.onProfileTap,
  });

  final _CommunityApiClient api;
  final _CommunitySummary initialCommunity;
  final String currentUserId;
  final VoidCallback? onTurnaTap;
  final VoidCallback? onProfileTap;

  @override
  State<_CommunityDetailPage> createState() => _CommunityDetailPageState();
}

class _CommunityDetailPageState extends State<_CommunityDetailPage> {
  late Future<_CommunityDetailData> _future;
  _CommunityDetailTab _selectedTab = _CommunityDetailTab.home;
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
        onProfileTap: widget.onProfileTap,
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
        SnackBar(content: Text('${data.community.name} topluluğuna katıldın.')),
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

  Future<void> _openChannel(
    _CommunitySummary community,
    _CommunityChannelSummary channel,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommunityChannelPage(
          api: widget.api,
          community: community,
          channel: channel,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _openTopic(_CommunityTopicSummary topic) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommunityTopicDetailPage(topic: topic),
      ),
    );
  }

  Widget _buildTabContent(
    _CommunityDetailData data, {
    required List<String> entryItems,
    required List<String> ruleItems,
  }) {
    if (!data.community.isMember && _selectedTab != _CommunityDetailTab.home) {
      return _CommunityLockedTabCard(
        tab: _selectedTab,
        onProfileTap: widget.onProfileTap,
      );
    }

    switch (_selectedTab) {
      case _CommunityDetailTab.home:
        return _buildHomeTab(
          data.community,
          entryItems: entryItems,
          ruleItems: ruleItems,
        );
      case _CommunityDetailTab.chat:
        return _buildChatTab(data.community);
      case _CommunityDetailTab.questions:
        return _buildQuestionsTab(data.community);
      case _CommunityDetailTab.resources:
        return _buildResourcesTab(data.community);
      case _CommunityDetailTab.members:
        return _buildMembersTab(data.community);
    }
  }

  Widget _buildHomeTab(
    _CommunitySummary community, {
    required List<String> entryItems,
    required List<String> ruleItems,
  }) {
    return Column(
      children: [
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
              if ((community.welcomeDescription ?? '').trim().isNotEmpty)
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
              _CommunitySectionHeader(emoji: '🤝', title: 'Networking mantığı'),
              SizedBox(height: 10),
              Text(
                'Birebir bağlantı kurmak isteyen üyeler önce istek gönderir. Kabul edilen bağlantılar Turna birebir sohbetine düşer.',
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
    );
  }

  Widget _buildChatTab(_CommunitySummary community) {
    final channels = community.channels
        .where(
          (channel) => channel.type == 'chat' || channel.type == 'announcement',
        )
        .toList();
    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CommunitySectionHeader(emoji: '💬', title: 'Sohbet odalari'),
          const SizedBox(height: 12),
          if (channels.isEmpty)
            const _CommunityEmptyState(
              emoji: '💤',
              title: 'Sohbet odasi bulunmadi',
              subtitle:
                  'Chat veya announcement tipindeki kanallar burada listelenecek.',
            )
          else
            ...List<Widget>.generate(channels.length, (index) {
              final channel = channels[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == channels.length - 1 ? 0 : 10,
                ),
                child: _ChannelTile(
                  channel: channel,
                  onTap: () => _openChannel(community, channel),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildQuestionsTab(_CommunitySummary community) {
    return FutureBuilder<List<_CommunityTopicSummary>>(
      future: widget.api.fetchTopics(
        communityId: community.id,
        type: 'question',
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CommunityErrorState(
            message: snapshot.error.toString(),
            onRetry: () async {
              setState(() {});
            },
          );
        }
        final topics = snapshot.data ?? const <_CommunityTopicSummary>[];
        return _SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CommunitySectionHeader(emoji: '❓', title: 'Soru akışı'),
              const SizedBox(height: 12),
              if (topics.isEmpty)
                const _CommunityEmptyState(
                  emoji: '🫥',
                  title: 'Soru bulunmadi',
                  subtitle: 'Question tipi topicler burada listelenecek.',
                )
              else
                ...List<Widget>.generate(topics.length, (index) {
                  final topic = topics[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == topics.length - 1 ? 0 : 10,
                    ),
                    child: _QuestionPreviewTile.fromTopic(
                      topic,
                      onTap: () => _openTopic(topic),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResourcesTab(_CommunitySummary community) {
    return FutureBuilder<List<_CommunityTopicSummary>>(
      future: Future.wait<List<_CommunityTopicSummary>>([
        widget.api.fetchTopics(communityId: community.id, type: 'resource'),
        widget.api.fetchTopics(communityId: community.id, type: 'event'),
      ]).then((items) => [...items[0], ...items[1]]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CommunityErrorState(
            message: snapshot.error.toString(),
            onRetry: () async {
              setState(() {});
            },
          );
        }
        final topics = snapshot.data ?? const <_CommunityTopicSummary>[];
        return _SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CommunitySectionHeader(
                emoji: '🗃️',
                title: 'Kaynaklar ve etkinlikler',
              ),
              const SizedBox(height: 12),
              if (topics.isEmpty)
                const _CommunityEmptyState(
                  emoji: '🪶',
                  title: 'Kaynak bulunmadi',
                  subtitle:
                      'Resource ve event tipi icerikler burada listelenecek.',
                )
              else
                ...List<Widget>.generate(topics.length, (index) {
                  final topic = topics[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == topics.length - 1 ? 0 : 10,
                    ),
                    child: _ResourcePreviewTile.fromTopic(
                      topic,
                      onTap: () => _openTopic(topic),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMembersTab(_CommunitySummary community) {
    return FutureBuilder<List<_CommunityMemberSummary>>(
      future: widget.api.fetchMembers(communityId: community.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CommunityErrorState(
            message: snapshot.error.toString(),
            onRetry: () async {
              setState(() {});
            },
          );
        }
        final members = snapshot.data ?? const <_CommunityMemberSummary>[];
        return Column(
          children: [
            _SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CommunitySectionHeader(
                    emoji: '👥',
                    title: 'Üye katmanı',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _CommunityChip(label: '👥 ${community.memberCount} üye'),
                      const _CommunityChip(label: '🪪 Rol bazlı görünüm'),
                      const _CommunityChip(label: '🤝 DM isteği mantığı'),
                    ],
                  ),
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
                    emoji: '🌱',
                    title: 'Üye dizini',
                  ),
                  const SizedBox(height: 12),
                  if (members.isEmpty)
                    const _CommunityEmptyState(
                      emoji: '🫥',
                      title: 'Üye bulunamadı',
                      subtitle:
                          'Topluluğa üyeler geldikçe bu alan profil bilgileriyle dolacak.',
                    )
                  else
                    ...List<Widget>.generate(members.length, (index) {
                      final member = members[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == members.length - 1 ? 0 : 10,
                        ),
                        child: _CommunityMemberTile(
                          emoji: _emojiForIndex(index),
                          name: member.user.displayName,
                          role: member.roleLabel,
                          subtitle: member.user.subtitle,
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        );
      },
    );
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
                    'Saygılı kal ve bağlamsız promosyon yapma.',
                    'Önce kanalda etkileşim kur, sonra DM isteği gönder.',
                    'Kaynak veya iddia paylaşırken net bağlam ver.',
                  ]
                : community.rules;
            final entryItems = community.entryChecklist.isEmpty
                ? const <String>[
                    'Kendini tanıt.',
                    'İlgili odayı takip et.',
                    'Bir sohbete katılarak görünür olmaya başla.',
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
                              'Topluluk detayı',
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
                                label: '👥 ${community.memberCount} üye',
                              ),
                              _CommunityMetricPill(
                                label: '🗂️ ${community.channels.length} oda',
                              ),
                              _CommunityMetricPill(
                                label: community.isMember
                                    ? '✅ Uyesin'
                                    : '🔓 Açık katılım',
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
                                      _busy ? 'Bekle...' : 'Topluluktan ayrıl',
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
                                                ? 'Topluluğa katıl'
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
                        onProfileTap: widget.onProfileTap,
                        compact: true,
                      ),
                    ),
                  const SizedBox(height: 16),
                  _CommunityDetailTabBar(
                    selectedTab: _selectedTab,
                    onSelected: (tab) {
                      setState(() => _selectedTab = tab);
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTabContent(
                    data,
                    entryItems: entryItems,
                    ruleItems: ruleItems,
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

class _CommunityChannelPage extends StatefulWidget {
  const _CommunityChannelPage({
    required this.api,
    required this.community,
    required this.channel,
    required this.currentUserId,
  });

  final _CommunityApiClient api;
  final _CommunitySummary community;
  final _CommunityChannelSummary channel;
  final String currentUserId;

  @override
  State<_CommunityChannelPage> createState() => _CommunityChannelPageState();
}

class _CommunityChannelPageState extends State<_CommunityChannelPage> {
  final _composerController = TextEditingController();
  final List<_CommunityMessageSummary> _items = <_CommunityMessageSummary>[];
  io.Socket? _socket;
  bool _loading = true;
  bool _sending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _connectRealtime();
  }

  @override
  void dispose() {
    _socket?.emit('community:channel:leave', {
      'communityId': widget.community.id,
      'channelId': widget.channel.id,
    });
    _socket?.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _connectRealtime() {
    final socket = io.io(widget.api.backendBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'forceNew': true,
      'autoConnect': false,
      'auth': {'token': widget.api.authToken},
    });

    socket.onConnect((_) {
      _communityLog('community socket connected', {
        'communityId': widget.community.id,
        'channelId': widget.channel.id,
      });
      socket.emit('community:channel:join', {
        'communityId': widget.community.id,
        'channelId': widget.channel.id,
      });
    });

    socket.on('community:channel:message', (payload) {
      if (payload is! Map) return;
      final data = Map<String, dynamic>.from(payload);
      if ((data['channelId'] ?? '').toString() != widget.channel.id) {
        return;
      }
      final rawMessage = Map<String, dynamic>.from(
        data['message'] as Map? ?? const {},
      );
      final message = _CommunityMessageSummary.fromMap(rawMessage);
      if (!mounted) return;
      setState(() {
        _upsertMessage(message);
      });
    });

    socket.on('community:thread:update', (payload) {
      if (payload is! Map) return;
      final data = Map<String, dynamic>.from(payload);
      if ((data['channelId'] ?? '').toString() != widget.channel.id) {
        return;
      }
      final rootMessageId = (data['rootMessageId'] ?? '').toString();
      final replyCount = (data['replyCount'] as num?)?.toInt() ?? 0;
      final index = _items.indexWhere((item) => item.id == rootMessageId);
      if (index < 0 || !mounted) return;
      final current = _items[index];
      setState(() {
        _items[index] = _CommunityMessageSummary(
          id: current.id,
          author: current.author,
          createdAt: current.createdAt,
          text: current.text,
          replyCount: replyCount,
          replyToMessageId: current.replyToMessageId,
          replyAuthorName: current.replyAuthorName,
          replyPreview: current.replyPreview,
        );
      });
    });

    socket.on('community:error', (payload) {
      if (!mounted || payload is! Map) return;
      final code = (payload['code'] ?? 'community_error').toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mapCommunitySocketError(code))));
    });

    socket.onDisconnect((reason) {
      _communityLog('community socket disconnected', {'reason': reason});
    });

    socket.connect();
    _socket = socket;
  }

  Future<void> _loadInitial() async {
    try {
      final feed = await widget.api.fetchChannelMessages(
        communityId: widget.community.id,
        channelId: widget.channel.id,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = null;
        _items
          ..clear()
          ..addAll(feed.items);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    await _loadInitial();
  }

  void _upsertMessage(_CommunityMessageSummary message) {
    if ((message.replyToMessageId ?? '').trim().isNotEmpty) {
      return;
    }
    final existingIndex = _items.indexWhere((item) => item.id == message.id);
    if (existingIndex >= 0) {
      _items[existingIndex] = message;
      return;
    }
    _items.add(message);
    _items.sort((left, right) => left.createdAt.compareTo(right.createdAt));
  }

  Future<void> _openThread(_CommunityMessageSummary message) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommunityThreadPage(
          api: widget.api,
          community: widget.community,
          channel: widget.channel,
          rootMessage: message,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _sendRootMessage() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final created = await widget.api.sendChannelMessage(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        text: text,
      );
      _composerController.clear();
      if (!mounted) return;
      setState(() {
        _upsertMessage(created);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final descriptor = _communityChannelDescriptor(widget.channel.type);
    return Scaffold(
      backgroundColor: _CommunityUiTokens.background,
      appBar: AppBar(
        backgroundColor: _CommunityUiTokens.background,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.channel.name),
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
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_errorMessage != null
                      ? _CommunityErrorState(
                          message: _errorMessage!,
                          onRetry: _reload,
                        )
                      : (_items.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: _CommunityEmptyState(
                                  emoji: '💬',
                                  title: 'Bu kanalda henuz mesaj yok',
                                  subtitle:
                                      'İlk mesajı göndererek topluluk akışını burada başlatabilirsin.',
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _reload,
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    24,
                                  ),
                                  itemCount: _items.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final item = _items[index];
                                    return _CommunityMessageBubble(
                                      message: item,
                                      mine:
                                          item.author.id ==
                                          widget.currentUserId,
                                      onReply: () => _openThread(item),
                                      onTap: () => _openThread(item),
                                    );
                                  },
                                ),
                              ))),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _CommunityUiTokens.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _composerController,
                          minLines: 1,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: 'Kanal mesajı yaz',
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _sending ? null : _sendRootMessage,
                        style: FilledButton.styleFrom(
                          backgroundColor: _CommunityUiTokens.text,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(_sending ? '...' : 'Gonder'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityThreadPage extends StatefulWidget {
  const _CommunityThreadPage({
    required this.api,
    required this.community,
    required this.channel,
    required this.rootMessage,
    required this.currentUserId,
  });

  final _CommunityApiClient api;
  final _CommunitySummary community;
  final _CommunityChannelSummary channel;
  final _CommunityMessageSummary rootMessage;
  final String currentUserId;

  @override
  State<_CommunityThreadPage> createState() => _CommunityThreadPageState();
}

class _CommunityThreadPageState extends State<_CommunityThreadPage> {
  final _composerController = TextEditingController();
  final List<_CommunityMessageSummary> _replies = <_CommunityMessageSummary>[];
  io.Socket? _socket;
  _CommunityMessageSummary? _root;
  bool _loading = true;
  bool _sending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _root = widget.rootMessage;
    _loadInitial();
    _connectRealtime();
  }

  @override
  void dispose() {
    _socket?.emit('community:thread:leave', {
      'communityId': widget.community.id,
      'channelId': widget.channel.id,
      'messageId': widget.rootMessage.id,
    });
    _socket?.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _connectRealtime() {
    final socket = io.io(widget.api.backendBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'forceNew': true,
      'autoConnect': false,
      'auth': {'token': widget.api.authToken},
    });

    socket.onConnect((_) {
      socket.emit('community:thread:join', {
        'communityId': widget.community.id,
        'channelId': widget.channel.id,
        'messageId': widget.rootMessage.id,
      });
    });

    socket.on('community:thread:message', (payload) {
      if (payload is! Map) return;
      final data = Map<String, dynamic>.from(payload);
      if ((data['rootMessageId'] ?? '').toString() != widget.rootMessage.id) {
        return;
      }
      final rawMessage = Map<String, dynamic>.from(
        data['message'] as Map? ?? const {},
      );
      final message = _CommunityMessageSummary.fromMap(rawMessage);
      if (!mounted) return;
      setState(() {
        final index = _replies.indexWhere((item) => item.id == message.id);
        if (index >= 0) {
          _replies[index] = message;
        } else {
          _replies.add(message);
          _replies.sort(
            (left, right) => left.createdAt.compareTo(right.createdAt),
          );
        }
        _root = _copyCommunityMessage(_root!, replyCount: _replies.length);
      });
    });

    socket.onDisconnect((reason) {
      _communityLog('community thread socket disconnected', {'reason': reason});
    });

    socket.connect();
    _socket = socket;
  }

  Future<void> _loadInitial() async {
    try {
      final thread = await widget.api.fetchThread(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        messageId: widget.rootMessage.id,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = null;
        _root = thread.root;
        _replies
          ..clear()
          ..addAll(thread.replies);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    await _loadInitial();
  }

  Future<void> _send() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final created = await widget.api.sendChannelMessage(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        text: text,
        replyToMessageId: widget.rootMessage.id,
      );
      _composerController.clear();
      if (!mounted) return;
      setState(() {
        final index = _replies.indexWhere((item) => item.id == created.id);
        if (index >= 0) {
          _replies[index] = created;
        } else {
          _replies.add(created);
          _replies.sort(
            (left, right) => left.createdAt.compareTo(right.createdAt),
          );
        }
        _root = _copyCommunityMessage(_root!, replyCount: _replies.length);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = _root;
    return Scaffold(
      backgroundColor: _CommunityUiTokens.background,
      appBar: AppBar(
        backgroundColor: _CommunityUiTokens.background,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yanıtlar'),
            Text(
              widget.channel.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_errorMessage != null || root == null
                ? _CommunityErrorState(
                    message: _errorMessage ?? 'Thread yüklenemedi.',
                    onRetry: _reload,
                  )
                : Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _reload,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              _CommunityThreadRootCard(
                                message: root,
                                mine: root.author.id == widget.currentUserId,
                                channelName: widget.channel.name,
                                replyCount: _replies.length,
                              ),
                              const SizedBox(height: 18),
                              _CommunityThreadRepliesHeader(
                                replyCount: _replies.length,
                              ),
                              const SizedBox(height: 12),
                              if (_replies.isEmpty)
                                const _CommunityThreadEmptyState()
                              else
                                ...List<Widget>.generate(_replies.length, (
                                  index,
                                ) {
                                  final item = _replies[index];
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: index == _replies.length - 1
                                          ? 0
                                          : 12,
                                    ),
                                    child: _CommunityThreadReplyTile(
                                      message: item,
                                      mine:
                                          item.author.id ==
                                          widget.currentUserId,
                                      isLast: index == _replies.length - 1,
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _CommunityUiTokens.border,
                              ),
                              boxShadow: _CommunityUiTokens.softShadow,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                10,
                                12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _composerController,
                                      minLines: 1,
                                      maxLines: 5,
                                      decoration: const InputDecoration(
                                        hintText: 'Thread yanıtı yaz',
                                        border: InputBorder.none,
                                        isCollapsed: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton(
                                    onPressed: _sending ? null : _send,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _CommunityUiTokens.text,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Text(_sending ? '...' : 'Gonder'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )),
    );
  }
}

class _CommunityThreadRootCard extends StatelessWidget {
  const _CommunityThreadRootCard({
    required this.message,
    required this.mine,
    required this.channelName,
    required this.replyCount,
  });

  final _CommunityMessageSummary message;
  final bool mine;
  final String channelName;
  final int replyCount;

  @override
  Widget build(BuildContext context) {
    final replyLabel = replyCount == 0
        ? 'Thread yeni acildi'
        : '$replyCount yanıt';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _CommunityUiTokens.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _CommunityUiTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.push_pin_outlined,
                  size: 15,
                  color: _CommunityUiTokens.textMuted,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Ana mesaj',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const Spacer(),
                Text(
                  '# $channelName',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _CommunityMessageBubble(
              message: message,
              mine: mine,
              dense: true,
              showReplyPreview: false,
              showCreatedAt: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.forum_outlined,
                  size: 15,
                  color: _CommunityUiTokens.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    replyLabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityThreadRepliesHeader extends StatelessWidget {
  const _CommunityThreadRepliesHeader({required this.replyCount});

  final int replyCount;

  @override
  Widget build(BuildContext context) {
    final trailing = replyCount == 0
        ? 'Ilk yanıt senin olabilir'
        : '$replyCount mesaj';
    return Row(
      children: [
        const Icon(
          Icons.subdirectory_arrow_right_rounded,
          size: 16,
          color: _CommunityUiTokens.textMuted,
        ),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Yanıtlar',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.text,
            ),
          ),
        ),
        Text(
          trailing,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: _CommunityUiTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class _CommunityThreadEmptyState extends StatelessWidget {
  const _CommunityThreadEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _CommunityUiTokens.surfaceSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'İlk yanıtı göndererek konuşmayı burada toparla.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityThreadReplyTile extends StatelessWidget {
  const _CommunityThreadReplyTile({
    required this.message,
    required this.mine,
    required this.isLast,
  });

  final _CommunityMessageSummary message;
  final bool mine;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _CommunityUiTokens.border),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 1.5,
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color: _CommunityUiTokens.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CommunityMessageBubble(
              message: message,
              mine: mine,
              dense: true,
              showReplyPreview: false,
              showCreatedAt: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityTopicDetailPage extends StatelessWidget {
  const _CommunityTopicDetailPage({required this.topic});

  final _CommunityTopicSummary topic;

  @override
  Widget build(BuildContext context) {
    final descriptor = switch (topic.type) {
      'event' => (emoji: '📅', label: 'Etkinlik'),
      'resource' => (emoji: '📚', label: 'Kaynak'),
      _ => (emoji: '❓', label: 'Soru'),
    };

    return Scaffold(
      backgroundColor: _CommunityUiTokens.background,
      appBar: AppBar(
        backgroundColor: _CommunityUiTokens.background,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Text(descriptor.label),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            _SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CommunityChip(
                        label: '${descriptor.emoji} ${descriptor.label}',
                      ),
                      if (topic.channel != null)
                        _CommunityChip(label: '#${topic.channel!.name}'),
                      if (topic.isPinned)
                        const _CommunityChip(label: '📌 Sabit'),
                      if (topic.isSolved)
                        const _CommunityChip(label: '✅ Cozuldu'),
                      if ((topic.eventStartsAt ?? '').trim().isNotEmpty)
                        _CommunityChip(
                          label:
                              '🗓️ ${_formatCommunityDate(topic.eventStartsAt!)}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    topic.title,
                    style: const TextStyle(
                      fontSize: 23,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: _CommunityUiTokens.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: _CommunityUiTokens.surfaceSoft,
                        child: Text(
                          topic.author.displayName.trim().isNotEmpty
                              ? topic.author.displayName.trim()[0]
                              : '👤',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _CommunityUiTokens.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topic.author.displayName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _CommunityUiTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatCommunityDate(topic.createdAt),
                              style: const TextStyle(
                                fontSize: 12,
                                color: _CommunityUiTokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _CommunityChip(label: '💬 ${topic.replyCount} cevap'),
                    ],
                  ),
                  if ((topic.body ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      topic.body!.trim(),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: _CommunityUiTokens.text,
                      ),
                    ),
                  ],
                  if (topic.tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: topic.tags
                          .map((tag) => _CommunityChip(label: '🏷️ $tag'))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CommunitySectionHeader(emoji: '🧵', title: 'Yanitlar'),
                  const SizedBox(height: 12),
                  if (topic.replies.isEmpty)
                    const _CommunityEmptyState(
                      emoji: '🫥',
                      title: 'Henüz yanıt yok',
                      subtitle:
                          'Bu icerik ilk cevap geldikce topluluk bilgisini zenginlestirecek.',
                    )
                  else
                    ...List<Widget>.generate(topic.replies.length, (index) {
                      final reply = topic.replies[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == topic.replies.length - 1 ? 0 : 10,
                        ),
                        child: _CommunityTopicReplyTile(reply: reply),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CommunityDetailTab { home, chat, questions, resources, members }

extension _CommunityDetailTabX on _CommunityDetailTab {
  String get label => switch (this) {
    _CommunityDetailTab.home => 'Anasayfa',
    _CommunityDetailTab.chat => 'Sohbet',
    _CommunityDetailTab.questions => 'Sorular',
    _CommunityDetailTab.resources => 'Kaynaklar',
    _CommunityDetailTab.members => 'Üyeler',
  };

  String get emoji => switch (this) {
    _CommunityDetailTab.home => '🏡',
    _CommunityDetailTab.chat => '💬',
    _CommunityDetailTab.questions => '❓',
    _CommunityDetailTab.resources => '📚',
    _CommunityDetailTab.members => '👥',
  };
}

class _CommunityDetailTabBar extends StatelessWidget {
  const _CommunityDetailTabBar({
    required this.selectedTab,
    required this.onSelected,
  });

  final _CommunityDetailTab selectedTab;
  final ValueChanged<_CommunityDetailTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _CommunityDetailTab.values.map((tab) {
          final selected = tab == selectedTab;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSelected(tab),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? _CommunityUiTokens.text
                      : _CommunityUiTokens.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _CommunityUiTokens.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tab.emoji, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 8),
                    Text(
                      tab.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : _CommunityUiTokens.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CommunityLockedTabCard extends StatelessWidget {
  const _CommunityLockedTabCard({required this.tab, this.onProfileTap});

  final _CommunityDetailTab tab;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tab.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 10),
          Text(
            '${tab.label} alanı üye olunca açılır',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Topluluğa katıldığında bu sekmede kanal akışı, sorular, kaynaklar ve üye dizini görünür olacak.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
          if (onProfileTap != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: onProfileTap,
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
              child: const Text(
                'Profili tamamlamak için Turna bölümüne dön',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
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
              'Bugün hangi toplulukta görünmek istiyorsun?',
              style: TextStyle(
                fontSize: 29,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.text,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Canlı sohbet, sorular, kaynaklar ve güvenli networking aynı akışta.',
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
                _CommunityMetricPill(label: '🤝 Güvenli bağlantı'),
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
    this.onProfileTap,
    this.compact = false,
  });

  final _CommunityProfileGate gate;
  final VoidCallback? onProfileTap;
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
                  'Community profiline son dokunuş',
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
                ? 'Mevcut profilin community katılımı için yeterli. Artık topluluklara katılıp mesaj istekleri gönderebilirsin.'
                : 'Topluluk katılımı için şu alanları tamamla: ${gate.missingItems.join(', ')}.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
          if (!gate.isComplete && onProfileTap != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onProfileTap,
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
                  compact ? 'Siz bölümüne dön' : 'Profili tamamlamak için dön',
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
  const _CommunityEventCard({required this.topic});

  final _CommunityTopicSummary topic;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if ((topic.eventStartsAt ?? '').trim().isNotEmpty)
        _formatCommunityDate(topic.eventStartsAt!),
      if (topic.channel != null) '#${topic.channel!.name}',
    ].join('  •  ');
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
          children: [
            const Text(
              '🎙️ Canlı oturum',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              topic.title.trim().isEmpty
                  ? 'Yaklaşan community etkinliği'
                  : topic.title.trim(),
              style: const TextStyle(
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.text,
              ),
            ),
            if (meta.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                meta,
                style: const TextStyle(
                  fontSize: 13,
                  color: _CommunityUiTokens.textMuted,
                ),
              ),
            ],
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

class _QuestionPreviewTile extends StatelessWidget {
  const _QuestionPreviewTile({
    required this.title,
    required this.subtitle,
    required this.badge,
    this.onTap,
  });

  factory _QuestionPreviewTile.fromTopic(
    _CommunityTopicSummary topic, {
    VoidCallback? onTap,
  }) {
    final badge = topic.isSolved
        ? 'Cozuldu'
        : (topic.replyCount > 0 ? '${topic.replyCount} cevap' : 'Yeni soru');
    final subtitle = (topic.body ?? '').trim().isNotEmpty
        ? topic.body!.trim()
        : topic.author.subtitle;
    return _QuestionPreviewTile(
      title: topic.title,
      subtitle: subtitle,
      badge: badge,
      onTap: onTap,
    );
  }

  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _CommunityUiTokens.surfaceSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: _CommunityUiTokens.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _CommunityChip(label: '❖ $badge'),
                  if (onTap != null) ...[
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourcePreviewTile extends StatelessWidget {
  const _ResourcePreviewTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.badge,
    this.onTap,
  });

  factory _ResourcePreviewTile.fromTopic(
    _CommunityTopicSummary topic, {
    VoidCallback? onTap,
  }) {
    final isEvent = topic.type == 'event';
    return _ResourcePreviewTile(
      emoji: isEvent ? '📅' : '📚',
      title: topic.title,
      subtitle: (topic.body ?? '').trim().isNotEmpty
          ? topic.body!.trim()
          : topic.author.subtitle,
      badge: isEvent
          ? (topic.eventStartsAt?.trim().isNotEmpty == true
                ? 'Etkinlik'
                : 'Canlı')
          : 'Kaynak',
      onTap: onTap,
    );
  }

  final String emoji;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _CommunityUiTokens.surfaceSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
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
                        height: 1.4,
                        color: _CommunityUiTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _CommunityChip(label: badge),
                  if (onTap != null) ...[
                    const SizedBox(height: 10),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityTopicReplyTile extends StatelessWidget {
  const _CommunityTopicReplyTile({required this.reply});

  final _CommunityTopicReplySummary reply;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _CommunityUiTokens.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    reply.author.displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _CommunityUiTokens.text,
                    ),
                  ),
                ),
                if (reply.isAccepted)
                  const _CommunityChip(label: '✅ En iyi cevap'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatCommunityDate(reply.createdAt),
              style: const TextStyle(
                fontSize: 12,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              reply.body,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _CommunityUiTokens.text,
              ),
            ),
          ],
        ),
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
  const _ChannelTile({required this.channel, this.onTap});

  final _CommunityChannelSummary channel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final descriptor = _communityChannelDescriptor(channel.type);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: DecoratedBox(
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
                      channel.description?.trim().isNotEmpty == true
                          ? channel.description!.trim()
                          : descriptor.label,
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
              if (!channel.isDefault && onTap != null) ...[
                const SizedBox(width: 10),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: _CommunityUiTokens.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityMessageBubble extends StatelessWidget {
  const _CommunityMessageBubble({
    required this.message,
    required this.mine,
    this.onReply,
    this.onTap,
    this.dense = false,
    this.showReplyPreview = true,
    this.showCreatedAt = false,
  });

  final _CommunityMessageSummary message;
  final bool mine;
  final VoidCallback? onReply;
  final VoidCallback? onTap;
  final bool dense;
  final bool showReplyPreview;
  final bool showCreatedAt;

  @override
  Widget build(BuildContext context) {
    final alignment = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = mine ? _CommunityUiTokens.text : Colors.white;
    final textColor = mine ? Colors.white : _CommunityUiTokens.text;
    final bubblePadding = dense ? 11.0 : 14.0;
    final authorSpacing = dense ? 3.0 : 6.0;
    final bodyFontSize = dense ? 13.5 : 14.0;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        if (showCreatedAt)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  message.author.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _formatCommunityDate(message.createdAt),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _CommunityUiTokens.textMuted,
                ),
              ),
            ],
          )
        else
          Text(
            message.author.displayName,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
        SizedBox(height: authorSpacing),
        GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(maxWidth: dense ? 340 : 320),
            padding: EdgeInsets.all(bubblePadding),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(dense ? 18 : 20),
              border: Border.all(color: _CommunityUiTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showReplyPreview &&
                    (message.replyPreview ?? '').trim().isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(bottom: dense ? 8 : 10),
                    padding: EdgeInsets.all(dense ? 8 : 10),
                    decoration: BoxDecoration(
                      color: mine
                          ? Colors.white.withValues(alpha: 0.12)
                          : _CommunityUiTokens.surfaceSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      [
                        if ((message.replyAuthorName ?? '').trim().isNotEmpty)
                          message.replyAuthorName!.trim(),
                        if ((message.replyPreview ?? '').trim().isNotEmpty)
                          message.replyPreview!.trim(),
                      ].join('\n'),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: mine
                            ? Colors.white70
                            : _CommunityUiTokens.textMuted,
                      ),
                    ),
                  ),
                Text(
                  message.text ?? '',
                  style: TextStyle(
                    fontSize: bodyFontSize,
                    height: 1.42,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onReply != null || (message.replyCount > 0 && onTap != null)) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReply != null)
                TextButton.icon(
                  onPressed: onReply,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    foregroundColor: _CommunityUiTokens.textMuted,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.reply_rounded, size: 16),
                  label: const Text(
                    'Yanıtla',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              if (message.replyCount > 0 && onTap != null) ...[
                if (onReply != null) const SizedBox(width: 6),
                TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    foregroundColor: _CommunityUiTokens.textMuted,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '${message.replyCount} yanıt',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
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
              'Topluluk, konu veya kişi ara',
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
                'Community verisi yüklenemedi',
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
      (emoji: '🏡', label: 'Anasayfa'),
      (emoji: '🧭', label: 'Keşfet'),
      (emoji: '💬', label: 'Turna'),
      (emoji: '🔔', label: 'Bildirimler'),
      (emoji: '🌿', label: 'Topluluklarım'),
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
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: _CommunityUiTokens.text,
                              ),
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
  VoidCallback? onProfileTap,
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
                  'Topluluklara katılmak ve mesaj isteği gönderebilmek için şu alanlar eksik: ${gate.missingItems.join(', ')}.',
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
                          onProfileTap?.call();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _CommunityUiTokens.text,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('Siz bölümüne dön'),
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
      return (emoji: '📣', label: 'Duyuru kanalı');
    case 'question':
      return (emoji: '❓', label: 'Soru-cevap alanı');
    case 'resource':
      return (emoji: '📚', label: 'Kaynak kütüphanesi');
    case 'event':
      return (emoji: '📅', label: 'Etkinlik alanı');
    default:
      return (emoji: '💬', label: 'Canlı sohbet odası');
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

_CommunityMessageSummary _copyCommunityMessage(
  _CommunityMessageSummary message, {
  int? replyCount,
}) {
  return _CommunityMessageSummary(
    id: message.id,
    author: message.author,
    createdAt: message.createdAt,
    text: message.text,
    replyCount: replyCount ?? message.replyCount,
    replyToMessageId: message.replyToMessageId,
    replyAuthorName: message.replyAuthorName,
    replyPreview: message.replyPreview,
  );
}

String _emojiForNotificationType(String type) {
  switch (type.toLowerCase()) {
    case 'mention':
      return '👋';
    case 'announcement':
      return '📣';
    case 'dm_request':
      return '🤝';
    default:
      return '💬';
  }
}

String _mapCommunitySocketError(String code) {
  switch (code) {
    case 'community_membership_required':
      return 'Bu kanala girmek için topluluk üyesi olman gerekiyor.';
    case 'community_channel_not_found':
      return 'Kanal bulunamadı.';
    case 'community_not_found':
      return 'Topluluk bulunamadı.';
    default:
      return code;
  }
}

String _formatCommunityDate(String iso) {
  final parsed = DateTime.tryParse(iso)?.toLocal();
  if (parsed == null) return iso;
  final day = parsed.day.toString().padLeft(2, '0');
  final month = parsed.month.toString().padLeft(2, '0');
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '$day.$month $hour:$minute';
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
