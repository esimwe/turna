part of '../../app/turna_app.dart';

class TurnaPrivacyPage extends StatefulWidget {
  const TurnaPrivacyPage({
    super.key,
    required this.session,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final VoidCallback onSessionExpired;

  @override
  State<TurnaPrivacyPage> createState() => _TurnaPrivacyPageState();
}

class _TurnaPrivacyPageState extends State<TurnaPrivacyPage> {
  TurnaPrivacySettings _privacy = TurnaPrivacySettings.defaults();
  TurnaStatusPrivacySettings _statusPrivacy = TurnaStatusPrivacySettings(
    mode: TurnaStatusPrivacyMode.myContacts,
  );
  bool _appLockEnabled = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        loadTurnaAppLockEnabledPreference(),
        ProfileApi.fetchPrivacySettings(widget.session),
        TurnaStatusApi.fetchPrivacySettings(widget.session),
      ]);
      if (!mounted) return;
      setState(() {
        _appLockEnabled = results[0] as bool;
        _privacy = results[1] as TurnaPrivacySettings;
        _statusPrivacy = results[2] as TurnaStatusPrivacySettings;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleAppLock(bool nextValue) async {
    if (_busy) return;
    final authenticated = await authenticateTurnaDeviceAccess(
      context,
      localizedReason: nextValue
          ? 'Turna uygulama kilidini açmak için cihaz doğrulaması gerekiyor.'
          : 'Turna uygulama kilidini kapatmak için cihaz doğrulaması gerekiyor.',
      unsupportedMessage: 'Bu cihazda uygulama kilidi desteklenmiyor.',
    );
    if (!mounted || !authenticated) return;

    setState(() => _busy = true);
    try {
      await setTurnaAppLockEnabledPreference(nextValue);
      if (!mounted) return;
      setState(() {
        _appLockEnabled = nextValue;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextValue
                ? 'Uygulama kilidi açıldı.'
                : 'Uygulama kilidi kapatıldı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _savePrivacySettings(TurnaPrivacySettings nextSettings) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await ProfileApi.updatePrivacySettings(
        widget.session,
        nextSettings,
      );
      if (!mounted) return;
      setState(() {
        _privacy = updated;
        _busy = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _saveStatusSettings(
    _TurnaStatusPrivacyEditorResult result,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updatedStatus = await TurnaStatusApi.updatePrivacySettings(
        widget.session,
        mode: result.settings.mode,
        targetUserIds: result.settings.targetUserIds,
      );
      final updatedPrivacy = await ProfileApi.updatePrivacySettings(
        widget.session,
        _privacy.copyWith(statusAllowReshare: result.allowReshare),
      );
      if (!mounted) return;
      setState(() {
        _statusPrivacy = updatedStatus;
        _privacy = updatedPrivacy;
        _busy = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openLastSeenPage() async {
    final result = await Navigator.push<_TurnaLastSeenPrivacyResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaLastSeenPrivacyPage(
          session: widget.session,
          initialLastSeen: _privacy.lastSeen,
          initialOnline: _privacy.online,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (result == null) return;
    await _savePrivacySettings(
      _privacy.copyWith(lastSeen: result.lastSeen, online: result.online),
    );
  }

  Future<void> _openAudiencePage(_TurnaPrivacyField field) async {
    final current = _settingForField(field);
    final title = switch (field) {
      _TurnaPrivacyField.profilePhoto => 'Profil resmi',
      _TurnaPrivacyField.about => 'Hakkımda',
      _TurnaPrivacyField.links => 'Bağlantılar',
      _TurnaPrivacyField.groups => 'Gruplar',
    };
    final prompt = switch (field) {
      _TurnaPrivacyField.profilePhoto => 'Profil resmimi kimler görebilir?',
      _TurnaPrivacyField.about => 'Hakkımda bilgisini kimler görebilir?',
      _TurnaPrivacyField.links => 'Profilimdeki bağlantıları kimler görebilir?',
      _TurnaPrivacyField.groups => 'Beni kimler gruplara ekleyebilir',
    };
    final footer = switch (field) {
      _TurnaPrivacyField.groups => const <String>[
        'Sizi gruplara ekleyemeyen yöneticiler, size özel olarak davet gönderme seçeneğini kullanabilir.',
        'Bu ayar topluluk duyuru grupları için geçerli değildir. Bir topluluğa eklendiğinizde topluluk duyuru grubuna da eklenmiş olursunuz.',
      ],
      _ => const <String>[],
    };
    final allowedModes = switch (field) {
      _TurnaPrivacyField.groups => const <TurnaPrivacyAudience>[
        TurnaPrivacyAudience.everyone,
        TurnaPrivacyAudience.myContacts,
        TurnaPrivacyAudience.excludedContacts,
      ],
      _ => const <TurnaPrivacyAudience>[
        TurnaPrivacyAudience.everyone,
        TurnaPrivacyAudience.myContacts,
        TurnaPrivacyAudience.excludedContacts,
        TurnaPrivacyAudience.nobody,
      ],
    };

    final result = await Navigator.push<TurnaPrivacyAudienceSetting>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaPrivacyAudiencePage(
          session: widget.session,
          title: title,
          prompt: prompt,
          initialSetting: current,
          allowedModes: allowedModes,
          footerLines: footer,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (result == null) return;
    await _savePrivacySettings(_applyFieldSetting(field, result));
  }

  Future<void> _openStatusPage() async {
    final result = await Navigator.push<_TurnaStatusPrivacyEditorResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaStatusPrivacyPage(
          session: widget.session,
          initialSettings: _statusPrivacy,
          initialAllowReshare: _privacy.statusAllowReshare,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (result == null) return;
    await _saveStatusSettings(result);
  }

  TurnaPrivacyAudienceSetting _settingForField(_TurnaPrivacyField field) {
    return switch (field) {
      _TurnaPrivacyField.profilePhoto => _privacy.profilePhoto,
      _TurnaPrivacyField.about => _privacy.about,
      _TurnaPrivacyField.links => _privacy.links,
      _TurnaPrivacyField.groups => _privacy.groups,
    };
  }

  TurnaPrivacySettings _applyFieldSetting(
    _TurnaPrivacyField field,
    TurnaPrivacyAudienceSetting setting,
  ) {
    return switch (field) {
      _TurnaPrivacyField.profilePhoto => _privacy.copyWith(
        profilePhoto: setting,
      ),
      _TurnaPrivacyField.about => _privacy.copyWith(about: setting),
      _TurnaPrivacyField.links => _privacy.copyWith(links: setting),
      _TurnaPrivacyField.groups => _privacy.copyWith(groups: setting),
    };
  }

  String _lastSeenSummary() {
    return '${_privacy.lastSeen.mode.label}, ${_privacy.online.label}';
  }

  String _statusSummary() {
    switch (_statusPrivacy.mode) {
      case TurnaStatusPrivacyMode.excludedContacts:
        return 'Şunlar hariç kişilerim';
      case TurnaStatusPrivacyMode.onlySharedWith:
        return 'Sadece şu kişilerle paylaş';
      case TurnaStatusPrivacyMode.myContacts:
        return 'Kişilerim';
    }
  }

  void _showPlaceholder(String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title yakında eklenecek.')));
  }

  @override
  Widget build(BuildContext context) {
    final unlockMethodLabel = turnaDeviceUnlockMethodLabel();
    return Scaffold(
      appBar: AppBar(title: const Text('Gizlilik')),
      backgroundColor: TurnaColors.backgroundSoft,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IgnorePointer(
              ignoring: _busy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  _TurnaPrivacyCard(
                    children: [
                      _TurnaPrivacyMenuRow(
                        title: 'Son görülme ve çevrimiçi',
                        trailingText: _lastSeenSummary(),
                        onTap: _openLastSeenPage,
                      ),
                      _TurnaPrivacyMenuRow(
                        title: 'Profil resmi',
                        trailingText: _privacy.profilePhoto.mode.label,
                        onTap: () =>
                            _openAudiencePage(_TurnaPrivacyField.profilePhoto),
                      ),
                      _TurnaPrivacyMenuRow(
                        title: 'Hakkımda',
                        trailingText: _privacy.about.mode.label,
                        onTap: () =>
                            _openAudiencePage(_TurnaPrivacyField.about),
                      ),
                      _TurnaPrivacyMenuRow(
                        title: 'Bağlantılar',
                        trailingText: _privacy.links.mode.label,
                        onTap: () =>
                            _openAudiencePage(_TurnaPrivacyField.links),
                      ),
                      _TurnaPrivacyMenuRow(
                        title: 'Gruplar',
                        trailingText: _privacy.groups.mode.label,
                        onTap: () =>
                            _openAudiencePage(_TurnaPrivacyField.groups),
                      ),
                      _TurnaPrivacyMenuRow(
                        title: 'Durum',
                        trailingText: _statusSummary(),
                        onTap: _openStatusPage,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _TurnaPrivacyCard(
                    children: [
                      _TurnaPrivacyMenuRow(
                        title: 'Canlı konum',
                        trailingText: 'Yok',
                        onTap: () => _showPlaceholder('Canlı konum'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Canlı konumunuzu paylaştığınız sohbetlerin listesi.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: TurnaColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _TurnaPrivacyCard(
                    children: [
                      _TurnaPrivacyMenuRow(
                        title: 'Aramalar',
                        onTap: () => _showPlaceholder('Aramalar'),
                      ),
                      _TurnaPrivacyMenuRow(
                        title: 'Kişiler',
                        onTap: () => _showPlaceholder('Kişiler'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Süreli mesajlar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: TurnaColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TurnaPrivacyCard(
                    children: [
                      _TurnaPrivacyMenuRow(
                        title: 'Varsayılan mesaj süresi',
                        trailingText: 'Kapalı',
                        onTap: () =>
                            _showPlaceholder('Varsayılan mesaj süresi'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Yeni sohbetlere, ayarladığınız süre dolduğunda kaybolacak süreli mesajlarla başlayın.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: TurnaColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _UserProfileGroupCard(
                    children: [
                      _UserProfileSwitchRow(
                        icon: Icons.lock_outline_rounded,
                        title: 'Uygulama Kilidi',
                        subtitle:
                            'Turna açılırken $unlockMethodLabel ile doğrulama iste.',
                        value: _appLockEnabled,
                        onChanged: _busy ? (_) {} : _toggleAppLock,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'Bu ayar açıkken Turna her açıldığında ve uygulama arka plandan geri geldiğinde cihaz doğrulaması ister.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: TurnaColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

enum _TurnaPrivacyField { profilePhoto, about, links, groups }

class _TurnaLastSeenPrivacyResult {
  const _TurnaLastSeenPrivacyResult({
    required this.lastSeen,
    required this.online,
  });

  final TurnaPrivacyAudienceSetting lastSeen;
  final TurnaOnlineVisibility online;
}

class _TurnaLastSeenPrivacyPage extends StatefulWidget {
  const _TurnaLastSeenPrivacyPage({
    required this.session,
    required this.initialLastSeen,
    required this.initialOnline,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaPrivacyAudienceSetting initialLastSeen;
  final TurnaOnlineVisibility initialOnline;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaLastSeenPrivacyPage> createState() =>
      _TurnaLastSeenPrivacyPageState();
}

class _TurnaLastSeenPrivacyPageState extends State<_TurnaLastSeenPrivacyPage> {
  late TurnaPrivacyAudienceSetting _lastSeen;
  late TurnaOnlineVisibility _online;

  @override
  void initState() {
    super.initState();
    _lastSeen = widget.initialLastSeen;
    _online = widget.initialOnline;
  }

  void _closePage() {
    Navigator.of(
      context,
    ).pop(_TurnaLastSeenPrivacyResult(lastSeen: _lastSeen, online: _online));
  }

  Future<void> _editTargets() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaPrivacyTargetSelectionPage(
          session: widget.session,
          title: 'Şunlar hariç kişilerim',
          emptyStateLabel:
              'Hariç tutulacak kişi görünmüyor. Rehberini senkronladıktan sonra burada kayıtlı Turna kullanıcılarını seçebilirsin.',
          initialSelectedUserIds: _lastSeen.targetUserIds,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _lastSeen = _lastSeen.copyWith(
        mode: TurnaPrivacyAudience.excludedContacts,
        targetUserIds: result,
      );
    });
  }

  String _excludedSummary() {
    final count = _lastSeen.targetUserIds.length;
    return count == 0 ? 'Düzenle' : '$count kişi hariç · Düzenle';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closePage();
        }
      },
      child: Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          leading: BackButton(onPressed: _closePage),
          title: const Text('Son görülme ve çevrimiçi'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Son görülme bilgimi kimler görebilir',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: TurnaColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _TurnaPrivacyCard(
              children: [
                _TurnaPrivacyOptionRow(
                  title: 'Herkes',
                  selected: _lastSeen.mode == TurnaPrivacyAudience.everyone,
                  onTap: () => setState(
                    () => _lastSeen = _lastSeen.copyWith(
                      mode: TurnaPrivacyAudience.everyone,
                    ),
                  ),
                ),
                _TurnaPrivacyOptionRow(
                  title: 'Kişilerim',
                  selected: _lastSeen.mode == TurnaPrivacyAudience.myContacts,
                  onTap: () => setState(
                    () => _lastSeen = _lastSeen.copyWith(
                      mode: TurnaPrivacyAudience.myContacts,
                    ),
                  ),
                ),
                _TurnaPrivacyOptionRow(
                  title: 'Şunlar hariç kişilerim...',
                  selected:
                      _lastSeen.mode == TurnaPrivacyAudience.excludedContacts,
                  actionLabel: _excludedSummary(),
                  onTap: _editTargets,
                ),
                _TurnaPrivacyOptionRow(
                  title: 'Hiç kimse',
                  selected: _lastSeen.mode == TurnaPrivacyAudience.nobody,
                  onTap: () => setState(
                    () => _lastSeen = _lastSeen.copyWith(
                      mode: TurnaPrivacyAudience.nobody,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Çevrimiçi olduğumu kimler görebilir',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: TurnaColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _TurnaPrivacyCard(
              children: [
                _TurnaPrivacyOptionRow(
                  title: 'Herkes',
                  selected: _online == TurnaOnlineVisibility.everyone,
                  onTap: () =>
                      setState(() => _online = TurnaOnlineVisibility.everyone),
                ),
                _TurnaPrivacyOptionRow(
                  title: 'Son görülme bilgisiyle aynı',
                  selected: _online == TurnaOnlineVisibility.sameAsLastSeen,
                  onTap: () => setState(
                    () => _online = TurnaOnlineVisibility.sameAsLastSeen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Son görülme ve çevrimiçi bilginizi paylaşmazsanız diğer kullanıcıların son görülme ve çevrimiçi bilgisini de göremezsiniz.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.32,
                  color: TurnaColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnaPrivacyAudiencePage extends StatefulWidget {
  const _TurnaPrivacyAudiencePage({
    required this.session,
    required this.title,
    required this.prompt,
    required this.initialSetting,
    required this.allowedModes,
    required this.footerLines,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String title;
  final String prompt;
  final TurnaPrivacyAudienceSetting initialSetting;
  final List<TurnaPrivacyAudience> allowedModes;
  final List<String> footerLines;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaPrivacyAudiencePage> createState() =>
      _TurnaPrivacyAudiencePageState();
}

class _TurnaPrivacyAudiencePageState extends State<_TurnaPrivacyAudiencePage> {
  late TurnaPrivacyAudienceSetting _setting;

  @override
  void initState() {
    super.initState();
    _setting = widget.initialSetting;
  }

  void _closePage() {
    Navigator.of(context).pop(_setting);
  }

  Future<void> _editTargets(TurnaPrivacyAudience mode) async {
    final title = mode == TurnaPrivacyAudience.onlySharedWith
        ? 'Sadece şu kişilerle paylaş'
        : 'Şunlar hariç kişilerim';
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaPrivacyTargetSelectionPage(
          session: widget.session,
          title: title,
          emptyStateLabel:
              'Seçilebilir kişi görünmüyor. Rehberini senkronladıktan sonra burada kayıtlı Turna kullanıcılarını seçebilirsin.',
          initialSelectedUserIds: _setting.targetUserIds,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _setting = _setting.copyWith(mode: mode, targetUserIds: result);
    });
  }

  String _selectionSummary(TurnaPrivacyAudience mode) {
    final count = _setting.targetUserIds.length;
    if (mode == TurnaPrivacyAudience.onlySharedWith) {
      return count == 0 ? 'Düzenle' : '$count kişi dahil · Düzenle';
    }
    return count == 0 ? 'Düzenle' : '$count kişi hariç · Düzenle';
  }

  Widget _buildOption(TurnaPrivacyAudience mode) {
    final isSelectionMode = mode.needsTargetSelection;
    return _TurnaPrivacyOptionRow(
      title: mode.label,
      selected: _setting.mode == mode,
      actionLabel: isSelectionMode && _setting.mode == mode
          ? _selectionSummary(mode)
          : null,
      onTap: () {
        if (isSelectionMode) {
          _editTargets(mode);
          return;
        }
        setState(() => _setting = _setting.copyWith(mode: mode));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closePage();
        }
      },
      child: Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          leading: BackButton(onPressed: _closePage),
          title: Text(widget.title),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                widget.prompt,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: TurnaColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _TurnaPrivacyCard(
              children: widget.allowedModes.map(_buildOption).toList(),
            ),
            if (widget.footerLines.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final line in widget.footerLines) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.32,
                      color: TurnaColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _TurnaStatusPrivacyEditorResult {
  const _TurnaStatusPrivacyEditorResult({
    required this.settings,
    required this.allowReshare,
  });

  final TurnaStatusPrivacySettings settings;
  final bool allowReshare;
}

class _TurnaStatusPrivacyPage extends StatefulWidget {
  const _TurnaStatusPrivacyPage({
    required this.session,
    required this.initialSettings,
    required this.initialAllowReshare,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final TurnaStatusPrivacySettings initialSettings;
  final bool initialAllowReshare;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaStatusPrivacyPage> createState() =>
      _TurnaStatusPrivacyPageState();
}

class _TurnaStatusPrivacyPageState extends State<_TurnaStatusPrivacyPage> {
  late TurnaStatusPrivacyMode _mode;
  late Set<String> _selectedUserIds;
  late bool _allowReshare;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialSettings.mode;
    _selectedUserIds = widget.initialSettings.targetUserIds.toSet();
    _allowReshare = widget.initialAllowReshare;
  }

  void _closePage() {
    Navigator.of(context).pop(
      _TurnaStatusPrivacyEditorResult(
        settings: TurnaStatusPrivacySettings(
          mode: _mode,
          targetUserIds: _selectedUserIds.toList(),
          mutedUserIds: widget.initialSettings.mutedUserIds,
        ),
        allowReshare: _allowReshare,
      ),
    );
  }

  Future<void> _editTargets(TurnaStatusPrivacyMode mode) async {
    final title = mode == TurnaStatusPrivacyMode.onlySharedWith
        ? 'Sadece şu kişilerle paylaş'
        : 'Şunlar hariç kişilerim';
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => _TurnaPrivacyTargetSelectionPage(
          session: widget.session,
          title: title,
          emptyStateLabel:
              'Seçilebilir kişi görünmüyor. Rehberini senkronladıktan sonra burada kayıtlı Turna kullanıcılarını seçebilirsin.',
          initialSelectedUserIds: _selectedUserIds.toList(),
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _mode = mode;
      _selectedUserIds = result.toSet();
    });
  }

  String _statusSelectionSummary(TurnaStatusPrivacyMode mode) {
    final count = _selectedUserIds.length;
    if (mode == TurnaStatusPrivacyMode.onlySharedWith) {
      return count == 0 ? 'Düzenle' : '$count kişi dahil · Düzenle';
    }
    return count == 0 ? 'Düzenle' : '$count kişi hariç · Düzenle';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closePage();
        }
      },
      child: Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          leading: BackButton(onPressed: _closePage),
          title: const Text('Durum'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _TurnaPrivacyCard(
              children: [
                _TurnaStatusOptionRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Kişilerim',
                  selected: _mode == TurnaStatusPrivacyMode.myContacts,
                  onTap: () =>
                      setState(() => _mode = TurnaStatusPrivacyMode.myContacts),
                ),
                _TurnaStatusOptionRow(
                  icon: Icons.person_remove_alt_1_outlined,
                  title: 'Şunlar hariç kişilerim',
                  subtitle: _mode == TurnaStatusPrivacyMode.excludedContacts
                      ? _statusSelectionSummary(
                          TurnaStatusPrivacyMode.excludedContacts,
                        )
                      : null,
                  selected: _mode == TurnaStatusPrivacyMode.excludedContacts,
                  onTap: () =>
                      _editTargets(TurnaStatusPrivacyMode.excludedContacts),
                ),
                _TurnaStatusOptionRow(
                  icon: Icons.person_add_alt_1_outlined,
                  title: 'Sadece şu kişilerle paylaş',
                  subtitle: _mode == TurnaStatusPrivacyMode.onlySharedWith
                      ? _statusSelectionSummary(
                          TurnaStatusPrivacyMode.onlySharedWith,
                        )
                      : null,
                  selected: _mode == TurnaStatusPrivacyMode.onlySharedWith,
                  onTap: () =>
                      _editTargets(TurnaStatusPrivacyMode.onlySharedWith),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Gizlilik ayarlarınızda yaptığınız değişiklikler, göndermiş olduğunuz durum güncellemelerini etkilemez.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.32,
                  color: TurnaColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _UserProfileGroupCard(
              children: [
                _UserProfileSwitchRow(
                  icon: Icons.repeat_rounded,
                  title: 'Paylaşıma izin ver',
                  subtitle:
                      'Durumunuzu görebilen kullanıcıların tekrar paylaşmasına ve iletmesine izin verin.',
                  value: _allowReshare,
                  onChanged: (value) => setState(() => _allowReshare = value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnaPrivacyTargetSelectionPage extends StatefulWidget {
  const _TurnaPrivacyTargetSelectionPage({
    required this.session,
    required this.title,
    required this.emptyStateLabel,
    required this.initialSelectedUserIds,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String title;
  final String emptyStateLabel;
  final List<String> initialSelectedUserIds;
  final VoidCallback onSessionExpired;

  @override
  State<_TurnaPrivacyTargetSelectionPage> createState() =>
      _TurnaPrivacyTargetSelectionPageState();
}

class _TurnaPrivacyTargetSelectionPageState
    extends State<_TurnaPrivacyTargetSelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  List<TurnaRegisteredContact> _contacts = const <TurnaRegisteredContact>[];
  late Set<String> _selectedUserIds;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedUserIds = widget.initialSelectedUserIds.toSet();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final contacts = await ChatApi.fetchRegisteredContacts(widget.session);
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Iterable<TurnaRegisteredContact> get _filteredContacts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    return _contacts.where((contact) {
      final haystack = [
        contact.resolvedTitle,
        contact.username ?? '',
        contact.phone ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    });
  }

  void _closePage() {
    Navigator.of(context).pop(_selectedUserIds.toList());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closePage();
        }
      },
      child: Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          leading: BackButton(onPressed: _closePage),
          title: Text(widget.title),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Kişi ara',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_contacts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        widget.emptyStateLabel,
                        style: const TextStyle(color: TurnaColors.textMuted),
                      ),
                    )
                  else
                    ..._filteredContacts.map((contact) {
                      final selected = _selectedUserIds.contains(contact.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          child: CheckboxListTile(
                            value: selected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedUserIds.add(contact.id);
                                } else {
                                  _selectedUserIds.remove(contact.id);
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.trailing,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            secondary: _ProfileAvatar(
                              label: contact.resolvedTitle,
                              avatarUrl: contact.avatarUrl,
                              authToken: widget.session.token,
                              radius: 20,
                            ),
                            title: Text(contact.resolvedTitle),
                            subtitle: Text(
                              contact.username?.trim().isNotEmpty == true
                                  ? '@${contact.username}'
                                  : (contact.phone ?? 'Turna kullanıcısı'),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}

class _TurnaPrivacyCard extends StatelessWidget {
  const _TurnaPrivacyCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Colors.black.withValues(alpha: 0.06),
              ),
          ],
        ],
      ),
    );
  }
}

class _TurnaPrivacyMenuRow extends StatelessWidget {
  const _TurnaPrivacyMenuRow({
    required this.title,
    required this.onTap,
    this.trailingText,
  });

  final String title;
  final String? trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF202124),
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText?.trim().isNotEmpty == true)
            Text(
              trailingText!,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF7A817D),
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF979D99)),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _TurnaPrivacyOptionRow extends StatelessWidget {
  const _TurnaPrivacyOptionRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.actionLabel,
  });

  final String title;
  final bool selected;
  final String? actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF202124),
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (actionLabel?.trim().isNotEmpty == true) ...[
            Text(
              actionLabel!,
              style: const TextStyle(
                fontSize: 14,
                color: TurnaColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF979D99)),
            const SizedBox(width: 8),
          ],
          if (selected)
            const Icon(Icons.check_rounded, color: TurnaColors.primary),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _TurnaStatusOptionRow extends StatelessWidget {
  const _TurnaStatusOptionRow({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F3),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF2B2F2D)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF202124),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: TurnaColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (selected)
              const Icon(Icons.check_rounded, color: TurnaColors.primary),
          ],
        ),
      ),
    );
  }
}
