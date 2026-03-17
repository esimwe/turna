part of turna_app;

class _TurnaMediaComposerPage extends StatelessWidget {
  const _TurnaMediaComposerPage({
    required this.session,
    required this.items,
    required this.onSessionExpired,
    this.chat,
    this.onPreparedSend,
    this.captionEnabled = true,
    this.initialQuality = MediaComposerQuality.standard,
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
  final MediaComposerQuality initialQuality;

  @override
  Widget build(BuildContext context) {
    return _MediaComposerPage(
      session: session,
      chat: chat,
      items: items,
      onSessionExpired: onSessionExpired,
      onPreparedSend: onPreparedSend,
      captionEnabled: captionEnabled,
      initialQuality: initialQuality,
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
    final maxAllowedBytes = seed.kind == ChatAttachmentKind.video
        ? kDocumentAttachmentMaxBytes
        : kInlineAttachmentSoftLimitBytes;
    if (sizeBytes > maxAllowedBytes) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            seed.kind == ChatAttachmentKind.video
                ? '${file.name} 2 GB ustu oldugu icin gonderilemiyor.'
                : '${file.name} 64 MB ustu oldugu icin inline medya olarak gonderilemiyor.',
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

Future<_PreparedComposerAttachment> prepareTurnaInlineMediaAttachment(
  MediaComposerSeed seed, {
  MediaComposerQuality quality = MediaComposerQuality.standard,
}) async {
  switch (seed.kind) {
    case ChatAttachmentKind.image:
      return _prepareTurnaInlineImageAttachment(seed, quality: quality);
    case ChatAttachmentKind.video:
      return _prepareTurnaInlineVideoAttachment(seed, quality: quality);
    case ChatAttachmentKind.file:
      throw TurnaApiException('Gönderilebilir medya bulunamadı.');
  }
}

Future<_PreparedComposerAttachment> _prepareTurnaInlineVideoAttachment(
  MediaComposerSeed seed, {
  required MediaComposerQuality quality,
}) async {
  final processed = await TurnaMediaBridge.processVideo(
    path: seed.file.path,
    transferMode: quality.transferMode,
    fileName: seed.fileName,
  );
  return _PreparedComposerAttachment(
    kind: ChatAttachmentKind.video,
    fileName: processed.fileName,
    contentType: processed.mimeType,
    filePath: processed.path,
    sizeBytes: processed.sizeBytes,
    width: processed.width,
    height: processed.height,
    durationSeconds: processed.durationSeconds,
  );
}

Future<_PreparedComposerAttachment> _prepareTurnaInlineImageAttachment(
  MediaComposerSeed seed, {
  required MediaComposerQuality quality,
}) async {
  final sourceBytes = await seed.file.readAsBytes();
  final codec = await ui.instantiateImageCodec(sourceBytes);
  final frame = await codec.getNextFrame();
  final sourceImage = frame.image;
  final sourceWidth = sourceImage.width.toDouble();
  final sourceHeight = sourceImage.height.toDouble();
  final scaledSize = _scaleTurnaMediaSizeToMax(
    Size(sourceWidth, sourceHeight),
    quality.imageMaxDimension,
  );
  final outputWidth = math.max(1, scaledSize.width.round());
  final outputHeight = math.max(1, scaledSize.height.round());

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..isAntiAlias = true;
  canvas.drawImageRect(
    sourceImage,
    Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
    Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
    paint,
  );

  final rendered = await recorder.endRecording().toImage(
    outputWidth,
    outputHeight,
  );
  final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) {
    throw TurnaApiException('Görsel hazırlanamadı.');
  }

  final encodedImage = img.Image.fromBytes(
    width: outputWidth,
    height: outputHeight,
    bytes: data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final jpgBytes = Uint8List.fromList(
    img.encodeJpg(encodedImage, quality: quality.jpegQuality),
  );

  return _PreparedComposerAttachment(
    kind: ChatAttachmentKind.image,
    fileName: replaceFileExtension(seed.fileName, 'jpg'),
    contentType: 'image/jpeg',
    bytes: jpgBytes,
    sizeBytes: jpgBytes.length,
    width: outputWidth,
    height: outputHeight,
  );
}

Size _scaleTurnaMediaSizeToMax(Size size, double maxDimension) {
  final longestSide = math.max(size.width, size.height);
  if (longestSide <= maxDimension) return size;
  final scale = maxDimension / longestSide;
  return Size(size.width * scale, size.height * scale);
}
