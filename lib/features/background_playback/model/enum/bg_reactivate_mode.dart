/// What a「仅当前」re-activation does to the 副音 queue when the gate is
/// (re)opened for the current foreground.
///
/// The gate is a pure play/stop permission (see [BackgroundPlaybackState.gateOpen]);
/// stopping it persists across every scope and media switch until the user opens
/// it again. This mode decides which 副音 track that next open lands on:
/// - [sameBg] keeps the file already loaded, so the user resumes the previous
///   track;
/// - [nextBg] advances the queue one step (wrap; a one-item list stays on
///   itself), so a repeated "this video's audio annoys me" lands on a NEW track.
///
/// Persisted as the `bg.reactivateMode` AUX row; only consulted under
/// [BgApplyScope.currentOnly].
enum BgReactivateMode {
  sameBg,
  nextBg,
}
