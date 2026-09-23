import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/view/queue/scenario_queue_page.dart';

void main() {
  // Regression: the docked panel and the standalone floating popup pass the
  // SAME flags (`embeddedInStoragesDb: false, modeQueueOverride: true`), so the
  // old two-flag condition could not tell them apart and the dock wrongly
  // painted its queue with the floating-popup theme (white-on-black text).
  group('isFloatingQueuePopup', () {
    test('docked panel must NOT use the floating popup theme', () {
      expect(
        isFloatingQueuePopup(
          embeddedInStoragesDb: false,
          modeQueueOverride: true,
          dockedPanel: true,
        ),
        isFalse,
      );
    });

    test('standalone floating queue popup DOES use the popup theme', () {
      expect(
        isFloatingQueuePopup(
          embeddedInStoragesDb: false,
          modeQueueOverride: true,
          dockedPanel: false,
        ),
        isTrue,
      );
    });

    test('embedded / non-override pages never use the popup theme', () {
      expect(
        isFloatingQueuePopup(
          embeddedInStoragesDb: true,
          modeQueueOverride: true,
          dockedPanel: false,
        ),
        isFalse,
      );
      expect(
        isFloatingQueuePopup(
          embeddedInStoragesDb: false,
          modeQueueOverride: false,
          dockedPanel: false,
        ),
        isFalse,
      );
    });
  });
}
