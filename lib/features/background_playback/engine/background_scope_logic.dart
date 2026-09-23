/// Activation scope of one 副音 run, as pure functions.
///
/// The 作用范围 ([BgApplyScope]) decides what happens to 副音 when the
/// foreground media changes:
/// - [BgApplyScope.all]: keeps playing its own queue (nothing to do).
/// - [BgApplyScope.currentOnly]: anchored to the media the run was started on —
///   leaving it pauses 副音 while the subsystem stays alive; returning resumes.
/// - [BgApplyScope.smart]: a newly opened media defaults to off, but a media
///   with a saved 副音 pairing auto-starts 副音 ("已保存副音 fg 自动播放").
///
/// Independently of the scope, a media the user explicitly closed 副音 for
/// lives in `offMediaKeys` and never plays 副音 — it always wins.
library;

import 'package:iris/features/background_playback/model/enum/bg_apply_scope.dart';
import 'package:iris/features/background_playback/model/enum/bg_cross_action.dart';

/// What the scope observer must do when the foreground media changes.
enum BgScopeAction {
  /// Nothing changes (副音 off, scope=all, or no new media).
  none,

  /// 副音 left a media it must not play — stop playing, keep the subsystem.
  pauseBg,

  /// 副音 returned to its anchored media — resume playing.
  resumeBg,

  /// The new media has a saved 副音 pairing (smart scope) — start 副音 for it.
  /// Fires from a cold (disabled) run too, so "已保存副音自动播放" can begin.
  startBg,
}

/// Decides the [BgScopeAction] for a foreground media switch.
///
/// [newFgHasSavedMapping] is only consulted for [BgApplyScope.smart].
BgScopeAction resolveBgScopeOnFgChange({
  required bool enabled,
  required BgApplyScope applyScope,
  required String? anchorKey,
  required String? newFgKey,
  Set<String> offMediaKeys = const <String>{},
  bool newFgHasSavedMapping = false,
  bool gateOpen = true,
}) {
  final key = newFgKey;
  if (key == null) return BgScopeAction.none;
  if (offMediaKeys.contains(key)) return BgScopeAction.pauseBg;
  // An explicit gate stop (quick-bar gate OFF / bg stop button) wins over every
  // scope: no auto-resume or auto-start until the user opens the gate again.
  if (!gateOpen) return BgScopeAction.none;

  switch (applyScope) {
    case BgApplyScope.all:
      return BgScopeAction.none;
    case BgApplyScope.currentOnly:
      if (!enabled) return BgScopeAction.none;
      final anchor = anchorKey;
      // No anchor = nothing to leave, so a media switch must not stop 副音.
      if (anchor == null) return BgScopeAction.none;
      return anchor == key ? BgScopeAction.resumeBg : BgScopeAction.pauseBg;
    case BgApplyScope.smart:
      // The auto-start must survive the disabled case: the observer only
      // reaches an enabled run through other means, so gating it here would
      // make [BgScopeAction.startBg] unreachable (and the callee a no-op).
      if (newFgHasSavedMapping) return BgScopeAction.startBg;
      return enabled ? BgScopeAction.pauseBg : BgScopeAction.none;
  }
}

/// What the pair does when the follower can no longer continue at the 副音
/// boundary (the foreground reached its end / the 副音 content mapped to the
/// foreground 100% is exhausted).
enum BgBoundaryAction {
  /// Strict lockstep: BOTH runtimes stop (the master included). The 仅当前
  /// contract — 副音 exists only inside this media, so when it runs out the
  /// pair ends here.
  stopBoth,

  /// 全部作用 with 「切新 bg」: advance the 副音 queue one step.
  newBg,

  /// 全部作用 with 「正常连播」, or 智能 with a saved mapping: 副音 keeps
  /// playing (its own queue, or the saved timeline driving the pair).
  keepPlaying,
}

/// Scope-aware boundary decision (高同步 follower exhausted).
///
/// - [BgApplyScope.currentOnly]: the pair is confined to this media →
///   [BgBoundaryAction.stopBoth] (strict lockstep, master included).
/// - [BgApplyScope.all]: follow the 跨视频 switch setting — a new LIST ITEM uses
///   [bgItemSwitch], an internal VIRTUAL segment uses [bgSegmentSwitch];
///   「切新 bg」→ [BgBoundaryAction.newBg], 「正常连播」→ keep.
/// - [BgApplyScope.smart]: the newly-current foreground's saved 副音 mapping
///   decides — present → [BgBoundaryAction.keepPlaying] (the timeline drives
///   副音), absent → [BgBoundaryAction.stopBoth].
BgBoundaryAction resolveBgBoundaryAction({
  required BgApplyScope applyScope,
  required BgCrossAction bgItemSwitch,
  required BgCrossAction bgSegmentSwitch,
  required bool transitionIsItem,
  required bool fgHasSavedMapping,
}) {
  switch (applyScope) {
    case BgApplyScope.currentOnly:
      return BgBoundaryAction.stopBoth;
    case BgApplyScope.all:
      final BgCrossAction rule =
          transitionIsItem ? bgItemSwitch : bgSegmentSwitch;
      return rule == BgCrossAction.newBg
          ? BgBoundaryAction.newBg
          : BgBoundaryAction.keepPlaying;
    case BgApplyScope.smart:
      return fgHasSavedMapping
          ? BgBoundaryAction.keepPlaying
          : BgBoundaryAction.stopBoth;
  }
}

/// Whether an enabled-but-targetless scope must stop the stale audio.
///
/// The open target already folds the mapped override over the natural queue
/// entry, so a missing target means an empty/out-of-range queue: without an
/// explicit stop the engine keeps playing its previous file. The disabled
/// path is excluded — it has its own stop effect.
bool shouldStopStaleEngine({
  required bool enabled,
  required bool hasOpenTarget,
}) =>
    enabled && !hasOpenTarget;

/// Whether 副音 is currently applied to the playing foreground media — the
/// quick-bar "对当前 / 不对当前" switch state.
bool resolveApplyToCurrent({
  required bool enabled,
  required BgApplyScope applyScope,
  required String? anchorKey,
  required Set<String> offMediaKeys,
  required String? fgKey,
}) {
  if (!enabled || fgKey == null || fgKey.isEmpty) return false;
  if (offMediaKeys.contains(fgKey)) return false;
  if (applyScope == BgApplyScope.currentOnly) return anchorKey == fgKey;
  return true;
}
