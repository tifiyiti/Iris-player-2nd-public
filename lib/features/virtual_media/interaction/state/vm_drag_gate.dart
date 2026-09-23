import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';

/// What the player hooks do with a cross-segment seek target.
enum VmDragSeekDecision {
  /// Seek / switch immediately (taps, same-segment ticks, direct strategy).
  seekNow,

  /// Drag in progress under the preview strategy: stash the virtual target,
  /// keep the picture, switch once on release.
  stashPreview,
}

/// Pure gate mapping (strategy, dragging, crossSegment) to a decision.
///
/// - Taps / gestures / keyboard (not dragging) always act immediately —
///   the strategy only governs drag ticks.
/// - Same-segment drag ticks always seek live under every strategy.
/// - Hidden [VmCrossSegmentDragStrategy.clampToCurrent] is never offered in
///   settings; if a stale row ever arrives here it falls back to direct
///   behavior instead of freezing the picture.
VmDragSeekDecision decideVmDragSeek({
  required VmCrossSegmentDragStrategy strategy,
  required bool isDragging,
  required bool crossSegment,
}) {
  if (!isDragging || !crossSegment) return VmDragSeekDecision.seekNow;
  return switch (strategy) {
    VmCrossSegmentDragStrategy.directSwitch => VmDragSeekDecision.seekNow,
    VmCrossSegmentDragStrategy.previewOnRelease =>
      VmDragSeekDecision.stashPreview,
    // Hidden from settings — degrade to direct, never to a dead picture.
    VmCrossSegmentDragStrategy.clampToCurrent => VmDragSeekDecision.seekNow,
  };
}

/// Throttle guard for cross-segment opens during a live drag: at most one
/// open per [window]. Dropped ticks are covered by the release commit, so
/// the finger's final position is never lost.
bool vmCrossJumpAllowed(
  DateTime? lastJumpAt,
  DateTime now, {
  Duration window = const Duration(milliseconds: 300),
}) {
  if (lastJumpAt == null) return true;
  return now.difference(lastJumpAt) >= window;
}

/// Whether a cross-segment seek should be STASHED for the release commit
/// instead of opened now.
///
/// Only live drag ticks are throttled. The drag-release commit runs with
/// `dragging == false` and MUST bypass the window — otherwise a slow tick's
/// final position is re-stashed and never applied (and the leftover target
/// can hijack a later, unrelated drag's release).
bool vmCrossJumpStashes({
  required bool dragging,
  required bool withinThrottleWindow,
}) =>
    dragging && withinThrottleWindow;
