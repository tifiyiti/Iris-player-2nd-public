import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/models/store/player_ui_state.dart';

part 'scrub_drag_state.freezed.dart';

/// Kind of scrub-surface session a surface holds.
///
/// - [seek]: a real scrub/drag. The surface pauses the player and issues live
///   seeks; it owns the slider preview and must stand the 副音 mirror down.
/// - [hold]: a press that only keeps the UI alive (dial corner long-press).
///   It never pauses and never seeks, so it must NOT gate preview syncing nor
///   the 副音 transport mirror.
enum ScrubDragKind { seek, hold }

/// The ONE owner of scrub-drag state (see the extension methods below).
///
/// Why this type exists: `isSeeking`/`isHoldingDown` used to be two booleans on
/// [PlayerUiState] written by nine widgets with no owner and no defensive
/// reset. A single lost `onPanCancel`/`onPanEnd` (rebuild, media flip) latched
/// them true forever, which froze every slider preview, pinned the control bar
/// visible and made the 副音 mirror believe a drag was still running. Modelling
/// the sessions as owner SETS makes begin/end idempotent, lets one surface's
/// teardown never clobber another's session, and makes "a drag is in progress"
/// a single derived truth.
@freezed
abstract class ScrubDragState with _$ScrubDragState {
  const factory ScrubDragState({
    /// Surfaces currently holding a seek/drag session (by owner id).
    @Default(<String>{}) Set<String> seekOwners,

    /// Surfaces currently holding a keep-alive press (by owner id).
    @Default(<String>{}) Set<String> holdOwners,
  }) = _ScrubDragState;

  const ScrubDragState._();

  /// True while any surface is actively scrubbing (paused + live-seeking).
  /// Read by the 副音 runtime to stand its position mirror down and by the
  /// player hooks' drag-release commit.
  bool get isScrubbing => seekOwners.isNotEmpty;

  /// True for a seek drag OR a keep-alive hold. Completion suppression and the
  /// control bar's "don't auto-hide under the finger" rule read this (a corner
  /// long-press must keep suppressing completion, exactly as before).
  bool get isHolding => seekOwners.isNotEmpty || holdOwners.isNotEmpty;

  /// Either kind in progress.
  bool get any => isScrubbing || isHolding;
}

/// Whether the idle timer may hide the control bar. Scrub sessions (either
/// kind) and desktop hover keep the UI alive even when no pointer events
/// arrive, so a hold-still mid-drag never hides the controls under the finger.
bool mayHideControl({
  required PlayerUiState ui,
  required ScrubDragState drag,
}) =>
    ui.isShowControl && !ui.isHovering && !drag.any;
