import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/interaction/controller/foreground_window_resolver.dart';

/// The align editor must edit the PHYSICAL file under the virtual merge, not
/// the merged timeline the player exposes (the "超长的合并视频" bug).
void main() {
  group('resolveForegroundWindow', () {
    test('virtual active: uses the current segment duration + local position',
        () {
      // Virtual total is 3h40m (a merge of many clips); segment 7 starts at
      // 1h12m and is 4 minutes long; the virtual playhead is 1h13m05s.
      final w = resolveForegroundWindow(
        virtualActive: true,
        playerDurationMs: 3 * 3600 * 1000 + 40 * 60 * 1000,
        playerPositionMs: (72 * 60 + 65) * 1000,
        virtualOffsetMs: 72 * 60 * 1000,
        segmentDurationMs: 4 * 60 * 1000,
      );
      expect(w.virtualActive, isTrue);
      expect(w.durationMs, 4 * 60 * 1000);
      expect(w.positionMs, 65 * 1000);
      expect(w.virtualOffsetMs, 72 * 60 * 1000);
    });

    test('virtual active: local position clamps into the segment', () {
      final w = resolveForegroundWindow(
        virtualActive: true,
        playerDurationMs: 1000000,
        playerPositionMs: 10,
        virtualOffsetMs: 5000,
        segmentDurationMs: 2000,
      );
      expect(w.positionMs, 0);
    });

    test('virtual active but unknown segment duration falls back to the player',
        () {
      final w = resolveForegroundWindow(
        virtualActive: true,
        playerDurationMs: 900000,
        playerPositionMs: 12345,
        virtualOffsetMs: 5000,
        segmentDurationMs: null,
      );
      expect(w.virtualActive, isFalse);
      expect(w.durationMs, 900000);
      expect(w.positionMs, 12345);
    });

    test('not virtual: raw player values pass through untouched', () {
      final w = resolveForegroundWindow(
        virtualActive: false,
        playerDurationMs: 60000,
        playerPositionMs: 4321,
        virtualOffsetMs: 999,
        segmentDurationMs: 100,
      );
      expect(w.virtualActive, isFalse);
      expect(w.durationMs, 60000);
      expect(w.positionMs, 4321);
    });

    test('playerPositionFor adds the virtual offset only while virtual', () {
      final virtual = resolveForegroundWindow(
        virtualActive: true,
        playerDurationMs: 100000,
        playerPositionMs: 0,
        virtualOffsetMs: 7000,
        segmentDurationMs: 10000,
      );
      expect(virtual.playerPositionFor(1500), 8500);

      final plain = resolveForegroundWindow(
        virtualActive: false,
        playerDurationMs: 100000,
        playerPositionMs: 0,
        virtualOffsetMs: 7000,
        segmentDurationMs: 10000,
      );
      expect(plain.playerPositionFor(1500), 1500);
    });

    test('negative player values degrade to zero, never negative', () {
      final w = resolveForegroundWindow(
        virtualActive: false,
        playerDurationMs: -1,
        playerPositionMs: -5,
        virtualOffsetMs: 0,
        segmentDurationMs: null,
      );
      expect(w.durationMs, 0);
      expect(w.positionMs, 0);
    });
  });
}
