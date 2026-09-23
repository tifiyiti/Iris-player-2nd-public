/// How the current 副音 file is anchored onto the foreground timeline.
///
/// The anchor is a pair `(fgAnchorMs, bgAnchorMs)`: the foreground position that
/// maps to the 副音 position. All bg positions are derived from the fg progress
/// and this anchor (`bgPos = fgPos - (fgAnchorMs - bgAnchorMs)`), never read
/// from or written to the media-node progress rows.
///
/// - [fromFgHead]: foreground 00:00 ↔ 副音 00:00 — the default; dragging
///   anywhere from 00:00 keeps 副音 under the playhead.
/// - [atFgPosition]: a deliberately chosen foreground moment maps to 副音 00:00
///   ("start aligning from the middle"); the moment is always the live
///   foreground position at apply time — no anchor is stored.
/// - [bgPercent]: the current foreground moment maps to [alignPercent]% of the
///   副音 file, so the remaining share is split between "can drag back" and
///   "still plays forward" — the bg-shorter-than-fg answer.
enum BgAlignMode {
  fromFgHead,
  atFgPosition,
  bgPercent,
}
