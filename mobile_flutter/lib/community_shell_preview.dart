import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';

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

  Future<List<_CommunitySummary>> fetchExplore({
    String? query,
    String? visibility,
  }) async {
    final params = <String, String>{};
    if ((query ?? '').trim().isNotEmpty) {
      params['q'] = query!.trim();
    }
    if ((visibility ?? '').trim().isNotEmpty && visibility != 'all') {
      params['visibility'] = visibility!.trim();
    }
    final res = await http.get(
      _uri('/api/communities/explore', params.isEmpty ? null : params),
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
    String? text,
    String? replyToMessageId,
    List<_CommunityOutgoingAttachmentDraft> attachments =
        const <_CommunityOutgoingAttachmentDraft>[],
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/channels/$channelId/messages'),
      headers: _headers,
      body: jsonEncode({
        if ((text ?? '').trim().isNotEmpty) 'text': text!.trim(),
        if ((replyToMessageId ?? '').trim().isNotEmpty)
          'replyToMessageId': replyToMessageId,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((item) => item.toMap()).toList(),
      }),
    );
    return _decodeChannelMessage(res, fallbackError: 'Mesaj gönderilemedi.');
  }

  Future<_CommunityAttachmentUploadTicket> createAttachmentUpload({
    required String communityId,
    required String channelId,
    required String kind,
    required String contentType,
    String? fileName,
  }) async {
    final res = await http.post(
      _uri(
        '/api/communities/$communityId/channels/$channelId/attachments/upload-url',
      ),
      headers: _headers,
      body: jsonEncode({
        'kind': kind,
        'contentType': contentType,
        if ((fileName ?? '').trim().isNotEmpty) 'fileName': fileName!.trim(),
      }),
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Ek yükleme bağlantısı hazırlanamadı.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    return _CommunityAttachmentUploadTicket.fromMap(data);
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

  Future<_CommunityDmRequestFeed> fetchDmRequests({
    required String communityId,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/dm-requests'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'DM istekleri yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    return _CommunityDmRequestFeed.fromMap(data);
  }

  Future<void> createDmRequest({
    required String communityId,
    required String userId,
    String? note,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/dm-requests'),
      headers: _headers,
      body: jsonEncode({
        'userId': userId,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      }),
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'DM isteği gönderilemedi.'),
      );
    }
  }

  Future<String?> acceptDmRequest({
    required String communityId,
    required String requestId,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/dm-requests/$requestId/accept'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'DM isteği kabul edilemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    return _CommunitySummary._nullableString(data['chatId']);
  }

  Future<void> rejectDmRequest({
    required String communityId,
    required String requestId,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/dm-requests/$requestId/reject'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'DM isteği reddedilemedi.'),
      );
    }
  }

  Future<_CommunityMessageSummary> toggleMessageReaction({
    required String communityId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {
    final res = await http.post(
      _uri(
        '/api/communities/$communityId/channels/$channelId/messages/$messageId/reactions',
      ),
      headers: _headers,
      body: jsonEncode({'emoji': emoji}),
    );
    return _decodeChannelMessage(
      res,
      fallbackError: 'Reaction güncellenemedi.',
    );
  }

  Future<_CommunityMessageSummary> setMessagePinned({
    required String communityId,
    required String channelId,
    required String messageId,
    required bool pinned,
  }) async {
    final res = await http.post(
      _uri(
        '/api/communities/$communityId/channels/$channelId/messages/$messageId/pin',
      ),
      headers: _headers,
      body: jsonEncode({'pinned': pinned}),
    );
    return _decodeChannelMessage(res, fallbackError: 'Mesaj sabitlenemedi.');
  }

  Future<void> reportMessage({
    required String communityId,
    required String channelId,
    required String messageId,
    required String reasonCode,
    String? details,
  }) async {
    final res = await http.post(
      _uri(
        '/api/communities/$communityId/channels/$channelId/messages/$messageId/report',
      ),
      headers: _headers,
      body: jsonEncode({
        'reasonCode': reasonCode,
        if ((details ?? '').trim().isNotEmpty) 'details': details!.trim(),
      }),
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(_decodeError(res, 'Mesaj raporlanamadı.'));
    }
  }

  Future<void> muteMember({
    required String communityId,
    required String userId,
    required int minutes,
    String? reason,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/members/$userId/mute'),
      headers: _headers,
      body: jsonEncode({
        'minutes': minutes,
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
      }),
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Sessize alma işlemi başarısız oldu.'),
      );
    }
  }

  Future<void> banMember({
    required String communityId,
    required String userId,
    String? reason,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/members/$userId/ban'),
      headers: _headers,
      body: jsonEncode({
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
      }),
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Ban işlemi başarısız oldu.'),
      );
    }
  }

  Future<List<_CommunityPinnedMessageSummary>> fetchPinnedMessages({
    required String communityId,
    int limit = 12,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/pinned-messages', {
        'limit': '$limit',
      }),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Sabit mesajlar yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => _CommunityPinnedMessageSummary.fromMap(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<List<_CommunityReportSummary>> fetchReports({
    required String communityId,
    String status = 'active',
    int limit = 20,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/reports', {
        'status': status,
        'limit': '$limit',
      }),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Community raporlari yuklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              _CommunityReportSummary.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> setReportStatus({
    required String communityId,
    required String reportId,
    required String status,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/reports/$reportId/status'),
      headers: _headers,
      body: jsonEncode({'status': status}),
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Rapor durumu güncellenemedi.'),
      );
    }
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
    String? query,
    bool? solved,
  }) async {
    final params = <String, String>{'type': type};
    if ((query ?? '').trim().isNotEmpty) {
      params['q'] = query!.trim();
    }
    if (solved != null) {
      params['solved'] = solved ? 'true' : 'false';
    }
    final res = await http.get(
      _uri('/api/communities/$communityId/topics', params),
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
    String? query,
    String? role,
  }) async {
    final params = <String, String>{};
    if ((query ?? '').trim().isNotEmpty) {
      params['q'] = query!.trim();
    }
    if ((role ?? '').trim().isNotEmpty && role != 'all') {
      params['role'] = role!.trim();
    }
    final res = await http.get(
      _uri(
        '/api/communities/$communityId/members',
        params.isEmpty ? null : params,
      ),
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
      body: jsonEncode(const <String, dynamic>{}),
    );
    return _decodeCommunityItem(res, fallbackError: 'Topluluğa katılınamadı.');
  }

  Future<List<_CommunityUserSummary>> fetchInviteDirectory() async {
    final res = await http.get(
      _uri('/api/chats/directory/list'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Davet dizini yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              _CommunityUserSummary.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> createInvite({
    required String communityId,
    required String userId,
    String? note,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/invites'),
      headers: _headers,
      body: jsonEncode({
        'userId': userId,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      }),
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(_decodeError(res, 'Davet gönderilemedi.'));
    }
  }

  Future<List<_CommunityInviteSummary>> fetchInvites({
    required String communityId,
    String? status,
    int limit = 20,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if ((status ?? '').trim().isNotEmpty) {
      params['status'] = status!.trim();
    }
    final res = await http.get(
      _uri('/api/communities/$communityId/invites', params),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(_decodeError(res, 'Davetler yüklenemedi.'));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              _CommunityInviteSummary.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<List<_CommunityBanSummary>> fetchBans({
    required String communityId,
    int limit = 30,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/bans', {'limit': '$limit'}),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Ban listesi yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              _CommunityBanSummary.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> unbanMember({
    required String communityId,
    required String userId,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/members/$userId/unban'),
      headers: _headers,
      body: jsonEncode(const <String, dynamic>{}),
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Ban kaldırma işlemi başarısız oldu.'),
      );
    }
  }

  Future<List<_CommunityJoinRequestSummary>> fetchJoinRequests({
    required String communityId,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/join-requests'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Katılım istekleri yüklenemedi.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => _CommunityJoinRequestSummary.fromMap(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<void> approveJoinRequest({
    required String communityId,
    required String requestId,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/join-requests/$requestId/approve'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Katılım isteği onaylanamadı.'),
      );
    }
  }

  Future<void> rejectJoinRequest({
    required String communityId,
    required String requestId,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/join-requests/$requestId/reject'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Katılım isteği reddedilemedi.'),
      );
    }
  }

  Future<_CommunitySearchSummary> searchCommunity({
    required String communityId,
    required String query,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/search', {'q': query}),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw _CommunityApiException(
        _decodeError(res, 'Topluluk içi arama başarısız oldu.'),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    return _CommunitySearchSummary.fromMap(data);
  }

  Future<_CommunityTopicSummary> fetchTopicDetail({
    required String communityId,
    required String topicId,
  }) async {
    final res = await http.get(
      _uri('/api/communities/$communityId/topics/$topicId'),
      headers: _headers,
    );
    return _decodeTopicItem(res, fallbackError: 'Konu detayı yüklenemedi.');
  }

  Future<_CommunityTopicSummary> createTopic({
    required String communityId,
    required String type,
    required String title,
    String? body,
    String? channelId,
    List<String> tags = const <String>[],
    String? eventStartsAt,
    bool isPinned = false,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/topics'),
      headers: _headers,
      body: jsonEncode({
        'type': type,
        'title': title,
        if ((body ?? '').trim().isNotEmpty) 'body': body!.trim(),
        if ((channelId ?? '').trim().isNotEmpty) 'channelId': channelId!.trim(),
        if (tags.isNotEmpty) 'tags': tags,
        if ((eventStartsAt ?? '').trim().isNotEmpty)
          'eventStartsAt': eventStartsAt!.trim(),
        if (isPinned) 'isPinned': true,
      }),
    );
    return _decodeTopicItem(res, fallbackError: 'Konu oluşturulamadı.');
  }

  Future<_CommunityTopicSummary> replyToTopic({
    required String communityId,
    required String topicId,
    required String body,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/topics/$topicId/replies'),
      headers: _headers,
      body: jsonEncode({'body': body}),
    );
    return _decodeTopicItem(res, fallbackError: 'Cevap gönderilemedi.');
  }

  Future<_CommunityTopicSummary> acceptTopicReply({
    required String communityId,
    required String topicId,
    required String replyId,
  }) async {
    final res = await http.post(
      _uri(
        '/api/communities/$communityId/topics/$topicId/replies/$replyId/accept',
      ),
      headers: _headers,
    );
    return _decodeTopicItem(res, fallbackError: 'Cevap kabul edilemedi.');
  }

  Future<_CommunityTopicSummary> setTopicSolved({
    required String communityId,
    required String topicId,
    required bool solved,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/topics/$topicId/solve'),
      headers: _headers,
      body: jsonEncode({'solved': solved}),
    );
    return _decodeTopicItem(
      res,
      fallbackError: 'Çözüldü durumu güncellenemedi.',
    );
  }

  Future<_CommunityTopicSummary> pinTopic({
    required String communityId,
    required String topicId,
    required bool pinned,
  }) async {
    final res = await http.post(
      _uri('/api/communities/$communityId/topics/$topicId/pin'),
      headers: _headers,
      body: jsonEncode({'pinned': pinned}),
    );
    return _decodeTopicItem(res, fallbackError: 'Sabit durumu güncellenemedi.');
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

  _CommunityTopicSummary _decodeTopicItem(
    http.Response res, {
    required String fallbackError,
  }) {
    if (res.statusCode >= 400) {
      throw _CommunityApiException(_decodeError(res, fallbackError));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(body['data'] as Map);
    return _CommunityTopicSummary.fromMap(data);
  }

  String _decodeError(http.Response res, String fallbackError) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final message = body['error']?.toString().trim();
      if (message != null && message.isNotEmpty) {
        switch (message) {
          case 'community_join_request_required':
            return 'Bu topluluk icin onay gerekli.';
          case 'community_invite_required':
            return 'Bu topluluk davet ile aciliyor.';
          case 'community_banned':
            return 'Bu topluluktan banlandin.';
          case 'community_storage_not_configured':
            return 'Community medya alani henuz hazir degil.';
          case 'community_member_muted':
            return 'Şu anda paylaşım yapamazsın, susturulmuşsun.';
          case 'community_owner_cannot_leave':
            return 'Kurucu rolu ile topluluktan ayrilamazsin.';
          case 'community_event_start_required':
            return 'Etkinlik olusturmak icin tarih gir.';
          case 'community_topic_create_forbidden':
            return 'Bu icerik tipini olusturma yetkin yok.';
          case 'community_dm_request_already_pending':
            return 'Bu üyeye zaten bekleyen bir DM isteğin var.';
          case 'community_dm_request_cooldown_active':
            return 'Bu üyeye kısa süre içinde tekrar DM isteği gönderemezsin.';
          case 'community_dm_request_rate_limited':
            return 'Çok fazla DM isteği gönderdin, biraz sonra tekrar dene.';
          case 'community_dm_request_target_not_found':
            return 'Bu kullanıcı için DM isteği açılamadı.';
          case 'community_member_moderation_forbidden':
            return 'Bu üyede bu işlemi yapma yetkin yok.';
          case 'community_invite_forbidden':
            return 'Bu toplulukta davet gönderme yetkin yok.';
          case 'community_invite_target_not_found':
            return 'Davet gönderilecek kullanıcı bulunamadı.';
          case 'community_invite_target_already_member':
            return 'Bu kullanıcı zaten topluluk üyesi.';
          case 'community_invites_failed':
            return 'Community davetleri su anda yuklenemedi.';
          case 'community_bans_failed':
            return 'Aktif ban listesi yuklenemedi.';
          case 'community_ban_not_found':
            return 'Aktif ban kaydi bulunamadi.';
          case 'community_member_unban_failed':
            return 'Ban kaldirma islemi basarisiz oldu.';
          case 'community_report_review_forbidden':
            return 'Community raporlarini inceleme yetkin yok.';
          case 'community_report_not_found':
            return 'Community raporu bulunamadi.';
          case 'community_report_self_forbidden':
            return 'Kendi mesajını raporlayamazsın.';
          case 'invalid_attachment_key':
            return 'Yuklenen dosya dogrulanamadi.';
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
    this.openQuestion,
    this.featuredResource,
  });

  final List<_CommunitySummary> explore;
  final List<_CommunitySummary> mine;
  final _CommunityTopicSummary? upcomingEvent;
  final _CommunityTopicSummary? openQuestion;
  final _CommunityTopicSummary? featuredResource;
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
      openQuestion: (map['openQuestion'] as Map?) == null
          ? null
          : _CommunityTopicSummary.fromMap(
              Map<String, dynamic>.from(map['openQuestion'] as Map),
            ),
      featuredResource: (map['featuredResource'] as Map?) == null
          ? null
          : _CommunityTopicSummary.fromMap(
              Map<String, dynamic>.from(map['featuredResource'] as Map),
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

class _CommunityPermissions {
  const _CommunityPermissions({
    this.canManageCommunity = false,
    this.canInviteMembers = false,
    this.canCreateQuestion = false,
    this.canCreateResource = false,
    this.canCreateEvent = false,
    this.canPinTopic = false,
  });

  final bool canManageCommunity;
  final bool canInviteMembers;
  final bool canCreateQuestion;
  final bool canCreateResource;
  final bool canCreateEvent;
  final bool canPinTopic;

  factory _CommunityPermissions.fromMap(Map<String, dynamic> map) {
    return _CommunityPermissions(
      canManageCommunity: map['canManageCommunity'] == true,
      canInviteMembers: map['canInviteMembers'] == true,
      canCreateQuestion: map['canCreateQuestion'] == true,
      canCreateResource: map['canCreateResource'] == true,
      canCreateEvent: map['canCreateEvent'] == true,
      canPinTopic: map['canPinTopic'] == true,
    );
  }
}

class _CommunityTopicPermissions {
  const _CommunityTopicPermissions({
    this.canReply = false,
    this.canAcceptAnswer = false,
    this.canChangeSolvedState = false,
    this.canPin = false,
  });

  final bool canReply;
  final bool canAcceptAnswer;
  final bool canChangeSolvedState;
  final bool canPin;

  factory _CommunityTopicPermissions.fromMap(Map<String, dynamic> map) {
    return _CommunityTopicPermissions(
      canReply: map['canReply'] == true,
      canAcceptAnswer: map['canAcceptAnswer'] == true,
      canChangeSolvedState: map['canChangeSolvedState'] == true,
      canPin: map['canPin'] == true,
    );
  }
}

class _CommunityJoinRequestSummary {
  const _CommunityJoinRequestSummary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.requester,
    this.note,
  });

  final String id;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String? note;
  final _CommunityUserSummary requester;

  factory _CommunityJoinRequestSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityJoinRequestSummary(
      id: (map['id'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      createdAt: (map['createdAt'] ?? '').toString(),
      updatedAt: (map['updatedAt'] ?? '').toString(),
      note: _CommunitySummary._nullableString(map['note']),
      requester: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['requester'] as Map? ?? const {}),
      ),
    );
  }
}

class _CommunitySearchSummary {
  const _CommunitySearchSummary({
    required this.channels,
    required this.topics,
    required this.members,
  });

  final List<_CommunityChannelSummary> channels;
  final List<_CommunityTopicSummary> topics;
  final List<_CommunityMemberSummary> members;

  factory _CommunitySearchSummary.fromMap(Map<String, dynamic> map) {
    return _CommunitySearchSummary(
      channels: (map['channels'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityChannelSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      topics: (map['topics'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                _CommunityTopicSummary.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      members: (map['members'] as List<dynamic>? ?? const [])
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
    this.attachments = const <_CommunityMessageAttachmentSummary>[],
    this.isPinned = false,
    this.reactions = const <_CommunityReactionSummary>[],
    this.replyCount = 0,
    this.replyToMessageId,
    this.replyAuthorName,
    this.replyPreview,
  });

  final String id;
  final _CommunityUserSummary author;
  final String createdAt;
  final String? text;
  final List<_CommunityMessageAttachmentSummary> attachments;
  final bool isPinned;
  final List<_CommunityReactionSummary> reactions;
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
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityMessageAttachmentSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      isPinned: map['isPinned'] == true,
      reactions: (map['reactions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityReactionSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
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

class _CommunityReactionSummary {
  const _CommunityReactionSummary({
    required this.emoji,
    required this.count,
    required this.reacted,
  });

  final String emoji;
  final int count;
  final bool reacted;

  factory _CommunityReactionSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityReactionSummary(
      emoji: (map['emoji'] ?? '').toString(),
      count: (map['count'] as num?)?.toInt() ?? 0,
      reacted: map['reacted'] == true,
    );
  }
}

class _CommunityMessageAttachmentSummary {
  const _CommunityMessageAttachmentSummary({
    required this.objectKey,
    required this.kind,
    required this.contentType,
    this.fileName,
    this.sizeBytes,
    this.width,
    this.height,
    this.durationSeconds,
    this.url,
  });

  final String objectKey;
  final String kind;
  final String contentType;
  final String? fileName;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final String? url;

  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';

  factory _CommunityMessageAttachmentSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityMessageAttachmentSummary(
      objectKey: (map['objectKey'] ?? '').toString(),
      kind: (map['kind'] ?? 'file').toString(),
      contentType: (map['contentType'] ?? 'application/octet-stream')
          .toString(),
      fileName: _CommunitySummary._nullableString(map['fileName']),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      url: _CommunitySummary._nullableString(map['url']),
    );
  }
}

class _CommunityAttachmentUploadTicket {
  const _CommunityAttachmentUploadTicket({
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
  });

  final String objectKey;
  final String uploadUrl;
  final Map<String, String> headers;

  factory _CommunityAttachmentUploadTicket.fromMap(Map<String, dynamic> map) {
    final rawHeaders = map['headers'] as Map<String, dynamic>? ?? const {};
    return _CommunityAttachmentUploadTicket(
      objectKey: (map['objectKey'] ?? '').toString(),
      uploadUrl: (map['uploadUrl'] ?? '').toString(),
      headers: rawHeaders.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }
}

class _CommunityOutgoingAttachmentDraft {
  const _CommunityOutgoingAttachmentDraft({
    required this.objectKey,
    required this.kind,
    required this.contentType,
    required this.sizeBytes,
    this.fileName,
  });

  final String objectKey;
  final String kind;
  final String contentType;
  final int sizeBytes;
  final String? fileName;

  Map<String, dynamic> toMap() {
    return {
      'objectKey': objectKey,
      'kind': kind,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'fileName': fileName,
    };
  }
}

class _CommunityAttachmentPayload {
  const _CommunityAttachmentPayload({
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });

  final String kind;
  final String fileName;
  final String contentType;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;
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
    this.permissions = const _CommunityTopicPermissions(),
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
  final _CommunityTopicPermissions permissions;

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
      permissions: _CommunityTopicPermissions.fromMap(
        Map<String, dynamic>.from(map['permissions'] as Map? ?? const {}),
      ),
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
    this.mutedUntil,
    this.muteReason,
  });

  final String? role;
  final String joinedAt;
  final _CommunityUserSummary user;
  final String? mutedUntil;
  final String? muteReason;

  bool get isMuted {
    final parsed = DateTime.tryParse(mutedUntil ?? '')?.toLocal();
    return parsed != null && parsed.isAfter(DateTime.now());
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

  factory _CommunityMemberSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityMemberSummary(
      role: _CommunitySummary._nullableString(map['role']),
      joinedAt: (map['joinedAt'] ?? '').toString(),
      mutedUntil: _CommunitySummary._nullableString(map['mutedUntil']),
      muteReason: _CommunitySummary._nullableString(map['muteReason']),
      user: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['user'] as Map? ?? const {}),
      ),
    );
  }
}

class _CommunityDmRequestSummary {
  const _CommunityDmRequestSummary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.requester,
    required this.target,
    this.note,
  });

  final String id;
  final String status;
  final String createdAt;
  final String? note;
  final _CommunityUserSummary requester;
  final _CommunityUserSummary target;

  factory _CommunityDmRequestSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityDmRequestSummary(
      id: (map['id'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      createdAt: (map['createdAt'] ?? '').toString(),
      note: _CommunitySummary._nullableString(map['note']),
      requester: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['requester'] as Map? ?? const {}),
      ),
      target: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['target'] as Map? ?? const {}),
      ),
    );
  }
}

