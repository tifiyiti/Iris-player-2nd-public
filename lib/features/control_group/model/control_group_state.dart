import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';

part 'control_group_state.freezed.dart';
part 'control_group_state.g.dart';

/// Persisted state of the one-handed bottom control-group switch.
///
/// [group] and [floatingButtonEnabled]/[floatingX]/[floatingY] survive app
/// restarts (KV-backed), while the floating button's live drag uses memory-only
/// frames and commits once on release.
@freezed
abstract class ControlGroupState with _$ControlGroupState {
  const factory ControlGroupState({
    /// Currently shown bottom group (defaults to the legacy playback row).
    @Default(PlayerControlGroup.playback) PlayerControlGroup group,

    /// Whether the draggable floating switch button is shown (More menu).
    ///
    /// This `true` is the DESKTOP factory default and the read-compat value for
    /// JSON written before the field existed; phones construct their state with
    /// it OFF instead (see [ControlGroupStore]).
    @Default(true) bool floatingButtonEnabled,

    /// Floating button position as a fraction of the host-minus-button box
    /// (0..1), so it survives window/video resizes.
    @Default(0.5) double floatingX,
    @Default(0.72) double floatingY,
  }) = _ControlGroupState;

  factory ControlGroupState.fromJson(Map<String, dynamic> json) =>
      _$ControlGroupStateFromJson(json);
}
