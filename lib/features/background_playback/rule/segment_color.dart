/// ARGB plumbing for the 副音 mapping-segment label colours.
///
/// A saved mapping segment carries an optional `colorArgb`; the foreground-axis
/// bars (editor) and the manager overview paint it. The colour is purely
/// cosmetic — it never participates in playback, overlap validation or
/// resolution. Rows written before v32 (or left unset) fall back to a stable
/// palette colour derived from the segment's start position, so the axis never
/// shows a flat grey and a given segment keeps the same colour across rebuilds.
///
/// Pure functions only; persistence lives on `MappingSegment.colorArgb` (a
/// Drift column). [normalizeSegmentColorArgb] locks alpha at FF — a translucent
/// label bar would vanish against the video and read as "no mapping".
library;

import 'dart:math';

/// Fallback colour used when a segment has no derivable colour. A saturated
/// orange stays legible on both light and dark video.
const int kSegmentColorDefaultArgb = 0xFFFF9800;

/// Preset swatches offered by the segment colour editor. All opaque; orange
/// (the fallback) is first so the palette and the derived default agree.
const List<int> kSegmentColorPresets = <int>[
  0xFFFF9800,
  0xFF2196F3,
  0xFF4CAF50,
  0xFFE91E63,
  0xFF9C27B0,
  0xFF009688,
  0xFFF44336,
  0xFFFFC107,
  0xFF3F51B5,
  0xFF00BCD4,
];

/// Forces alpha to FF and masks to 32 bits. Any colour a user picks (or a
/// corrupt stored value) funnels through here.
int normalizeSegmentColorArgb(int argb) => (argb & 0x00FFFFFF) | 0xFF000000;

/// A random palette colour for a brand-new segment (the "default random"
/// contract). [rng] is injectable for deterministic tests.
int randomSegmentColorArgb([Random? rng]) {
  final r = rng ?? Random();
  return kSegmentColorPresets[r.nextInt(kSegmentColorPresets.length)];
}

/// The colour to paint for a segment: the explicit choice when present, else a
/// stable palette colour derived from [seed] (the segment's `fgStartMs`).
int resolveSegmentColorArgb({int? explicit, required int seed}) {
  if (explicit != null) return normalizeSegmentColorArgb(explicit);
  final palette = kSegmentColorPresets;
  return palette[seed.abs() % palette.length];
}

/// Uppercase `#AARRGGBB` label for tooltips/subtitles.
String segmentColorLabel(int argb) {
  final v = normalizeSegmentColorArgb(argb) & 0xFFFFFFFF;
  return '#${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
