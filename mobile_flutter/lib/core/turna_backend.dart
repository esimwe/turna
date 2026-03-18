String _normalizeTurnaBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

const String _kDefaultBackendBaseUrl = 'https://api.turna.im';
final String kBackendBaseUrl = _normalizeTurnaBaseUrl(
  const String.fromEnvironment(
    'TURNA_BACKEND_URL',
    defaultValue: _kDefaultBackendBaseUrl,
  ),
);

Map<String, String>? buildTurnaAuthHeaders(String? authToken) {
  final trimmed = authToken?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return {'Authorization': 'Bearer $trimmed'};
}

String normalizeTurnaRemoteUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final remote = Uri.tryParse(trimmed);
  final backend = Uri.tryParse(kBackendBaseUrl);
  if (remote == null || backend == null) return trimmed;

  final sameHost = remote.host.toLowerCase() == backend.host.toLowerCase();
  final shouldUpgradeToHttps =
      sameHost && backend.scheme == 'https' && remote.scheme == 'http';
  if (!shouldUpgradeToHttps) return trimmed;

  return remote
      .replace(
        scheme: 'https',
        port: remote.hasPort && remote.port != 80 ? remote.port : null,
      )
      .toString();
}
