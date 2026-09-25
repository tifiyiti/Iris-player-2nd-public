import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart'
    show ScanPhase;
import 'package:iris/features/scenario_playback/actions/scan_play_gate.dart';

/// Regression: the "scan finished — continue playing?" prompt must be offered
/// ONCE. A multi-storage batch completes once per storage (multiple
/// `scanning → done` transitions); the latch must suppress every offer after
/// the first, and a previously accumulated listener must not fire again.
void main() {
  test('offers on the first scanning -> done transition', () {
    expect(
      shouldOfferScanResume(
        previousPhase: ScanPhase.scanning,
        nextPhase: ScanPhase.done,
        offered: false,
      ),
      isTrue,
    );
  });

  test('a later terminal transition (same batch) is suppressed', () {
    expect(
      shouldOfferScanResume(
        previousPhase: ScanPhase.scanning,
        nextPhase: ScanPhase.done,
        offered: true,
      ),
      isFalse,
      reason: 'only one prompt per armed intent, however many units complete',
    );
  });

  test('offers for stopped and error terminals too', () {
    for (final terminal in [ScanPhase.stopped, ScanPhase.error]) {
      expect(
        shouldOfferScanResume(
          previousPhase: ScanPhase.scanning,
          nextPhase: terminal,
          offered: false,
        ),
        isTrue,
      );
    }
  });

  test('does not offer outside scanning -> terminal', () {
    expect(
      shouldOfferScanResume(
        previousPhase: ScanPhase.idle,
        nextPhase: ScanPhase.done,
        offered: false,
      ),
      isFalse,
    );
    expect(
      shouldOfferScanResume(
        previousPhase: ScanPhase.scanning,
        nextPhase: ScanPhase.scanning,
        offered: false,
      ),
      isFalse,
    );
    expect(
      shouldOfferScanResume(
        previousPhase: ScanPhase.done,
        nextPhase: ScanPhase.done,
        offered: false,
      ),
      isFalse,
    );
  });
}
