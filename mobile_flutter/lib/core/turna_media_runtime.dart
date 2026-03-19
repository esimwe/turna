part of '../app/turna_app.dart';

class TurnaMediaBridge {
  static const MethodChannel _channel = MethodChannel('turna/media');

  static Future<void> saveToGallery({
    required String path,
    String? mimeType,
  }) async {
    await _channel.invokeMethod('saveToGallery', {
      'path': path,
      'mimeType': mimeType,
    });
  }

  static Future<void> shareFile({
    required String path,
    String? mimeType,
  }) async {
    await _channel.invokeMethod('shareFile', {
      'path': path,
      'mimeType': mimeType,
    });
  }

  static Future<void> shareText({required String text}) async {
    await _channel.invokeMethod('shareText', {'text': text});
  }

  static Future<void> saveFile({
    required String path,
    String? mimeType,
    String? fileName,
  }) async {
    await _channel.invokeMethod('saveFile', {
      'path': path,
      'mimeType': mimeType,
      'fileName': fileName,
    });
  }

  static Future<TurnaDocumentScanResult?> scanDocument() async {
    final payload = await _channel.invokeMapMethod<String, dynamic>(
      'scanDocument',
    );
    if (payload == null) return null;
    return TurnaDocumentScanResult.fromMap(Map<String, dynamic>.from(payload));
  }

  static Future<TurnaProcessedVideoResult> processVideo({
    required String path,
    required ChatAttachmentTransferMode transferMode,
    String? fileName,
  }) async {
    final payload = await _channel.invokeMapMethod<String, dynamic>(
      'processVideo',
      {'path': path, 'transferMode': transferMode.name, 'fileName': fileName},
    );
    if (payload == null) {
      throw TurnaApiException('Video islenemedi.');
    }
    return TurnaProcessedVideoResult.fromMap(
      Map<String, dynamic>.from(payload),
    );
  }

  static Future<int> getPdfPageCount({required String path}) async {
    final count = await _channel.invokeMethod<int>('getPdfPageCount', {
      'path': path,
    });
    return count ?? 0;
  }

  static Future<Uint8List?> renderPdfPage({
    required String path,
    required int pageIndex,
    int targetWidth = 1440,
  }) async {
    final data = await _channel.invokeMethod<Uint8List>('renderPdfPage', {
      'path': path,
      'pageIndex': pageIndex,
      'targetWidth': targetWidth,
    });
    return data;
  }
}

