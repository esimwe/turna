part of '../../app/turna_app.dart';

String _normalizeTurnaSharedPhone(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.startsWith('+') ? trimmed : '+$trimmed';
}

List<String> _buildTurnaSharedContactQueries(Iterable<String> phones) {
  final queries = <String>[];
  final seen = <String>{};
  for (final phone in phones) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) continue;
    final normalized = _normalizeTurnaSharedPhone(trimmed);
    for (final candidate in <String>{trimmed, normalized}) {
      if (candidate.isEmpty || !seen.add(candidate)) continue;
      queries.add(candidate);
    }
  }
  return queries;
}

Future<TurnaUserProfile?> _lookupTurnaSharedContactUser(
  AuthSession session,
  Iterable<String> phones,
) async {
  for (final query in _buildTurnaSharedContactQueries(phones)) {
    final user = await ChatApi.lookupUser(session, query);
    if (user != null) return user;
  }
  return null;
}

ChatPreview _buildTurnaSharedContactChatPreview(
  AuthSession session,
  TurnaUserProfile user,
) {
  final phone = user.phone;
  final fallbackName = phone == null || phone.trim().isEmpty
      ? user.displayName
      : formatTurnaDisplayPhone(phone);
  return ChatPreview(
    chatId: ChatApi.buildDirectChatId(session.userId, user.id),
    name: TurnaContactsDirectory.resolveDisplayLabel(
      phone: phone,
      fallbackName: fallbackName,
    ),
    message: '',
    time: '',
    phone: phone,
    avatarUrl: user.avatarUrl,
    peerId: user.id,
  );
}

void _showTurnaSharedContactSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> openTurnaSharedContactMessage(
  BuildContext context, {
  required AuthSession session,
  required TurnaCallCoordinator callCoordinator,
  required VoidCallback onSessionExpired,
  required TurnaSharedContactPayload payload,
  bool replaceCurrentRoute = false,
}) async {
  try {
    final user = await _lookupTurnaSharedContactUser(session, payload.phones);
    if (!context.mounted) return;
    if (user == null) {
      _showTurnaSharedContactSnackBar(
        context,
        'Bu kişi için Turna hesabı bulunamadı.',
      );
      return;
    }

    final route = buildChatRoomRoute(
      chat: _buildTurnaSharedContactChatPreview(session, user),
      session: session,
      callCoordinator: callCoordinator,
      onSessionExpired: onSessionExpired,
    );
    if (replaceCurrentRoute) {
      await Navigator.of(context).pushReplacement<void, void>(route);
    } else {
      await Navigator.of(context).push(route);
    }
  } on TurnaUnauthorizedException {
    if (!context.mounted) return;
    onSessionExpired();
  } catch (error) {
    if (!context.mounted) return;
    _showTurnaSharedContactSnackBar(context, error.toString());
  }
}

Future<void> addTurnaSharedContactToAddressBook(
  BuildContext context,
  TurnaSharedContactPayload payload,
) async {
  try {
    final contact = Contact(
      displayName: payload.previewLabel,
      phones: payload.phones
          .where((item) => item.trim().isNotEmpty)
          .map((item) => Phone(_normalizeTurnaSharedPhone(item)))
          .toList(),
    );
    await FlutterContacts.openExternalInsert(contact);
  } catch (error) {
    if (!context.mounted) return;
    _showTurnaSharedContactSnackBar(context, 'Kişi kartı açılamadı: $error');
  }
}

Future<void> addTurnaUserProfileToAddressBook(
  BuildContext context,
  TurnaUserProfile profile,
) async {
  try {
    final phone = profile.phone?.trim() ?? '';
    final email = profile.email?.trim() ?? '';
    final contact = Contact(
      displayName: profile.displayName,
      phones: phone.isEmpty
          ? const <Phone>[]
          : [Phone(_normalizeTurnaSharedPhone(phone))],
      emails: email.isEmpty ? const <Email>[] : [Email(email)],
    );
    await FlutterContacts.openExternalInsert(contact);
  } catch (error) {
    if (!context.mounted) return;
    _showTurnaSharedContactSnackBar(context, 'Kişi kartı açılamadı: $error');
  }
}

