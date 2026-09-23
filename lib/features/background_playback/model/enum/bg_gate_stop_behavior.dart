/// What the quick-bar 副音 gate (and the bg stop button) does to the engine
/// when it CLOSES the gate — i.e. an explicit stop for the current media.
///
/// This is a resource-level choice, never a feature switch: the run (enabled,
/// queue, index, anchor) and the warm native instance always survive a gate
/// stop. It only decides how much of the loaded media is kept:
///
/// - [pause]: keep the media and its decoder/file handle loaded, just paused.
///   The next gate open re-runs the alignment plan instead of resuming the
///   remembered position.
/// - [unload]: release the media and its decoder/file handle (a true stop); the
///   next gate open reloads the file and re-aligns.
///
/// Distinct from disabling the feature (which also clears the run state) and
/// from `releaseResources` (which drops the warm instance too).
enum BgGateStopBehavior {
  /// 暂停媒体（下次重新对齐）: keep the media loaded, only pause it.
  pause,

  /// 卸载媒体资源（下次重新载入）: release the decoder/file handle.
  unload,
}
