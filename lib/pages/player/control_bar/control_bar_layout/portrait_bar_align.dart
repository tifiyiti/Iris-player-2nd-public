import 'package:flutter/material.dart';
import 'package:iris/models/store/app_state.dart';

/// Alignment mapping for the phone-PORTRAIT bottom bar (`MobileControlLayout`).
///
/// PORTRAIT-only: the one-handed side panel positions its block with
/// `sidewayBarX`/`sidewayBarPos`, and the standalone desktop 副音 row follows
/// `background_playback.quickBarAlign`. Keeping the two portrait groups here
/// (instead of inline switches) makes the mapping unit-testable without
/// pumping a widget.

/// `MainAxisAlignment` for the normal playback rows.
///
/// [PortraitBarAlign.center] uses `spaceEvenly` — the pre-238d47c2 look where
/// both rows spread across the full bar; left/right pack to an edge.
MainAxisAlignment portraitPlaybackRowAlign(PortraitBarAlign align) =>
    switch (align) {
      PortraitBarAlign.left => MainAxisAlignment.start,
      PortraitBarAlign.center => MainAxisAlignment.spaceEvenly,
      PortraitBarAlign.right => MainAxisAlignment.end,
    };

/// `Alignment` for the WHOLE 副音 quick block.
///
/// The 副音 bar is a shrink-wrapped `BalancedButtonWrap` (its rows cannot
/// spread), so [PortraitBarAlign.center] centres the block as a whole — the
/// pre-238d47c2 look. The block must be positioned by an outer `Align`, because
/// a `Column` would centre it regardless of the wrap's own alignment.
Alignment portraitSubAudioBlockAlign(PortraitBarAlign align) =>
    switch (align) {
      PortraitBarAlign.left => Alignment.centerLeft,
      PortraitBarAlign.center => Alignment.center,
      PortraitBarAlign.right => Alignment.centerRight,
    };

/// `MainAxisAlignment` for the 副音 quick bar's INTERNAL rows (a multi-row
/// wrap aligns its shorter rows with this; single-row blocks ignore it).
MainAxisAlignment portraitSubAudioWrapAlign(PortraitBarAlign align) =>
    switch (align) {
      PortraitBarAlign.left => MainAxisAlignment.start,
      PortraitBarAlign.center => MainAxisAlignment.center,
      PortraitBarAlign.right => MainAxisAlignment.end,
    };
