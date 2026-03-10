part of '../main.dart';

class TurnaSharedContactPayload {
  const TurnaSharedContactPayload({
    required this.displayName,
    this.phones = const <String>[],
  });

  final String displayName;
  final List<String> phones;

  String get previewLabel {
    final trimmed = displayName.trim();
    return trimmed.isNotEmpty ? trimmed : 'Kisi';
  }

  String get primaryPhone => phones.isNotEmpty ? phones.first : '';

  String get subtitle {
    if (phones.isEmpty) return 'Paylasilan kisi';
    if (phones.length == 1) return formatTurnaSharedPhone(phones.first);
    return '${formatTurnaSharedPhone(phones.first)} ve ${phones.length - 1} numara daha';
  }

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'phones': phones,
  };

  factory TurnaSharedContactPayload.fromMap(Map<String, dynamic> map) {
    final phones = (map['phones'] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return TurnaSharedContactPayload(
      displayName: (map['displayName'] ?? '').toString().trim(),
      phones: phones,
    );
  }
}

String formatTurnaSharedPhone(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final normalized = trimmed.startsWith('+') ? trimmed : '+$trimmed';
  return formatTurnaDisplayPhone(normalized);
}

Future<void> openTurnaSharedContactCard(
  BuildContext context,
  TurnaSharedContactPayload payload,
) async {
  final phones = payload.phones.where((item) => item.trim().isNotEmpty).toList();
  if (phones.isEmpty) return;
  if (phones.length == 1) {
    await launchUrl(
      Uri.parse('tel:${phones.first.startsWith('+') ? phones.first : '+${phones.first}'}'),
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                payload.previewLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Aramak icin bir numara sec'),
            ),
            for (final phone in phones)
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: Text(formatTurnaSharedPhone(phone)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await launchUrl(
                    Uri.parse('tel:${phone.startsWith('+') ? phone : '+$phone'}'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
          ],
        ),
      );
    },
  );
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
    return _contacts.where((contact) {
      if (contact.displayName.toLowerCase().contains(query)) return true;
      return contact.phones.any(
        (phone) => formatTurnaSharedPhone(phone).toLowerCase().contains(query),
      );
    }).toList(growable: false);
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
          child: const Text('Iptal'),
        ),
        title: const Text('Kisi gonder'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Kisi ara',
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
                    title: 'Kisi erisimi gerekli',
                    subtitle: 'Rehberinizden kisi paylasabilmek icin izin vermeniz gerekiyor.',
                    primaryLabel: 'Tekrar dene',
                    onPrimary: _loadContacts,
                  )
                : contacts.isEmpty
                ? _ContactPickerEmptyState(
                    title: 'Kisi bulunamadi',
                    subtitle: 'Rehberinizde telefon numarasi olan kisi yok veya arama sonucu bos.',
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
                              color: TurnaColors.primary.withValues(alpha: 0.12),
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
              FilledButton(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
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
    this.onTap,
  });

  final TurnaSharedContactPayload payload;
  final bool mine;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final cardColor = mine ? TurnaColors.chatOutgoing : Colors.white;
    final textColor = mine
        ? TurnaColors.chatOutgoingText
        : TurnaColors.chatIncomingText;
    final phones = payload.phones.take(2).toList(growable: false);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 250,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: mine
                ? TurnaColors.chatOutgoing.withValues(alpha: 0.92)
                : TurnaColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: mine
                        ? Colors.white.withValues(alpha: 0.36)
                        : TurnaColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.perm_contact_calendar_rounded,
                    color: mine ? TurnaColors.chatOutgoingText : TurnaColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payload.previewLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${payload.phones.length} numara',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.72),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final phone in phones) ...[
              Row(
                children: [
                  Icon(
                    Icons.phone_outlined,
                    size: 16,
                    color: textColor.withValues(alpha: 0.68),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatTurnaSharedPhone(phone),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (payload.phones.length > phones.length)
              Text(
                '+${payload.phones.length - phones.length} numara daha',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.72),
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
