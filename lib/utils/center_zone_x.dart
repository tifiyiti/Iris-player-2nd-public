import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Geometry for the faint 45° X that marks the four center tap sectors of the
/// ring dial / circle slider (see `centerZoneForOffset`).
///
/// The X used to be two full diagonals crossing at the center, which drew
/// straight through the center time readout. It is now four INDEPENDENT arms:
/// the outer endpoint still sits on the hit circle (so the sector hint is
/// unchanged), the inner endpoint stops at a circular hole sized from the
/// measured readout, and nothing is drawn inside that hole.
///
/// Why a circle: a 45° ray through a centered text box leaves it after
/// `sqrt(2) * min(halfWidth, halfHeight)`, so a circular hole of that radius
/// removes exactly the same span the box would have covered.

/// Breathing room kept between the measured readout and the arms, so a glyph
/// never touches a line.
const double kCenterZoneGapPadding = 6.0;

/// Hard cap on the share of the hit radius the hole may consume. The arms are
/// the ONLY visual encoding of the four sectors, so they must survive a large
/// readout (VM's 4 rows) or a small dial; past this point the arms may graze
/// the text corners instead of vanishing.
const double kCenterZoneMaxGapFactor = 0.75;

/// Shortest arm still worth painting; below it the X is dropped entirely
/// rather than leaving a degenerate stub.
const double kCenterZoneMinArm = 2.0;

/// Row-size memo keyed by the layout-relevant style fields. A position tick
/// only changes the current-time row, so the other rows are reused instead of
/// being re-laid-out every frame.
final Map<String, Size> _rowSizeCache = <String, Size>{};
const int _kRowSizeCacheCap = 256;

Size _measureRow(({String text, TextStyle style}) row) {
  final TextStyle s = row.style;
  final String key = '${row.text}|${s.fontSize}|${s.height}|${s.fontWeight}|'
      '${s.letterSpacing}';
  final Size? cached = _rowSizeCache[key];
  if (cached != null) return cached;
  final TextPainter tp = TextPainter(
    text: TextSpan(text: row.text, style: s),
    textDirection: TextDirection.ltr,
  )..layout();
  final Size size = tp.size;
  tp.dispose();
  // Bounded cache: time labels change every tick, so an unbounded map would
  // grow with the session.
  if (_rowSizeCache.length >= _kRowSizeCacheCap) _rowSizeCache.clear();
  _rowSizeCache[key] = size;
  return size;
}

/// Radius of the hole the X must leave open so it never sits on the center
/// readout. 0 means "no readout, draw the full X" (the legacy look).
double centerZoneGapRadius({
  required List<({String text, TextStyle style})> rows,
  required double radius,
}) {
  if (radius <= 0 || rows.isEmpty) return 0;
  double widest = 0;
  double totalHeight = 0;
  for (final ({String text, TextStyle style}) row in rows) {
    final Size size = _measureRow(row);
    widest = math.max(widest, size.width);
    totalHeight += size.height;
  }
  if (widest <= 0 || totalHeight <= 0) return 0;
  final double needed =
      math.sqrt2 / 2 * math.min(widest, totalHeight) + kCenterZoneGapPadding;
  return math.min(needed, radius * kCenterZoneMaxGapFactor);
}

/// The four 45° arms as (inner, outer) endpoint pairs, or an empty list when
/// no usable arm remains.
List<(Offset, Offset)> centerZoneArms({
  required Offset center,
  required double radius,
  required double gapRadius,
}) {
  if (radius <= 0) return const <(Offset, Offset)>[];
  final double inner = gapRadius.clamp(0.0, radius).toDouble();
  if (radius - inner < kCenterZoneMinArm) return const <(Offset, Offset)>[];
  const double k = math.sqrt1_2;
  const List<Offset> dirs = <Offset>[
    Offset(k, k),
    Offset(k, -k),
    Offset(-k, k),
    Offset(-k, -k),
  ];
  return <(Offset, Offset)>[
    for (final Offset d in dirs) (center + d * inner, center + d * radius),
  ];
}

/// Paints the sector-boundary X as four arms around [gapRadius].
///
/// [color] defaults to `Colors.white.withValues(alpha: 0.18)` — deliberately
/// faint: a reachability hint over live video, never decoration.
void paintCenterZoneX(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required double gapRadius,
  Color color = const Color(0x2EFFFFFF),
  double strokeWidth = 1.0,
}) {
  final List<(Offset, Offset)> arms =
      centerZoneArms(center: center, radius: radius, gapRadius: gapRadius);
  if (arms.isEmpty) return;
  final Paint paint = Paint()
    ..strokeWidth = strokeWidth
    ..style = PaintingStyle.stroke
    ..color = color;
  for (final (Offset a, Offset b) in arms) {
    canvas.drawLine(a, b, paint);
  }
}
