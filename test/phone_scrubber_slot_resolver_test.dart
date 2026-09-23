import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_scrubber_slot.dart';
import 'package:iris/models/store/app_state.dart';

void main() {
  group('resolveScrubberSlot', () {
    test('stale dial degrades to legacy circle slider when gate is off', () {
      expect(
        resolveScrubberSlot(
            kind: PhoneOneHandedScrubberKind.dial, metadataEnabled: false),
        PhoneScrubberSlot.legacyCircleSlider,
      );
    });

    test('dial renders one-handed when metadata gate is on', () {
      expect(
        resolveScrubberSlot(
            kind: PhoneOneHandedScrubberKind.dial, metadataEnabled: true),
        PhoneScrubberSlot.oneHanded,
      );
    });

    test('retired designs (arc/timeLens/snake) degrade to the legacy circle',
        () {
      // Requirement #6: the pre-dial designs are FULLY retired — they can
      // never render the one-handed slot again (load-time normalization also
      // folds them into classic; this is the runtime belt-and-braces).
      const kinds = <PhoneOneHandedScrubberKind>[
        PhoneOneHandedScrubberKind.arc,
        PhoneOneHandedScrubberKind.timeLens,
        PhoneOneHandedScrubberKind.snake,
      ];
      for (final kind in kinds) {
        expect(
          resolveScrubberSlot(kind: kind, metadataEnabled: false),
          PhoneScrubberSlot.legacyCircleSlider,
          reason: '$kind must degrade with the gate off',
        );
        expect(
          resolveScrubberSlot(kind: kind, metadataEnabled: true),
          PhoneScrubberSlot.legacyCircleSlider,
          reason: '$kind must degrade with the gate on',
        );
      }
    });

    test('classic (simple circle arc) always renders the legacy circle slider',
        () {
      expect(
        resolveScrubberSlot(
            kind: PhoneOneHandedScrubberKind.classic, metadataEnabled: true),
        PhoneScrubberSlot.legacyCircleSlider,
      );
      expect(
        resolveScrubberSlot(
            kind: PhoneOneHandedScrubberKind.classic, metadataEnabled: false),
        PhoneScrubberSlot.legacyCircleSlider,
      );
    });
  });
}
