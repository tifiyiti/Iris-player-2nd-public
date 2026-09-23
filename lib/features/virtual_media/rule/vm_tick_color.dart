/// ARGB color plumbing for the virtual-media segment boundary ticks.
///
/// The ticks stay thin WHITE vertical bars by default (the industry
/// recommendation for axis ticks: max contrast on any track), sticking out
/// past the slider axis by `vmMarkTickExtent` per side; the color is
/// user-customizable through the metadata-driven row
/// `virtualmedia.markTickColor` (int ARGB, alpha locked at FF). Pure
/// functions only — persistence lives in AppStore (`vmMarkTickColor`),
/// decoding of stored rows funnels through [sanitizeVmTickColorArgb] so a
/// corrupt row degrades to opaque white instead of breaking the slider.
library;

/// Default tick color: opaque white.
const int kVmTickColorDefaultArgb = 0xFFFFFFFF;

/// Preset swatches offered by the color editor. All opaque (alpha input is
/// locked at FF — translucent ticks vanish on the progress axis); the
/// default (white, the industry recommendation for axis ticks) is first.
const List<int> kVmTickColorPresets = <int>[
  0xFFFFFFFF,
  0xFFFFEB3B,
  0xFF00BCD4,
  0xFFFF9800,
  0xFFE91E63,
  0xFF8BC34A,
  0xFFF44336,
  0xFF2196F3,
  0xFF4CAF50,
  0xFF9C27B0,
  0xFFFF5722,
  0xFF000000,
];

/// Validates a stored `virtualmedia.markTickColor` row (decimal int string,
/// tolerating `#RRGGBB` / `#AARRGGBB` for forward compatibility).
/// Anything unparseable or outside the 32-bit ARGB range degrades to
/// [kVmTickColorDefaultArgb] — corrupt settings must never break playback UI.
int sanitizeVmTickColorArgb(String? raw) {
  if (raw == null) return kVmTickColorDefaultArgb;
  final t = raw.trim();
  if (t.isEmpty) return kVmTickColorDefaultArgb;
  if (t.startsWith('#')) {
    final hex = t.substring(1);
    if (hex.length != 6 && hex.length != 8) {
      return kVmTickColorDefaultArgb;
    }
    final full = hex.length == 6 ? 'FF$hex' : hex;
    final v = int.tryParse(full, radix: 16);
    if (v == null) return kVmTickColorDefaultArgb;
    return v;
  }
  final v = int.tryParse(t);
  if (v == null || v < 0 || v > 0xFFFFFFFF) {
    return kVmTickColorDefaultArgb;
  }
  return v;
}

/// Uppercase `#AARRGGBB` label for settings subtitles.
String vmTickColorLabel(int argb) {
  final v = argb & 0xFFFFFFFF;
  return '#${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
