import 'package:freezed_annotation/freezed_annotation.dart';

part 'ab_loop_state.freezed.dart';

/// A-B section-repeat state (capability_matrix §3 🟡). Ephemeral: never
/// persisted, resets naturally when playback moves to another item.
@freezed
abstract class AbLoopState with _$AbLoopState {
  const factory AbLoopState({
    Duration? pointA,
    Duration? pointB,

    /// Loop engine armed — requires both points; cleared by [AbEvent.clear].
    @Default(false) bool enabled,
  }) = _AbLoopState;
}

/// User intents driving the reducer (keyboard B [/] \\ today, gestures tomorrow).
enum AbEvent { setPointA, setPointB, quickToggle, toggleSectionRepeat, clear }

/// Pure transition logic shared by keyboard executor and any future phone UI.
///
/// Semantics (PotPlayer-flavored simplification):
/// - setPointA always rewrites A (and keeps B only if it stays ahead);
///   enabling requires both bounds afterwards.
/// - setPointB only accepts positions at/after A.
/// - quickToggle: with both bounds present this arms/disarms the loop;
///   otherwise it RESETS everything (fastest way to bail out).
/// - toggleSectionRepeat arms only when both bounds exist; never mutates them.
AbLoopState abReduce(
  AbLoopState state,
  AbEvent event,
  Duration position,
) {
  switch (event) {
    case AbEvent.setPointA:
      final b = state.pointB;
      return AbLoopState(
        pointA: position,
        pointB: b != null && b >= position ? b : null,
        enabled: false,
      );
    case AbEvent.setPointB:
      final a = state.pointA ?? Duration.zero;
      // B at or before A is a zero-length/degenerate section: ignoring it
      // keeps enabled=true reachable only for a real A→B span, so the engine
      // can never seek-storm between identical points.
      if (position <= a) return state;
      return AbLoopState(pointA: a, pointB: position, enabled: true);
    case AbEvent.quickToggle:
      if (!state.enabled && state.pointA != null && state.pointB != null) {
        return state.copyWith(enabled: true);
      }
      return const AbLoopState(); // nothing usable → full reset
    case AbEvent.toggleSectionRepeat:
      if (state.pointA == null || state.pointB == null) return state;
      return state.copyWith(enabled: !state.enabled);
    case AbEvent.clear:
      return const AbLoopState();
  }
}
