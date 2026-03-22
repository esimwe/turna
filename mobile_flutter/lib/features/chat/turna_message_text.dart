import 'dart:convert';

import 'turna_contact_models.dart';
import 'turna_location_models.dart';

final RegExp _kTurnaReplyMarkerPattern = RegExp(
  r'^\[\[turna-reply:([A-Za-z0-9_-]+)\]\]\n?',
);
final RegExp _kTurnaStatusMarkerPattern = RegExp(
  r'^\[\[turna-status:([A-Za-z0-9_-]+)\]\]\n?',
);
final RegExp _kTurnaLocationMarkerPattern = RegExp(
  r'^\[\[turna-location:([A-Za-z0-9_-]+)\]\]\n?',
);
final RegExp _kTurnaContactMarkerPattern = RegExp(
  r'^\[\[turna-contact:([A-Za-z0-9_-]+)\]\]\n?',
);
const String _kTurnaDeletedEveryoneMarker = '[[turna-deleted-everyone]]';

class TurnaReplyPayload {
  const TurnaReplyPayload({
    required this.messageId,
    required this.senderLabel,
    required this.previewText,
  });

  final String messageId;
  final String senderLabel;
  final String previewText;

  Map<String, dynamic> toMap() => {
    'messageId': messageId,
    'senderLabel': senderLabel,
    'previewText': previewText,
  };

  factory TurnaReplyPayload.fromMap(Map<String, dynamic> map) {
    return TurnaReplyPayload(
      messageId: (map['messageId'] ?? '').toString(),
      senderLabel: (map['senderLabel'] ?? '').toString(),
      previewText: (map['previewText'] ?? '').toString(),
    );
  }
}

class TurnaStatusMessagePayload {
  const TurnaStatusMessagePayload({
    required this.statusId,
    required this.authorUserId,
    required this.authorDisplayName,
    required this.statusType,
    required this.previewText,
  });

  final String statusId;
  final String authorUserId;
  final String authorDisplayName;
  final String statusType;
  final String previewText;

  String get previewLabel {
    final trimmed = previewText.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return switch (statusType.trim().toLowerCase()) {
      'video' => 'Video durumu',
      'image' => 'Fotograf durumu',
      _ => 'Durum',
    };
  }

  String get typeLabel => switch (statusType.trim().toLowerCase()) {
    'video' => 'Video durumu',
    'image' => 'Fotograf durumu',
    _ => 'Durum',
  };

  Map<String, dynamic> toMap() => {
    'statusId': statusId,
    'authorUserId': authorUserId,
    'authorDisplayName': authorDisplayName,
    'statusType': statusType,
    'previewText': previewText,
  };

  factory TurnaStatusMessagePayload.fromMap(Map<String, dynamic> map) {
    return TurnaStatusMessagePayload(
      statusId: (map['statusId'] ?? '').toString(),
      authorUserId: (map['authorUserId'] ?? '').toString(),
      authorDisplayName: (map['authorDisplayName'] ?? '').toString(),
      statusType: (map['statusType'] ?? 'text').toString(),
      previewText: (map['previewText'] ?? '').toString(),
    );
  }
}

class ParsedTurnaMessageText {
  const ParsedTurnaMessageText({
    required this.text,
    this.reply,
    this.status,
    this.location,
    this.contact,
    this.deletedForEveryone = false,
  });

  final String text;
  final TurnaReplyPayload? reply;
  final TurnaStatusMessagePayload? status;
  final TurnaLocationPayload? location;
  final TurnaSharedContactPayload? contact;
  final bool deletedForEveryone;
}

