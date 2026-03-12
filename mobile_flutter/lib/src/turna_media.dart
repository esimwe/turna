part of '../main.dart';

class _TurnaMediaComposerPage extends StatelessWidget {
  const _TurnaMediaComposerPage({
    required this.session,
    required this.items,
    required this.onSessionExpired,
    this.chat,
    this.onPreparedSend,
    this.captionEnabled = true,
  }) : assert(
         chat != null || onPreparedSend != null,
         'chat veya onPreparedSend verilmelidir.',
       );

  final AuthSession session;
  final ChatPreview? chat;
  final List<MediaComposerSeed> items;
  final VoidCallback onSessionExpired;
  final _MediaComposerPreparedSend? onPreparedSend;
  final bool captionEnabled;

  @override
  Widget build(BuildContext context) {
    return _MediaComposerPage(
      session: session,
      chat: chat,
      items: items,
      onSessionExpired: onSessionExpired,
      onPreparedSend: onPreparedSend,
      captionEnabled: captionEnabled,
    );
  }
}

MediaComposerSeed? buildTurnaMediaComposerSeed(
  XFile file, {
  ChatAttachmentKind? forcedKind,
  void Function(String message)? onError,
}) {
  final contentType = file.mimeType?.trim().isNotEmpty == true
      ? file.mimeType!.trim()
      : guessContentTypeForFileName(file.name);
  if (contentType == null) {
    onError?.call('${file.name} için medya türü okunamadı.');
    return null;
  }

  final kind =
      forcedKind ??
      (contentType.startsWith('image/')
          ? ChatAttachmentKind.image
          : contentType.startsWith('video/')
          ? ChatAttachmentKind.video
          : null);
  if (kind == null) {
    onError?.call('Gönderilebilir medya bulunamadı.');
    return null;
  }

  final fileName = file.name.trim().isEmpty
      ? 'media-${DateTime.now().millisecondsSinceEpoch}'
      : file.name.trim();

  return MediaComposerSeed(
    kind: kind,
    file: file,
    fileName: fileName,
    contentType: contentType,
    sizeBytes: 0,
  );
}

Future<List<MediaComposerSeed>> buildTurnaMediaComposerSeeds(
  BuildContext context,
  List<XFile> files, {
  int limit = kComposerMediaLimit,
}) async {
  final seeds = <MediaComposerSeed>[];
  final messenger = ScaffoldMessenger.maybeOf(context);

  for (final file in files.take(limit)) {
    final seed = buildTurnaMediaComposerSeed(file);
    if (seed == null) continue;

    final sizeBytes = await file.length();
    if (sizeBytes > kInlineAttachmentSoftLimitBytes) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '${file.name} 64 MB üstü olduğu için inline medya olarak gönderilemiyor.',
          ),
        ),
      );
      continue;
    }

    seeds.add(
      MediaComposerSeed(
        kind: seed.kind,
        file: seed.file,
        fileName: seed.fileName,
        contentType: seed.contentType,
        sizeBytes: sizeBytes,
      ),
    );
  }

  if (seeds.isEmpty) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Gönderilebilir medya bulunamadı.')),
    );
  }
  return seeds;
}
