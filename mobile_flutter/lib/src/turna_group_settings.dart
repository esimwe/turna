part of '../main.dart';

class _TurnaGroupSettingsPage extends StatefulWidget {
  const _TurnaGroupSettingsPage({
    required this.session,
    required this.chatId,
    required this.detail,
    required this.members,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final TurnaChatDetail detail;
  final List<TurnaGroupMember> members;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupSettingsPage> createState() =>
      _TurnaGroupSettingsPageState();
}

class _TurnaGroupSettingsPageState extends State<_TurnaGroupSettingsPage> {
  late TurnaChatDetail _detail;
  late List<TurnaGroupMember> _members;
  bool _saving = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
    _members = widget.members;
  }

  String get _myRole => (_detail.myRole ?? '').trim().toUpperCase();
  bool get _isOwner => _myRole == 'OWNER';
  bool get _isAdmin => _myRole == 'ADMIN';
  bool get _canReviewRequests => _isOwner || _isAdmin;
  bool get _canManageModeration => _isOwner || _isAdmin || _myRole == 'EDITOR';

  void _closePage() {
    Navigator.of(context).pop(_changed);
  }

  bool _policyAllows(String policy) {
    switch (policy.trim().toUpperCase()) {
      case 'EVERYONE':
        return true;
      case 'EDITOR_ONLY':
        return _isOwner || _isAdmin || _myRole == 'EDITOR';
      case 'ADMIN_ONLY':
        return _isOwner || _isAdmin;
      default:
        return _isOwner;
    }
  }

  String _policyLabel(String policy) {
    switch (policy.trim().toUpperCase()) {
      case 'OWNER_ONLY':
        return 'Sadece sahip';
      case 'ADMIN_ONLY':
        return 'Sadece adminler';
      case 'EDITOR_ONLY':
        return 'Editör ve üstü';
      default:
        return 'Herkes';
    }
  }

  Future<void> _applySettings({
    bool? isPublic,
    bool? joinApprovalRequired,
    String? whoCanSend,
    String? whoCanEditInfo,
    String? whoCanInvite,
    String? whoCanAddMembers,
    String? whoCanStartCalls,
    bool? historyVisibleToNewMembers,
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final detail = await ChatApi.updateGroupSettings(
        widget.session,
        chatId: widget.chatId,
        isPublic: isPublic,
        joinApprovalRequired: joinApprovalRequired,
        whoCanSend: whoCanSend,
        whoCanEditInfo: whoCanEditInfo,
        whoCanInvite: whoCanInvite,
        whoCanAddMembers: whoCanAddMembers,
        whoCanStartCalls: whoCanStartCalls,
        historyVisibleToNewMembers: historyVisibleToNewMembers,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _saving = false;
        _changed = true;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _pickPrivacyMode() async {
    final value = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  _detail.isPublic
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: const Text('Açık grup'),
                subtitle: const Text('Bağlantı veya katılım isteği ile büyür.'),
                onTap: () => Navigator.of(context).pop(true),
              ),
              ListTile(
                leading: Icon(
                  !_detail.isPublic
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: const Text('Özel grup'),
                subtitle: const Text(
                  'Sadece davet bağlantısı veya doğrudan ekleme ile girilir.',
                ),
                onTap: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (value == null || value == _detail.isPublic) return;
    await _applySettings(
      isPublic: value,
      joinApprovalRequired: value ? _detail.joinApprovalRequired : false,
    );
  }

  Future<void> _openInviteLinks() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupInviteLinksPage(
          session: widget.session,
          chatId: widget.chatId,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() => _changed = true);
    }
  }

  Future<void> _openJoinRequests() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupJoinRequestsPage(
          session: widget.session,
          chatId: widget.chatId,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() => _changed = true);
    }
  }

  Future<void> _openMuteList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupMuteListPage(
          session: widget.session,
          chatId: widget.chatId,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _openBanList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TurnaGroupBanListPage(
          session: widget.session,
          chatId: widget.chatId,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _pickPolicy({
    required String title,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        const options = <String>[
          'OWNER_ONLY',
          'ADMIN_ONLY',
          'EDITOR_ONLY',
          'EVERYONE',
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              for (final option in options)
                ListTile(
                  leading: Icon(
                    currentValue.trim().toUpperCase() == option
                        ? Icons.check_circle_rounded
                        : Icons.tune_rounded,
                  ),
                  title: Text(_policyLabel(option)),
                  onTap: () => Navigator.of(context).pop(option),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null || selected == currentValue.trim().toUpperCase()) {
      return;
    }
    onSelected(selected);
  }

  Future<void> _transferOwnership() async {
    if (!_isOwner || _saving) return;
    final candidates = _members
        .where((member) => member.userId != widget.session.userId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      setState(() => _error = 'Sahiplik devri için başka bir üye gerekli.');
      return;
    }

    final nextOwner = await showModalBottomSheet<TurnaGroupMember>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Text(
                  'Sahipliği devret',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (final member in candidates)
                ListTile(
                  leading: _ProfileAvatar(
                    label: member.displayName,
                    avatarUrl: member.avatarUrl,
                    authToken: widget.session.token,
                    radius: 20,
                  ),
                  title: Text(member.displayName),
                  subtitle: Text(
                    member.role.trim().toUpperCase() == 'ADMIN'
                        ? 'Admin'
                        : member.role.trim().toUpperCase() == 'EDITOR'
                        ? 'Editör'
                        : 'Üye',
                  ),
                  onTap: () => Navigator.of(context).pop(member),
                ),
            ],
          ),
        );
      },
    );
    if (nextOwner == null) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sahipliği devret'),
          content: Text(
            'Grubun sahipliğini ${nextOwner.displayName} kişisine devretmek istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Devret'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ChatApi.transferGroupOwnership(
        widget.session,
        chatId: widget.chatId,
        newOwnerUserId: nextOwner.userId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _closePage,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Grup Ayarları'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: TurnaColors.error),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TurnaColors.divider),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('Grup tipi'),
                  subtitle: Text(_detail.isPublic ? 'Açık grup' : 'Özel grup'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving ? null : _pickPrivacyMode,
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.approval_outlined),
                  title: const Text('Katılım onayı'),
                  subtitle: Text(
                    _detail.isPublic
                        ? 'Açık gruba katılmak isteyenler onay bekler.'
                        : 'Özel gruplarda yalnızca davet bağlantısı çalışır.',
                  ),
                  value: _detail.isPublic && _detail.joinApprovalRequired,
                  onChanged: !_detail.isPublic || _saving
                      ? null
                      : (value) => _applySettings(joinApprovalRequired: value),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded),
                  title: const Text('Kim mesaj gönderebilir?'),
                  subtitle: Text(_policyLabel(_detail.whoCanSend)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving
                      ? null
                      : () => _pickPolicy(
                          title: 'Kim mesaj gönderebilir?',
                          currentValue: _detail.whoCanSend,
                          onSelected: (value) =>
                              _applySettings(whoCanSend: value),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Kim grup bilgisini düzenleyebilir?'),
                  subtitle: Text(_policyLabel(_detail.whoCanEditInfo)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving
                      ? null
                      : () => _pickPolicy(
                          title: 'Kim grup bilgisini düzenleyebilir?',
                          currentValue: _detail.whoCanEditInfo,
                          onSelected: (value) =>
                              _applySettings(whoCanEditInfo: value),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Kim davet edebilir?'),
                  subtitle: Text(_policyLabel(_detail.whoCanInvite)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving
                      ? null
                      : () => _pickPolicy(
                          title: 'Kim davet edebilir?',
                          currentValue: _detail.whoCanInvite,
                          onSelected: (value) =>
                              _applySettings(whoCanInvite: value),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.call_rounded),
                  title: const Text('Kim çağrı başlatabilir?'),
                  subtitle: Text(_policyLabel(_detail.whoCanStartCalls)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving
                      ? null
                      : () => _pickPolicy(
                          title: 'Kim çağrı başlatabilir?',
                          currentValue: _detail.whoCanStartCalls,
                          onSelected: (value) =>
                              _applySettings(whoCanStartCalls: value),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: const Text('Kim üye ekleyebilir?'),
                  subtitle: Text(_policyLabel(_detail.whoCanAddMembers)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _saving
                      ? null
                      : () => _pickPolicy(
                          title: 'Kim üye ekleyebilir?',
                          currentValue: _detail.whoCanAddMembers,
                          onSelected: (value) =>
                              _applySettings(whoCanAddMembers: value),
                        ),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.history_toggle_off_rounded),
                  title: const Text('Yeni üyeler eski mesajları görsün'),
                  subtitle: Text(
                    _detail.historyVisibleToNewMembers
                        ? 'Yeni katılanlar önceki mesaj geçmişini görebilir.'
                        : 'Yeni katılanlar yalnızca katıldıktan sonraki mesajları görür.',
                  ),
                  value: _detail.historyVisibleToNewMembers,
                  onChanged: _saving
                      ? null
                      : (value) =>
                            _applySettings(historyVisibleToNewMembers: value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TurnaColors.divider),
            ),
            child: Column(
              children: [
                if (_policyAllows(_detail.whoCanInvite))
                  ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: const Text('Davet bağlantıları'),
                    subtitle: const Text(
                      '7 gün, 30 gün veya sınırsız bağlantı oluştur.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openInviteLinks,
                  ),
                if (_policyAllows(_detail.whoCanInvite))
                  const Divider(height: 1),
                if (_canReviewRequests)
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('Katılım istekleri'),
                    subtitle: const Text(
                      'Bekleyen katılım isteklerini onayla veya reddet.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openJoinRequests,
                  ),
                if (_canReviewRequests) const Divider(height: 1),
                if (_canManageModeration)
                  ListTile(
                    leading: const Icon(Icons.volume_off_outlined),
                    title: const Text('Sessize alınanlar'),
                    subtitle: const Text('Aktif mute listesini gör ve yönet.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openMuteList,
                  ),
                if (_canManageModeration) const Divider(height: 1),
                if (_isOwner || _isAdmin)
                  ListTile(
                    leading: const Icon(Icons.gpp_bad_outlined),
                    title: const Text('Yasaklananlar'),
                    subtitle: const Text('Ban listesini gör ve yasak kaldır.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openBanList,
                  ),
              ],
            ),
          ),
          if (_isOwner) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _transferOwnership,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Sahipliği Devret'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TurnaGroupInviteLinksPage extends StatefulWidget {
  const _TurnaGroupInviteLinksPage({
    required this.session,
    required this.chatId,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupInviteLinksPage> createState() =>
      _TurnaGroupInviteLinksPageState();
}

class _TurnaGroupInviteLinksPageState
    extends State<_TurnaGroupInviteLinksPage> {
  List<TurnaGroupInviteLink> _items = const <TurnaGroupInviteLink>[];
  bool _loading = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  void _closePage() => Navigator.of(context).pop(_changed);

  String _formatInviteExpiry(TurnaGroupInviteLink item) {
    if ((item.revokedAt ?? '').trim().isNotEmpty) return 'İptal edildi';
    if ((item.expiresAt ?? '').trim().isEmpty) return 'Sınırsız';
    final dt = parseTurnaLocalDateTime(item.expiresAt!);
    if (dt == null) return 'Süre bilgisi yok';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatApi.fetchGroupInviteLinks(
        widget.session,
        chatId: widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _createInvite() async {
    final duration = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('7 Gün'),
                onTap: () => Navigator.of(context).pop('7_DAYS'),
              ),
              ListTile(
                leading: const Icon(Icons.date_range_outlined),
                title: const Text('30 Gün'),
                onTap: () => Navigator.of(context).pop('30_DAYS'),
              ),
              ListTile(
                leading: const Icon(Icons.all_inclusive_rounded),
                title: const Text('Sınırsız'),
                onTap: () => Navigator.of(context).pop('UNLIMITED'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (duration == null) return;
    try {
      final created = await ChatApi.createGroupInviteLink(
        widget.session,
        chatId: widget.chatId,
        duration: duration,
      );
      if (!mounted) return;
      setState(() {
        _items = [created, ..._items];
        _changed = true;
      });
      await Clipboard.setData(ClipboardData(text: created.inviteUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Davet bağlantısı kopyalandı.')),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _revokeInvite(TurnaGroupInviteLink item) async {
    try {
      await ChatApi.revokeGroupInviteLink(
        widget.session,
        chatId: widget.chatId,
        inviteLinkId: item.id,
      );
      if (!mounted) return;
      setState(() {
        _items = _items
            .map(
              (entry) => entry.id == item.id
                  ? TurnaGroupInviteLink(
                      id: entry.id,
                      token: entry.token,
                      inviteUrl: entry.inviteUrl,
                      expiresAt: entry.expiresAt,
                      revokedAt: DateTime.now().toIso8601String(),
                      createdAt: entry.createdAt,
                    )
                  : entry,
            )
            .toList(growable: false);
        _changed = true;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _closePage,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Davet Bağlantıları'),
        actions: [
          IconButton(
            onPressed: _createInvite,
            icon: const Icon(Icons.add_link_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: TurnaColors.error),
                    ),
                  ),
                ..._items.map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TurnaColors.divider),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.link_rounded),
                      title: Text(
                        item.inviteUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_formatInviteExpiry(item)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          final messenger = ScaffoldMessenger.of(context);
                          if (value == 'copy') {
                            await Clipboard.setData(
                              ClipboardData(text: item.inviteUrl),
                            );
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Bağlantı kopyalandı.'),
                              ),
                            );
                            return;
                          }
                          if (value == 'revoke') {
                            await _revokeInvite(item);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'copy',
                            child: Text('Kopyala'),
                          ),
                          if ((item.revokedAt ?? '').trim().isEmpty)
                            const PopupMenuItem(
                              value: 'revoke',
                              child: Text('İptal et'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'Henüz davet bağlantısı oluşturulmadı.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TurnaGroupJoinRequestsPage extends StatefulWidget {
  const _TurnaGroupJoinRequestsPage({
    required this.session,
    required this.chatId,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupJoinRequestsPage> createState() =>
      _TurnaGroupJoinRequestsPageState();
}

class _TurnaGroupJoinRequestsPageState
    extends State<_TurnaGroupJoinRequestsPage> {
  List<TurnaGroupJoinRequest> _items = const <TurnaGroupJoinRequest>[];
  bool _loading = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  void _closePage() => Navigator.of(context).pop(_changed);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatApi.fetchGroupJoinRequests(
        widget.session,
        chatId: widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _approve(TurnaGroupJoinRequest request) async {
    try {
      await ChatApi.approveGroupJoinRequest(
        widget.session,
        chatId: widget.chatId,
        requestId: request.id,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.where((item) => item.id != request.id).toList();
        _changed = true;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _reject(TurnaGroupJoinRequest request) async {
    try {
      await ChatApi.rejectGroupJoinRequest(
        widget.session,
        chatId: widget.chatId,
        requestId: request.id,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.where((item) => item.id != request.id).toList();
        _changed = true;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _closePage,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Katılım İstekleri'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: TurnaColors.error),
                    ),
                  ),
                ..._items.map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TurnaColors.divider),
                    ),
                    child: Row(
                      children: [
                        _ProfileAvatar(
                          label: item.displayName,
                          avatarUrl: item.avatarUrl,
                          authToken: widget.session.token,
                          radius: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if ((item.username ?? '').trim().isNotEmpty)
                                Text(
                                  '@${item.username!.trim()}',
                                  style: const TextStyle(
                                    color: TurnaColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _reject(item),
                          child: const Text('Reddet'),
                        ),
                        FilledButton(
                          onPressed: () => _approve(item),
                          child: const Text('Onayla'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'Bekleyen katılım isteği yok.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TurnaGroupMuteListPage extends StatefulWidget {
  const _TurnaGroupMuteListPage({
    required this.session,
    required this.chatId,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupMuteListPage> createState() =>
      _TurnaGroupMuteListPageState();
}

class _TurnaGroupMuteListPageState extends State<_TurnaGroupMuteListPage> {
  List<TurnaGroupMuteEntry> _items = const <TurnaGroupMuteEntry>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatApi.fetchGroupMutes(
        widget.session,
        chatId: widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _unmute(TurnaGroupMuteEntry entry) async {
    try {
      await ChatApi.unmuteGroupMember(
        widget.session,
        chatId: widget.chatId,
        memberUserId: entry.userId,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.where((item) => item.id != entry.id).toList();
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessize Alınanlar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: TurnaColors.error),
                    ),
                  ),
                ..._items.map(
                  (item) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 4,
                    ),
                    leading: _ProfileAvatar(
                      label: item.displayName,
                      avatarUrl: item.avatarUrl,
                      authToken: widget.session.token,
                      radius: 22,
                    ),
                    title: Text(item.displayName),
                    subtitle: Text(
                      (item.mutedUntil ?? '').trim().isEmpty
                          ? 'Kalıcı sessizde'
                          : 'Süre: ${item.mutedUntil}',
                    ),
                    trailing: TextButton(
                      onPressed: () => _unmute(item),
                      child: const Text('Kaldır'),
                    ),
                  ),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'Aktif mute kaydı yok.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TurnaGroupBanListPage extends StatefulWidget {
  const _TurnaGroupBanListPage({
    required this.session,
    required this.chatId,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaGroupBanListPage> createState() => _TurnaGroupBanListPageState();
}

class _TurnaGroupBanListPageState extends State<_TurnaGroupBanListPage> {
  List<TurnaGroupBanEntry> _items = const <TurnaGroupBanEntry>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatApi.fetchGroupBans(
        widget.session,
        chatId: widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _unban(TurnaGroupBanEntry entry) async {
    try {
      await ChatApi.unbanGroupMember(
        widget.session,
        chatId: widget.chatId,
        memberUserId: entry.userId,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.where((item) => item.id != entry.id).toList();
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yasaklananlar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: TurnaColors.error),
                    ),
                  ),
                ..._items.map(
                  (item) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 4,
                    ),
                    leading: _ProfileAvatar(
                      label: item.displayName,
                      avatarUrl: item.avatarUrl,
                      authToken: widget.session.token,
                      radius: 22,
                    ),
                    title: Text(item.displayName),
                    subtitle: Text(
                      item.reason?.trim().isNotEmpty == true
                          ? item.reason!.trim()
                          : 'Aktif yasak',
                    ),
                    trailing: TextButton(
                      onPressed: () => _unban(item),
                      child: const Text('Kaldır'),
                    ),
                  ),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'Aktif yasak kaydı yok.',
                        style: TextStyle(color: TurnaColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TurnaAddGroupMembersPage extends StatefulWidget {
  const _TurnaAddGroupMembersPage({
    required this.session,
    required this.chatId,
    required this.existingUserIds,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String chatId;
  final Set<String> existingUserIds;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaAddGroupMembersPage> createState() =>
      _TurnaAddGroupMembersPageState();
}

class _TurnaAddGroupMembersPageState extends State<_TurnaAddGroupMembersPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedUserIds = <String>{};
  List<TurnaRegisteredContact> _registeredContacts =
      const <TurnaRegisteredContact>[];
  bool _loading = true;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadContacts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TurnaRegisteredContact> get _filteredContacts {
    final query = _searchController.text.trim().toLowerCase();
    final contacts = _registeredContacts
        .where(
          (contact) =>
              contact.id != widget.session.userId &&
              !widget.existingUserIds.contains(contact.id),
        )
        .toList(growable: false);
    if (query.isEmpty) return contacts;
    return contacts
        .where((contact) {
          final title = contact.resolvedTitle.toLowerCase();
          final username = (contact.username ?? '').toLowerCase();
          final phone = (contact.phone ?? '').toLowerCase();
          return title.contains(query) ||
              username.contains(query.replaceAll('@', '')) ||
              phone.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _loadContacts({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await TurnaContactsDirectory.ensureLoaded(force: force);
      if (!mounted) return;
      if (!TurnaContactsDirectory.permissionGranted) {
        setState(() {
          _loading = false;
          _registeredContacts = const <TurnaRegisteredContact>[];
        });
        return;
      }

      final contacts = TurnaContactsDirectory.snapshotForSync();
      await ProfileApi.syncContacts(widget.session, contacts);
      final registered = await ChatApi.fetchRegisteredContacts(widget.session);
      if (!mounted) return;
      setState(() {
        _registeredContacts = registered;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedUserIds.isEmpty || _adding) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await ChatApi.addGroupMembers(
        widget.session,
        chatId: widget.chatId,
        memberUserIds: _selectedUserIds.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _adding = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _filteredContacts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Üye Ekle'),
        actions: [
          TextButton(
            onPressed: _adding || _selectedUserIds.isEmpty ? null : _submit,
            child: Text(_adding ? 'Ekleniyor...' : 'Ekle'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Kişi ara',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: TurnaColors.backgroundMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _error!,
                style: const TextStyle(color: TurnaColors.error),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !TurnaContactsDirectory.permissionGranted &&
                      _registeredContacts.isEmpty
                ? _CenteredState(
                    icon: Icons.perm_contact_calendar_outlined,
                    title: 'Rehber izni gerekli',
                    message:
                        'Turna kullanan rehber kişilerini görmek için rehber izni ver.',
                    primaryLabel: 'Rehber iznini iste',
                    onPrimary: () => _loadContacts(force: true),
                  )
                : contacts.isEmpty
                ? _CenteredState(
                    icon: Icons.group_outlined,
                    title: 'Eklenebilecek kişi bulunamadı',
                    message:
                        'Rehberindeki kayıtlı Turna kullanıcıları burada listelenecek.',
                    primaryLabel: 'Kişileri yenile',
                    onPrimary: () => _loadContacts(force: true),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: contacts.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      final selected = _selectedUserIds.contains(contact.id);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selectedUserIds.remove(contact.id);
                            } else {
                              _selectedUserIds.add(contact.id);
                            }
                          });
                        },
                        leading: _ProfileAvatar(
                          label: contact.resolvedTitle,
                          avatarUrl: contact.avatarUrl,
                          authToken: widget.session.token,
                          radius: 24,
                        ),
                        title: Text(
                          contact.resolvedTitle,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            if ((contact.username ?? '').trim().isNotEmpty)
                              '@${contact.username!.trim()}',
                            if ((contact.phone ?? '').trim().isNotEmpty)
                              formatTurnaDisplayPhone(contact.phone!),
                          ].join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Checkbox(
                          value: selected,
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedUserIds.remove(contact.id);
                              } else {
                                _selectedUserIds.add(contact.id);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
