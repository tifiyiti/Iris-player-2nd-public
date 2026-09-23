import 'package:freezed_annotation/freezed_annotation.dart';

part 'tag_play_state.freezed.dart';

/// In-memory state of the tag_play subsystem.
///
/// The tag/member/view-state data itself lives in Drift; this store carries
/// the small global session prefs: the pin order (pin ≠ filtering — it only
/// reorders the sheet so frequently-used tags sit on top) and which tag view
/// is currently driving playback (null = no-tag / original list).
@freezed
abstract class TagPlayState with _$TagPlayState {
  const factory TagPlayState({
    /// Globally pinned tag ids in display order (pinned first).
    @Default(<int>[]) List<int> pinnedTagIds,

    /// Tag whose filtered play view currently drives playback, if any.
    int? activeViewTagId,

    /// Return path of tag views: the ids entered BEFORE the active one,
    /// newest last (stack). Popping returns to the previous tag's own
    /// bookmark; an empty stack means exit goes back to the no-tag list.
    ///
    /// Only populated while [viewStackEnabled] is ON; forced empty when OFF
    /// so stale rows cannot resurface the jump-back row.
    @Default(<int>[]) List<int> viewStackTagIds,

    /// Whether the "previous view" return stack is offered at all.
    /// Off by default: the sheet's radio already shows the active tag, so
    /// jumping back to the previous one is an optional preference the user
    /// opts into (`tagplay.viewStackEnabled`). When OFF the outgoing tag is
    /// never stashed and the sheet never renders the jump-back row.
    @Default(false) bool viewStackEnabled,

    /// Whether the numeric command bar shows in the sheet. Defaults off —
    /// phones tap the rows directly; desktop overrides it to always-on (see
    /// [resolveTagPlayInputBarEnabled]), where the numpad keys need the bar.
    @Default(false) bool inputBarEnabled,

    /// Whether the command hint banner shows. Turning it off is the
    /// "permanently close" outcome of the banner's close dialog, undone from
    /// the settings row.
    @Default(true) bool inputHintEnabled,

    /// Global "ignore scenario" switch. When ON, the ACTIVE tag view resolves
    /// to the tag's whole active membership instead of the scenario's
    /// effective stream ∩ members. Only meaningful while a tag view drives
    /// playback — the no-tag path always keeps the scenario's own sources.
    @Default(false) bool ignoreScenario,

    /// Whether a SUCCESSFUL command closes a shortcut-opened sheet by itself.
    /// Desktop-only: the numpad entry keys are the sole door that opens the
    /// sheet with a prefill, so the More button and the phone tag gesture are
    /// unaffected. Failures keep the sheet open for correction.
    @Default(false) bool autoCloseOnSubmit,
  }) = _TagPlayState;
}