ParsedTurnaMessageText parseTurnaMessageText(String raw) {
  if (raw.trim() == _kTurnaDeletedEveryoneMarker) {
    return const ParsedTurnaMessageText(
      text: 'Silindi.',
      deletedForEveryone: true,
    );
  }

  var working = raw;
  TurnaReplyPayload? reply;
  TurnaStatusMessagePayload? status;

  final replyMatch = _kTurnaReplyMarkerPattern.firstMatch(working);
  if (replyMatch != null) {
    try {
      final encoded = replyMatch.group(1)!;
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
      );
      reply = TurnaReplyPayload.fromMap(
        jsonDecode(decoded) as Map<String, dynamic>,
      );
      working = working.substring(replyMatch.end);
    } catch (_) {
      return ParsedTurnaMessageText(text: raw);
    }
  }

  final statusMatch = _kTurnaStatusMarkerPattern.firstMatch(working);
  if (statusMatch != null) {
    try {
      final encoded = statusMatch.group(1)!;
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
      );
      status = TurnaStatusMessagePayload.fromMap(
        jsonDecode(decoded) as Map<String, dynamic>,
      );
      working = working.substring(statusMatch.end);
    } catch (_) {
      return ParsedTurnaMessageText(text: raw);
    }
  }

  final locationMatch = _kTurnaLocationMarkerPattern.firstMatch(working);
  if (locationMatch != null) {
    try {
      final encoded = locationMatch.group(1)!;
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
      );
      final payload = TurnaLocationPayload.fromMap(
        jsonDecode(decoded) as Map<String, dynamic>,
      );
      final cleaned = working.substring(locationMatch.end).trimLeft();
      return ParsedTurnaMessageText(
        text: cleaned,
        reply: reply,
        status: status,
        location: payload,
      );
    } catch (_) {
      return ParsedTurnaMessageText(text: raw);
    }
  }

  final contactMatch = _kTurnaContactMarkerPattern.firstMatch(working);
  if (contactMatch != null) {
    try {
      final encoded = contactMatch.group(1)!;
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
      );
      final payload = TurnaSharedContactPayload.fromMap(
        jsonDecode(decoded) as Map<String, dynamic>,
      );
      final cleaned = working.substring(contactMatch.end).trimLeft();
      return ParsedTurnaMessageText(
        text: cleaned,
        reply: reply,
        status: status,
        contact: payload,
      );
    } catch (_) {
      return ParsedTurnaMessageText(text: raw);
    }
  }

  return ParsedTurnaMessageText(text: working, reply: reply, status: status);
}

String buildTurnaReplyEncodedText({
  required TurnaReplyPayload reply,
  required String text,
}) {
  final encoded = base64UrlEncode(
    utf8.encode(jsonEncode(reply.toMap())),
  ).replaceAll('=', '');
  return '[[turna-reply:$encoded]]\n$text';
}

String buildTurnaStatusEncodedText({
  required TurnaStatusMessagePayload status,
  String text = '',
}) {
  final encoded = base64UrlEncode(
    utf8.encode(jsonEncode(status.toMap())),
  ).replaceAll('=', '');
  final trimmedText = text.trim();
  if (trimmedText.isEmpty) {
    return '[[turna-status:$encoded]]';
  }
  return '[[turna-status:$encoded]]\n$trimmedText';
}

String buildTurnaLocationEncodedText({required TurnaLocationPayload location}) {
  final encoded = base64UrlEncode(
    utf8.encode(jsonEncode(location.toMap())),
  ).replaceAll('=', '');
  return '[[turna-location:$encoded]]';
}

String buildTurnaContactEncodedText({
  required TurnaSharedContactPayload contact,
}) {
  final encoded = base64UrlEncode(
    utf8.encode(jsonEncode(contact.toMap())),
  ).replaceAll('=', '');
  return '[[turna-contact:$encoded]]';
}

String sanitizeTurnaChatPreviewText(String raw) {
  final parsed = parseTurnaMessageText(raw);
  if (parsed.deletedForEveryone) return parsed.text;
  if (parsed.location != null) {
    return parsed.location!.previewLabel;
  }
  if (parsed.contact != null) {
    return parsed.contact!.previewLabel;
  }
  final cleaned = parsed.text.trim();
  if (cleaned.isNotEmpty) return cleaned;
  if (parsed.status != null) {
    return parsed.status!.previewLabel;
  }
  return parsed.reply?.previewText ?? raw;
}
