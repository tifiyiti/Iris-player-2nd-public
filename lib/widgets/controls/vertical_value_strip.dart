import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Vertical value slider drawn with a [CustomPaint] (no [Slider] widget).
///
/// Extracted from the seek-step strip so the 副音 fg/bg volume-ratio dialog can
/// reuse the exact same interaction: top = [max], bottom = [min], drag anywhere
/// updates immediately, no animation ticker (keeps widget tests pumpable).
class VerticalValueStrip extends HookWidget {
  const VerticalValueStrip({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.trackColor,
    this.accent,
    this.stripWidth = 36,
    this.valueLabel,
    this.semanticLabel,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  /// Fired once when the finger lifts (used by the ratio dialog's live mode
  /// to commit the final value).
  final ValueChanged<int>? onChangeEnd;

  /// Track color; defaults to the theme's primary.
  final Color? accent;

  /// Inactive track color; defaults to a dimmed white.
  final Color? trackColor;

  final double stripWidth;

  /// Optional label painted above the strip (e.g. the current value).
  final String? valueLabel;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color accentColor = accent ?? Theme.of(context).colorScheme.primary;
    final Color trackColorValue =
        trackColor ?? Colors.white.withValues(alpha: 0.22);
    final double span = (max - min).toDouble();

    void emit(double dy, double height) {
      if (height <= 0 || span <= 0) return;
      final double frac = (dy / height).clamp(0.0, 1.0);
      // Top = max, bottom = min.
      final int v = (max - frac * span).round().clamp(min, max);
      if (v != value) onChanged(v);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double h =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 180;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (valueLabel != null) ...[
              Text(
                valueLabel!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      shadows: const [
                        Shadow(blurRadius: 4, color: Colors.black54),
                      ],
                    ),
              ),
              const SizedBox(height: 6),
            ],
            Expanded(
              child: Semantics(
                slider: true,
                label: semanticLabel,
                value: '$value',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => emit(d.localPosition.dy, h),
                  onPanUpdate: (d) => emit(d.localPosition.dy, h),
                  onPanEnd: (_) => onChangeEnd?.call(value),
                  onTapDown: (d) => emit(d.localPosition.dy, h),
                  onTapUp: (_) => onChangeEnd?.call(value),
                  child: CustomPaint(
                    size: Size(stripWidth, h),
                    painter: _VerticalStripPainter(
                      value: value,
                      min: min,
                      max: max,
                      accent: accentColor,
                      trackColor: trackColorValue,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VerticalStripPainter extends CustomPainter {
  _VerticalStripPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    required this.trackColor,
  });

  final int value;
  final int min;
  final int max;
  final Color accent;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    const double trackW = 3;
    final double trackX = (w - trackW) / 2;
    const double thumbR = 5;

    final RRect trackBg = RRect.fromRectAndRadius(
      Rect.fromLTWH(trackX, thumbR, trackW, h - thumbR * 2),
      const Radius.circular(trackW / 2),
    );
    canvas.drawRRect(trackBg, Paint()..color = trackColor);

    final double span = (max - min).toDouble();
    final double frac = span <= 0 ? 0 : ((value - min) / span).clamp(0.0, 1.0);
    final double activeH = (h - thumbR * 2) * frac;
    if (activeH > 0) {
      final RRect active = RRect.fromRectAndRadius(
        Rect.fromLTWH(trackX, h - thumbR - activeH, trackW, activeH),
        const Radius.circular(trackW / 2),
      );
      canvas.drawRRect(active, Paint()..color = accent.withValues(alpha: 0.9));
    }

    final double thumbY = (h - thumbR) - frac * (h - thumbR * 2);
    final Offset thumbC = Offset(w / 2, thumbY);
    canvas.drawCircle(
        thumbC, thumbR + 1.5, Paint()..color = Colors.black.withValues(alpha: 0.25));
    canvas.drawCircle(thumbC, thumbR, Paint()..color = Colors.white);
    canvas.drawCircle(thumbC, thumbR - 1, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _VerticalStripPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.min != min ||
      oldDelegate.max != max ||
      oldDelegate.accent != accent ||
      oldDelegate.trackColor != trackColor;
}
