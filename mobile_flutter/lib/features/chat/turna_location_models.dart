import 'dart:math' as math;

import '../../core/turna_profile_models.dart';

enum TurnaLocationShareMode { current, live }

class TurnaLocationPayload {
  const TurnaLocationPayload({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.title,
    this.subtitle,
    this.live = false,
    this.liveId,
    this.startedAt,
    this.expiresAt,
    this.updatedAt,
    this.endedAt,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String? title;
  final String? subtitle;
  final bool live;
  final String? liveId;
  final String? startedAt;
  final String? expiresAt;
  final String? updatedAt;
  final String? endedAt;

  bool get hasEnded => (endedAt?.trim().isNotEmpty ?? false) || !isLiveActive;

  bool get isLiveActive {
    if (!live) return false;
    if (endedAt?.trim().isNotEmpty ?? false) return false;
    final expires = DateTime.tryParse(expiresAt ?? '');
    if (expires == null) return false;
    return DateTime.now().isBefore(expires.toLocal());
  }

  String get previewLabel {
    if (live) {
      return isLiveActive ? 'Canlı konum' : 'Canlı konum (sona erdi)';
    }
    final trimmedTitle = title?.trim() ?? '';
    if (trimmedTitle.isNotEmpty) return trimmedTitle;
    return 'Konum';
  }

  String get displayTitle {
    if (live) return 'Canlı konum';
    final trimmedTitle = title?.trim() ?? '';
    if (trimmedTitle.isNotEmpty) return trimmedTitle;
    return 'Konum';
  }

  String get displaySubtitle {
    if (live) {
      if (endedAt?.trim().isNotEmpty ?? false) {
        return 'Paylaşım sona erdi';
      }
      final expires = DateTime.tryParse(expiresAt ?? '');
      if (expires != null) {
        final remaining = expires.toLocal().difference(DateTime.now());
        if (!remaining.isNegative) {
          return 'Kalan ${formatTurnaDurationShort(remaining)}';
        }
      }
      final updated = DateTime.tryParse(updatedAt ?? '');
      if (updated != null) {
        return 'Son güncelleme ${formatTurnaClockLabel(updated.toLocal())}';
      }
      return 'Canlı paylaşım';
    }

    final trimmedSubtitle = subtitle?.trim() ?? '';
    if (trimmedSubtitle.isNotEmpty) return trimmedSubtitle;
    return formatTurnaLocationCoordinates(latitude, longitude);
  }

  TurnaLocationPayload copyWith({
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? title,
    String? subtitle,
    bool? live,
    String? liveId,
    String? startedAt,
    String? expiresAt,
    String? updatedAt,
    String? endedAt,
  }) {
    return TurnaLocationPayload(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      live: live ?? this.live,
      liveId: liveId ?? this.liveId,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': accuracyMeters,
    'title': title,
    'subtitle': subtitle,
    'live': live,
    'liveId': liveId,
    'startedAt': startedAt,
    'expiresAt': expiresAt,
    'updatedAt': updatedAt,
    'endedAt': endedAt,
  };

  factory TurnaLocationPayload.fromMap(Map<String, dynamic> map) {
    double? parseDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse('$value');
    }

    return TurnaLocationPayload(
      latitude: parseDouble(map['latitude']) ?? 0,
      longitude: parseDouble(map['longitude']) ?? 0,
      accuracyMeters: parseDouble(map['accuracyMeters']),
      title: turnaProfileNullableString(map['title']),
      subtitle: turnaProfileNullableString(map['subtitle']),
      live: map['live'] == true,
      liveId: turnaProfileNullableString(map['liveId']),
      startedAt: turnaProfileNullableString(map['startedAt']),
      expiresAt: turnaProfileNullableString(map['expiresAt']),
      updatedAt: turnaProfileNullableString(map['updatedAt']),
      endedAt: turnaProfileNullableString(map['endedAt']),
    );
  }
}

class TurnaLocationSelection {
  const TurnaLocationSelection({
    required this.payload,
    required this.mode,
    this.liveDuration,
  });

  final TurnaLocationPayload payload;
  final TurnaLocationShareMode mode;
  final Duration? liveDuration;
}

String formatTurnaLocationCoordinates(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

String formatTurnaDurationShort(Duration duration) {
  final clamped = duration.isNegative ? Duration.zero : duration;
  if (clamped.inHours >= 1) {
    final hours = clamped.inHours;
    final minutes = clamped.inMinutes.remainder(60);
    return minutes > 0 ? '$hours sa $minutes dk' : '$hours sa';
  }
  final minutes = math.max(1, clamped.inMinutes);
  return '$minutes dk';
}

String formatTurnaClockLabel(DateTime value) {
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
