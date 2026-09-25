import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_scrubber_slot.dart';
import 'package:iris/models/store/app_state.dart';

/// Fresh-install contract: a brand-new install ships with the ring dial as the
/// side-panel design. Existing installs keep whatever they persisted — this is
/// purely the `@Default` seeding a virgin `AppState` (no blob, no rows).
void main() {
  test('fresh AppState defaults the side scrubber design to dial (拨环)', () {
    expect(const AppState().phoneOneHandedScrubberKind,
        PhoneSideScrubberKind.dial);
  });

  test('the fresh default renders the one-handed dial under the metadata gate',
      () {
    // Metadata gate is ON for new installs (useMetadataSettings @Default true),
    // so the dial default actually renders instead of degrading.
    expect(const AppState().useMetadataSettings, isTrue);
    expect(
      resolveScrubberSlot(
        kind: const AppState().phoneOneHandedScrubberKind,
        metadataEnabled: true,
      ),
      PhoneScrubberSlot.oneHanded,
    );
  });
}