class _CommunityDmRequestFeed {
  const _CommunityDmRequestFeed({required this.incoming, required this.sent});

  final List<_CommunityDmRequestSummary> incoming;
  final List<_CommunityDmRequestSummary> sent;

  factory _CommunityDmRequestFeed.fromMap(Map<String, dynamic> map) {
    return _CommunityDmRequestFeed(
      incoming: (map['incoming'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityDmRequestSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      sent: (map['sent'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _CommunityDmRequestSummary.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class _CommunityPinnedMessageSummary {
  const _CommunityPinnedMessageSummary({
    required this.channel,
    required this.message,
  });

  final _CommunityChannelSummary channel;
  final _CommunityMessageSummary message;

  factory _CommunityPinnedMessageSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityPinnedMessageSummary(
      channel: _CommunityChannelSummary.fromMap(
        Map<String, dynamic>.from(map['channel'] as Map? ?? const {}),
      ),
      message: _CommunityMessageSummary.fromMap(
        Map<String, dynamic>.from(map['message'] as Map? ?? const {}),
      ),
    );
  }
}

class _CommunityReportSummary {
  const _CommunityReportSummary({
    required this.id,
    required this.reasonCode,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.reporter,
    this.details,
    this.reportedUser,
    this.channel,
    this.message,
  });

  final String id;
  final String reasonCode;
  final String? details;
  final String status;
  final String createdAt;
  final String updatedAt;
  final _CommunityUserSummary reporter;
  final _CommunityUserSummary? reportedUser;
  final _CommunityChannelSummary? channel;
  final _CommunityMessageSummary? message;

  factory _CommunityReportSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityReportSummary(
      id: (map['id'] ?? '').toString(),
      reasonCode: (map['reasonCode'] ?? '').toString(),
      details: _CommunitySummary._nullableString(map['details']),
      status: (map['status'] ?? 'open').toString(),
      createdAt: (map['createdAt'] ?? '').toString(),
      updatedAt: (map['updatedAt'] ?? '').toString(),
      reporter: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['reporter'] as Map? ?? const {}),
      ),
      reportedUser: (map['reportedUser'] as Map?) == null
          ? null
          : _CommunityUserSummary.fromMap(
              Map<String, dynamic>.from(map['reportedUser'] as Map),
            ),
      channel: (map['channel'] as Map?) == null
          ? null
          : _CommunityChannelSummary.fromMap(
              Map<String, dynamic>.from(map['channel'] as Map),
            ),
      message: (map['message'] as Map?) == null
          ? null
          : _CommunityMessageSummary.fromMap(
              Map<String, dynamic>.from(map['message'] as Map),
            ),
    );
  }
}

class _CommunityInviteSummary {
  const _CommunityInviteSummary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.invitedUser,
    required this.createdBy,
    this.note,
    this.respondedAt,
  });

  final String id;
  final String status;
  final String createdAt;
  final String? note;
  final String? respondedAt;
  final _CommunityUserSummary invitedUser;
  final _CommunityUserSummary createdBy;

  factory _CommunityInviteSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityInviteSummary(
      id: (map['id'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      createdAt: (map['createdAt'] ?? '').toString(),
      note: _CommunitySummary._nullableString(map['note']),
      respondedAt: _CommunitySummary._nullableString(map['respondedAt']),
      invitedUser: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['invitedUser'] as Map? ?? const {}),
      ),
      createdBy: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['createdBy'] as Map? ?? const {}),
      ),
    );
  }
}

class _CommunityBanSummary {
  const _CommunityBanSummary({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.user,
    this.reason,
    this.bannedByUserId,
  });

  final String id;
  final String createdAt;
  final String updatedAt;
  final String? reason;
  final String? bannedByUserId;
  final _CommunityUserSummary user;

  factory _CommunityBanSummary.fromMap(Map<String, dynamic> map) {
    return _CommunityBanSummary(
      id: (map['id'] ?? '').toString(),
      createdAt: (map['createdAt'] ?? '').toString(),
      updatedAt: (map['updatedAt'] ?? '').toString(),
      reason: _CommunitySummary._nullableString(map['reason']),
      bannedByUserId: _CommunitySummary._nullableString(map['bannedByUserId']),
      user: _CommunityUserSummary.fromMap(
        Map<String, dynamic>.from(map['user'] as Map? ?? const {}),
      ),
    );
  }
}

class _CommunityMembersTabData {
  const _CommunityMembersTabData({
    required this.members,
    required this.dmRequests,
    this.invites = const <_CommunityInviteSummary>[],
    this.bans = const <_CommunityBanSummary>[],
  });

  final List<_CommunityMemberSummary> members;
  final _CommunityDmRequestFeed dmRequests;
  final List<_CommunityInviteSummary> invites;
  final List<_CommunityBanSummary> bans;
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
    this.hasPendingJoinRequest = false,
    this.hasInvite = false,
    this.joinState = 'open',
    this.permissions = const _CommunityPermissions(),
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
  final bool hasPendingJoinRequest;
  final bool hasInvite;
  final String joinState;
  final _CommunityPermissions permissions;

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
      hasPendingJoinRequest: map['hasPendingJoinRequest'] == true,
      hasInvite: map['hasInvite'] == true,
      joinState: (map['joinState'] ?? 'open').toString(),
      permissions: _CommunityPermissions.fromMap(
        Map<String, dynamic>.from(map['permissions'] as Map? ?? const {}),
      ),
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
                const _CommunitySectionHeader(emoji: '❓', title: 'Açık soru'),
                const SizedBox(height: 12),
                if (data.openQuestion == null)
                  const _CommunityEmptyState(
                    emoji: '🧠',
                    title: 'Açık soru yok',
                    subtitle:
                        'Üyeler yeni soru açtıkça burada görünen tartışmalar olacak.',
                  )
                else
                  _QuestionPreviewTile.fromTopic(data.openQuestion!),
                const SizedBox(height: _CommunityUiTokens.sectionGap),
                const _CommunitySectionHeader(
                  emoji: '📚',
                  title: 'Öne çıkan kaynak',
                ),
                const SizedBox(height: 12),
                if (data.featuredResource == null)
                  const _CommunityEmptyState(
                    emoji: '🪶',
                    title: 'Kaynak görünmüyor',
                    subtitle:
                        'Topluluklarında sabitlenen veya yeni eklenen kaynaklar burada çıkacak.',
                  )
                else
                  _ResourcePreviewTile.fromTopic(data.featuredResource!),
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
  final _queryController = TextEditingController();
  String _visibility = 'all';

  @override
  void initState() {
    super.initState();
    _future = _loadExplore();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<List<_CommunitySummary>> _loadExplore() {
    return widget.api.fetchExplore(
      query: _queryController.text,
      visibility: _visibility,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadExplore();
    });
    await _future;
  }

