/// Alignment of a freshly picked 副音 file against the foreground timeline.
///
/// Alignment always targets the CURRENT REAL single file: the caller passes the
/// physical foreground window (a Virtual Media merge is undone before the
/// decision), never the merged virtual duration.
///
/// The anchor is a pair `(fgAnchorMs, bgAnchorMs)`: the foreground position that
/// maps to the 副音 position. All bg positions are derived from the fg progress
/// and this anchor (`bgPos = fgPos - (fgAnchorMs - bgAnchorMs)`), never read
/// from or written to the media-node progress rows.
///
/// The mode applied on every alignment (first file or a user switch) comes from
/// the persisted default ([BgAlignDefault] → [BgAlignMode]). There is no longer
/// an "ask on shorter bg" branch: a mandatory remaining-time threshold
/// ([shouldWarnBgRunningOut]) raises the prompt instead.
library;

import 'package:iris/features/background_playback/model/enum/bg_align_default.dart';
import 'package:iris/features/background_playback/model/enum/bg_align_mode.dart';
import 'package:iris/features/background_playback/model/enum/bg_exhausted_action.dart';

/// Default "start from this share" when the user asks for a percentage.
const int kDefaultAlignPercent = 30;

/// Default remaining-副音 time (seconds) below which the alignment popup is
/// raised ("对齐后 bg 可播放时间 < xxx"). The setting is mandatory, so this is
/// always active.
const int kDefaultAlignWarnRemainSec = 5;

/// Lower bound of the mandatory remaining-time threshold.
const int kMinAlignWarnRemainSec = 1;

/// Upper bound of the mandatory remaining-time threshold.
const int kMaxAlignWarnRemainSec = 120;

/// Clamps a stored remaining-time threshold into the supported range.
int clampAlignWarnRemainSec(int seconds) =>
    seconds.clamp(kMinAlignWarnRemainSec, kMaxAlignWarnRemainSec);

/// The playable remainder of the aligned 副音, in milliseconds.
///
/// Without a 仅当前 window this is the raw file remainder (`bgDur - bgPos`).
/// With one, the window ceiling (the bg position mapped to fg 100%) caps it:
/// anything past the ceiling is unplayable (clamped/paused by the runtime
/// observer), so it must not count toward — or against — the threshold. A bg
/// already parked past the ceiling floors at zero.
int bgEffectiveRemainingMs({
  required int bgDurMs,
  required int bgPosMs,
  int? ceilingLocalMs,
}) {
  final int pos = bgPosMs < 0 ? 0 : bgPosMs;
  var remaining = bgDurMs - pos;
  if (ceilingLocalMs != null && ceilingLocalMs - pos < remaining) {
    remaining = ceilingLocalMs - pos;
  }
  return remaining < 0 ? 0 : remaining;
}

/// Whether the alignment popup should be raised because the aligned 副音 is
/// about to run out: `bgDur - bgPos < threshold`.
///
/// `bgPos` is the 副音 position AFTER alignment, so this is "对齐后 bg 可播放
/// 时间". An unknown duration never warns.
///
/// Under 仅当前 + 高同步 the [ceilingLocalMs] window ceiling caps the
/// remainder (see [bgEffectiveRemainingMs]); a bg parked past the ceiling is
/// NOT warned here — the runtime observer owns that state and the caller
/// skips the prompt for it.
bool shouldWarnBgRunningOut({
  required int bgDurMs,
  required int bgPosMs,
  int thresholdSec = kDefaultAlignWarnRemainSec,
  int? ceilingLocalMs,
}) {
  if (bgDurMs <= 0) return false;
  final int t = clampAlignWarnRemainSec(thresholdSec);
  final int remaining = bgEffectiveRemainingMs(
    bgDurMs: bgDurMs,
    bgPosMs: bgPosMs,
    ceilingLocalMs: ceilingLocalMs,
  );
  return remaining < t * 1000;
}