class TurnaDocumentScanResult {
  const TurnaDocumentScanResult({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.pageCount,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int? pageCount;

  factory TurnaDocumentScanResult.fromMap(Map<String, dynamic> map) {
    return TurnaDocumentScanResult(
      path: (map['path'] ?? '').toString(),
      fileName: (map['fileName'] ?? '').toString(),
      mimeType: (map['mimeType'] ?? 'application/pdf').toString(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      pageCount: (map['pageCount'] as num?)?.toInt(),
    );
  }
}

class TurnaProcessedVideoResult {
  const TurnaProcessedVideoResult({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.durationSeconds,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationSeconds;

  factory TurnaProcessedVideoResult.fromMap(Map<String, dynamic> map) {
    return TurnaProcessedVideoResult(
      path: (map['path'] ?? '').toString(),
      fileName: (map['fileName'] ?? '').toString(),
      mimeType: (map['mimeType'] ?? 'video/mp4').toString(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
    );
  }
}

class TurnaLocalMediaCache {
  static const String _cacheDirName = 'turna-media-cache';
  static Directory? _cacheDir;
  static final Map<String, File> _resolvedFiles = {};
  static final Map<String, Future<File?>> _pendingFiles = {};
  static final Map<String, File> _preparedFiles = {};

  static File? peek(String cacheKey) {
    final file = _resolvedFiles[cacheKey];
    if (file == null) return null;
    if (!file.existsSync()) {
      _resolvedFiles.remove(cacheKey);
      return null;
    }
    return file;
  }

  static Future<File?> getOrDownloadFile({
    required String cacheKey,
    required String url,
    String? authToken,
  }) async {
    final cached = peek(cacheKey);
    if (cached != null) {
      return cached;
    }

    final pending = _pendingFiles[cacheKey];
    if (pending != null) {
      return pending;
    }

    final future = _resolveOrDownload(
      cacheKey: cacheKey,
      url: url,
      authToken: authToken,
    );
    _pendingFiles[cacheKey] = future;

    try {
      return await future;
    } finally {
      if (identical(_pendingFiles[cacheKey], future)) {
        _pendingFiles.remove(cacheKey);
      }
    }
  }

  static Future<void> remove(String cacheKey) async {
    _pendingFiles.remove(cacheKey);
    final file = _resolvedFiles.remove(cacheKey) ?? await _fileForKey(cacheKey);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final preparedKeys = _preparedFiles.keys
        .where((key) => key == cacheKey || key.startsWith('$cacheKey:'))
        .toList(growable: false);
    for (final key in preparedKeys) {
      final prepared = _preparedFiles.remove(key);
      if (prepared != null && await prepared.exists()) {
        try {
          await prepared.delete();
        } catch (_) {}
      }
    }
  }

  static Future<File> prepareMediaFile({
    required String cacheKey,
    required File sourceFile,
    String? mimeType,
    String? fileName,
  }) async {
    final preferredExtension = _preferredMediaExtension(
      mimeType: mimeType,
      fileName: fileName,
    );
    if (preferredExtension.isEmpty) {
      return sourceFile;
    }

    final currentExtension = sourceFile.path.split('.').last.toLowerCase();
    if (currentExtension == preferredExtension) {
      return sourceFile;
    }

    final preparedKey = '$cacheKey:$preferredExtension';
    final existing = _preparedFiles[preparedKey];
    if (existing != null && await existing.exists()) {
      final existingStat = await existing.stat();
      final sourceStat = await sourceFile.stat();
      if (existingStat.modified.isAfter(sourceStat.modified) ||
          existingStat.modified.isAtSameMomentAs(sourceStat.modified)) {
        return existing;
      }
    }

    final dir = await _ensureCacheDir();
    final target = File(
      '${dir.path}/${_hashKey(preparedKey)}.$preferredExtension',
    );
    try {
      if (await target.exists()) {
        await target.delete();
      }
    } catch (_) {}
    await sourceFile.copy(target.path);
    _preparedFiles[preparedKey] = target;
    return target;
  }

  static Future<File?> _resolveOrDownload({
    required String cacheKey,
    required String url,
    String? authToken,
  }) async {
    final normalizedUrl = normalizeTurnaRemoteUrl(url);
    try {
      final file = await _fileForKey(cacheKey);
      if (await file.exists()) {
        final length = await file.length();
        if (length > 0) {
          _resolvedFiles[cacheKey] = file;
          return file;
        }
        try {
          await file.delete();
        } catch (_) {}
      }

      Future<http.Response> request(String? token) {
        return http.get(
          Uri.parse(normalizedUrl),
          headers: buildTurnaAuthHeaders(token),
        );
      }

      var response = await request(authToken);
      if (response.statusCode >= 400 &&
          authToken != null &&
          authToken.trim().isNotEmpty) {
        response = await request(null);
      }

      if (response.statusCode >= 400) {
        turnaLog('media cache download failed', {
          'cacheKey': cacheKey,
          'statusCode': response.statusCode,
          'url': normalizedUrl,
        });
        return null;
      }

      if (response.bodyBytes.isEmpty) {
        turnaLog('media cache empty response', {
          'cacheKey': cacheKey,
          'url': normalizedUrl,
        });
        return null;
      }

      await file.writeAsBytes(response.bodyBytes, flush: true);
      _resolvedFiles[cacheKey] = file;
      return file;
    } catch (error) {
      turnaLog('media cache resolve failed', {
        'cacheKey': cacheKey,
        'url': normalizedUrl,
        'error': '$error',
      });
      return null;
    }
  }

  static Future<Directory> _ensureCacheDir() async {
    final existing = _cacheDir;
    if (existing != null) return existing;

    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory('${baseDir.path}/$_cacheDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  static Future<File> _fileForKey(String cacheKey) async {
    final dir = await _ensureCacheDir();
    return File('${dir.path}/${_hashKey(cacheKey)}.bin');
  }

  static String _hashKey(String value) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(value)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '${hash.toRadixString(16).padLeft(8, '0')}-${value.length}';
  }

  static String _preferredMediaExtension({String? mimeType, String? fileName}) {
    final lowerMime = (mimeType ?? '').toLowerCase();
    final lowerName = (fileName ?? '').toLowerCase();

    String? fromName() {
      if (!lowerName.contains('.')) return null;
      final ext = lowerName.split('.').last.trim();
      return ext.isEmpty ? null : ext;
    }

    final nameExt = fromName();
    if (nameExt != null && nameExt != 'bin') {
      return nameExt;
    }

    if (lowerMime.startsWith('video/')) {
      if (lowerMime.contains('quicktime')) return 'mov';
      if (lowerMime.contains('webm')) return 'webm';
      if (lowerMime.contains('x-matroska') || lowerMime.contains('mkv')) {
        return 'mkv';
      }
      return 'mp4';
    }

    if (lowerMime.startsWith('image/')) {
      if (lowerMime.contains('png')) return 'png';
      if (lowerMime.contains('webp')) return 'webp';
      if (lowerMime.contains('gif')) return 'gif';
      if (lowerMime.contains('heic') || lowerMime.contains('heif')) {
        return 'heic';
      }
      return 'jpg';
    }

    return '';
  }
}
