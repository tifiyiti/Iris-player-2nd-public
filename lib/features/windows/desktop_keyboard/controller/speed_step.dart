/// Pure speed-step semantics for the X/C keys (PotPlayer parity).
///
/// Steps to the next/previous entry of a sorted stop list. The ends SATURATE
/// (no wrap): a held key keeps auto-repeating, so it must park on the min/max
/// instead of jumping back to the other extreme. [direction] > 0 = faster.
double nextSpeedStop(double current, int direction, List<double> stops) {
  if (direction > 0) {
    for (final s in stops) {
      if (s > current + 1e-9) return s;
    }
    return stops.last;
  }
  var next = stops.first;
  for (final s in stops) {
    if (s < current - 1e-9) next = s;
  }
  return next;
}
