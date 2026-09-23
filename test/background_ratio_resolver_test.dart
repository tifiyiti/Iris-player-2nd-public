import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/media_ratio.dart';
import 'package:iris/features/background_playback/services/background_ratio_resolver.dart';

/// sub_media §5.5 — which fg/bg ratio pair actually applies.
///
/// Two layers: a per-foreground-media override and the global default. An
/// empty override falls back to global; the whole ratio is bypassed when the
/// user cleared "use saved ratio" (then both sides run at the master volume).
void main() {
  const global = MediaRatio(fgPercent: 30, bgPercent: 100);
  const override = MediaRatio(fgPercent: 80, bgPercent: 20);

  group('resolveEffectiveRatio', () {
    test('uses the per-media override when one exists for the fg key', () {
      final r = resolveEffectiveRatio(
        volumeRatioEnabled: true,
        global: global,
        perMedia: const {'k1': override},
        fgKey: 'k1',
      );
      expect(r, override);
    });

    test('falls back to the global pair for a media with no override', () {
      final r = resolveEffectiveRatio(
        volumeRatioEnabled: true,
        global: global,
        perMedia: const {'k1': override},
        fgKey: 'k2',
      );
      expect(r, global);
    });

    test('falls back to global when no foreground media is loaded', () {
      final r = resolveEffectiveRatio(
        volumeRatioEnabled: true,
        global: global,
        perMedia: const {'k1': override},
        fgKey: null,
      );
      expect(r, global);
    });

    test('cleared "use saved ratio" bypasses the ratio entirely (100/100)', () {
      final r = resolveEffectiveRatio(
        volumeRatioEnabled: false,
        global: global,
        perMedia: const {'k1': override},
        fgKey: 'k1',
      );
      expect(r.fgPercent, 100);
      expect(r.bgPercent, 100);
    });

    test('clamps out-of-range stored values into 0..100', () {
      final r = resolveEffectiveRatio(
        volumeRatioEnabled: true,
        global: const MediaRatio(fgPercent: 300, bgPercent: -20),
        perMedia: const {},
        fgKey: null,
      );
      expect(r.fgPercent, 100);
      expect(r.bgPercent, 0);
    });
  });
}
