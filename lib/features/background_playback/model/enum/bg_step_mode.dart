/// How a 副音 queue step (user next/prev) affects the FOREGROUND runtime.
///
/// This is deliberately a separate axis from `BgSeekLink`: the link axis governs
/// continuous position mirroring (dragging a slider), while this axis governs
/// only the discrete step ACTION, which is the common way users change tracks.
enum BgStepMode {
  /// Stepping 副音 swaps only the 副音 track; the foreground position is left
  /// untouched. The default — what users want most of the time.
  swapOnly,

  /// Stepping 副音 follows the link: under `linked` + `high` the mapped target
  /// is applied to the foreground, rolling across foreground files as needed.
  followLink,
}
