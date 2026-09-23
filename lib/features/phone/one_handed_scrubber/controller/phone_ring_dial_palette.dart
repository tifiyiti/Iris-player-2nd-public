import 'package:flutter/painting.dart' show Color, HSLColor;

import 'package:iris/models/store/app_state.dart';

/// Block-wheel colours for the ring dial ("Ring dial" one-handed design).
///
/// Schemes are pure functions of the sector index (mod 12) so the painter
/// stays stateless. Adjacent sectors are always distinguishable: narrow-band
/// schemes alternate lightness on top of their hue walk.
const int kDialSectorCount = 12;

/// Legacy rainbow wheel — 12 hues, 30° apart (pre-scheme default look).
const List<double> _kRainbowHues = <double>[
  0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330,
];

/// Cold band: cyans/blues/violet, ~8.6° hue steps with alternating lightness.
const List<double> _kColdHues = <double>[
  185, 194, 203, 212, 221, 230, 239, 248, 257, 266, 275, 284,
];

/// Warm band: reds/oranges/yellows with alternating lightness.
const List<double> _kWarmHues = <double>[
  355, 4, 13, 22, 31, 40, 49, 58, 350, 9, 18, 27,
];

Color dialBlockColor(RingDialPalette palette, int index) {
  final int i = index % kDialSectorCount;
  switch (palette) {
    case RingDialPalette.rainbow:
      return HSLColor.fromAHSL(1, _kRainbowHues[i], 0.30, 0.48).toColor();
    case RingDialPalette.cold:
      // Alternating lightness keeps neighbours separable inside a narrow band.
      return HSLColor.fromAHSL(
              1, _kColdHues[i], 0.38, i.isEven ? 0.42 : 0.56)
          .toColor();
    case RingDialPalette.warm:
      return HSLColor.fromAHSL(
              1, _kWarmHues[i], 0.42, i.isEven ? 0.44 : 0.58)
          .toColor();
    case RingDialPalette.mono:
      // Achromatic wayfinding: luminance carries the block identity, so the
      // scheme stays readable for colour-blind users and over any footage.
      return HSLColor.fromAHSL(1, 0, 0.0, i.isEven ? 0.88 : 0.42).toColor();
  }
}
