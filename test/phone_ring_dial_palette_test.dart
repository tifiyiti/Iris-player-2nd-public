import 'package:flutter/material.dart' show Color, HSLColor;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_palette.dart';
import 'package:iris/models/store/app_state.dart';

double _hueOf(Color c) => HSLColor.fromColor(c).hue;
double _satOf(Color c) => HSLColor.fromColor(c).saturation;

void main() {
  group('dialBlockColor', () {
    test('rainbow preserves the legacy 12-hue wheel (30deg steps)', () {
      for (int i = 0; i < 12; i++) {
        expect(_hueOf(dialBlockColor(RingDialPalette.rainbow, i)),
            closeTo((i * 30).toDouble(), 0.5),
            reason: 'sector $i');
      }
    });

    test('every scheme cycles every 12 sectors', () {
      for (final RingDialPalette p in RingDialPalette.values) {
        for (int i = 0; i < 12; i++) {
          expect(
            dialBlockColor(p, i + 12).value,
            dialBlockColor(p, i).value,
            reason: '$p sector $i',
          );
        }
      }
    });

    test('adjacent sectors are distinguishable in every scheme', () {
      for (final RingDialPalette p in RingDialPalette.values) {
        for (int i = 0; i < 11; i++) {
          final Color a = dialBlockColor(p, i);
          final Color b = dialBlockColor(p, i + 1);
          expect(a.value == b.value, isFalse, reason: '$p sectors $i/$i+1');
        }
      }
    });

    test('cold hues stay in the cool band', () {
      for (int i = 0; i < 12; i++) {
        final double h = _hueOf(dialBlockColor(RingDialPalette.cold, i));
        expect(h, inInclusiveRange(140, 320), reason: 'sector $i');
      }
    });

    test('warm hues stay in the warm band', () {
      for (int i = 0; i < 12; i++) {
        final double h = _hueOf(dialBlockColor(RingDialPalette.warm, i));
        final bool warm = h <= 90 || h >= 330;
        expect(warm, isTrue, reason: 'sector $i hue $h');
      }
    });

    test('mono is achromatic (relies on luminance steps)', () {
      for (int i = 0; i < 12; i++) {
        expect(_satOf(dialBlockColor(RingDialPalette.mono, i)), lessThan(0.02),
            reason: 'sector $i');
      }
    });
  });
}
