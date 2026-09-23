import 'package:flutter/material.dart';
import 'package:iris/features/background_playback/resolver/mapping_overview_math.dart';
import 'package:iris/features/background_playback/rule/segment_color.dart';

/// The Level-2 overview bar: the whole foreground duration as a 0–100% strip
/// with one painted slice per [MappingBlock].
///
/// Colors are deliberate and shared with the editor's language: accent =
/// covered bg, muted = silence, gray = uncovered (bg ran out), faint outline =
/// gap. Uncovered slices are always painted gray so a long neighbouring window
/// can never visually absorb the missing part.
class MappingTimelineOverview extends StatelessWidget {
  const MappingTimelineOverview({
    super.key,
    required this.blocks,
    required this.fgTotalMs,
    required this.semanticsLabel,
    this.height = 22,
  });

  final List<MappingBlock> blocks;
  final int fgTotalMs;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: semanticsLabel,
      readOnly: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          key: const ValueKey('mapping_overview_track'),
          painter: _OverviewPainter(
            blocks: blocks,
            fgTotalMs: fgTotalMs,
            gap: scheme.onSurface.withValues(alpha: 0.10),
            gapBorder: scheme.onSurface.withValues(alpha: 0.22),
            silence: scheme.tertiary.withValues(alpha: 0.55),
            covered: scheme.primary,
            uncovered: scheme.onSurface.withValues(alpha: 0.20),
            boundary: scheme.surface.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

class _OverviewPainter extends CustomPainter {
  _OverviewPainter({
    required this.blocks,
    required this.fgTotalMs,
    required this.gap,
    required this.gapBorder,
    required this.silence,
    required this.covered,
    required this.uncovered,
    required this.boundary,
  });

  final List<MappingBlock> blocks;
  final int fgTotalMs;
  final Color gap;
  final Color gapBorder;
  final Color silence;
  final Color covered;
  final Color uncovered;
  final Color boundary;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    // Track background.
    canvas.drawRRect(rrect, Paint()..color = gap);

    if (fgTotalMs <= 0) return;
    final barH = size.height;
    final boundaryPaint = Paint()
      ..color = boundary
      ..strokeWidth = 1.5;

    for (final b in blocks) {
      final x0 = MappingOverviewMath.fracOf(b.startMs, fgTotalMs)! * size.width;
      final x1 = MappingOverviewMath.fracOf(b.endMs, fgTotalMs)! * size.width;
      if (x1 - x0 <= 0) continue;
      final rect = Rect.fromLTRB(x0, 0, x1, barH);
      switch (b.kind) {
        case MappingBlockKind.gap:
          // Track background already shows; draw only the outline.
          canvas.drawRect(
            rect.deflate(0.75),
            Paint()
              ..color = gapBorder
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        case MappingBlockKind.silence:
          canvas.drawRect(rect, Paint()..color = silence);
        case MappingBlockKind.covered:
          // A covered slice wears its segment's label colour so the manager
          // matches the editor's fg axis; the theme accent is the fallback.
          final seg = b.segment;
          final color = seg == null
              ? covered
              : Color(resolveSegmentColorArgb(
                  explicit: seg.colorArgb,
                  seed: seg.fgStartMs,
                ));
          canvas.drawRect(rect, Paint()..color = color);
        case MappingBlockKind.uncovered:
          canvas.drawRect(rect, Paint()..color = uncovered);
      }
      canvas.drawLine(
        Offset(x1, 0),
        Offset(x1, barH),
        boundaryPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_OverviewPainter old) =>
      old.fgTotalMs != fgTotalMs ||
      old.blocks != blocks ||
      old.covered != covered ||
      old.uncovered != uncovered ||
      old.silence != silence;
}