Future<void> openTurnaSharedContactCard(
  BuildContext context,
  TurnaSharedContactPayload payload, {
  required AuthSession session,
  required TurnaCallCoordinator callCoordinator,
  required VoidCallback onSessionExpired,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TurnaSharedContactDetailsPage(
        payload: payload,
        session: session,
        callCoordinator: callCoordinator,
        onSessionExpired: onSessionExpired,
      ),
    ),
  );
}

class TurnaSharedContactDetailsPage extends StatefulWidget {
  const TurnaSharedContactDetailsPage({
    super.key,
    required this.payload,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final TurnaSharedContactPayload payload;
  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<TurnaSharedContactDetailsPage> createState() =>
      _TurnaSharedContactDetailsPageState();
}

class _TurnaSharedContactDetailsPageState
    extends State<TurnaSharedContactDetailsPage> {
  final Map<String, TurnaUserProfile?> _resolvedUsers =
      <String, TurnaUserProfile?>{};
  final Set<String> _busyKeys = <String>{};

  Future<TurnaUserProfile?> _resolveUserForPhone(String phone) async {
    if (_resolvedUsers.containsKey(phone)) {
      return _resolvedUsers[phone];
    }

    try {
      final user = await _lookupTurnaSharedContactUser(widget.session, [phone]);
      if (!mounted) return user;
      setState(() => _resolvedUsers[phone] = user);
      return user;
    } on TurnaUnauthorizedException {
      if (!mounted) return null;
      widget.onSessionExpired();
      return null;
    } catch (error) {
      _showTurnaSharedContactSnackBar(context, error.toString());
      return null;
    }
  }

  Future<void> _runBusy(String key, Future<void> Function() task) async {
    if (_busyKeys.contains(key)) return;
    setState(() => _busyKeys.add(key));
    try {
      await task();
    } finally {
      if (mounted) {
        setState(() => _busyKeys.remove(key));
      }
    }
  }

  Future<void> _handleAddContact() async {
    await _runBusy('add-contact', () async {
      await addTurnaSharedContactToAddressBook(context, widget.payload);
    });
  }

  Future<void> _handleMessageAllPhones() async {
    await _runBusy('message-all', () async {
      await openTurnaSharedContactMessage(
        context,
        session: widget.session,
        callCoordinator: widget.callCoordinator,
        onSessionExpired: widget.onSessionExpired,
        payload: widget.payload,
        replaceCurrentRoute: true,
      );
    });
  }

  Future<void> _handleMessagePhone(String phone) async {
    await _runBusy('message:$phone', () async {
      final user = await _resolveUserForPhone(phone);
      if (!mounted || user == null) {
        if (mounted) {
          _showTurnaSharedContactSnackBar(
            context,
            'Bu numara Turna hesabına bağlı değil.',
          );
        }
        return;
      }

      await Navigator.of(context).pushReplacement<void, void>(
        buildChatRoomRoute(
          chat: _buildTurnaSharedContactChatPreview(widget.session, user),
          session: widget.session,
          callCoordinator: widget.callCoordinator,
          onSessionExpired: widget.onSessionExpired,
        ),
      );
    });
  }

  Future<void> _handleCallPhone(String phone, TurnaCallType type) async {
    await _runBusy('${type.name}:$phone', () async {
      final user = await _resolveUserForPhone(phone);
      if (!mounted || user == null) {
        if (mounted) {
          _showTurnaSharedContactSnackBar(
            context,
            'Bu numara Turna hesabına bağlı değil.',
          );
        }
        return;
      }

      try {
        final started = await CallApi.startCall(
          widget.session,
          calleeId: user.id,
          type: type,
        );
        if (!mounted) return;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OutgoingCallPage(
              session: widget.session,
              coordinator: widget.callCoordinator,
              initialCall: started,
              onSessionExpired: widget.onSessionExpired,
            ),
          ),
        );
      } on TurnaUnauthorizedException {
        if (!mounted) return;
        widget.onSessionExpired();
      } catch (error) {
        if (!mounted) return;
        _showTurnaSharedContactSnackBar(context, error.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final phones = widget.payload.phones
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(backgroundColor: const Color(0xFFF3F4F6)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Column(
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF3DBA3),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.person_rounded,
                    size: 52,
                    color: Color(0xFF6B4B23),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.payload.previewLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _TurnaSharedContactDetailTile(
              title: 'Rehbere kaydet',
              onTap: _handleAddContact,
              trailing: _busyKeys.contains('add-contact')
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 20,
                      color: TurnaColors.success,
                    ),
            ),
            const SizedBox(height: 12),
            for (final phone in phones) ...[
              _TurnaSharedContactPhoneTile(
                label: 'telefon',
                phone: formatTurnaSharedPhone(phone),
                messageBusy: _busyKeys.contains('message:$phone'),
                videoBusy: _busyKeys.contains('video:$phone'),
                voiceBusy: _busyKeys.contains('audio:$phone'),
                onMessage: () => _handleMessagePhone(phone),
                onVideoCall: () => _handleCallPhone(phone, TurnaCallType.video),
                onVoiceCall: () => _handleCallPhone(phone, TurnaCallType.audio),
              ),
              const SizedBox(height: 10),
            ],
            if (phones.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: _busyKeys.contains('message-all')
                      ? null
                      : _handleMessageAllPhones,
                  icon: _busyKeys.contains('message-all')
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Bulunan Turna hesabı ile mesajlaş'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TurnaSharedContactDetailTile extends StatelessWidget {
  const _TurnaSharedContactDetailTile({
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailingWidgets = trailing == null ? null : <Widget>[trailing!];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: TurnaColors.success,
                  ),
                ),
              ),
              ...?trailingWidgets,
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnaSharedContactPhoneTile extends StatelessWidget {
  const _TurnaSharedContactPhoneTile({
    required this.label,
    required this.phone,
    required this.onMessage,
    required this.onVideoCall,
    required this.onVoiceCall,
    this.messageBusy = false,
    this.videoBusy = false,
    this.voiceBusy = false,
  });

  final String label;
  final String phone;
  final VoidCallback onMessage;
  final VoidCallback onVideoCall;
  final VoidCallback onVoiceCall;
  final bool messageBusy;
  final bool videoBusy;
  final bool voiceBusy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: TurnaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF222222),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _TurnaSharedContactActionIcon(
            icon: Icons.chat_rounded,
            onTap: onMessage,
            busy: messageBusy,
          ),
          const SizedBox(width: 8),
          _TurnaSharedContactActionIcon(
            icon: Icons.videocam_rounded,
            onTap: onVideoCall,
            busy: videoBusy,
          ),
          const SizedBox(width: 8),
          _TurnaSharedContactActionIcon(
            icon: Icons.call_rounded,
            onTap: onVoiceCall,
            busy: voiceBusy,
          ),
        ],
      ),
    );
  }
}

class _TurnaSharedContactActionIcon extends StatelessWidget {
  const _TurnaSharedContactActionIcon({
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F5F7),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, size: 19, color: const Color(0xFF111111)),
          ),
        ),
      ),
    );
  }
}

