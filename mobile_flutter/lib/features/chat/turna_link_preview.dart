import 'dart:convert';

import 'package:http/http.dart' as http;

final RegExp kTurnaSharedUrlPattern = RegExp(
  r'((?:(?:https?:\/\/)|(?:www\.))?(?<!@)(?:[a-z0-9-]+\.)+[a-z]{2,}(?:[\/?#][^\s<]*)?)',
  caseSensitive: false,
);

String _trimTurnaUrlEdgePunctuation(String value) {
  var current = value.trim();
  while (current.isNotEmpty && RegExp(r'[\])},.!?;:]+$').hasMatch(current)) {
    current = current.substring(0, current.length - 1);
  }
  return current;
}

Uri? parseTurnaSharedUrl(String raw) {
  final trimmed = _trimTurnaUrlEdgePunctuation(raw);
  if (trimmed.isEmpty) return null;
  final normalized =
      trimmed.startsWith('http://') || trimmed.startsWith('https://')
      ? trimmed
      : 'https://$trimmed';
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.trim().isEmpty) return null;
  return uri;
}

List<Uri> extractTurnaUrls(String text) {
  final found = <Uri>[];
  final seen = <String>{};
  for (final match in kTurnaSharedUrlPattern.allMatches(text)) {
    final uri = parseTurnaSharedUrl(match.group(0) ?? '');
    if (uri == null) continue;
    final key = uri.toString();
    if (seen.add(key)) {
      found.add(uri);
    }
  }
  return found;
}

class TurnaLinkPreviewMetadata {
  const TurnaLinkPreviewMetadata({
    required this.uri,
    required this.title,
    required this.host,
    required this.displayUrl,
  });

  final Uri uri;
  final String title;
  final String host;
  final String displayUrl;
}

class TurnaLinkPreviewCache {
  static final Map<String, TurnaLinkPreviewMetadata> _resolved = {};
  static final Map<String, Future<TurnaLinkPreviewMetadata>> _pending = {};
  static final RegExp _titlePattern = RegExp(
    r'<title[^>]*>(.*?)<\/title>',
    caseSensitive: false,
    dotAll: true,
  );

  static TurnaLinkPreviewMetadata? peek(Uri uri) => _resolved[uri.toString()];

  static Future<TurnaLinkPreviewMetadata> resolve(Uri uri) async {
    final normalized = uri.toString();
    final cached = _resolved[normalized];
    if (cached != null) return cached;

    final pending = _pending[normalized];
    if (pending != null) return pending;

    final future = _fetch(uri);
    _pending[normalized] = future;
    try {
      final resolved = await future;
      _resolved[normalized] = resolved;
      return resolved;
    } finally {
      if (identical(_pending[normalized], future)) {
        _pending.remove(normalized);
      }
    }
  }

  static Future<TurnaLinkPreviewMetadata> _fetch(Uri uri) async {
    final host = uri.host.replaceFirst(
      RegExp(r'^www\.', caseSensitive: false),
      '',
    );
    final displayUrl = host.isEmpty ? uri.toString() : '$host${uri.path}';

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Turna/1.0 Mobile',
        },
      );
      if (response.statusCode >= 400 || response.bodyBytes.isEmpty) {
        return TurnaLinkPreviewMetadata(
          uri: uri,
          title: host.isEmpty ? uri.toString() : host,
          host: host,
          displayUrl: displayUrl,
        );
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final rawTitle = _titlePattern.firstMatch(html)?.group(1) ?? '';
      final cleanedTitle = rawTitle
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .trim();

      return TurnaLinkPreviewMetadata(
        uri: uri,
        title: cleanedTitle.isEmpty
            ? (host.isEmpty ? uri.toString() : host)
            : cleanedTitle,
        host: host,
        displayUrl: displayUrl,
      );
    } catch (_) {
      return TurnaLinkPreviewMetadata(
        uri: uri,
        title: host.isEmpty ? uri.toString() : host,
        host: host,
        displayUrl: displayUrl,
      );
    }
  }
}
