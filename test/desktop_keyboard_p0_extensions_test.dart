import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/sync_steps.dart';

/// P0 sync-adjustment math shared by the keyboard executor and the
/// track-panel controls (phone).
void main() {
  group('nextSyncDelay', () {
    test('steps by ±0.5s from zero', () {
      expect(nextSyncDelay(0, 1), 0.5);
      expect(nextSyncDelay(0, -1), -0.5);
    });

    test('accumulates', () {
      expect(nextSyncDelay(nextSyncDelay(0, 1), 1), 1.0);
      expect(nextSyncDelay(1.5, -1), 1.0);
    });

    test('clamps to ±60s', () {
      expect(nextSyncDelay(60, 1), 60);
      expect(nextSyncDelay(-60, -1), -60);
      expect(nextSyncDelay(kMaxSyncSeconds, 1), kMaxSyncSeconds);
    });
  });
}
