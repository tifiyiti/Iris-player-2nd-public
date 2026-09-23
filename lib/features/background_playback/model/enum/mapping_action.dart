/// What a 副音 mapping segment does while the foreground is inside its range.
enum MappingAction {
  /// Play the referenced background file across its own [start,end] window.
  playMedia,

  /// No 副音 for this foreground window (原音 only).
  silence,
}
