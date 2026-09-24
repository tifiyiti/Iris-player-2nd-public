import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';

part 'control_group_state.freezed.dart';
part 'control_group_state.g.dart';

/// Persisted state of the one-handed bottom control-group switch.
///
/// [group], the two per-orientation visibility flags and [floatingX]/[floatingY]
/// survive app restarts (KV-backed), while the floating button's live drag uses
/// memory-only frames and commits once on release.
@freezed
abstract class ControlGroupState with _$ControlGroupState {
  const factory ControlGroupState({
    /// Currently shown bottom group (defaults to the legacy playback row).
    @Default(PlayerControlGroup.playback) PlayerControlGroup group,

    /// Whether the draggable switch button is shown in PORTRAIT (More menu).
    ///
    /// Portrait ships ON: it is the phone's primary, one-handed orientation,
    /// where the floater is the most reachable. Landscape ships OFF (see
    /// [floatingButtonLandscape]) because the bottom bar already fits in one
    /// row there, so the extra floater only adds clutter.
    @Default(true) bool floatingButtonPortrait,

    /// Whether the draggable switch button is shown in LANDSCAPE.
    @Default(false) bool floatingButtonLandscape,

    /// Floating button position as a fraction of the host-minus-button box
    /// (0..1), so it survives window/video resizes. Shared by both orientations.
    @Default(0.5) double floatingX,
    @Default(0.72) double floatingY,
  }) = _ControlGroupState;

  /// Reads persisted state.
  ///
  /// Legacy-JSON upgrading (the pre-orientation single `floatingButtonEnabled`)
  /// lives in [ControlGroupStore.load], NOT here: a hand-written `fromJson`
  /// body would make json_serializable drop the generated `_$…FromJson` helper.
  factory ControlGroupState.fromJson(Map<String, dynamic> json) =>
      _$ControlGroupStateFromJson(json);
}
