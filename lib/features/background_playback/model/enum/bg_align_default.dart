/// The persisted DEFAULT alignment applied whenever a 副音 file is (re)aligned.
///
/// Mirrors [BgAlignMode] one-to-one: the shared alignment popup's 「更新」区
/// applies a mode to the running pair immediately, while its 「默认」区 writes
/// the chosen mode here so every later alignment starts from it.
///
/// There is no longer an "always ask" value: a mandatory remaining-time
/// threshold (see `alignAutoPauseRemainSec`) raises the prompt instead.
enum BgAlignDefault {
  /// 00:00↔00:00: 副音 tracks the video clock (`bgPos = fgPos`).
  fgHead,

  /// 副音 00:00 sits at the video's current moment (`bgPos = 0` at anchor).
  fgPosition,

  /// 副音 starts at [percent]% of its duration, anchored to the video moment.
  bgPercent,
}
