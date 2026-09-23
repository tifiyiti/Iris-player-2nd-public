import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/rule/segment_color.dart';

void main() {
  group('segment color plumbing', () {
    test('normalize locks alpha at FF and masks to 32 bits', () {
      expect(normalizeSegmentColorArgb(0x00123456), 0xFF123456);
      expect(normalizeSegmentColorArgb(0x80123456), 0xFF123456);
      expect(normalizeSegmentColorArgb(0xFF123456), 0xFF123456);
    });

    test('random picks a preset colour deterministically from the rng', () {
      final color = randomSegmentColorArgb(Random(7));
      expect(kSegmentColorPresets, contains(color));
      // The same seed reproduces the same colour.
      expect(randomSegmentColorArgb(Random(7)), color);
    });

    test('resolve prefers the explicit colour', () {
      expect(
        resolveSegmentColorArgb(explicit: 0x00ABCDEF, seed: 12345),
        normalizeSegmentColorArgb(0x00ABCDEF),
      );
    });

    test('resolve derives a stable colour from the seed when unset', () {
      final a = resolveSegmentColorArgb(explicit: null, seed: 12345);
      final b = resolveSegmentColorArgb(explicit: null, seed: 12345);
      expect(a, b);
      expect(kSegmentColorPresets, contains(a));
    });

    test('resolve derives the same colour for seeds a palette apart', () {
      final first = resolveSegmentColorArgb(explicit: null, seed: 0);
      final second =
          resolveSegmentColorArgb(explicit: null, seed: kSegmentColorPresets.length);
      expect(first, second);
    });

    test('label renders uppercase #AARRGGBB', () {
      expect(segmentColorLabel(0xFF00BCD4), '#FF00BCD4');
      expect(segmentColorLabel(0x00123456), '#FF123456');
    });
  });
}
