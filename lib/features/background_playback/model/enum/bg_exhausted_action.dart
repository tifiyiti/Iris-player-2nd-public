/// What happens when the CURRENT 副音 file finishes while the foreground keeps
/// playing (the "bg 可播放超过 bg1" boundary).
///
/// Chosen from the shared alignment popup and persisted as the
/// `bg.exhaustedAction` AUX row.
enum BgExhaustedAction {
  /// The next queued 副音 file (bg2) starts at its own 00:00 aligned to the
  /// foreground moment the previous file ended — the continuous "顺次补位"
  /// chain. Default.
  nextBg,

  /// 副音 stops here and the foreground returns to its own original audio,
  /// un-ducked ([BackgroundVolumePolicy]). No further 副音 file plays.
  stopRestoreFg,
}
