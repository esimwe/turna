import 'dart:math' as math;

import 'package:flutter/material.dart';

const int kComposerMediaLimit = 30;
const int kInlineAttachmentSoftLimitBytes = 64 * 1024 * 1024;
const int kDocumentAttachmentMaxBytes = 2 * 1024 * 1024 * 1024;
const int kStatusMaxVideoDurationSeconds = 60;
const int kInlineImagePickerQuality = 82;
const double kInlineImagePickerMaxDimension = 2200;
const double kInlineImageSdMaxDimension = 1600;
const double kInlineImageHdMaxDimension = 2560;
const int kInlineVideoStandardMaxHeight = 720;
const int kInlineVideoHdMaxHeight = 1080;
const int kInlineVideoStandardBitrate = 1800000;
const int kInlineVideoHdBitrate = 4200000;
const Offset kComposerOverlayDefaultPosition = Offset(0.5, 0.5);
const Rect kComposerFullCropRectNormalized = Rect.fromLTWH(0, 0, 1, 1);
const double kComposerCropInitialInset = 0.08;
const double kComposerCropMinSide = 0.18;
const List<Color> kComposerPaletteStops = [
  Color(0xFFFFFFFF),
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFD60A),
  Color(0xFF34C759),
  Color(0xFF00C7BE),
  Color(0xFF0A84FF),
  Color(0xFF5E5CE6),
  Color(0xFFBF5AF2),
  Color(0xFFFF2D55),
];
const List<MediaCropPreset> kComposerCropPresets = [
  MediaCropPreset(id: 'free', label: 'Serbest', freeform: true),
  MediaCropPreset(id: 'fit', label: 'Sigdir', fullImage: true),
  MediaCropPreset(id: 'original', label: 'Orijinal', useOriginalAspect: true),
  MediaCropPreset(id: 'square', label: 'Kare', aspectRatio: 1),
  MediaCropPreset(id: '2x3', label: '2:3', aspectRatio: 2 / 3),
  MediaCropPreset(id: '3x5', label: '3:5', aspectRatio: 3 / 5),
  MediaCropPreset(id: '3x4', label: '3:4', aspectRatio: 3 / 4),
  MediaCropPreset(id: '4x5', label: '4:5', aspectRatio: 4 / 5),
  MediaCropPreset(id: '5x7', label: '5:7', aspectRatio: 5 / 7),
  MediaCropPreset(id: '9x16', label: '9:16', aspectRatio: 9 / 16),
];

class MediaCropPreset {
  const MediaCropPreset({
    required this.id,
    required this.label,
    this.aspectRatio,
    this.useOriginalAspect = false,
    this.fullImage = false,
    this.freeform = false,
  });

  final String id;
  final String label;
  final double? aspectRatio;
  final bool useOriginalAspect;
  final bool fullImage;
  final bool freeform;
}

Color composerColorForValue(double value) {
  final clamped = value.clamp(0.0, 1.0).toDouble();
  if (kComposerPaletteStops.length == 1) return kComposerPaletteStops.first;
  final scaled = clamped * (kComposerPaletteStops.length - 1);
  final lowerIndex = scaled.floor();
  final upperIndex = math.min(lowerIndex + 1, kComposerPaletteStops.length - 1);
  final t = scaled - lowerIndex;
  return Color.lerp(
        kComposerPaletteStops[lowerIndex],
        kComposerPaletteStops[upperIndex],
        t,
      ) ??
      kComposerPaletteStops[lowerIndex];
}