/// Whether the mandatory remaining-副音 prompt should be raised at all.
///
/// The prompt exists so the user can react to a 副音 that is about to run out.
/// Under [BgExhaustedAction.nextBg] there is nothing to react to — the
/// continuation is automatic (the next queued file starts at the video moment
/// the previous one ended, looping the list), so the prompt is suppressed and
/// playback is never interrupted. It is kept for
/// [BgExhaustedAction.stopRestoreFg], where the user must be able to learn that
/// 副音 will stop and the video's own audio returns.
bool shouldRaiseAlignThreshold({
  required bool enabled,
  required bool gateOpen,
  required BgExhaustedAction exhaustedAction,
  required int bgDurMs,
  required int bgPosMs,
  required int thresholdSec,
  int? ceilingLocalMs,
}) {
  if (!enabled || !gateOpen) return false;
  if (exhaustedAction == BgExhaustedAction.nextBg) return false;
  return shouldWarnBgRunningOut(
    bgDurMs: bgDurMs,
    bgPosMs: bgPosMs,
    thresholdSec: thresholdSec,
    ceilingLocalMs: ceilingLocalMs,
  );
}

/// The 副音 seek target for [percent]% of [bgDurMs] (clamped to 0..100%).
int alignPercentTargetMs(int bgDurMs, int percent) {
  if (bgDurMs <= 0) return 0;
  final int p = percent.clamp(0, 100);
  return (bgDurMs * p / 100).round().clamp(0, bgDurMs);
}

/// Resolves the running pair's alignment anchor pair for [mode].
///
/// [currentFgMs] is the foreground moment the anchor is taken at ("更新到
/// 当前"). The pair defines the fixed offset `fg - bg`.
({int fgAnchorMs, int bgAnchorMs}) resolveAlignmentAnchor({
  required BgAlignMode mode,
  required int currentFgMs,
  required int bgDurMs,
  required int percent,
}) {
  final int fg = currentFgMs < 0 ? 0 : currentFgMs;
  switch (mode) {
    case BgAlignMode.fromFgHead:
      return (fgAnchorMs: 0, bgAnchorMs: 0);
    case BgAlignMode.atFgPosition:
      return (fgAnchorMs: fg, bgAnchorMs: 0);
    case BgAlignMode.bgPercent:
      return (
        fgAnchorMs: fg,
        bgAnchorMs: alignPercentTargetMs(bgDurMs, percent),
      );
  }
}

/// The fixed `fg - bg` offset implied by an anchor pair.
int alignmentOffsetMs({required int fgAnchorMs, required int bgAnchorMs}) =>
    fgAnchorMs - bgAnchorMs;

/// The fixed `fg - bg` offset implied by aligning [mode] at [currentFgMs].
///
/// The counterpart of [bgAlignTargetMs] for the AUTHORITATIVE offset: a user
/// alignment (「更新到当前」/「00:00↔00:00」/ percent) stores this so the runtime
/// observer can keep the pair on the user's offset instead of re-deriving one
/// from position samples. See `BackgroundPlaybackState.alignOffsetMs`.
int resolveAlignmentOffsetMs({
  required BgAlignMode mode,
  required int currentFgMs,
  required int bgDurMs,
  required int percent,
}) {
  final anchor = resolveAlignmentAnchor(
    mode: mode,
    currentFgMs: currentFgMs,
    bgDurMs: bgDurMs,
    percent: percent,
  );
  return alignmentOffsetMs(
    fgAnchorMs: anchor.fgAnchorMs,
    bgAnchorMs: anchor.bgAnchorMs,
  );
}

/// The 副音 seek target for [mode] anchored at foreground moment [fgPosMs].
///
/// `target = fgPos - (fgAnchor - bgAnchor)`, clamped into the 副音 file. The
/// single source of truth for the popup's 「更新」区 and the runtime observer.
int bgAlignTargetMs({
  required BgAlignMode mode,
  required int fgPosMs,
  required int bgDurMs,
  required int percent,
}) {
  final anchor = resolveAlignmentAnchor(
    mode: mode,
    currentFgMs: fgPosMs,
    bgDurMs: bgDurMs,
    percent: percent,
  );
  return (fgPosMs -
          alignmentOffsetMs(
            fgAnchorMs: anchor.fgAnchorMs,
            bgAnchorMs: anchor.bgAnchorMs,
          ))
      .clamp(0, bgDurMs <= 0 ? 0 : bgDurMs);
}

