import 'dart:convert';

import 'turna_contact_models.dart';
import 'turna_location_models.dart';

final RegExp _kTurnaReplyMarkerPattern = RegExp(
  r'^\[\[turna-reply:([A-Za-z0-9_-]+)\]\]\n?',
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

class ParsedTurnaMessageText {
  const ParsedTurnaMessageText({
    required this.text,
    this.reply,
    this.location,
    this.contact,
    this.deletedForEveryone = false,
  });

  final String text;
  final TurnaReplyPayload? reply;
  final TurnaLocationPayload? location;
  final TurnaSharedContactPayload? contact;
  final bool deletedForEveryone;
}

class _PinnedMessageDraft {
  const _PinnedMessageDraft({
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

  factory _PinnedMessageDraft.fromMap(Map<String, dynamic> map) {
    return _PinnedMessageDraft(
      messageId: (map['messageId'] ?? '').toString(),
      senderLabel: (map['senderLabel'] ?? '').toString(),
      previewText: (map['previewText'] ?? '').toString(),
    );
  }
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
        contact: payload,
      );
    } catch (_) {
      return ParsedTurnaMessageText(text: raw);
    }
  }

  return ParsedTurnaMessageText(text: working, reply: reply);
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
  return parsed.reply?.previewText ?? raw;
}
