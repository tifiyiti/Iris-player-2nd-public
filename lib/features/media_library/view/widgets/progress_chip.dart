import 'package:flutter/material.dart' hide Chip;
import 'package:iris/widgets/chip.dart';

/// Shared playback-progress chip for the new (DB-driven) media/storage UIs.
///
/// Canonical legacy style (kept identical across all callers):
/// - remaining (duration - position) <= 5s → `100%`
/// - otherwise → `<position/duration percent, rounded> %` (with a space).
///
/// Callers decide visibility (e.g. only for video items that have a playback
/// record, including 0%).
///
/// AXTree stability (flutter/flutter#182444): the chip is decorative and —
/// via [LiveProgressChip] — ticks every second inside paged popups over the
/// playing video. Its percent text carries zero assistive value, so it is
/// excluded from the semantics tree to stop feeding the engine's
/// accessibility bridge mutating nodes.
class ProgressChip extends StatelessWidget {
  const ProgressChip({
    super.key,
    required this.positionMs,
    required this.durationMs,
  });

  final int positionMs;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    if (durationMs <= 0) return const SizedBox.shrink();

    final remaining = durationMs - positionMs;
    if (remaining <= 5000) {
      return ExcludeSemantics(child: const Chip(text: '100%'));
    }

    final percent = (positionMs / durationMs * 100).toStringAsFixed(0);
    return ExcludeSemantics(child: Chip(text: '$percent %'));
  }
}