/// Maps the persisted default one-to-one onto the session anchor mode.
BgAlignMode modeForAlignDefault(BgAlignDefault d) => switch (d) {
      BgAlignDefault.fgHead => BgAlignMode.fromFgHead,
      BgAlignDefault.fgPosition => BgAlignMode.atFgPosition,
      BgAlignDefault.bgPercent => BgAlignMode.bgPercent,
    };

/// Maps a session anchor mode back onto its persisted default counterpart.
///
/// The inverse of [modeForAlignDefault]: the alignment editor's 「默认对齐」
/// scope persists the tapped mode through this without touching the running
/// pair (no seek, no [BgAlignMode] change).
BgAlignDefault defaultForAlignMode(BgAlignMode m) => switch (m) {
      BgAlignMode.fromFgHead => BgAlignDefault.fgHead,
      BgAlignMode.atFgPosition => BgAlignDefault.fgPosition,
      BgAlignMode.bgPercent => BgAlignDefault.bgPercent,
    };

/// Decodes a persisted `bg.alignDefault` value, tolerating the LEGACY names
/// (`ask`/`fromHead`/`fromMid`) so an upgraded install keeps its preference.
///
/// - `ask` (the old "always prompt") → [BgAlignDefault.fgHead] (the new default;
///   the mandatory threshold now owns the prompt);
/// - `fromHead` (bg 00:00 at the fg moment) → [BgAlignDefault.fgPosition];
/// - `fromMid` (from the remembered share) → [BgAlignDefault.bgPercent].
BgAlignDefault? bgAlignDefaultFromName(String? name) {
  if (name == null) return null;
  final direct = BgAlignDefault.values.asNameMap()[name];
  if (direct != null) return direct;
  switch (name) {
    case 'ask':
      return BgAlignDefault.fgHead;
    case 'fromHead':
      return BgAlignDefault.fgPosition;
    case 'fromMid':
      return BgAlignDefault.bgPercent;
  }
  return null;
}

/// Whether the modal alignment prompt must align on close because the 副音
/// file changed behind it (natural completion advanced the queue while the
/// dialog was open).
///
/// The runtime observer skips the new file while the prompt is up
/// (`askingForRun`), so without this the newcomer would play unaligned. A
/// terminal run ([bgExhausted]) or a disabled subsystem never realigns.
bool modalCloseNeedsRealign({
  required String? entryKey,
  required String? exitKey,
  required bool enabled,
  required bool bgExhausted,
}) =>
    enabled &&
    !bgExhausted &&
    entryKey != null &&
    exitKey != null &&
    entryKey != exitKey;

/// Whether the modal alignment prompt may resume 副音 playback on close.
///
/// A run that terminated behind the dialog (`bgExhausted`, e.g. the file
/// completed under `stopRestoreFg`) must never be revived: restoring it would
/// restart a dead run and re-duck the foreground. The foreground side is
/// restored unconditionally by the caller.
///
/// The user gate must still be open: a gate stop pressed while the dialog is up
/// owns the transport, and the modal must not revive 副音 behind it.
bool shouldRestoreBgAfterModal({
  required bool bgWasPlaying,
  required bool bgExhausted,
  bool gateOpen = true,
}) =>
    bgWasPlaying && !bgExhausted && gateOpen;

/// The two bg-only choices offered by the VM tiled manual-switch dialog (no
/// foreground restart: the VM link cannot drive the foreground runtime there).
enum BgAlignChoice {
  /// 副音 00:00 aligned to the video's current position.
  fromHead,

  /// 副音 starts at [percent]% of its duration, aligned to the video.
  percent,
}

/// The 副音 seek target (ms) for a VM tiled manual [choice].
int resolveBgAlignmentChoice({
  required BgAlignChoice choice,
  required int bgDurMs,
  int percent = kDefaultAlignPercent,
}) =>
    choice == BgAlignChoice.percent && bgDurMs > 0
        ? alignPercentTargetMs(bgDurMs, percent)
        : 0;
