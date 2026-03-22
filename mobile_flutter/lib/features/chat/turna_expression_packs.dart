part of '../../app/turna_app.dart';

enum TurnaExpressionPackSourceKind { bundledGenerated, remoteZip }

extension TurnaExpressionPackSourceKindX on TurnaExpressionPackSourceKind {
  static TurnaExpressionPackSourceKind fromWire(String value) {
    switch (value.trim().toLowerCase()) {
      case 'remote_zip':
        return TurnaExpressionPackSourceKind.remoteZip;
      default:
        return TurnaExpressionPackSourceKind.bundledGenerated;
    }
  }
}

enum TurnaExpressionAssetType {
  staticPng,
  staticWebp,
  animatedLottie,
  videoWebm,
}

extension TurnaExpressionAssetTypeX on TurnaExpressionAssetType {
  static TurnaExpressionAssetType fromWire(String value) {
    switch (value.trim().toLowerCase()) {
      case 'static_webp':
        return TurnaExpressionAssetType.staticWebp;
      case 'animated_lottie':
        return TurnaExpressionAssetType.animatedLottie;
      case 'video_webm':
        return TurnaExpressionAssetType.videoWebm;
      default:
        return TurnaExpressionAssetType.staticPng;
    }
  }
}

class TurnaExpressionPackCatalogLoader {
  static const String _starterManifestAsset =
      'assets/turna_packs/starter_manifest.json';
  static const String _cacheDirName = 'turna-expression-packs';

  static List<_TurnaStickerPack>? _cachedStickerPacks;

  static Future<List<_TurnaStickerPack>> _loadStickerPacks() async {
    final cached = _cachedStickerPacks;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(_starterManifestAsset);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final packs = (map['packs'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => _parseStickerPack(
            Map<String, dynamic>.from(item),
            inheritedVersion: (map['catalogVersion'] ?? '').toString(),
          ),
        )
        .whereType<_TurnaStickerPack>()
        .toList(growable: false);
    _cachedStickerPacks = packs;
    return packs;
  }

  static Future<Directory> ensureCachedZipPack({
    required String packId,
    required String version,
    required List<int> zipBytes,
  }) async {
    final root = await _packVersionDirectory(packId: packId, version: version);
    final readyMarker = File('${root.path}/.ready');
    if (await readyMarker.exists()) {
      return root;
    }

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    for (final entry in archive) {
      final normalizedPath = _normalizedArchivePath(entry.name);
      if (normalizedPath == null) continue;
      final outputPath = '${root.path}/$normalizedPath';
      if (entry.isFile) {
        final data = entry.content as List<int>;
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data, flush: true);
      } else {
        await Directory(outputPath).create(recursive: true);
      }
    }

    await readyMarker.writeAsString(DateTime.now().toIso8601String());
    return root;
  }

  static Future<bool> isPackVersionCached({
    required String packId,
    required String version,
  }) async {
    final root = await _packVersionDirectory(packId: packId, version: version);
    return File('${root.path}/.ready').exists();
  }

  static Future<File?> resolveCachedAsset({
    required String packId,
    required String version,
    required String relativePath,
  }) async {
    final root = await _packVersionDirectory(packId: packId, version: version);
    final normalizedPath = _normalizedArchivePath(relativePath);
    if (normalizedPath == null) return null;
    final file = File('${root.path}/$normalizedPath');
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  static Future<Directory> _packVersionDirectory({
    required String packId,
    required String version,
  }) async {
    final baseDir = await getApplicationSupportDirectory();
    return Directory(
      '${baseDir.path}/$_cacheDirName/${_safeSegment(packId)}/${_safeSegment(version)}',
    );
  }

  static String _safeSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'default';
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  static String? _normalizedArchivePath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('../') ||
        normalized.contains('..\\')) {
      return null;
    }
    return normalized;
  }

  static _TurnaStickerPack? _parseStickerPack(
    Map<String, dynamic> map, {
    required String inheritedVersion,
  }) {
    final id = (map['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    final title = (map['title'] ?? '').toString().trim();
    final subtitle = (map['subtitle'] ?? '').toString().trim();
    final version = (map['version'] ?? inheritedVersion).toString().trim();
    final sourceKind = TurnaExpressionPackSourceKindX.fromWire(
      (map['sourceKind'] ?? '').toString(),
    );
    final items = (map['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => _parseStickerItem(Map<String, dynamic>.from(item)))
        .whereType<_TurnaStickerItem>()
        .toList(growable: false);
    if (items.isEmpty) return null;
    return _TurnaStickerPack(
      id: id,
      title: title.isEmpty ? 'Paket' : title,
      subtitle: subtitle,
      sourceKind: sourceKind,
      version: version.isEmpty ? '1' : version,
      items: items,
    );
  }

  static _TurnaStickerItem? _parseStickerItem(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    final emoji = (map['emoji'] ?? '').toString().trim();
    final label = (map['label'] ?? '').toString().trim();
    if (id.isEmpty || emoji.isEmpty || label.isEmpty) return null;
    final palette = (map['palette'] as List<dynamic>? ?? const [])
        .map((item) => _parseColor(item.toString()))
        .whereType<Color>()
        .toList(growable: false);
    return _TurnaStickerItem(
      id: id,
      emoji: emoji,
      label: label,
      colors: palette.length >= 2
          ? palette.take(2).toList(growable: false)
          : const <Color>[Color(0xFFEAECEF), Color(0xFFBBC4D2)],
      assetType: TurnaExpressionAssetTypeX.fromWire(
        (map['assetType'] ?? '').toString(),
      ),
      relativeAssetPath: (map['relativeAssetPath'] ?? '').toString().trim(),
    );
  }

  static Color? _parseColor(String value) {
    final normalized = value.trim().replaceAll('#', '');
    if (normalized.isEmpty) return null;
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    if (hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return Color(parsed);
  }
}
