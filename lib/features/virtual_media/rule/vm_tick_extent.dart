/// Extent plumbing for virtual-media segment boundary ticks.
///
/// Extent = pixels the vertical bar sticks out past the progress axis on
/// EACH side (linear track: `top-extent`, height `+2*extent`; radial arcs:
/// `radius±extent`). 0 means flush with the axis (a 2px line inside the
/// track, never hidden). Pure functions only — persistence lives in
/// AppStore (`markTickExtent`) via the `virtualmedia.markTickExtent` row.
library;

/// Default extent: 3px per side (halved from the legacy 6px/±9px).
const int kVmTickExtentDefaultPx = 3;

/// Minimum extent: flush with the axis.
const int kVmTickExtentMinPx = 0;

/// Maximum extent.
const int kVmTickExtentMaxPx = 10;

/// Validates a stored `virtualmedia.markTickExtent` row (decimal int
/// string). Out-of-range values clamp; garbage degrades to
/// [kVmTickExtentDefaultPx].
int sanitizeVmTickExtentPx(String? raw) {
  if (raw == null) return kVmTickExtentDefaultPx;
  final v = int.tryParse(raw.trim());
  if (v == null) return kVmTickExtentDefaultPx;
  return v.clamp(kVmTickExtentMinPx, kVmTickExtentMaxPx);
}

/// `Npx` label for settings subtitles.
String vmTickExtentLabel(int px) => '${px.clamp(kVmTickExtentMinPx, kVmTickExtentMaxPx)}px';