  String _joinLabel(_CommunitySummary community, bool busy) {
    if (community.isMember) return 'Katıldın';
    if (busy) return 'Bekle...';
    switch (community.joinState) {
      case 'pending':
        return 'İstek gönderildi';
      case 'invited':
        return 'Daveti kabul et';
      case 'approval':
        return 'İstek gönder';
      case 'invite_only':
        return 'Davet gerekli';
      default:
        return 'Katıl';
    }
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
      final joined = await widget.api.join(community.id);
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            joined.joinState == 'pending'
                ? '${community.name} için istek gönderildi.'
                : '${community.name} topluluğuna katıldın.',
          ),
        ),
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
                _CommunitySearchField(
                  controller: _queryController,
                  onChanged: (_) => _reload(),
                  hintText: 'Topluluk ara',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _CommunityFilterChip(
                      label: 'Tümü',
                      selected: _visibility == 'all',
                      onTap: () {
                        setState(() => _visibility = 'all');
                        _reload();
                      },
                    ),
                    _CommunityFilterChip(
                      label: 'Açık',
                      selected: _visibility == 'public',
                      onTap: () {
                        setState(() => _visibility = 'public');
                        _reload();
                      },
                    ),
                    _CommunityFilterChip(
                      label: 'İstek',
                      selected: _visibility == 'request_only',
                      onTap: () {
                        setState(() => _visibility = 'request_only');
                        _reload();
                      },
                    ),
                    _CommunityFilterChip(
                      label: 'Davet',
                      selected: _visibility == 'invite_only',
                      onTap: () {
                        setState(() => _visibility = 'invite_only');
                        _reload();
                      },
                    ),
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
                        stats:
                            '${community.summaryText}  •  ${_labelForVisibility(community.visibility)}',
                        accent: _accentForCommunity(community, index),
                        onTap: () => _openCommunity(community),
                        actionLabel: _joinLabel(community, busy),
                        onAction:
                            community.isMember ||
                                busy ||
                                community.joinState == 'pending' ||
                                community.joinState == 'invite_only'
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
                        highlightMentions: notification.type == 'mention',
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
  String _questionQuery = '';
  String _resourceQuery = '';
  String _memberQuery = '';
  String _memberRole = 'all';

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
      final joined = await widget.api.join(data.community.id);
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            joined.joinState == 'pending'
                ? '${data.community.name} için katılım isteği gönderildi.'
                : '${data.community.name} topluluğuna katıldın.',
          ),
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
    _CommunityChannelSummary channel, {
    _CommunityMessageSummary? initialMessage,
    String? focusMessageId,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommunityChannelPage(
          api: widget.api,
          community: community,
          channel: channel,
          currentUserId: widget.currentUserId,
          initialMessage: initialMessage,
          initialFocusMessageId: focusMessageId,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _openMessageTarget(
    _CommunitySummary community,
    _CommunityChannelSummary channel,
    _CommunityMessageSummary message,
  ) async {
    final rootMessageId = (message.replyToMessageId ?? '').trim();
    if (rootMessageId.isEmpty) {
      await _openChannel(
        community,
        channel,
        initialMessage: message,
        focusMessageId: message.id,
      );
      return;
    }

    try {
      final thread = await widget.api.fetchThread(
        communityId: community.id,
        channelId: channel.id,
        messageId: rootMessageId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _CommunityThreadPage(
            api: widget.api,
            community: community,
            channel: channel,
            rootMessage: thread.root,
            currentUserId: widget.currentUserId,
            initialFocusMessageId: message.id,
          ),
        ),
      );
      if (!mounted) return;
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openReportTarget(
    _CommunitySummary community,
    _CommunityReportSummary report,
  ) async {
    final channel = report.channel;
    final message = report.message;
    if (channel == null || message == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Raporun bagli oldugu mesaj bulunamadi.')),
      );
      return;
    }
    await _openMessageTarget(community, channel, message);
  }

  Future<void> _openTopic(_CommunityTopicSummary topic) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommunityTopicDetailPage(
          api: widget.api,
          community: widget.initialCommunity,
          topicId: topic.id,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _openCommunitySearch(_CommunitySummary community) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommunitySearchPage(
          api: widget.api,
          community: community,
          currentUserId: widget.currentUserId,
          onOpenTopic: _openTopic,
          onOpenChannel: (channel) => _openChannel(community, channel),
        ),
      ),
    );
  }

  Future<void> _openTopicComposer(
    _CommunitySummary community, {
    required String initialType,
  }) async {
    final created = await Navigator.of(context).push<_CommunityTopicSummary>(
      MaterialPageRoute<_CommunityTopicSummary>(
        builder: (_) => _CommunityTopicComposerPage(
          api: widget.api,
          community: community,
          initialType: initialType,
        ),
      ),
    );
    if (created == null || !mounted) return;
    await _reload();
    if (!mounted) return;
    await _openTopic(created);
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
    return Column(
      children: [
        if (community.isMember) ...[
          FutureBuilder<List<_CommunityPinnedMessageSummary>>(
            future: widget.api.fetchPinnedMessages(communityId: community.id),
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
              final pinned =
                  snapshot.data ?? const <_CommunityPinnedMessageSummary>[];
              return _CommunityPinnedMessagesCard(
                items: pinned,
                onOpenMessage: (_CommunityPinnedMessageSummary item) =>
                    _openMessageTarget(community, item.channel, item.message),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        _SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CommunitySectionHeader(
                emoji: '💬',
                title: 'Sohbet odalari',
              ),
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
        ),
      ],
    );
  }

  Widget _buildQuestionsTab(_CommunitySummary community) {
    return FutureBuilder<List<_CommunityTopicSummary>>(
      future: widget.api.fetchTopics(
        communityId: community.id,
        type: 'question',
        query: _questionQuery,
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
              Row(
                children: [
                  const Expanded(
                    child: _CommunitySectionHeader(
                      emoji: '❓',
                      title: 'Soru akışı',
                    ),
                  ),
                  if (community.permissions.canCreateQuestion)
                    IconButton(
                      onPressed: () => _openTopicComposer(
                        community,
                        initialType: 'question',
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: _CommunityUiTokens.surfaceSoft,
                        foregroundColor: _CommunityUiTokens.text,
                      ),
                      icon: const Icon(Icons.add_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _CommunitySearchField(
                hintText: 'Soru ara',
                onChanged: (value) => setState(() => _questionQuery = value),
              ),
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
        widget.api.fetchTopics(
          communityId: community.id,
          type: 'resource',
          query: _resourceQuery,
        ),
        widget.api.fetchTopics(
          communityId: community.id,
          type: 'event',
          query: _resourceQuery,
        ),
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
              Row(
                children: [
                  const Expanded(
                    child: _CommunitySectionHeader(
                      emoji: '🗃️',
                      title: 'Kaynaklar ve etkinlikler',
                    ),
                  ),
                  if (community.permissions.canCreateResource ||
                      community.permissions.canCreateEvent)
                    IconButton(
                      onPressed: () => _openTopicComposer(
                        community,
                        initialType: community.permissions.canCreateResource
                            ? 'resource'
                            : 'event',
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: _CommunityUiTokens.surfaceSoft,
                        foregroundColor: _CommunityUiTokens.text,
                      ),
                      icon: const Icon(Icons.add_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _CommunitySearchField(
                hintText: 'Kaynak veya etkinlik ara',
                onChanged: (value) => setState(() => _resourceQuery = value),
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
    if (!community.isMember) {
      return const _SurfaceCard(
        padding: EdgeInsets.all(18),
        child: _CommunityEmptyState(
          emoji: '🔒',
          title: 'Uye katmani kilitli',
          subtitle:
              'Uyeleri, DM isteklerini ve moderasyon aksiyonlarini gormek icin once topluluga katil.',
        ),
      );
    }

    return FutureBuilder<_CommunityMembersTabData>(
      future: _loadMembersTab(community),
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
        final tabData =
            snapshot.data ??
            const _CommunityMembersTabData(
              members: <_CommunityMemberSummary>[],
              dmRequests: _CommunityDmRequestFeed(
                incoming: <_CommunityDmRequestSummary>[],
                sent: <_CommunityDmRequestSummary>[],
              ),
              invites: <_CommunityInviteSummary>[],
              bans: <_CommunityBanSummary>[],
            );
        final members = tabData.members;
        final dmRequests = tabData.dmRequests;
        final invites = tabData.invites;
        final bans = tabData.bans;
        final pendingInvites = invites
            .where((item) => item.status == 'pending')
            .toList();
        final inviteHistory = invites
            .where((item) => item.status != 'pending')
            .toList();
        final sentByUser = <String, _CommunityDmRequestSummary>{
          for (final item in dmRequests.sent) item.target.id: item,
        };
        final incomingByUser = <String, _CommunityDmRequestSummary>{
          for (final item in dmRequests.incoming) item.requester.id: item,
        };
        return Column(
          children: [
            if (community.permissions.canManageCommunity ||
                community.permissions.canInviteMembers) ...[
              _SurfaceCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _CommunitySectionHeader(
                      emoji: '🧰',
                      title: 'Yonetim paneli',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _CommunityChip(label: 'Rol: ${community.roleLabel}'),
                        _CommunityChip(
                          label:
                              'Gorunurluk: ${_labelForVisibility(community.visibility)}',
                        ),
                        if (community.permissions.canManageCommunity)
                          const _CommunityChip(label: 'Join review acik'),
                        if (community.permissions.canInviteMembers)
                          const _CommunityChip(label: 'Davet acik'),
                        if (community.permissions.canInviteMembers)
                          _CommunityChip(
                            label: 'Bekleyen davet ${pendingInvites.length}',
                          ),
                        if (community.permissions.canManageCommunity)
                          _CommunityChip(label: 'Aktif ban ${bans.length}'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Moderasyon, davet ve rapor akislarini buradan takip edebilirsin.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: _CommunityUiTokens.textMuted,
                      ),
                    ),
                    if (community.permissions.canInviteMembers) ...[
                      const SizedBox(height: 14),
                      FilledButton.tonalIcon(
                        onPressed: () => _openInvitePicker(community, members),
                        style: FilledButton.styleFrom(
                          backgroundColor: _CommunityUiTokens.surfaceSoft,
                          foregroundColor: _CommunityUiTokens.text,
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Turna dizininden uye davet et'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (community.permissions.canInviteMembers) ...[
              _CommunityInviteHistoryCard(
                invites: invites,
                pendingInvites: pendingInvites,
                historyInvites: inviteHistory,
              ),
              const SizedBox(height: 16),
            ],
            if (community.permissions.canManageCommunity) ...[
              _CommunityJoinRequestsCard(
                api: widget.api,
                community: community,
                onChanged: _reload,
              ),
              const SizedBox(height: 16),
              _CommunityBannedMembersCard(
                items: bans,
                onUnban: (_CommunityBanSummary ban) =>
                    _unbanMember(community, ban),
              ),
              const SizedBox(height: 16),
              _CommunityReportsInboxCard(
                api: widget.api,
                community: community,
                onOpenTarget: (_CommunityReportSummary report) =>
                    _openReportTarget(community, report),
              ),
              const SizedBox(height: 16),
            ],
            _CommunityDmRequestsCard(
              feed: dmRequests,
              onAccept: (_CommunityDmRequestSummary request) =>
                  _acceptDmRequest(community, request),
              onReject: (_CommunityDmRequestSummary request) =>
                  _rejectDmRequest(community, request),
            ),
            const SizedBox(height: 16),
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
                  _CommunitySearchField(
                    hintText: 'Üye ara',
                    onChanged: (value) => setState(() => _memberQuery = value),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CommunityFilterChip(
                        label: 'Tümü',
                        selected: _memberRole == 'all',
                        onTap: () => setState(() => _memberRole = 'all'),
                      ),
                      _CommunityFilterChip(
                        label: 'Admin',
                        selected: _memberRole == 'admin',
                        onTap: () => setState(() => _memberRole = 'admin'),
                      ),
                      _CommunityFilterChip(
                        label: 'Mentor',
                        selected: _memberRole == 'mentor',
                        onTap: () => setState(() => _memberRole = 'mentor'),
                      ),
                      _CommunityFilterChip(
                        label: 'Üye',
                        selected: _memberRole == 'member',
                        onTap: () => setState(() => _memberRole = 'member'),
                      ),
                    ],
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
                      final incomingRequest = incomingByUser[member.user.id];
                      final sentRequest = sentByUser[member.user.id];
                      final canModerate = _canModerateCommunityMember(
                        viewerRole: community.role,
                        viewerUserId: widget.currentUserId,
                        target: member,
                      );
                      String? primaryActionLabel;
                      VoidCallback? onPrimaryAction;
                      String? secondaryActionLabel;
                      VoidCallback? onSecondaryAction;
                      if (member.user.id != widget.currentUserId) {
                        if (incomingRequest != null) {
                          primaryActionLabel = 'Kabul et';
                          onPrimaryAction = () =>
                              _acceptDmRequest(community, incomingRequest);
                          secondaryActionLabel = 'Reddet';
                          onSecondaryAction = () =>
                              _rejectDmRequest(community, incomingRequest);
                        } else if (sentRequest != null) {
                          primaryActionLabel = 'Istek gonderildi';
                        } else {
                          primaryActionLabel = 'DM istegi';
                          onPrimaryAction = () =>
                              _createDmRequest(community, member);
                        }
                      }
                      final badges = <String>[
                        if (member.isMuted) 'Sessizde',
                        if (member.muteReason?.trim().isNotEmpty == true)
                          member.muteReason!.trim(),
                      ];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == members.length - 1 ? 0 : 10,
                        ),
                        child: _CommunityMemberTile(
                          emoji: _emojiForIndex(index),
                          name: member.user.displayName,
                          role: member.roleLabel,
                          subtitle: member.user.subtitle,
                          badges: badges,
                          primaryActionLabel: primaryActionLabel,
                          onPrimaryAction: onPrimaryAction,
                          secondaryActionLabel: secondaryActionLabel,
                          onSecondaryAction: onSecondaryAction,
                          showChevron: false,
                          onMore: canModerate
                              ? () => _handleMemberModerationMenu(
                                  community,
                                  member,
                                )
                              : null,
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

  Future<_CommunityMembersTabData> _loadMembersTab(
    _CommunitySummary community,
  ) async {
    final results = await Future.wait<Object>([
      widget.api.fetchMembers(
        communityId: community.id,
        query: _memberQuery,
        role: _memberRole,
      ),
      widget.api.fetchDmRequests(communityId: community.id),
      community.permissions.canInviteMembers
          ? widget.api.fetchInvites(communityId: community.id)
          : Future<List<_CommunityInviteSummary>>.value(
              const <_CommunityInviteSummary>[],
            ),
      community.permissions.canManageCommunity
          ? widget.api.fetchBans(communityId: community.id)
          : Future<List<_CommunityBanSummary>>.value(
              const <_CommunityBanSummary>[],
            ),
    ]);
    return _CommunityMembersTabData(
      members: results[0] as List<_CommunityMemberSummary>,
      dmRequests: results[1] as _CommunityDmRequestFeed,
      invites: results[2] as List<_CommunityInviteSummary>,
      bans: results[3] as List<_CommunityBanSummary>,
    );
  }

  Future<void> _openInvitePicker(
    _CommunitySummary community,
    List<_CommunityMemberSummary> members,
  ) async {
    try {
      final directory = await widget.api.fetchInviteDirectory();
      if (!mounted) return;
      final memberIds = members.map((item) => item.user.id).toSet();
      final candidates =
          directory
              .where(
                (item) =>
                    item.id != widget.currentUserId &&
                    !memberIds.contains(item.id),
              )
              .toList()
            ..sort(
              (left, right) => left.displayName.toLowerCase().compareTo(
                right.displayName.toLowerCase(),
              ),
            );
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Davet edilebilecek yeni kisi bulunamadi.'),
          ),
        );
        return;
      }
      final selected = await _showCommunityInvitePicker(
        context,
        candidates: candidates,
      );
      if (selected == null || !mounted) return;
      await widget.api.createInvite(
        communityId: community.id,
        userId: selected.id,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selected.displayName} icin davet gonderildi.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _createDmRequest(
    _CommunitySummary community,
    _CommunityMemberSummary member,
  ) async {
    final note = await _showCommunityDmRequestComposer(context, target: member);
    if (note == null) return;
    try {
      await widget.api.createDmRequest(
        communityId: community.id,
        userId: member.user.id,
        note: note.trim().isEmpty ? null : note.trim(),
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member.user.displayName} icin DM istegi gonderildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _acceptDmRequest(
    _CommunitySummary community,
    _CommunityDmRequestSummary request,
  ) async {
    try {
      await widget.api.acceptDmRequest(
        communityId: community.id,
        requestId: request.id,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${request.requester.displayName} ile Turna DM hazir.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _rejectDmRequest(
    _CommunitySummary community,
    _CommunityDmRequestSummary request,
  ) async {
    try {
      await widget.api.rejectDmRequest(
        communityId: community.id,
        requestId: request.id,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${request.requester.displayName} istegi reddedildi.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _handleMemberModerationMenu(
    _CommunitySummary community,
    _CommunityMemberSummary member,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.volume_off_outlined),
                  title: const Text('1 saat sessize al'),
                  onTap: () => Navigator.of(context).pop('mute_60'),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: const Text('24 saat sessize al'),
                  onTap: () => Navigator.of(context).pop('mute_1440'),
                ),
                if (member.isMuted)
                  ListTile(
                    leading: const Icon(Icons.volume_up_outlined),
                    title: const Text('Sessizi kaldir'),
                    onTap: () => Navigator.of(context).pop('unmute'),
                  ),
                ListTile(
                  leading: const Icon(Icons.gavel_rounded),
                  title: const Text('Topluluktan banla'),
                  textColor: Colors.redAccent,
                  iconColor: Colors.redAccent,
                  onTap: () => Navigator.of(context).pop('ban'),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      switch (action) {
        case 'mute_60':
          await widget.api.muteMember(
            communityId: community.id,
            userId: member.user.id,
            minutes: 60,
            reason: 'Community moderation',
          );
          break;
        case 'mute_1440':
          await widget.api.muteMember(
            communityId: community.id,
            userId: member.user.id,
            minutes: 1440,
            reason: 'Community moderation',
          );
          break;
        case 'unmute':
          await widget.api.muteMember(
            communityId: community.id,
            userId: member.user.id,
            minutes: 0,
          );
          break;
        case 'ban':
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Uyeyi banla'),
                content: Text(
                  '${member.user.displayName} topluluktan cikarilacak ve mevcut DM istekleri kapanacak.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Vazgec'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    child: const Text('Banla'),
                  ),
                ],
              );
            },
          );
          if (confirmed != true) return;
          await widget.api.banMember(
            communityId: community.id,
            userId: member.user.id,
            reason: 'Community moderation',
          );
          break;
        default:
          return;
      }

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member.user.displayName} icin moderation guncellendi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _unbanMember(
    _CommunitySummary community,
    _CommunityBanSummary ban,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ban kaldir'),
          content: Text(
            '${ban.user.displayName} icin community ban kaydi kaldirilsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: _CommunityUiTokens.text,
              ),
              child: const Text('Ban kaldir'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await widget.api.unbanMember(
        communityId: community.id,
        userId: ban.user.id,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ban.user.displayName} icin ban kaldirildi.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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
                      if (community.isMember)
                        IconButton(
                          onPressed: () => _openCommunitySearch(community),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _CommunityUiTokens.text,
                          ),
                          icon: const Icon(Icons.search_rounded),
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
                                    : '${_emojiForVisibility(community.visibility)} ${_labelForVisibility(community.visibility)}',
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
                                    onPressed:
                                        _busy ||
                                            community.joinState == 'pending' ||
                                            community.joinState == 'invite_only'
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
                                                ? _joinCtaLabel(community)
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
    this.initialMessage,
    this.initialFocusMessageId,
  });

  final _CommunityApiClient api;
  final _CommunitySummary community;
  final _CommunityChannelSummary channel;
  final String currentUserId;
  final _CommunityMessageSummary? initialMessage;
  final String? initialFocusMessageId;

  @override
  State<_CommunityChannelPage> createState() => _CommunityChannelPageState();
}

class _CommunityChannelPageState extends State<_CommunityChannelPage> {
  final _composerController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<_CommunityMessageSummary> _items = <_CommunityMessageSummary>[];
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  io.Socket? _socket;
  Timer? _mentionDebounce;
  bool _loading = true;
  bool _sending = false;
  bool _attachmentBusy = false;
  bool _mentionLoading = false;
  bool _initialFocusHandled = false;
  String? _highlightMessageId;
  String? _errorMessage;
  String _mentionLookupKey = '';
  _CommunityMentionQuery? _activeMentionQuery;
  List<_CommunityMemberSummary> _mentionSuggestions =
      const <_CommunityMemberSummary>[];

  @override
  void initState() {
    super.initState();
    _highlightMessageId = widget.initialFocusMessageId;
    _composerController.addListener(_handleComposerChanged);
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
    _mentionDebounce?.cancel();
    _composerController.removeListener(_handleComposerChanged);
    _scrollController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _clearMentionSuggestions() {
    _mentionDebounce?.cancel();
    if (!mounted) return;
    setState(() {
      _mentionLoading = false;
      _mentionLookupKey = '';
      _activeMentionQuery = null;
      _mentionSuggestions = const <_CommunityMemberSummary>[];
    });
  }

  void _handleComposerChanged() {
    final mention = _extractCommunityMentionQuery(_composerController.value);
    if (mention == null) {
      if (_activeMentionQuery != null ||
          _mentionSuggestions.isNotEmpty ||
          _mentionLoading) {
        _clearMentionSuggestions();
      }
      return;
    }

    final lookupKey = mention.query;
    if (mounted) {
      setState(() => _activeMentionQuery = mention);
    }
    if (_mentionLookupKey == lookupKey && _mentionSuggestions.isNotEmpty) {
      return;
    }

    _mentionDebounce?.cancel();
    setState(() {
      _mentionLookupKey = lookupKey;
      _mentionLoading = true;
    });
    _mentionDebounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final results = await widget.api.fetchMembers(
          communityId: widget.community.id,
          query: lookupKey.isEmpty ? null : lookupKey,
        );
        if (!mounted) return;
        final currentMention = _extractCommunityMentionQuery(
          _composerController.value,
        );
        if (currentMention == null || currentMention.query != lookupKey) {
          return;
        }
        setState(() {
          _activeMentionQuery = currentMention;
          _mentionLoading = false;
          _mentionSuggestions = results
              .where(
                (item) =>
                    item.user.id != widget.currentUserId &&
                    (item.user.username ?? '').trim().isNotEmpty,
              )
              .take(5)
              .toList();
        });
      } catch (_) {
        if (!mounted) return;
        final currentMention = _extractCommunityMentionQuery(
          _composerController.value,
        );
        if (currentMention == null || currentMention.query != lookupKey) {
          return;
        }
        setState(() {
          _mentionLoading = false;
          _mentionSuggestions = const <_CommunityMemberSummary>[];
        });
      }
    });
  }

  void _applyMention(_CommunityMemberSummary member) {
    final username = member.user.username?.trim();
    final mention = _extractCommunityMentionQuery(_composerController.value);
    if (username == null || username.isEmpty || mention == null) return;
    final value = _composerController.value;
    final nextText =
        '${value.text.substring(0, mention.start)}@$username ${value.text.substring(mention.end)}';
    final nextOffset = mention.start + username.length + 2;
    _composerController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    _clearMentionSuggestions();
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
          attachments: current.attachments,
          isPinned: current.isPinned,
          reactions: current.reactions,
          replyCount: replyCount,
          replyToMessageId: current.replyToMessageId,
          replyAuthorName: current.replyAuthorName,
          replyPreview: current.replyPreview,
        );
      });
    });

    socket.on('community:message:update', (payload) {
      if (payload is! Map) return;
      final data = Map<String, dynamic>.from(payload);
      if ((data['channelId'] ?? '').toString() != widget.channel.id) {
        return;
      }
      final rawMessage = Map<String, dynamic>.from(
        data['message'] as Map? ?? const {},
      );
      final message = _CommunityMessageSummary.fromMap(rawMessage);
      final index = _items.indexWhere((item) => item.id == message.id);
      if (!mounted || index < 0) return;
      setState(() {
        _items[index] = message;
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
        final injected = widget.initialMessage;
        if (injected != null &&
            (injected.replyToMessageId ?? '').trim().isEmpty &&
            !_items.any((item) => item.id == injected.id)) {
          _items.add(injected);
          _items.sort(
            (left, right) => left.createdAt.compareTo(right.createdAt),
          );
        }
      });
      _scheduleFocusToMessage();
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

  GlobalKey _messageKeyFor(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  Future<bool> _scrollToMessage(String messageId) async {
    final targetKey = _messageKeys[messageId];
    final targetContext = targetKey?.currentContext;
    if (targetContext == null) return false;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
    return true;
  }

  void _scheduleFocusToMessage() {
    final messageId = widget.initialFocusMessageId?.trim();
    if (_initialFocusHandled || messageId == null || messageId.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final focused = await _scrollToMessage(messageId);
      if (!mounted || !focused) return;
      setState(() {
        _initialFocusHandled = true;
        _highlightMessageId = messageId;
      });
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!mounted || _highlightMessageId != messageId) return;
        setState(() => _highlightMessageId = null);
      });
    });
  }

  Future<void> _toggleReaction(
    _CommunityMessageSummary message,
    String emoji,
  ) async {
    try {
      final updated = await widget.api.toggleMessageReaction(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        messageId: message.id,
        emoji: emoji,
      );
      if (!mounted) return;
      setState(() => _upsertMessage(updated));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showReactionPicker(_CommunityMessageSummary message) async {
    final emoji = await _showCommunityReactionPicker(context);
    if (emoji == null) return;
    await _toggleReaction(message, emoji);
  }

  Future<void> _togglePin(_CommunityMessageSummary message) async {
    try {
      final updated = await widget.api.setMessagePinned(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        messageId: message.id,
        pinned: !message.isPinned,
      );
      if (!mounted) return;
      setState(() => _upsertMessage(updated));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _reportMessage(_CommunityMessageSummary message) async {
    final reason = await _showCommunityReportReasonPicker(context);
    if (reason == null) return;
    try {
      await widget.api.reportMessage(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        messageId: message.id,
        reasonCode: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mesaj raporlandı.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _handleMessageMenu(_CommunityMessageSummary message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final canPin = _communityRolePriority(widget.community.role) <= 3;
        final isMine = message.author.id == widget.currentUserId;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.add_reaction_outlined),
                  title: const Text('Reaction ekle'),
                  onTap: () => Navigator.of(context).pop('react'),
                ),
                if (canPin)
                  ListTile(
                    leading: Icon(
                      message.isPinned
                          ? Icons.push_pin_outlined
                          : Icons.push_pin_rounded,
                    ),
                    title: Text(
                      message.isPinned ? 'Sabiti kaldır' : 'Mesajı sabitle',
                    ),
                    onTap: () => Navigator.of(context).pop('pin'),
                  ),
                if (!isMine)
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Mesajı raporla'),
                    onTap: () => Navigator.of(context).pop('report'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    switch (action) {
      case 'react':
        await _showReactionPicker(message);
        return;
      case 'pin':
        await _togglePin(message);
        return;
      case 'report':
        await _reportMessage(message);
        return;
    }
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

  Future<void> _showAttachmentSheet() async {
    if (_attachmentBusy || _sending) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Galeriden gorsel sec'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Kamera ile cek'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.attach_file_rounded),
                  title: const Text('Dosya ekle'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_attachmentBusy || _sending) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 92,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final payload = _CommunityAttachmentPayload(
        kind: 'image',
        fileName: picked.name,
        contentType: _communityContentTypeForFileName(picked.name),
        bytes: bytes,
      );
      await _sendAttachment(payload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gorsel secilemedi: $error')));
    }
  }

  Future<void> _pickFile() async {
    if (_attachmentBusy || _sending) return;
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && (file.path ?? '').trim().isNotEmpty) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        throw Exception('Dosya okunamadi.');
      }
      final contentType = _communityContentTypeForFileName(file.name);
      final payload = _CommunityAttachmentPayload(
        kind: _communityAttachmentKindForContentType(contentType),
        fileName: file.name,
        contentType: contentType,
        bytes: bytes,
      );
      await _sendAttachment(payload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya secilemedi: $error')));
    }
  }

  Future<void> _sendAttachment(_CommunityAttachmentPayload payload) async {
    setState(() => _attachmentBusy = true);
    try {
      final upload = await widget.api.createAttachmentUpload(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        kind: payload.kind,
        contentType: payload.contentType,
        fileName: payload.fileName,
      );
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: payload.bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw _CommunityApiException('Dosya yuklenemedi.');
      }

      final created = await widget.api.sendChannelMessage(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        text: _composerController.text.trim().isEmpty
            ? null
            : _composerController.text.trim(),
        attachments: <_CommunityOutgoingAttachmentDraft>[
          _CommunityOutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: payload.kind,
            contentType: payload.contentType,
            sizeBytes: payload.sizeBytes,
            fileName: payload.fileName,
          ),
        ],
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
        setState(() => _attachmentBusy = false);
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
                                  controller: _scrollController,
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
                                    return KeyedSubtree(
                                      key: _messageKeyFor(item.id),
                                      child: _CommunityMessageBubble(
                                        message: item,
                                        mine:
                                            item.author.id ==
                                            widget.currentUserId,
                                        onReply: () => _openThread(item),
                                        onTap: () => _openThread(item),
                                        onAddReaction: () =>
                                            _showReactionPicker(item),
                                        onToggleReaction: (emoji) =>
                                            _toggleReaction(item, emoji),
                                        onMore: () => _handleMessageMenu(item),
                                        showCreatedAt: true,
                                        highlighted:
                                            _highlightMessageId == item.id,
                                      ),
                                    );
                                  },
                                ),
                              ))),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_activeMentionQuery != null &&
                      (_mentionLoading || _mentionSuggestions.isNotEmpty)) ...[
                    _CommunityMentionSuggestionsCard(
                      items: _mentionSuggestions,
                      loading: _mentionLoading,
                      onSelect: _applyMention,
                    ),
                    const SizedBox(height: 10),
                  ],
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _CommunityUiTokens.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: (_sending || _attachmentBusy)
                                ? null
                                : _showAttachmentSheet,
                            visualDensity: VisualDensity.compact,
                            icon: _attachmentBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add_circle_outline_rounded),
                            color: _CommunityUiTokens.textMuted,
                          ),
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
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: (_sending || _attachmentBusy)
                                ? null
                                : _sendRootMessage,
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
                ],
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
    this.initialFocusMessageId,
  });

  final _CommunityApiClient api;
  final _CommunitySummary community;
  final _CommunityChannelSummary channel;
  final _CommunityMessageSummary rootMessage;
  final String currentUserId;
  final String? initialFocusMessageId;

  @override
  State<_CommunityThreadPage> createState() => _CommunityThreadPageState();
}

class _CommunityThreadPageState extends State<_CommunityThreadPage> {
  final _composerController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<_CommunityMessageSummary> _replies = <_CommunityMessageSummary>[];
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  io.Socket? _socket;
  Timer? _mentionDebounce;
  _CommunityMessageSummary? _root;
  bool _loading = true;
  bool _sending = false;
  bool _attachmentBusy = false;
  bool _mentionLoading = false;
  bool _initialFocusHandled = false;
  String? _highlightMessageId;
  String? _errorMessage;
  String _mentionLookupKey = '';
  _CommunityMentionQuery? _activeMentionQuery;
  List<_CommunityMemberSummary> _mentionSuggestions =
      const <_CommunityMemberSummary>[];

  @override
  void initState() {
    super.initState();
    _highlightMessageId = widget.initialFocusMessageId;
    _root = widget.rootMessage;
    _composerController.addListener(_handleComposerChanged);
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
    _mentionDebounce?.cancel();
    _composerController.removeListener(_handleComposerChanged);
    _scrollController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _clearMentionSuggestions() {
    _mentionDebounce?.cancel();
    if (!mounted) return;
    setState(() {
      _mentionLoading = false;
      _mentionLookupKey = '';
      _activeMentionQuery = null;
      _mentionSuggestions = const <_CommunityMemberSummary>[];
    });
  }

  void _handleComposerChanged() {
    final mention = _extractCommunityMentionQuery(_composerController.value);
    if (mention == null) {
      if (_activeMentionQuery != null ||
          _mentionSuggestions.isNotEmpty ||
          _mentionLoading) {
        _clearMentionSuggestions();
      }
      return;
    }

    final lookupKey = mention.query;
    if (mounted) {
      setState(() => _activeMentionQuery = mention);
    }
    if (_mentionLookupKey == lookupKey && _mentionSuggestions.isNotEmpty) {
      return;
    }

    _mentionDebounce?.cancel();
    setState(() {
      _mentionLookupKey = lookupKey;
      _mentionLoading = true;
    });
    _mentionDebounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final results = await widget.api.fetchMembers(
          communityId: widget.community.id,
          query: lookupKey.isEmpty ? null : lookupKey,
        );
        if (!mounted) return;
        final currentMention = _extractCommunityMentionQuery(
          _composerController.value,
        );
        if (currentMention == null || currentMention.query != lookupKey) {
          return;
        }
        setState(() {
          _activeMentionQuery = currentMention;
          _mentionLoading = false;
          _mentionSuggestions = results
              .where(
                (item) =>
                    item.user.id != widget.currentUserId &&
                    (item.user.username ?? '').trim().isNotEmpty,
              )
              .take(5)
              .toList();
        });
      } catch (_) {
        if (!mounted) return;
        final currentMention = _extractCommunityMentionQuery(
          _composerController.value,
        );
        if (currentMention == null || currentMention.query != lookupKey) {
          return;
        }
        setState(() {
          _mentionLoading = false;
          _mentionSuggestions = const <_CommunityMemberSummary>[];
        });
      }
    });
  }

  void _applyMention(_CommunityMemberSummary member) {
    final username = member.user.username?.trim();
    final mention = _extractCommunityMentionQuery(_composerController.value);
    if (username == null || username.isEmpty || mention == null) return;
    final value = _composerController.value;
    final nextText =
        '${value.text.substring(0, mention.start)}@$username ${value.text.substring(mention.end)}';
    final nextOffset = mention.start + username.length + 2;
    _composerController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    _clearMentionSuggestions();
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

    socket.on('community:message:update', (payload) {
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
        if (message.id == widget.rootMessage.id) {
          _root = _copyCommunityMessage(message, replyCount: _replies.length);
          return;
        }
        final index = _replies.indexWhere((item) => item.id == message.id);
        if (index >= 0) {
          _replies[index] = message;
        }
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
      _scheduleFocusToMessage();
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

  void _upsertReply(_CommunityMessageSummary message) {
    final index = _replies.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      _replies[index] = message;
    } else {
      _replies.add(message);
      _replies.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    }
  }

  GlobalKey _messageKeyFor(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  Future<bool> _scrollToMessage(String messageId) async {
    final targetKey = _messageKeys[messageId];
    final targetContext = targetKey?.currentContext;
    if (targetContext == null) return false;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
    return true;
  }

  void _scheduleFocusToMessage() {
    final messageId = widget.initialFocusMessageId?.trim();
    if (_initialFocusHandled || messageId == null || messageId.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final focused = await _scrollToMessage(messageId);
      if (!mounted || !focused) return;
      setState(() {
        _initialFocusHandled = true;
        _highlightMessageId = messageId;
      });
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!mounted || _highlightMessageId != messageId) return;
        setState(() => _highlightMessageId = null);
      });
    });
  }

  Future<void> _toggleReaction(
    _CommunityMessageSummary message,
    String emoji,
  ) async {
    try {
      final updated = await widget.api.toggleMessageReaction(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        messageId: message.id,
        emoji: emoji,
      );
      if (!mounted) return;
      setState(() {
        if (updated.id == widget.rootMessage.id) {
          _root = _copyCommunityMessage(updated, replyCount: _replies.length);
        } else {
          _upsertReply(updated);
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showReactionPicker(_CommunityMessageSummary message) async {
    final emoji = await _showCommunityReactionPicker(context);
    if (emoji == null) return;
    await _toggleReaction(message, emoji);
  }

  Future<void> _togglePin(_CommunityMessageSummary message) async {
    try {
      final updated = await widget.api.setMessagePinned(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        messageId: message.id,
        pinned: !message.isPinned,
      );
      if (!mounted) return;
      setState(() {
        if (updated.id == widget.rootMessage.id) {
          _root = _copyCommunityMessage(updated, replyCount: _replies.length);
        } else {
          _upsertReply(updated);
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _reportMessage(_CommunityMessageSummary message) async {
    final reason = await _showCommunityReportReasonPicker(context);
    if (reason == null) return;
    try {
      await widget.api.reportMessage(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        messageId: message.id,
        reasonCode: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mesaj raporlandı.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _handleMessageMenu(_CommunityMessageSummary message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final canPin = _communityRolePriority(widget.community.role) <= 3;
        final isMine = message.author.id == widget.currentUserId;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.add_reaction_outlined),
                  title: const Text('Reaction ekle'),
                  onTap: () => Navigator.of(context).pop('react'),
                ),
                if (canPin)
                  ListTile(
                    leading: Icon(
                      message.isPinned
                          ? Icons.push_pin_outlined
                          : Icons.push_pin_rounded,
                    ),
                    title: Text(
                      message.isPinned ? 'Sabiti kaldır' : 'Mesajı sabitle',
                    ),
                    onTap: () => Navigator.of(context).pop('pin'),
                  ),
                if (!isMine)
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Mesajı raporla'),
                    onTap: () => Navigator.of(context).pop('report'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    switch (action) {
      case 'react':
        await _showReactionPicker(message);
        return;
      case 'pin':
        await _togglePin(message);
        return;
      case 'report':
        await _reportMessage(message);
        return;
    }
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
        _upsertReply(created);
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

  Future<void> _showAttachmentSheet() async {
    if (_attachmentBusy || _sending) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Galeriden gorsel sec'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Kamera ile cek'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.attach_file_rounded),
                  title: const Text('Dosya ekle'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_attachmentBusy || _sending) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 92,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final payload = _CommunityAttachmentPayload(
        kind: 'image',
        fileName: picked.name,
        contentType: _communityContentTypeForFileName(picked.name),
        bytes: bytes,
      );
      await _sendAttachment(payload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gorsel secilemedi: $error')));
    }
  }

  Future<void> _pickFile() async {
    if (_attachmentBusy || _sending) return;
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && (file.path ?? '').trim().isNotEmpty) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        throw Exception('Dosya okunamadi.');
      }
      final contentType = _communityContentTypeForFileName(file.name);
      final payload = _CommunityAttachmentPayload(
        kind: _communityAttachmentKindForContentType(contentType),
        fileName: file.name,
        contentType: contentType,
        bytes: bytes,
      );
      await _sendAttachment(payload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya secilemedi: $error')));
    }
  }

  Future<void> _sendAttachment(_CommunityAttachmentPayload payload) async {
    setState(() => _attachmentBusy = true);
    try {
      final upload = await widget.api.createAttachmentUpload(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        kind: payload.kind,
        contentType: payload.contentType,
        fileName: payload.fileName,
      );
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: payload.bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw _CommunityApiException('Dosya yuklenemedi.');
      }

      final created = await widget.api.sendChannelMessage(
        communityId: widget.community.id,
        channelId: widget.channel.id,
        text: _composerController.text.trim().isEmpty
            ? null
            : _composerController.text.trim(),
        replyToMessageId: widget.rootMessage.id,
        attachments: <_CommunityOutgoingAttachmentDraft>[
          _CommunityOutgoingAttachmentDraft(
            objectKey: upload.objectKey,
            kind: payload.kind,
            contentType: payload.contentType,
            sizeBytes: payload.sizeBytes,
            fileName: payload.fileName,
          ),
        ],
      );
      _composerController.clear();
      if (!mounted) return;
      setState(() {
        _upsertReply(created);
        _root = _copyCommunityMessage(_root!, replyCount: _replies.length);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _attachmentBusy = false);
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
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              KeyedSubtree(
                                key: _messageKeyFor(root.id),
                                child: _CommunityThreadRootCard(
                                  message: root,
                                  mine: root.author.id == widget.currentUserId,
                                  channelName: widget.channel.name,
                                  replyCount: _replies.length,
                                  onAddReaction: () =>
                                      _showReactionPicker(root),
                                  onToggleReaction: (emoji) =>
                                      _toggleReaction(root, emoji),
                                  onMore: () => _handleMessageMenu(root),
                                  highlighted: _highlightMessageId == root.id,
                                ),
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
                                    child: KeyedSubtree(
                                      key: _messageKeyFor(item.id),
                                      child: _CommunityThreadReplyTile(
                                        message: item,
                                        mine:
                                            item.author.id ==
                                            widget.currentUserId,
                                        isLast: index == _replies.length - 1,
                                        onAddReaction: () =>
                                            _showReactionPicker(item),
                                        onToggleReaction: (emoji) =>
                                            _toggleReaction(item, emoji),
                                        onMore: () => _handleMessageMenu(item),
                                        highlighted:
                                            _highlightMessageId == item.id,
                                      ),
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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_activeMentionQuery != null &&
                                  (_mentionLoading ||
                                      _mentionSuggestions.isNotEmpty)) ...[
                                _CommunityMentionSuggestionsCard(
                                  items: _mentionSuggestions,
                                  loading: _mentionLoading,
                                  onSelect: _applyMention,
                                ),
                                const SizedBox(height: 10),
                              ],
                              DecoratedBox(
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
                                      IconButton(
                                        onPressed: (_sending || _attachmentBusy)
                                            ? null
                                            : _showAttachmentSheet,
                                        visualDensity: VisualDensity.compact,
                                        icon: _attachmentBusy
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons
                                                    .add_circle_outline_rounded,
                                              ),
                                        color: _CommunityUiTokens.textMuted,
                                      ),
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
                                      const SizedBox(width: 8),
                                      FilledButton(
                                        onPressed: (_sending || _attachmentBusy)
                                            ? null
                                            : _send,
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              _CommunityUiTokens.text,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          _sending ? '...' : 'Gonder',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
    this.highlighted = false,
    this.onAddReaction,
    this.onToggleReaction,
    this.onMore,
  });

  final _CommunityMessageSummary message;
  final bool mine;
  final String channelName;
  final int replyCount;
  final bool highlighted;
  final VoidCallback? onAddReaction;
  final ValueChanged<String>? onToggleReaction;
  final VoidCallback? onMore;

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
              highlighted: highlighted,
              onAddReaction: onAddReaction,
              onToggleReaction: onToggleReaction,
              onMore: onMore,
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
    this.highlighted = false,
    this.onAddReaction,
    this.onToggleReaction,
    this.onMore,
  });

  final _CommunityMessageSummary message;
  final bool mine;
  final bool isLast;
  final bool highlighted;
  final VoidCallback? onAddReaction;
  final ValueChanged<String>? onToggleReaction;
  final VoidCallback? onMore;

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
              highlighted: highlighted,
              onAddReaction: onAddReaction,
              onToggleReaction: onToggleReaction,
              onMore: onMore,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityTopicDetailPage extends StatefulWidget {
  const _CommunityTopicDetailPage({
    required this.api,
    required this.community,
    required this.topicId,
    required this.currentUserId,
  });

  final _CommunityApiClient api;
  final _CommunitySummary community;
  final String topicId;
  final String currentUserId;

  @override
  State<_CommunityTopicDetailPage> createState() =>
      _CommunityTopicDetailPageState();
}

class _CommunityTopicDetailPageState extends State<_CommunityTopicDetailPage> {
  final _replyController = TextEditingController();
  _CommunityTopicSummary? _topic;
  bool _loading = true;
  bool _sending = false;
  bool _updating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final topic = await widget.api.fetchTopicDetail(
        communityId: widget.community.id,
        topicId: widget.topicId,
      );
      if (!mounted) return;
      setState(() {
        _topic = topic;
        _loading = false;
        _errorMessage = null;
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
    await _load();
  }

  Future<void> _sendReply() async {
    final topic = _topic;
    final body = _replyController.text.trim();
    if (topic == null || body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final updated = await widget.api.replyToTopic(
        communityId: widget.community.id,
        topicId: topic.id,
        body: body,
      );
      _replyController.clear();
      if (!mounted) return;
      setState(() => _topic = updated);
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

  Future<void> _acceptReply(_CommunityTopicReplySummary reply) async {
    final topic = _topic;
    if (topic == null || _updating) return;
    setState(() => _updating = true);
    try {
      final updated = await widget.api.acceptTopicReply(
        communityId: widget.community.id,
        topicId: topic.id,
        replyId: reply.id,
      );
      if (!mounted) return;
      setState(() => _topic = updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _toggleSolved() async {
    final topic = _topic;
    if (topic == null || _updating) return;
    setState(() => _updating = true);
    try {
      final updated = await widget.api.setTopicSolved(
        communityId: widget.community.id,
        topicId: topic.id,
        solved: !topic.isSolved,
      );
      if (!mounted) return;
      setState(() => _topic = updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _togglePinned() async {
    final topic = _topic;
    if (topic == null || _updating) return;
    setState(() => _updating = true);
    try {
      final updated = await widget.api.pinTopic(
        communityId: widget.community.id,
        topicId: topic.id,
        pinned: !topic.isPinned,
      );
      if (!mounted) return;
      setState(() => _topic = updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topic = _topic;
    final descriptor = switch (topic?.type ?? 'question') {
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_errorMessage != null || topic == null
                ? _CommunityErrorState(
                    message: _errorMessage ?? 'Konu yüklenemedi.',
                    onRetry: _reload,
                  )
                : Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _reload,
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
                                          label:
                                              '${descriptor.emoji} ${descriptor.label}',
                                        ),
                                        if (topic.channel != null)
                                          _CommunityChip(
                                            label: '#${topic.channel!.name}',
                                          ),
                                        if (topic.isPinned)
                                          const _CommunityChip(
                                            label: '📌 Sabit',
                                          ),
                                        if (topic.isSolved)
                                          const _CommunityChip(
                                            label: '✅ Cozuldu',
                                          ),
                                        if ((topic.eventStartsAt ?? '')
                                            .trim()
                                            .isNotEmpty)
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
                                          backgroundColor:
                                              _CommunityUiTokens.surfaceSoft,
                                          child: Text(
                                            topic.author.displayName
                                                    .trim()
                                                    .isNotEmpty
                                                ? topic.author.displayName
                                                      .trim()[0]
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                topic.author.displayName,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      _CommunityUiTokens.text,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatCommunityDate(
                                                  topic.createdAt,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: _CommunityUiTokens
                                                      .textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        _CommunityChip(
                                          label: '💬 ${topic.replyCount} cevap',
                                        ),
                                      ],
                                    ),
                                    if ((topic.body ?? '')
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      _CommunityTextWithMentions(
                                        text: topic.body!.trim(),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.55,
                                          color: _CommunityUiTokens.text,
                                        ),
                                        mentionBackgroundColor:
                                            _CommunityUiTokens.success
                                                .withValues(alpha: 0.12),
                                      ),
                                    ],
                                    if (topic.tags.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: topic.tags
                                            .map(
                                              (tag) => _CommunityChip(
                                                label: '🏷️ $tag',
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                    if (topic
                                            .permissions
                                            .canChangeSolvedState ||
                                        topic.permissions.canPin) ...[
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (topic
                                              .permissions
                                              .canChangeSolvedState)
                                            FilledButton.tonal(
                                              onPressed: _updating
                                                  ? null
                                                  : _toggleSolved,
                                              child: Text(
                                                topic.isSolved
                                                    ? 'Çözümü geri al'
                                                    : 'Çözüldü olarak işaretle',
                                              ),
                                            ),
                                          if (topic.permissions.canPin)
                                            FilledButton.tonal(
                                              onPressed: _updating
                                                  ? null
                                                  : _togglePinned,
                                              child: Text(
                                                topic.isPinned
                                                    ? 'Sabitten çıkar'
                                                    : 'Sabitle',
                                              ),
                                            ),
                                        ],
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
                                    const _CommunitySectionHeader(
                                      emoji: '🧵',
                                      title: 'Yanitlar',
                                    ),
                                    const SizedBox(height: 12),
                                    if (topic.replies.isEmpty)
                                      const _CommunityEmptyState(
                                        emoji: '🫥',
                                        title: 'Henüz yanıt yok',
                                        subtitle:
                                            'Bu icerik ilk cevap geldikce topluluk bilgisini zenginlestirecek.',
                                      )
                                    else
                                      ...List<
                                        Widget
                                      >.generate(topic.replies.length, (index) {
                                        final reply = topic.replies[index];
                                        return Padding(
                                          padding: EdgeInsets.only(
                                            bottom:
                                                index ==
                                                    topic.replies.length - 1
                                                ? 0
                                                : 12,
                                          ),
                                          child: Column(
                                            children: [
                                              _CommunityTopicReplyTile(
                                                reply: reply,
                                              ),
                                              if (topic
                                                      .permissions
                                                      .canAcceptAnswer &&
                                                  !reply.isAccepted) ...[
                                                const SizedBox(height: 8),
                                                Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: TextButton.icon(
                                                    onPressed: _updating
                                                        ? null
                                                        : () => _acceptReply(
                                                            reply,
                                                          ),
                                                    icon: const Icon(
                                                      Icons
                                                          .check_circle_outline,
                                                      size: 16,
                                                    ),
                                                    label: const Text(
                                                      'En iyi cevap olarak işaretle',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (topic.permissions.canReply)
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
                                        controller: _replyController,
                                        minLines: 1,
                                        maxLines: 5,
                                        decoration: const InputDecoration(
                                          hintText: 'Cevap yaz',
                                          border: InputBorder.none,
                                          isCollapsed: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    FilledButton(
                                      onPressed: _sending ? null : _sendReply,
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            _CommunityUiTokens.text,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
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

class _CommunitySearchPage extends StatefulWidget {
  const _CommunitySearchPage({
    required this.api,
    required this.community,
    required this.currentUserId,
    required this.onOpenTopic,
    required this.onOpenChannel,
  });

  final _CommunityApiClient api;
  final _CommunitySummary community;
  final String currentUserId;
  final Future<void> Function(_CommunityTopicSummary topic) onOpenTopic;
  final Future<void> Function(_CommunityChannelSummary channel) onOpenChannel;

  @override
  State<_CommunitySearchPage> createState() => _CommunitySearchPageState();
}

class _CommunitySearchPageState extends State<_CommunitySearchPage> {
  final _controller = TextEditingController();
  Future<_CommunitySearchSummary>? _future;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    final query = value.trim();
    if (query.length < 2) {
      setState(() => _future = null);
      return;
    }
    setState(() {
      _future = widget.api.searchCommunity(
        communityId: widget.community.id,
        query: query,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CommunityUiTokens.background,
      appBar: AppBar(
        backgroundColor: _CommunityUiTokens.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Topluluk içi arama'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _CommunitySearchField(
              controller: _controller,
              hintText: 'Kanal, konu veya üye ara',
              onChanged: _search,
            ),
            const SizedBox(height: 16),
            if (_future == null)
              const _CommunityEmptyState(
                emoji: '🔎',
                title: 'Aramaya başla',
                subtitle:
                    'En az iki karakter yazarak kanal, konu ve üyeleri birlikte ara.',
              )
            else
              FutureBuilder<_CommunitySearchSummary>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _CommunityErrorState(
                      message: snapshot.error.toString(),
                      onRetry: () async => _search(_controller.text),
                    );
                  }
                  final result = snapshot.data!;
                  return Column(
                    children: [
                      _SurfaceCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _CommunitySectionHeader(
                              emoji: '💬',
                              title: 'Kanallar',
                            ),
                            const SizedBox(height: 12),
                            if (result.channels.isEmpty)
                              const Text(
                                'Eşleşen kanal yok.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _CommunityUiTokens.textMuted,
                                ),
                              )
                            else
                              ...List<Widget>.generate(result.channels.length, (
                                index,
                              ) {
                                final channel = result.channels[index];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == result.channels.length - 1
                                        ? 0
                                        : 10,
                                  ),
                                  child: _ChannelTile(
                                    channel: channel,
                                    onTap: () async {
                                      Navigator.of(context).pop();
                                      await widget.onOpenChannel(channel);
                                    },
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
                              emoji: '🧵',
                              title: 'Konular',
                            ),
                            const SizedBox(height: 12),
                            if (result.topics.isEmpty)
                              const Text(
                                'Eşleşen konu yok.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _CommunityUiTokens.textMuted,
                                ),
                              )
                            else
                              ...List<Widget>.generate(result.topics.length, (
                                index,
                              ) {
                                final topic = result.topics[index];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == result.topics.length - 1
                                        ? 0
                                        : 10,
                                  ),
                                  child: (topic.type == 'question'
                                      ? _QuestionPreviewTile.fromTopic(
                                          topic,
                                          onTap: () async {
                                            Navigator.of(context).pop();
                                            await widget.onOpenTopic(topic);
                                          },
                                        )
                                      : _ResourcePreviewTile.fromTopic(
                                          topic,
                                          onTap: () async {
                                            Navigator.of(context).pop();
                                            await widget.onOpenTopic(topic);
                                          },
                                        )),
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
                              emoji: '👥',
                              title: 'Üyeler',
                            ),
                            const SizedBox(height: 12),
                            if (result.members.isEmpty)
                              const Text(
                                'Eşleşen üye yok.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _CommunityUiTokens.textMuted,
                                ),
                              )
                            else
                              ...List<Widget>.generate(result.members.length, (
                                index,
                              ) {
                                final member = result.members[index];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == result.members.length - 1
                                        ? 0
                                        : 10,
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
              ),
          ],
        ),
      ),
    );
  }
}

class _CommunityTopicComposerPage extends StatefulWidget {
  const _CommunityTopicComposerPage({
    required this.api,
    required this.community,
    required this.initialType,
  });

  final _CommunityApiClient api;
  final _CommunitySummary community;
  final String initialType;

  @override
  State<_CommunityTopicComposerPage> createState() =>
      _CommunityTopicComposerPageState();
}

class _CommunityTopicComposerPageState
    extends State<_CommunityTopicComposerPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _tagsController = TextEditingController();
  final _eventDateController = TextEditingController();
  late String _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagsController.dispose();
    _eventDateController.dispose();
    super.dispose();
  }

  List<String> get _allowedTypes {
    final types = <String>[];
    if (widget.community.permissions.canCreateQuestion) types.add('question');
    if (widget.community.permissions.canCreateResource) types.add('resource');
    if (widget.community.permissions.canCreateEvent) types.add('event');
    return types;
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final created = await widget.api.createTopic(
        communityId: widget.community.id,
        type: _type,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        tags: _tagsController.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
        eventStartsAt: _type == 'event'
            ? _eventDateController.text.trim()
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CommunityUiTokens.background,
      appBar: AppBar(
        backgroundColor: _CommunityUiTokens.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Yeni konu'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'İçerik tipi',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _CommunityUiTokens.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allowedTypes.map((type) {
                      final selected = _type == type;
                      return _CommunityFilterChip(
                        label: _topicTypeLabel(type),
                        selected: selected,
                        onTap: () => setState(() => _type = type),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Başlık',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bodyController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Etiketler',
                      hintText: 'örn: onboarding, flutter, kariyer',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_type == 'event') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _eventDateController,
                      decoration: const InputDecoration(
                        labelText: 'Etkinlik tarihi',
                        hintText: '2026-03-20T19:30:00.000Z',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _CommunityUiTokens.text,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(_saving ? 'Bekle...' : 'Konuyu oluştur'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityJoinRequestsCard extends StatefulWidget {
  const _CommunityJoinRequestsCard({
    required this.api,
    required this.community,
    required this.onChanged,
  });

  final _CommunityApiClient api;
  final _CommunitySummary community;
  final Future<void> Function() onChanged;

  @override
  State<_CommunityJoinRequestsCard> createState() =>
      _CommunityJoinRequestsCardState();
}

class _CommunityJoinRequestsCardState
    extends State<_CommunityJoinRequestsCard> {
  late Future<List<_CommunityJoinRequestSummary>> _future;
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchJoinRequests(communityId: widget.community.id);
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.api.fetchJoinRequests(communityId: widget.community.id);
    });
    await _future;
  }

  Future<void> _approve(_CommunityJoinRequestSummary request) async {
    if (_busyIds.contains(request.id)) return;
    setState(() => _busyIds.add(request.id));
    try {
      await widget.api.approveJoinRequest(
        communityId: widget.community.id,
        requestId: request.id,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      await widget.onChanged();
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(request.id));
      }
    }
  }

  Future<void> _reject(_CommunityJoinRequestSummary request) async {
    if (_busyIds.contains(request.id)) return;
    setState(() => _busyIds.add(request.id));
    try {
      await widget.api.rejectJoinRequest(
        communityId: widget.community.id,
        requestId: request.id,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      await widget.onChanged();
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(request.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_CommunityJoinRequestSummary>>(
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
        final requests =
            snapshot.data ?? const <_CommunityJoinRequestSummary>[];
        return _SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CommunitySectionHeader(
                emoji: '🫱',
                title: 'Katılım istekleri',
              ),
              const SizedBox(height: 12),
              if (requests.isEmpty)
                const Text(
                  'Bekleyen istek yok.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _CommunityUiTokens.textMuted,
                  ),
                )
              else
                ...List<Widget>.generate(requests.length, (index) {
                  final request = requests[index];
                  final busy = _busyIds.contains(request.id);
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == requests.length - 1 ? 0 : 12,
                    ),
                    child: _SurfaceCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.requester.displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _CommunityUiTokens.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            request.requester.subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _CommunityUiTokens.textMuted,
                            ),
                          ),
                          if ((request.note ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              request.note!,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: _CommunityUiTokens.text,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonal(
                                  onPressed: busy
                                      ? null
                                      : () => _reject(request),
                                  child: const Text('Reddet'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: busy
                                      ? null
                                      : () => _approve(request),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _CommunityUiTokens.text,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(busy ? 'Bekle...' : 'Onayla'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _CommunityReportsInboxCard extends StatefulWidget {
  const _CommunityReportsInboxCard({
    required this.api,
    required this.community,
    this.onOpenTarget,
  });

  final _CommunityApiClient api;
  final _CommunitySummary community;
  final ValueChanged<_CommunityReportSummary>? onOpenTarget;

  @override
  State<_CommunityReportsInboxCard> createState() =>
      _CommunityReportsInboxCardState();
}

class _CommunityReportsInboxCardState
    extends State<_CommunityReportsInboxCard> {
  late Future<List<_CommunityReportSummary>> _future;
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchReports(communityId: widget.community.id);
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.api.fetchReports(communityId: widget.community.id);
    });
    await _future;
  }

  Future<void> _updateStatus(_CommunityReportSummary report) async {
    final nextStatus = await _showCommunityReportStatusPicker(
      context,
      currentStatus: report.status,
    );
    if (nextStatus == null || _busyIds.contains(report.id)) return;
    setState(() => _busyIds.add(report.id));
    try {
      await widget.api.setReportStatus(
        communityId: widget.community.id,
        reportId: report.id,
        status: nextStatus,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rapor ${_communityReportStatusLabel(nextStatus).toLowerCase()} olarak guncellendi.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(report.id));
      }
    }
  }

  Future<void> _openDetail(_CommunityReportSummary report) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final detailText = (report.details ?? '').trim();
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Report detayi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CommunityChip(
                      label: 'Sebep: ${report.reasonCode.toUpperCase()}',
                    ),
                    _CommunityChip(
                      label: _communityReportStatusLabel(report.status),
                    ),
                    _CommunityChip(
                      label: _formatCommunityDate(report.createdAt),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Raporlayan: ${report.reporter.displayName}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                if (report.reportedUser != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Hedef: ${report.reportedUser!.displayName}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ),
                ],
                if (report.channel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '#${report.channel!.name}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ),
                ],
                if (report.message != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Hedef mesaj',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    color: _CommunityUiTokens.surfaceSoft,
                    child: _CommunityMessageBubble(
                      message: report.message!,
                      mine: false,
                      dense: true,
                      showCreatedAt: true,
                    ),
                  ),
                ],
                if (detailText.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Rapor aciklamasi',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    color: _CommunityUiTokens.surfaceSoft,
                    child: Text(
                      detailText,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: _CommunityUiTokens.text,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _updateStatus(report);
                        },
                        child: const Text('Durumu guncelle'),
                      ),
                    ),
                    if (widget.onOpenTarget != null &&
                        report.message != null &&
                        report.channel != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            widget.onOpenTarget!(report);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _CommunityUiTokens.text,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Mesaja git'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_CommunityReportSummary>>(
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
        final reports = snapshot.data ?? const <_CommunityReportSummary>[];
        return _SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CommunitySectionHeader(emoji: '🚨', title: 'Report inbox'),
              const SizedBox(height: 12),
              if (reports.isEmpty)
                const Text(
                  'Aktif community raporu yok.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _CommunityUiTokens.textMuted,
                  ),
                )
              else
                ...List<Widget>.generate(reports.length, (index) {
                  final report = reports[index];
                  final busy = _busyIds.contains(report.id);
                  final detailText = (report.details ?? '').trim();
                  final messageText =
                      (report.message?.text ?? '').trim().isNotEmpty
                      ? report.message!.text!.trim()
                      : null;
                  final snippet =
                      messageText ??
                      (report.message == null
                          ? null
                          : 'Mesaj ek ya da kisa icerikten olusuyor.');
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == reports.length - 1 ? 0 : 12,
                    ),
                    child: _SurfaceCard(
                      padding: const EdgeInsets.all(14),
                      color: _CommunityUiTokens.surfaceSoft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _CommunityChip(
                                      label:
                                          'Sebep: ${report.reasonCode.toUpperCase()}',
                                    ),
                                    _CommunityChip(
                                      label: _communityReportStatusLabel(
                                        report.status,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: () => _openDetail(report),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: _CommunityUiTokens.text,
                                ),
                                child: const Text('Detay'),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.tonal(
                                onPressed: busy
                                    ? null
                                    : () => _updateStatus(report),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(busy ? '...' : 'Durum'),
                              ),
                            ],
                          ),
                          if (widget.onOpenTarget != null) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => widget.onOpenTarget!(report),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: _CommunityUiTokens.text,
                              ),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                              ),
                              label: const Text('Mesaja git'),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            'Raporlayan: ${report.reporter.displayName}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _CommunityUiTokens.text,
                            ),
                          ),
                          if (report.reportedUser != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Hedef: ${report.reportedUser!.displayName}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _CommunityUiTokens.textMuted,
                              ),
                            ),
                          ],
                          if (report.channel != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '#${report.channel!.name}  •  ${_formatCommunityDate(report.createdAt)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _CommunityUiTokens.textMuted,
                              ),
                            ),
                          ],
                          if (snippet != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              snippet,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: _CommunityUiTokens.text,
                              ),
                            ),
                          ],
                          if (detailText.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              detailText,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: _CommunityUiTokens.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _CommunityPinnedMessagesCard extends StatelessWidget {
  const _CommunityPinnedMessagesCard({
    required this.items,
    required this.onOpenMessage,
  });

  final List<_CommunityPinnedMessageSummary> items;
  final ValueChanged<_CommunityPinnedMessageSummary> onOpenMessage;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CommunitySectionHeader(emoji: '📌', title: 'Sabit mesajlar'),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text(
              'Henüz sabitlenmiş mesaj yok.',
              style: TextStyle(
                fontSize: 13,
                color: _CommunityUiTokens.textMuted,
              ),
            )
          else
            ...List<Widget>.generate(items.length, (index) {
              final item = items[index];
              final preview = (item.message.text ?? '').trim().isNotEmpty
                  ? item.message.text!.trim()
                  : 'Medya veya kisa mesaj';
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == items.length - 1 ? 0 : 10,
                ),
                child: InkWell(
                  onTap: () => onOpenMessage(item),
                  borderRadius: BorderRadius.circular(18),
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _CommunityUiTokens.surfaceSoft,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _CommunityUiTokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#${item.channel.name}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: _CommunityUiTokens.text,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatCommunityDate(item.message.createdAt),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: _CommunityUiTokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: _CommunityUiTokens.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.message.author.displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _CommunityUiTokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
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
    this.badges = const <String>[],
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.onMore,
    this.showChevron = true,
  });

  final String emoji;
  final String name;
  final String role;
  final String subtitle;
  final List<String> badges;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final VoidCallback? onMore;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final hasActions =
        (primaryActionLabel ?? '').trim().isNotEmpty ||
        (secondaryActionLabel ?? '').trim().isNotEmpty;
    return _SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
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
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: badges
                            .map((item) => _CommunityChip(label: item))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (onMore != null)
                IconButton(
                  onPressed: onMore,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.more_horiz_rounded),
                  color: _CommunityUiTokens.textMuted,
                )
              else if (showChevron)
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: _CommunityUiTokens.textMuted,
                ),
            ],
          ),
          if (hasActions) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if ((primaryActionLabel ?? '').trim().isNotEmpty)
                  FilledButton.tonal(
                    onPressed: onPrimaryAction,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: _CommunityUiTokens.text,
                      backgroundColor: _CommunityUiTokens.surfaceSoft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    child: Text(primaryActionLabel!),
                  ),
                if ((secondaryActionLabel ?? '').trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onSecondaryAction,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: _CommunityUiTokens.textMuted,
                    ),
                    child: Text(secondaryActionLabel!),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CommunityDmRequestsCard extends StatelessWidget {
  const _CommunityDmRequestsCard({
    required this.feed,
    required this.onAccept,
    required this.onReject,
  });

  final _CommunityDmRequestFeed feed;
  final ValueChanged<_CommunityDmRequestSummary> onAccept;
  final ValueChanged<_CommunityDmRequestSummary> onReject;

  @override
  Widget build(BuildContext context) {
    final hasContent = feed.incoming.isNotEmpty || feed.sent.isNotEmpty;
    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CommunitySectionHeader(emoji: '🤝', title: 'DM istekleri'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CommunityChip(label: 'Gelen ${feed.incoming.length}'),
              _CommunityChip(label: 'Giden ${feed.sent.length}'),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasContent)
            const Text(
              'Bekleyen DM istegi yok. Uye kartlarindan yeni istek baslatabilirsin.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _CommunityUiTokens.textMuted,
              ),
            )
          else ...[
            if (feed.incoming.isNotEmpty) ...[
              const Text(
                'Gelen',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _CommunityUiTokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ...List<Widget>.generate(feed.incoming.length, (index) {
                final request = feed.incoming[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == feed.incoming.length - 1 ? 0 : 10,
                  ),
                  child: _SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    color: _CommunityUiTokens.surfaceSoft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.requester.displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _CommunityUiTokens.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request.requester.subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _CommunityUiTokens.textMuted,
                          ),
                        ),
                        if ((request.note ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            request.note!.trim(),
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: _CommunityUiTokens.text,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton.tonal(
                              onPressed: () => onAccept(request),
                              style: FilledButton.styleFrom(
                                backgroundColor: _CommunityUiTokens.surfaceSoft,
                                foregroundColor: _CommunityUiTokens.text,
                              ),
                              child: const Text('Kabul et'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => onReject(request),
                              child: const Text('Reddet'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            if (feed.sent.isNotEmpty) ...[
              if (feed.incoming.isNotEmpty) const SizedBox(height: 14),
              const Text(
                'Gonderdiklerin',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _CommunityUiTokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ...List<Widget>.generate(feed.sent.length, (index) {
                final request = feed.sent[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == feed.sent.length - 1 ? 0 : 10,
                  ),
                  child: _SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    color: _CommunityUiTokens.surfaceSoft,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.target.displayName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _CommunityUiTokens.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                request.target.subtitle,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _CommunityUiTokens.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const _CommunityChip(label: 'Bekliyor'),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

class _CommunityInviteHistoryCard extends StatelessWidget {
  const _CommunityInviteHistoryCard({
    required this.invites,
    required this.pendingInvites,
    required this.historyInvites,
  });

  final List<_CommunityInviteSummary> invites;
  final List<_CommunityInviteSummary> pendingInvites;
  final List<_CommunityInviteSummary> historyInvites;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CommunitySectionHeader(emoji: '✉️', title: 'Davet gecmisi'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CommunityChip(label: 'Toplam ${invites.length}'),
              _CommunityChip(label: 'Bekleyen ${pendingInvites.length}'),
              _CommunityChip(label: 'Gecmis ${historyInvites.length}'),
            ],
          ),
          const SizedBox(height: 12),
          if (invites.isEmpty)
            const Text(
              'Gonderilmis community daveti yok.',
              style: TextStyle(
                fontSize: 13,
                color: _CommunityUiTokens.textMuted,
              ),
            )
          else ...[
            if (pendingInvites.isNotEmpty) ...[
              const Text(
                'Bekleyen',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _CommunityUiTokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ...List<Widget>.generate(pendingInvites.length, (index) {
                final invite = pendingInvites[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == pendingInvites.length - 1 ? 0 : 10,
                  ),
                  child: _CommunityInviteListTile(invite: invite),
                );
              }),
            ],
            if (historyInvites.isNotEmpty) ...[
              if (pendingInvites.isNotEmpty) const SizedBox(height: 14),
              const Text(
                'Son durumlar',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _CommunityUiTokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ...List<Widget>.generate(historyInvites.length, (index) {
                final invite = historyInvites[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == historyInvites.length - 1 ? 0 : 10,
                  ),
                  child: _CommunityInviteListTile(invite: invite),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

class _CommunityInviteListTile extends StatelessWidget {
  const _CommunityInviteListTile({required this.invite});

  final _CommunityInviteSummary invite;

  @override
  Widget build(BuildContext context) {
    final note = (invite.note ?? '').trim();
    final username = (invite.invitedUser.username ?? '').trim();
    final dateLabel = invite.status == 'pending'
        ? _formatCommunityDate(invite.createdAt)
        : _formatCommunityDate(invite.respondedAt ?? invite.createdAt);
    return _SurfaceCard(
      padding: const EdgeInsets.all(14),
      color: _CommunityUiTokens.surfaceSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invite.invitedUser.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _CommunityChip(label: _communityInviteStatusLabel(invite.status)),
            ],
          ),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '@$username',
              style: const TextStyle(
                fontSize: 12.5,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Olusturma: $dateLabel',
            style: const TextStyle(
              fontSize: 12,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: _CommunityUiTokens.text,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommunityBannedMembersCard extends StatelessWidget {
  const _CommunityBannedMembersCard({
    required this.items,
    required this.onUnban,
  });

  final List<_CommunityBanSummary> items;
  final ValueChanged<_CommunityBanSummary> onUnban;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CommunitySectionHeader(emoji: '⛔', title: 'Aktif banlar'),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text(
              'Aktif community ban kaydi yok.',
              style: TextStyle(
                fontSize: 13,
                color: _CommunityUiTokens.textMuted,
              ),
            )
          else
            ...List<Widget>.generate(items.length, (index) {
              final item = items[index];
              final reason = (item.reason ?? '').trim();
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == items.length - 1 ? 0 : 10,
                ),
                child: _SurfaceCard(
                  padding: const EdgeInsets.all(14),
                  color: _CommunityUiTokens.surfaceSoft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.user.displayName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _CommunityUiTokens.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.user.subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _CommunityUiTokens.textMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ban: ${_formatCommunityDate(item.createdAt)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _CommunityUiTokens.textMuted,
                              ),
                            ),
                            if (reason.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                reason,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: _CommunityUiTokens.text,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonal(
                        onPressed: () => onUnban(item),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _CommunityUiTokens.text,
                        ),
                        child: const Text('Ban kaldir'),
                      ),
                    ],
                  ),
                ),
              );
            }),
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
    this.highlightMentions = false,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool highlightMentions;

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
                _CommunityTextWithMentions(
                  text: title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                  mentionBackgroundColor: highlightMentions
                      ? _CommunityUiTokens.success.withValues(alpha: 0.14)
                      : null,
                  mentionColor: _CommunityUiTokens.text,
                ),
                const SizedBox(height: 4),
                _CommunityTextWithMentions(
                  text: subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _CommunityUiTokens.textMuted,
                  ),
                  mentionBackgroundColor: highlightMentions
                      ? _CommunityUiTokens.success.withValues(alpha: 0.12)
                      : null,
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
            _CommunityTextWithMentions(
              text: reply.body,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _CommunityUiTokens.text,
              ),
              mentionBackgroundColor: _CommunityUiTokens.success.withValues(
                alpha: 0.12,
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
    this.onAddReaction,
    this.onToggleReaction,
    this.onMore,
    this.dense = false,
    this.showReplyPreview = true,
    this.showCreatedAt = false,
    this.highlighted = false,
  });

  final _CommunityMessageSummary message;
  final bool mine;
  final VoidCallback? onReply;
  final VoidCallback? onTap;
  final VoidCallback? onAddReaction;
  final ValueChanged<String>? onToggleReaction;
  final VoidCallback? onMore;
  final bool dense;
  final bool showReplyPreview;
  final bool showCreatedAt;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final alignment = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = mine ? _CommunityUiTokens.text : Colors.white;
    final textColor = mine ? Colors.white : _CommunityUiTokens.text;
    final bubblePadding = dense ? 11.0 : 14.0;
    final authorSpacing = dense ? 3.0 : 6.0;
    final bodyFontSize = dense ? 13.5 : 14.0;
    final pinColor = mine ? Colors.white70 : _CommunityUiTokens.textMuted;
    final decorationBorderColor = highlighted
        ? _CommunityUiTokens.success
        : _CommunityUiTokens.border;
    final decorationShadow = highlighted
        ? <BoxShadow>[
            BoxShadow(
              color: _CommunityUiTokens.success.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ]
        : const <BoxShadow>[];
    final hasActionRow =
        onReply != null ||
        onAddReaction != null ||
        onMore != null ||
        (message.replyCount > 0 && onTap != null);
    final metaChildren = <Widget>[
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
      if (showCreatedAt) ...[
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
      if (message.isPinned) ...[
        const SizedBox(width: 8),
        Icon(Icons.push_pin_rounded, size: 13, color: pinColor),
        const SizedBox(width: 4),
        Text(
          'Sabit',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: pinColor,
          ),
        ),
      ],
    ];
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: metaChildren),
        SizedBox(height: authorSpacing),
        GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(maxWidth: dense ? 340 : 320),
            padding: EdgeInsets.all(bubblePadding),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(dense ? 18 : 20),
              border: Border.all(color: decorationBorderColor, width: 1.2),
              boxShadow: decorationShadow,
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
                if (message.attachments.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: (message.text ?? '').trim().isNotEmpty
                          ? (dense ? 10 : 12)
                          : 0,
                    ),
                    child: _CommunityAttachmentList(
                      attachments: message.attachments,
                      dense: dense,
                      mine: mine,
                    ),
                  ),
                if ((message.text ?? '').trim().isNotEmpty)
                  _CommunityTextWithMentions(
                    text: message.text!.trim(),
                    style: TextStyle(
                      fontSize: bodyFontSize,
                      height: 1.42,
                      color: textColor,
                    ),
                    mentionColor: textColor,
                    mentionBackgroundColor: mine
                        ? Colors.white.withValues(alpha: 0.14)
                        : _CommunityUiTokens.success.withValues(alpha: 0.14),
                  ),
              ],
            ),
          ),
        ),
        if (message.reactions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: message.reactions.map((reaction) {
                return _CommunityReactionChip(
                  reaction: reaction,
                  onTap: onToggleReaction == null
                      ? null
                      : () => onToggleReaction!(reaction.emoji),
                );
              }).toList(),
            ),
          ),
        ],
        if (hasActionRow) ...[
          const SizedBox(height: 6),
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (onAddReaction != null)
                  _CommunityActionChip(
                    icon: Icons.add_reaction_outlined,
                    label: 'React',
                    onTap: onAddReaction!,
                  ),
                if (message.replyCount > 0 && onTap != null) ...[
                  InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: _CommunityUiTokens.surfaceSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _CommunityUiTokens.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.forum_outlined,
                              size: 15,
                              color: _CommunityUiTokens.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${message.replyCount} yanıt',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _CommunityUiTokens.text,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: _CommunityUiTokens.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (onMore != null)
                  _CommunityActionChip(
                    icon: Icons.more_horiz_rounded,
                    label: 'Daha',
                    onTap: onMore!,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CommunityReactionChip extends StatelessWidget {
  const _CommunityReactionChip({required this.reaction, this.onTap});

  final _CommunityReactionSummary reaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = reaction.reacted
        ? _CommunityUiTokens.surfaceSoft
        : Colors.white;
    final borderColor = reaction.reacted
        ? _CommunityUiTokens.textMuted
        : _CommunityUiTokens.border;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          '${reaction.emoji} ${reaction.count}',
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

class _CommunityActionChip extends StatelessWidget {
  const _CommunityActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _CommunityUiTokens.surfaceSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _CommunityUiTokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: _CommunityUiTokens.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityAttachmentList extends StatelessWidget {
  const _CommunityAttachmentList({
    required this.attachments,
    required this.dense,
    required this.mine,
  });

  final List<_CommunityMessageAttachmentSummary> attachments;
  final bool dense;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: attachments.map((attachment) {
        final child = attachment.isImage
            ? _CommunityImageAttachmentCard(
                attachment: attachment,
                dense: dense,
              )
            : _CommunityFileAttachmentCard(attachment: attachment, mine: mine);
        return Padding(
          padding: EdgeInsets.only(
            bottom: attachment == attachments.last ? 0 : 8,
          ),
          child: child,
        );
      }).toList(),
    );
  }
}

class _CommunityImageAttachmentCard extends StatelessWidget {
  const _CommunityImageAttachmentCard({
    required this.attachment,
    required this.dense,
  });

  final _CommunityMessageAttachmentSummary attachment;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final imageUrl = (attachment.url ?? '').trim();
    final aspectRatio =
        attachment.width != null &&
            attachment.height != null &&
            attachment.width! > 0 &&
            attachment.height! > 0
        ? attachment.width! / attachment.height!
        : 1.1;
    final effectiveAspectRatio = dense
        ? aspectRatio.clamp(0.85, 1.6).toDouble()
        : aspectRatio.clamp(0.7, 1.5).toDouble();
    return InkWell(
      onTap: imageUrl.isEmpty
          ? null
          : () => _openCommunityAttachment(context, attachment),
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: effectiveAspectRatio,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _CommunityUiTokens.surfaceSoft,
              border: Border.all(color: _CommunityUiTokens.border),
            ),
            child: imageUrl.isEmpty
                ? const Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: _CommunityUiTokens.textMuted,
                    ),
                  )
                : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: _CommunityUiTokens.textMuted,
                      ),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _CommunityFileAttachmentCard extends StatelessWidget {
  const _CommunityFileAttachmentCard({
    required this.attachment,
    required this.mine,
  });

  final _CommunityMessageAttachmentSummary attachment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final background = mine
        ? Colors.white.withValues(alpha: 0.12)
        : _CommunityUiTokens.surfaceSoft;
    final foreground = mine ? Colors.white : _CommunityUiTokens.text;
    final subForeground = mine ? Colors.white70 : _CommunityUiTokens.textMuted;
    return InkWell(
      onTap: () => _openCommunityAttachment(context, attachment),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: mine
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                attachment.isVideo
                    ? Icons.smart_display_outlined
                    : Icons.insert_drive_file_outlined,
                color: foreground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.fileName?.trim().isNotEmpty == true
                        ? attachment.fileName!.trim()
                        : (attachment.isVideo ? 'Video' : 'Dosya'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    attachment.isVideo
                        ? 'Video • ${_formatCommunityFileSize(attachment.sizeBytes)}'
                        : _formatCommunityFileSize(attachment.sizeBytes),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: subForeground,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 16, color: subForeground),
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

final RegExp _kCommunityMentionPattern = RegExp(
  r'(^|[\s(])@([a-zA-Z0-9_]{3,32})\b',
);
final RegExp _kCommunityMentionDraftPattern = RegExp(
  r'(^|[\s(])@([a-zA-Z0-9_]{0,32})$',
);

class _CommunityMentionQuery {
  const _CommunityMentionQuery({
    required this.query,
    required this.start,
    required this.end,
  });

  final String query;
  final int start;
  final int end;
}

class _CommunityTextWithMentions extends StatelessWidget {
  const _CommunityTextWithMentions({
    required this.text,
    required this.style,
    this.mentionColor,
    this.mentionBackgroundColor,
  });

  final String text;
  final TextStyle style;
  final Color? mentionColor;
  final Color? mentionBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      _buildCommunityMentionText(
        text,
        style: style,
        mentionColor: mentionColor,
        mentionBackgroundColor: mentionBackgroundColor,
      ),
    );
  }
}

class _CommunityMentionSuggestionsCard extends StatelessWidget {
  const _CommunityMentionSuggestionsCard({
    required this.items,
    required this.loading,
    required this.onSelect,
  });

  final List<_CommunityMemberSummary> items;
  final bool loading;
  final ValueChanged<_CommunityMemberSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    if (!loading && items.isEmpty) {
      return const SizedBox.shrink();
    }
    return _SurfaceCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '@ mention',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _CommunityUiTokens.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ...List<Widget>.generate(items.length, (index) {
              final item = items[index];
              final username = item.user.username?.trim() ?? '';
              return InkWell(
                onTap: username.isEmpty ? null : () => onSelect(item),
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _CommunityUiTokens.surfaceSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          item.user.displayName.trim().isNotEmpty
                              ? item.user.displayName.trim()[0].toUpperCase()
                              : '@',
                          style: const TextStyle(
                            fontSize: 15,
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
                              item.user.displayName,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _CommunityUiTokens.text,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '@$username',
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
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CommunitySearchField extends StatelessWidget {
  const _CommunitySearchField({
    this.controller,
    this.onChanged,
    this.hintText = 'Topluluk, konu veya kişi ara',
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _CommunityUiTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: _CommunityUiTokens.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: InputBorder.none,
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: _CommunityUiTokens.textMuted,
                  ),
                ),
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

class _CommunityFilterChip extends StatelessWidget {
  const _CommunityFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(_CommunityUiTokens.chipRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? _CommunityUiTokens.text
              : _CommunityUiTokens.surfaceSoft,
          borderRadius: BorderRadius.circular(_CommunityUiTokens.chipRadius),
          border: Border.all(color: _CommunityUiTokens.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : _CommunityUiTokens.text,
          ),
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    required this.padding,
    this.color = _CommunityUiTokens.surface,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
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
    attachments: message.attachments,
    isPinned: message.isPinned,
    reactions: message.reactions,
    replyCount: replyCount ?? message.replyCount,
    replyToMessageId: message.replyToMessageId,
    replyAuthorName: message.replyAuthorName,
    replyPreview: message.replyPreview,
  );
}

TextSpan _buildCommunityMentionText(
  String rawText, {
  required TextStyle style,
  Color? mentionColor,
  Color? mentionBackgroundColor,
}) {
  final text = rawText.trim();
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in _kCommunityMentionPattern.allMatches(text)) {
    final username = match.group(2)?.trim();
    if (username == null || username.isEmpty) continue;
    final mentionStart = match.start + (match.group(1)?.length ?? 0);
    if (mentionStart > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, mentionStart), style: style),
      );
    }
    spans.add(
      TextSpan(
        text: '@$username',
        style: style.copyWith(
          fontWeight: FontWeight.w700,
          color: mentionColor ?? style.color,
          backgroundColor: mentionBackgroundColor,
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: style));
  }
  if (spans.isEmpty) {
    spans.add(TextSpan(text: text, style: style));
  }
  return TextSpan(style: style, children: spans);
}

_CommunityMentionQuery? _extractCommunityMentionQuery(TextEditingValue value) {
  final text = value.text;
  if (text.trim().isEmpty) return null;
  final caret = value.selection.baseOffset >= 0
      ? value.selection.baseOffset
      : text.length;
  if (caret < 0 || caret > text.length) return null;
  final prefix = text.substring(0, caret);
  final match = _kCommunityMentionDraftPattern.firstMatch(prefix);
  if (match == null) return null;
  final query = (match.group(2) ?? '').trim();
  final start = prefix.length - query.length - 1;
  if (start < 0) return null;
  return _CommunityMentionQuery(
    query: query.toLowerCase(),
    start: start,
    end: caret,
  );
}

String _labelForVisibility(String value) {
  switch (value) {
    case 'request_only':
      return 'Onaylı katılım';
    case 'invite_only':
      return 'Davet ile';
    default:
      return 'Açık katılım';
  }
}

String _emojiForVisibility(String value) {
  switch (value) {
    case 'request_only':
      return '🫱';
    case 'invite_only':
      return '✉️';
    default:
      return '🔓';
  }
}

String _communityReportStatusLabel(String value) {
  switch (value) {
    case 'under_review':
      return 'Incelemede';
    case 'actioned':
      return 'Aksiyon alindi';
    case 'rejected':
      return 'Reddedildi';
    case 'resolved':
      return 'Kapandi';
    default:
      return 'Acik';
  }
}

String _communityInviteStatusLabel(String value) {
  switch (value) {
    case 'accepted':
      return 'Kabul edildi';
    case 'rejected':
      return 'Reddedildi';
    default:
      return 'Bekliyor';
  }
}

int _communityRolePriority(String? role) {
  switch ((role ?? '').toLowerCase()) {
    case 'owner':
      return 0;
    case 'admin':
      return 1;
    case 'moderator':
      return 2;
    case 'mentor':
      return 3;
    default:
      return 4;
  }
}

bool _canModerateCommunityMember({
  required String? viewerRole,
  required String viewerUserId,
  required _CommunityMemberSummary target,
}) {
  final normalized = (viewerRole ?? '').toLowerCase();
  if (normalized != 'owner' &&
      normalized != 'admin' &&
      normalized != 'moderator') {
    return false;
  }
  if (viewerUserId == target.user.id) return false;
  return _communityRolePriority(viewerRole) <
      _communityRolePriority(target.role);
}

const List<String> _kCommunityReactionOptions = <String>[
  '👍',
  '❤️',
  '🔥',
  '👏',
  '😂',
];

String _communityContentTypeForFileName(String fileName) {
  final normalized = fileName.trim().toLowerCase();
  if (normalized.endsWith('.png')) return 'image/png';
  if (normalized.endsWith('.webp')) return 'image/webp';
  if (normalized.endsWith('.gif')) return 'image/gif';
  if (normalized.endsWith('.heic')) return 'image/heic';
  if (normalized.endsWith('.heif')) return 'image/heif';
  if (normalized.endsWith('.mov')) return 'video/quicktime';
  if (normalized.endsWith('.webm')) return 'video/webm';
  if (normalized.endsWith('.mp4')) return 'video/mp4';
  if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (normalized.endsWith('.pdf')) return 'application/pdf';
  if (normalized.endsWith('.txt')) return 'text/plain';
  if (normalized.endsWith('.zip')) return 'application/zip';
  return 'application/octet-stream';
}

String _communityAttachmentKindForContentType(String contentType) {
  if (contentType.startsWith('image/')) return 'image';
  if (contentType.startsWith('video/')) return 'video';
  return 'file';
}

String _formatCommunityFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return 'Dosya';
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  final formatted = value >= 100 || index == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[index]}';
}

Future<void> _openCommunityAttachment(
  BuildContext context,
  _CommunityMessageAttachmentSummary attachment,
) async {
  final url = (attachment.url ?? '').trim();
  if (url.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dosya baglantisi hazir degil.')),
    );
    return;
  }

  if (attachment.isImage) {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Gorsel acilamadi.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
    return;
  }

  final launched = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Dosya acilamadi.')));
  }
}

Future<String?> _showCommunityReactionPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reaction ekle',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _CommunityUiTokens.text,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _kCommunityReactionOptions.map((emoji) {
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(emoji),
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _CommunityUiTokens.surfaceSoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _CommunityUiTokens.border),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<String?> _showCommunityReportReasonPicker(BuildContext context) {
  const options = <MapEntry<String, String>>[
    MapEntry('spam', 'Spam / alakasiz'),
    MapEntry('harassment', 'Taciz / saldiri'),
    MapEntry('unsafe', 'Guvensiz icerik'),
    MapEntry('copyright', 'Telif / izinsiz paylasim'),
  ];
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((item) {
              return ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(item.value),
                onTap: () => Navigator.of(context).pop(item.key),
              );
            }).toList(),
          ),
        ),
      );
    },
  );
}

Future<String?> _showCommunityReportStatusPicker(
  BuildContext context, {
  required String currentStatus,
}) {
  const options = <MapEntry<String, String>>[
    MapEntry('under_review', 'Incelemede'),
    MapEntry('actioned', 'Aksiyon alindi'),
    MapEntry('rejected', 'Reddedildi'),
    MapEntry('resolved', 'Kapandi'),
  ];
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((item) {
              final selected = item.key == currentStatus;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                ),
                title: Text(item.value),
                onTap: () => Navigator.of(context).pop(item.key),
              );
            }).toList(),
          ),
        ),
      );
    },
  );
}

Future<String?> _showCommunityDmRequestComposer(
  BuildContext context, {
  required _CommunityMemberSummary target,
}) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          18 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${target.user.displayName} icin DM istegi',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _CommunityUiTokens.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              target.user.subtitle,
              style: const TextStyle(
                fontSize: 12.5,
                color: _CommunityUiTokens.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Kisa bir not birakmak istersen yazabilirsin',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Vazgec'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(controller.text),
                  child: const Text('Gonder'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

Future<_CommunityUserSummary?> _showCommunityInvitePicker(
  BuildContext context, {
  required List<_CommunityUserSummary> candidates,
}) {
  var query = '';
  return showModalBottomSheet<_CommunityUserSummary>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = candidates.where((item) {
            final normalized = query.trim().toLowerCase();
            if (normalized.isEmpty) return true;
            return item.displayName.toLowerCase().contains(normalized) ||
                (item.username ?? '').toLowerCase().contains(normalized) ||
                (item.about ?? '').toLowerCase().contains(normalized);
          }).toList();
          return Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              18 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Uye davet et',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _CommunityUiTokens.text,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Isim veya username ara',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      setSheetState(() => query = value.trim()),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 360,
                  child: filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text(
                            'Eslestirilecek kisi bulunamadi.',
                            style: TextStyle(
                              fontSize: 13,
                              color: _CommunityUiTokens.textMuted,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return _SurfaceCard(
                              padding: const EdgeInsets.all(14),
                              color: _CommunityUiTokens.surfaceSoft,
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      item.displayName.trim().isNotEmpty
                                          ? item.displayName
                                                .trim()[0]
                                                .toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: _CommunityUiTokens.text,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.displayName,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: _CommunityUiTokens.text,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.about?.trim().isNotEmpty == true
                                              ? item.about!.trim()
                                              : (item.username
                                                            ?.trim()
                                                            .isNotEmpty ==
                                                        true
                                                    ? '@${item.username!.trim()}'
                                                    : 'Turna kullanicisi'),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: _CommunityUiTokens.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton.tonal(
                                    onPressed: () =>
                                        Navigator.of(sheetContext).pop(item),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: _CommunityUiTokens.text,
                                    ),
                                    child: const Text('Davet et'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _joinCtaLabel(_CommunitySummary community) {
  switch (community.joinState) {
    case 'pending':
      return 'İstek gönderildi';
    case 'invited':
      return 'Daveti kabul et';
    case 'approval':
      return 'Katılım isteği gönder';
    case 'invite_only':
      return 'Davet gerekli';
    default:
      return 'Topluluğa katıl';
  }
}

String _topicTypeLabel(String type) {
  switch (type) {
    case 'resource':
      return 'Kaynak';
    case 'event':
      return 'Etkinlik';
    default:
      return 'Soru';
  }
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
