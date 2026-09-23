/// Formats [duration] as `h:mm:ss` when it spans at least one hour, otherwise
/// `mm:ss`. Sign is dropped — callers prefix `+`/`-` for the A-B segment
/// readouts (lead-in / overflow).
///
/// Deliberately separate from `formatDurationToMinutes`, which renders total
/// minutes (`1h → "60:00"`); the segment readouts must stay readable at long
/// durations, so hours are kept distinct here.
String formatDurationHms(Duration duration) {
  final d = duration.isNegative ? -duration : duration;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '${two(m)}:${two(s)}';
}
