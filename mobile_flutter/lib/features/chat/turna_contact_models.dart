import '../../core/turna_file_utils.dart';

class TurnaSharedContactPayload {
  const TurnaSharedContactPayload({
    required this.displayName,
    this.phones = const <String>[],
  });

  final String displayName;
  final List<String> phones;

  String get previewLabel {
    final trimmed = displayName.trim();
    return trimmed.isNotEmpty ? trimmed : 'Kişi';
  }

  String get primaryPhone => phones.isNotEmpty ? phones.first : '';

  String get subtitle {
    if (phones.isEmpty) return 'Paylaşılan kişi';
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