class ContactSharePickerPage extends StatefulWidget {
  const ContactSharePickerPage({super.key});

  @override
  State<ContactSharePickerPage> createState() => _ContactSharePickerPageState();
}

class _ContactSharePickerPageState extends State<ContactSharePickerPage> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  List<TurnaContactSyncEntry> _contacts = const <TurnaContactSyncEntry>[];

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

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    await TurnaContactsDirectory.ensureLoaded(force: true);
    final next = TurnaContactsDirectory.snapshotForSync().toList()
      ..sort(
        (left, right) => left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        ),
      );
    if (!mounted) return;
    setState(() {
      _contacts = next;
      _loading = false;
    });
  }

  List<TurnaContactSyncEntry> get _filteredContacts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    return _contacts
        .where((contact) {
          if (contact.displayName.toLowerCase().contains(query)) return true;
          return contact.phones.any(
            (phone) =>
                formatTurnaSharedPhone(phone).toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _filteredContacts;
    final hasPermission = TurnaContactsDirectory.permissionGranted;

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        leadingWidth: 84,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        title: const Text('Kişi gönder'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Kişi ara',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !hasPermission
                ? _ContactPickerEmptyState(
                    title: 'Kişi erişimi gerekli',
                    subtitle:
                        'Rehberinizden kişi paylaşabilmek için izin vermeniz gerekiyor.',
                    primaryLabel: 'Tekrar dene',
                    onPrimary: _loadContacts,
                  )
                : contacts.isEmpty
                ? _ContactPickerEmptyState(
                    title: 'Kişi bulunamadı',
                    subtitle:
                        'Rehberinizde telefon numarası olan kişi yok veya arama sonucu boş.',
                    primaryLabel: 'Yenile',
                    onPrimary: _loadContacts,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: contacts.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      final subtitle = contact.phones.isEmpty
                          ? 'Numara yok'
                          : contact.phones
                                .take(2)
                                .map(formatTurnaSharedPhone)
                                .join(' • ');
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: TurnaColors.primary.withValues(
                                alpha: 0.12,
                              ),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.perm_contact_calendar_rounded,
                              color: TurnaColors.primary,
                            ),
                          ),
                          title: Text(
                            contact.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.pop(
                              context,
                              TurnaSharedContactPayload(
                                displayName: contact.displayName,
                                phones: contact.phones,
                              ),
                            );
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

class _ContactPickerEmptyState extends StatelessWidget {
  const _ContactPickerEmptyState({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: TurnaColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.perm_contact_calendar_outlined,
                size: 38,
                color: TurnaColors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: TurnaColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: TurnaColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnaSharedContactMessageCard extends StatelessWidget {
  const _TurnaSharedContactMessageCard({
    required this.payload,
    required this.mine,
    required this.session,
    required this.callCoordinator,
    required this.onSessionExpired,
    this.overlayFooter,
  });

  final TurnaSharedContactPayload payload;
  final bool mine;
  final AuthSession session;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;
  final Widget? overlayFooter;

  @override
  Widget build(BuildContext context) {
    final cardColor = mine ? TurnaColors.chatOutgoing : Colors.white;
    final textColor = mine
        ? TurnaColors.chatOutgoingText
        : TurnaColors.chatIncomingText;
    final borderColor = mine
        ? TurnaColors.chatOutgoing.withValues(alpha: 0.92)
        : TurnaColors.border;
    final headerColor = mine
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFF2F3F5);
    final showOverlayFooter = overlayFooter != null;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: headerColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              onTap: () {
                unawaited(
                  openTurnaSharedContactCard(
                    context,
                    payload,
                    session: session,
                    callCoordinator: callCoordinator,
                    onSessionExpired: onSessionExpired,
                  ),
                );
              },
              child: SizedBox(
                width: double.infinity,
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        12,
                        14,
                        showOverlayFooter ? 36 : 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: mine
                                      ? Colors.white.withValues(alpha: 0.8)
                                      : const Color(0xFFE3E4E8),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.person_rounded,
                                  color: mine
                                      ? TurnaColors.chatOutgoingText
                                      : TurnaColors.textMuted,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  payload.previewLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: textColor.withValues(alpha: 0.72),
                                size: 24,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (showOverlayFooter)
                      Positioned(right: 8, bottom: 8, child: overlayFooter!),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TurnaSharedContactCardButton(
                    label: 'Mesaj',
                    color: mine ? TurnaColors.success : TurnaColors.primary,
                    onTap: () {
                      unawaited(
                        openTurnaSharedContactMessage(
                          context,
                          session: session,
                          callCoordinator: callCoordinator,
                          onSessionExpired: onSessionExpired,
                          payload: payload,
                        ),
                      );
                    },
                  ),
                ),
                Container(width: 1, height: 54, color: borderColor),
                Expanded(
                  child: _TurnaSharedContactCardButton(
                    label: 'Kişi ekle',
                    color: mine ? TurnaColors.success : TurnaColors.primary,
                    onTap: () {
                      unawaited(
                        addTurnaSharedContactToAddressBook(context, payload),
                      );
                    },
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

class _TurnaSharedContactCardButton extends StatelessWidget {
  const _TurnaSharedContactCardButton({
    required this.label,
    required this.onTap,
    required this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
