import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/seek_tiers.dart';

/// Contract for the four seek tiers derived from the user base step.
///
///   tierSeconds(base, tier) = clamp(base × [1,3,6,12][tier], 1, 3600)
void main() {
  group('kSeekTierMultipliers', () {
    test('is the documented 1/3/6/12 ladder', () {
      expect(kSeekTierMultipliers, <int>[1, 3, 6, 12]);
      expect(kSeekTierMultipliers.length, SeekTier.values.length);
    });
  });

  group('seekTierSeconds', () {
    test('default base 5 maps to 5/15/30/60', () {
      expect(seekTierSeconds(5, SeekTier.small), 5);
      expect(seekTierSeconds(5, SeekTier.medium), 15);
      expect(seekTierSeconds(5, SeekTier.large), 30);
      expect(seekTierSeconds(5, SeekTier.huge), 60);
    });

    test('scales with the base step', () {
      expect(seekTierSeconds(10, SeekTier.small), 10);
      expect(seekTierSeconds(10, SeekTier.medium), 30);
      expect(seekTierSeconds(10, SeekTier.large), 60);
      expect(seekTierSeconds(10, SeekTier.huge), 120);
    });

    test('tiers are strictly increasing for any valid base', () {
      for (var base = 1; base <= 120; base++) {
        final values = SeekTier.values
            .map((t) => seekTierSeconds(base, t))
            .toList(growable: false);
        for (var i = 1; i < values.length; i++) {
          expect(values[i], greaterThan(values[i - 1]),
              reason: 'tier $i not above tier ${i - 1} at base=$base');
        }
      }
    });

    test('always at least 1s and never above the ceiling', () {
      for (var base = 1; base <= 120; base++) {
        for (final tier in SeekTier.values) {
          final v = seekTierSeconds(base, tier);
          expect(v, greaterThanOrEqualTo(1));
          expect(v, lessThanOrEqualTo(kMaxSeekTierSeconds));
        }
      }
    });

    test('defensive against out-of-range base (clamped to [1,120])', () {
      expect(seekTierSeconds(0, SeekTier.small), 1);
      expect(seekTierSeconds(-5, SeekTier.medium), 3);
      expect(seekTierSeconds(10000, SeekTier.huge), 120 * 12);
    });
  });
}
