part of '../../app/turna_app.dart';

class TurnaScheduledMessagesPage extends StatefulWidget {
  const TurnaScheduledMessagesPage({
    super.key,
    required this.session,
    required this.chat,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final ChatPreview chat;
  final VoidCallback onSessionExpired;

  @override
  State<TurnaScheduledMessagesPage> createState() =>
      _TurnaScheduledMessagesPageState();
}

class _TurnaScheduledMessagesPageState
    extends State<TurnaScheduledMessagesPage> {
  List<TurnaScheduledMessageSummary> _items =
      const <TurnaScheduledMessageSummary>[];
  bool _loading = true;
  String? _error;
  final Set<String> _busyIds = <String>{};

  bool get _isSavedMessagesChat =>
      ChatApi.isSavedMessagesChatId(widget.chat.chatId, widget.session.userId);

  String get _title =>
      _isSavedMessagesChat ? 'Hatırlatıcılar' : 'Zamanlanmış mesajlar';

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatApi.listScheduledMessages(
        widget.session,
        chatId: widget.chat.chatId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _formatScheduledAt(String iso) {
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return 'Bilinmeyen zaman';
    final now = DateTime.now();
    final sameYear = parsed.year == now.year;
    final dd = parsed.day.toString().padLeft(2, '0');
    final mm = parsed.month.toString().padLeft(2, '0');
    final yyyy = parsed.year.toString();
    final hh = parsed.hour.toString().padLeft(2, '0');
    final min = parsed.minute.toString().padLeft(2, '0');
    return sameYear ? '$dd.$mm  $hh:$min' : '$dd.$mm.$yyyy  $hh:$min';
  }

  Future<void> _deleteItem(TurnaScheduledMessageSummary item) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  _isSavedMessagesChat
                      ? 'Hatırlatıcıyı kaldır'
                      : 'Zamanlanmış mesajı kaldır',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  sanitizeTurnaChatPreviewText(item.text).trim().isEmpty
                      ? 'Bu kayıt kaldırılacak.'
                      : sanitizeTurnaChatPreviewText(item.text).trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: TurnaColors.error,
                ),
                title: const Text(
                  'Kaldır',
                  style: TextStyle(color: TurnaColors.error),
                ),
                onTap: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _busyIds.add(item.id));
    try {
      await ChatApi.deleteScheduledMessage(
        widget.session,
        scheduledMessageId: item.id,
      );
      if (!mounted) return;
      setState(() {
        _busyIds.remove(item.id);
        _items = _items.where((entry) => entry.id != item.id).toList();
      });
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyIds.remove(item.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(title: Text(_title)),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && items.isEmpty
            ? ListView(
                children: [
                  SizedBox(
                    height: 420,
                    child: _CenteredState(
                      icon: Icons.schedule_rounded,
                      title: 'Liste yüklenemedi',
                      message: _error!,
                    ),
                  ),
                ],
              )
            : items.isEmpty
            ? ListView(
                children: [
                  SizedBox(
                    height: 420,
                    child: _CenteredState(
                      icon: _isSavedMessagesChat
                          ? Icons.notifications_active_outlined
                          : Icons.schedule_rounded,
                      title: _isSavedMessagesChat
                          ? 'Hatırlatıcı yok'
                          : 'Zamanlanmış mesaj yok',
                      message: _isSavedMessagesChat
                          ? 'Uzun basılı gönder menüsünden hatırlatıcı ayarladıkların burada görünür.'
                          : 'Uzun basılı gönder menüsünden zamanladığın mesajlar burada görünür.',
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final preview = sanitizeTurnaChatPreviewText(
                    item.text,
                  ).trim();
                  final isFailed =
                      item.status == TurnaScheduledMessageStatus.failed;
                  final isBusy = _busyIds.contains(item.id);
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isFailed
                              ? const Color(0xFFFFEFEA)
                              : TurnaColors.primary50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          isFailed
                              ? Icons.error_outline_rounded
                              : (_isSavedMessagesChat
                                    ? Icons.notifications_active_outlined
                                    : Icons.schedule_rounded),
                          color: isFailed
                              ? TurnaColors.error
                              : TurnaColors.primary,
                        ),
                      ),
                      title: Text(
                        preview.isEmpty ? 'Mesaj' : preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isFailed
                                  ? 'Gönderilemedi • ${_formatScheduledAt(item.scheduledFor)}'
                                  : 'Planlandı • ${_formatScheduledAt(item.scheduledFor)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: TurnaColors.textMuted,
                              ),
                            ),
                            if (item.silent)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Sessiz gönderim açık',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: TurnaColors.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (isFailed &&
                                (item.lastError ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  item.lastError!.trim(),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: TurnaColors.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'Kaldır',
                        onPressed: isBusy ? null : () => _deleteItem(item),
                        icon: isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemCount: items.length,
              ),
      ),
    );
  }
}
