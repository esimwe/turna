import '../features/chat/turna_chat_models.dart';

DateTime? parseTurnaLocalDateTime(String? raw) {
  final iso = raw?.trim();
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}

int compareTurnaTimestamps(String? left, String? right) {
  final leftDate = parseTurnaLocalDateTime(left);
  final rightDate = parseTurnaLocalDateTime(right);
  if (leftDate != null && rightDate != null) {
    return leftDate.compareTo(rightDate);
  }
  if (leftDate != null) return 1;
  if (rightDate != null) return -1;
  return (left ?? '').compareTo(right ?? '');
}

String formatTurnaLocalClock(String? raw) {
  final dt = parseTurnaLocalDateTime(raw);
  if (dt == null) return '';
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String formatTurnaDisplayPhone(String? raw) {
  final source = raw?.trim() ?? '';
  if (source.isEmpty || !source.startsWith('+')) return source;

  final digits = source.replaceAll(RegExp(r'\D+'), '');
  if (digits.length < 7) return source;

  if (digits.startsWith('90') && digits.length == 12) {
    final national = digits.substring(2);
    return '+90 ${national.substring(0, 3)} ${national.substring(3, 6)} ${national.substring(6, 8)} ${national.substring(8, 10)}';
  }

  if (digits.startsWith('44') && digits.length == 12) {
    final national = digits.substring(2);
    return '+44 ${national.substring(0, 4)} ${national.substring(4)}';
  }

  final countryLength = digits.length > 11 ? 3 : 2;
  final country = digits.substring(0, countryLength);
  final national = digits.substring(countryLength);
  final groups = <String>[];
  var cursor = 0;
  while (cursor < national.length) {
    final remaining = national.length - cursor;
    final take = remaining > 4
        ? 3
        : remaining > 2
        ? 2
        : remaining;
    groups.add(national.substring(cursor, cursor + take));
    cursor += take;
  }
  return '+$country ${groups.join(' ')}'.trim();
}

String? guessContentTypeForFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.m4v')) return 'video/x-m4v';
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.aac')) return 'audio/aac';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  if (lower.endsWith('.opus')) return 'audio/opus';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.txt')) return 'text/plain';
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.zip')) return 'application/zip';
  return 'application/octet-stream';
}

bool isTurnaAudioAttachment(ChatAttachment attachment) {
  final contentType = attachment.contentType.toLowerCase();
  if (contentType.startsWith('audio/')) return true;
  final fileName = (attachment.fileName ?? '').toLowerCase();
  return fileName.endsWith('.m4a') ||
      fileName.endsWith('.aac') ||
      fileName.endsWith('.mp3') ||
      fileName.endsWith('.wav') ||
      fileName.endsWith('.ogg') ||
      fileName.endsWith('.opus');
}

String turnaAttachmentFileExtension(ChatAttachment attachment) {
  final fileName = (attachment.fileName ?? '').trim();
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex >= 0 && dotIndex < fileName.length - 1) {
    return fileName.substring(dotIndex + 1).toLowerCase();
  }
  final contentType = attachment.contentType.toLowerCase().trim();
  if (contentType.contains('/')) {
    return contentType.split('/').last.toLowerCase();
  }
  return '';
}

bool turnaAttachmentHasImageContent(ChatAttachment attachment) {
  if (attachment.kind == ChatAttachmentKind.image) return true;
  final contentType = attachment.contentType.toLowerCase();
  if (contentType.startsWith('image/')) return true;
  final extension = turnaAttachmentFileExtension(attachment);
  return extension == 'jpg' ||
      extension == 'jpeg' ||
      extension == 'png' ||
      extension == 'webp' ||
      extension == 'gif' ||
      extension == 'heic' ||
      extension == 'heif';
}

bool turnaAttachmentHasVideoContent(ChatAttachment attachment) {
  if (attachment.kind == ChatAttachmentKind.video) return true;
  final contentType = attachment.contentType.toLowerCase();
  if (contentType.startsWith('video/')) return true;
  final extension = turnaAttachmentFileExtension(attachment);
  return extension == 'mp4' ||
      extension == 'mov' ||
      extension == 'm4v' ||
      extension == 'webm' ||
      extension == 'mkv' ||
      extension == 'avi';
}

bool turnaAttachmentHasPdfContent(ChatAttachment attachment) {
  final contentType = attachment.contentType.toLowerCase();
  if (contentType == 'application/pdf') return true;
  return turnaAttachmentFileExtension(attachment) == 'pdf';
}

bool isTurnaImageAttachment(ChatAttachment attachment) {
  if (attachment.kind == ChatAttachmentKind.file) return false;
  return turnaAttachmentHasImageContent(attachment);
}

bool isTurnaVideoAttachment(ChatAttachment attachment) {
  if (attachment.kind == ChatAttachmentKind.file) return false;
  return turnaAttachmentHasVideoContent(attachment);
}

String formatBytesLabel(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final display = value >= 10 || unitIndex == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$display ${units[unitIndex]}';
}

String replaceFileExtension(String fileName, String extension) {
  final dotIndex = fileName.lastIndexOf('.');
  final base = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
  return '$base.$extension';
}
