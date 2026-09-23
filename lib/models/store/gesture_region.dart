import 'package:flutter/cupertino.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'gesture_region.freezed.dart';
part 'gesture_region.g.dart';

const String kLayoutDefault = 'region';
const String kLayoutRegion = 'region';
const String kLayoutRegionPortrait = 'regionPortrait';
const String kLayoutRegionRightSide = 'regionRightSide';
const String kLayoutRegionLeftSide = 'regionLeftSide';

/// Deprecated aliases — kept for legacy blob migration.
@Deprecated('Use kLayoutRegionRightSide')
const String kLayoutRightHand = 'rightHand';
@Deprecated('Use kLayoutRegionLeftSide')
const String kLayoutLeftHand = 'leftHand';

/// Tag-play profile: cloned from the default layout with an added top-strip
/// double-tap zone that opens the tag play sheet. Old profiles are untouched.
/// Deprecated: meta now uses unified tag-play分区 for all region profiles.
@Deprecated('Use kLayoutRegion* with tag strip')
const String kLayoutTagPlay = 'tagPlay';
@Deprecated('Use kLayoutRegionRightSide')
const String kLayoutTagPlayRightSide = 'tagPlayRightSide';
@Deprecated('Use kLayoutRegionLeftSide')
const String kLayoutTagPlayLeftSide = 'tagPlayLeftSide';

enum GestureIntent {
  tap,
  doubleTap,

  longPress,
  longPressPanHorizontal,
  longPressPanVertical,

  panHorizontal,
  panVertical,

  hover,
}

enum GestureActionType {
  none,

  // Playback
  playPause,
  play,
  pause,
  toggleControls,

  // Seeking
  adjustSeekStep,
  seekForward,
  seekBackward,
  seekTo,

  // Rate
  // Speed (IMPORTANT SPLIT)
  activateTransientSpeed, // long press → apply immediately
  updateTransientSpeed, // long press + pan
  deactivateTransientSpeed, // release → restore

  showPlaybackRateSelector, // long press (mode B)
  updatePlaybackRateFromSelector, // pan

  // UI
  showProgress,
  toggleFullscreen,

  // Tag play
  openTagPlaySheet,

  // System
  adjustVolume,
  adjustBrightness,
}

@freezed
abstract class GestureAction with _$GestureAction {
  const factory GestureAction({
    required GestureActionType type,

    // Optional parameters (executor interprets them)
    double? value,
    Duration? duration,
  }) = _GestureAction;

  factory GestureAction.fromJson(Map<String, dynamic> json) => _$GestureActionFromJson(json);
}

class RectConverter implements JsonConverter<Rect, Map<String, dynamic>> {
  const RectConverter();

  @override
  Rect fromJson(Map<String, dynamic> json) {
    return Rect.fromLTWH(
      (json['left'] as num).toDouble(),
      (json['top'] as num).toDouble(),
      (json['width'] as num).toDouble(),
      (json['height'] as num).toDouble(),
    );
  }

  @override
  Map<String, dynamic> toJson(Rect rect) {
    return {
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
  }
}

@freezed
abstract class GestureRegion with _$GestureRegion {
  const factory GestureRegion({
    @RectConverter() required Rect normalizedRect, // normalized 0..1
    required GestureAction action,
  }) = _GestureRegion;

  factory GestureRegion.fromJson(Map<String, dynamic> json) => _$GestureRegionFromJson(json);
}

@freezed
abstract class GestureLayout with _$GestureLayout {
  const factory GestureLayout({
    required GestureIntent intent,
    required List<GestureRegion> regions,
  }) = _GestureLayout;

  factory GestureLayout.fromJson(Map<String, dynamic> json) => _$GestureLayoutFromJson(json);
}

GestureAction resolveAction({
  required GestureIntent intent,
  required Offset normalizedPos,
  required Map<GestureIntent, GestureLayout> layouts,
}) {
  final layout = layouts[intent];
  if (layout == null) return const GestureAction(type: GestureActionType.none);

  for (final region in layout.regions) {
    if (region.normalizedRect.contains(normalizedPos)) {
      return region.action;
    }
  }

  return const GestureAction(type: GestureActionType.none);
}
