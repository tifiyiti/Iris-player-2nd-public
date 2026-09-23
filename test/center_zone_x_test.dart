import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/center_zone_x.dart';

/// One laid-out center readout row (mirrors the painter call sites).
typedef _Row = ({String text, TextStyle style});

/// Lays a row out the way [centerZoneGapRadius] does, so the assertions below
/// compare against the SAME box the production gap is derived from.
Size _measure(_Row row) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: row.text, style: row.style),
    textDirection: TextDirection.ltr,
  )..layout();
  final Size size = tp.size;
  tp.dispose();
  return size;
}

Rect _textBox(List<_Row> rows) {
  double w = 0;
  double h = 0;
  for (final _Row r in rows) {
    final Size s = _measure(r);
    w = math.max(w, s.width);
    h += s.height;
  }
  return Rect.fromCenter(center: Offset.zero, width: w, height: h);
}

bool _segmentTouchesRect(Offset a, Offset b, Rect rect) {
  const int steps = 256;
  for (int i = 0; i <= steps; i++) {
    if (rect.contains(Offset.lerp(a, b, i / steps)!)) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('centerZoneArms', () {
    test('draws the four 45° diagonals between gap and radius', () {
      const Offset center = Offset(100, 50);
      const double radius = 40;
      const double gap = 20;
      final arms =
          centerZoneArms(center: center, radius: radius, gapRadius: gap);
      expect(arms, hasLength(4));
      final Set<String> quadrants = <String>{};
      for (final (Offset inner, Offset outer) in arms) {
        expect((inner - center).distance, closeTo(gap, 1e-9));
        expect((outer - center).distance, closeTo(radius, 1e-9));
        final Offset d = outer - center;
        expect(d.dx.abs(), closeTo(d.dy.abs(), 1e-9),
            reason: 'arm must sit on a 45° diagonal');
        quadrants.add('${d.dx.sign}/${d.dy.sign}');
      }
      expect(quadrants, hasLength(4), reason: 'four distinct quadrants');
    });

    test('gapRadius 0 reproduces the legacy full X', () {
      final arms =
          centerZoneArms(center: Offset.zero, radius: 30, gapRadius: 0);
      expect(arms, hasLength(4));
      for (final (Offset inner, Offset outer) in arms) {
        expect(inner, Offset.zero);
        expect((outer).distance, closeTo(30, 1e-9));
      }
    });

    test('collapses when no arm of usable length remains', () {
      expect(centerZoneArms(center: Offset.zero, radius: 10, gapRadius: 10),
          isEmpty);
      expect(centerZoneArms(center: Offset.zero, radius: 10, gapRadius: 9.5),
          isEmpty);
      expect(centerZoneArms(center: Offset.zero, radius: 0, gapRadius: 0),
          isEmpty);
      expect(centerZoneArms(center: Offset.zero, radius: 10, gapRadius: 7),
          hasLength(4));
    });
  });

  group('centerZoneGapRadius', () {
    test('clears the measured center text box when it fits', () {
      final rows = <_Row>[
        (text: '12:34', style: const TextStyle(fontSize: 16)),
        (text: '/ 45:67', style: const TextStyle(fontSize: 15)),
      ];
      const double radius = 41.8;
      final gap = centerZoneGapRadius(rows: rows, radius: radius);
      expect(gap, lessThan(radius));
      final Rect box = _textBox(rows);
      final arms = centerZoneArms(
          center: Offset.zero, radius: radius, gapRadius: gap);
      expect(arms, hasLength(4));
      for (final (Offset a, Offset b) in arms) {
        expect(_segmentTouchesRect(a, b, box), isFalse,
            reason: 'arm $a -> $b must not sit on the center text');
      }
    });

    test('is clamped so the arms never disappear under a huge readout', () {
      final rows = <_Row>[
        (text: '12:34:56', style: const TextStyle(fontSize: 16)),
        (text: '11:22:33', style: const TextStyle(fontSize: 11, height: 1.1)),
        (text: '/ 1:02:03', style: const TextStyle(fontSize: 15)),
        (text: '/ 11:22:33', style: const TextStyle(fontSize: 11, height: 1.1)),
      ];
      const double radius = 41.8;
      final gap = centerZoneGapRadius(rows: rows, radius: radius);
      expect(gap, closeTo(radius * kCenterZoneMaxGapFactor, 1e-9));
      final arms = centerZoneArms(
          center: Offset.zero, radius: radius, gapRadius: gap);
      expect(arms, hasLength(4));
      for (final (Offset a, Offset b) in arms) {
        expect((b - a).distance,
            closeTo(radius * (1 - kCenterZoneMaxGapFactor), 1e-9));
      }
    });

    test('no text -> no hole (legacy full X)', () {
      expect(centerZoneGapRadius(rows: const <_Row>[], radius: 40), 0);
      expect(
          centerZoneGapRadius(
              rows: <_Row>[(text: '', style: const TextStyle(fontSize: 16))],
              radius: 40),
          0);
    });

    test('scales the hole with the measured text, not the dial', () {
      final rows = <_Row>[
        (text: '12:34', style: const TextStyle(fontSize: 16)),
      ];
      final Size s = _measure(rows.single);
      final gap = centerZoneGapRadius(rows: rows, radius: 1000);
      expect(
          gap,
          closeTo(
              math.sqrt2 / 2 * math.min(s.width, s.height) +
                  kCenterZoneGapPadding,
              1e-9));
    });
  });
}
