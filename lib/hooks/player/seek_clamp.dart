/// Shared millisecond-precision seek clamp for the player hooks.
///
/// Both backends (media_kit, fvp) clamp a user seek target into
/// `[0, totalMs]`. A seconds-based comparison truncates sub-second precision
/// and misses negative sub-second targets entirely
/// (`Duration(-500ms).inSeconds == 0`), so this helper compares
/// [inMilliseconds] on both sides.
Duration clampSeekTarget(Duration newPosition, Duration total) {
  if (newPosition.inMilliseconds < 0) return Duration.zero;
  if (newPosition.inMilliseconds > total.inMilliseconds) return total;
  return newPosition;
}
