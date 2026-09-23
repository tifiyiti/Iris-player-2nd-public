import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/scrub_drag_state.dart';

/// The single writer of [ScrubDragState].
///
/// Every scrub surface (ring dial / arc / time-lens / snake / circle slider /
/// linear slider / region gesture / align panel) declares its session here
/// instead of poking `PlayerUiState.isSeeking`/`isHoldingDown` directly. Owner
/// ids make the calls idempotent and let a widget's `dispose` release its own
/// session without touching another surface's.
class ScrubDragStore extends Store<ScrubDragState> {
  ScrubDragStore() : super(const ScrubDragState());

  /// Arms a real scrub/drag session for [owner].
  void beginSeek(String owner) {
    if (state.seekOwners.contains(owner)) return;
    set(state.copyWith(seekOwners: <String>{...state.seekOwners, owner}));
  }

  /// Ends [owner]'s scrub session (no-op when it never began).
  void endSeek(String owner) {
    if (!state.seekOwners.contains(owner)) return;
    set(state.copyWith(
        seekOwners: <String>{...state.seekOwners}..remove(owner)));
  }

  /// Arms a keep-alive press for [owner] (never pauses / never seeks).
  void beginHold(String owner) {
    if (state.holdOwners.contains(owner)) return;
    set(state.copyWith(holdOwners: <String>{...state.holdOwners, owner}));
  }

  /// Ends [owner]'s keep-alive press.
  void endHold(String owner) {
    if (!state.holdOwners.contains(owner)) return;
    set(state.copyWith(
        holdOwners: <String>{...state.holdOwners}..remove(owner)));
  }

  /// Defensive teardown used on player/session/route changes: NO gesture can
  /// survive a media swap, so every session is dropped. This is the latch-proof
  /// backstop the old bare booleans never had.
  void resetAll() {
    if (state.seekOwners.isEmpty && state.holdOwners.isEmpty) return;
    set(const ScrubDragState());
  }
}

ScrubDragStore useScrubDragStore() => create(() => ScrubDragStore());

/// Stable owner ids for every scrub surface. Owner identity (instead of a
/// shared boolean) is what makes a surface's `dispose` release only its own
/// session; the strings also name the owner in `log.dial` output.
abstract final class ScrubOwners {
  static const String ringDial = 'ringDial';
  static const String arc = 'arc';
  static const String timeLens = 'timeLens';
  static const String snake = 'snake';
  static const String circleSlider = 'circleSlider';
  static const String linearSlider = 'linearSlider';
  static const String regionGesture = 'regionGesture';
  static const String areaGesture = 'areaGesture';
  static const String alignPanel = 'alignPanel';
}
