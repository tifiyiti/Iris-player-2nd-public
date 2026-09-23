import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/services/bg_seek_window.dart';

/// 仅当前 + 高同步：当前 bg 受 fg 限制的可播窗口。
void main() {
  group('resolveBgSeekWindow', () {
    test('null bounds mean the whole file, with no limit marks', () {
      final window = resolveBgSeekWindow(
        duration: const Duration(minutes: 3),
      );
      expect(window.loMs, 0);
      expect(window.hiMs, 180000);
      expect(window.hasLimit, isFalse);
      expect(window.floorFraction, 0.0);
      expect(window.ceilingFraction, 1.0);
    });

    test('a strict subset has a limit and reports both fractions', () {
      final window = resolveBgSeekWindow(
        duration: const Duration(minutes: 4),
        floorMs: 30000,
        ceilingMs: 150000,
      );
      expect(window.hasLimit, isTrue);
      expect(window.floorFraction, closeTo(0.125, 1e-9));
      expect(window.ceilingFraction, closeTo(0.625, 1e-9));
      expect(window.spanFraction, closeTo(0.5, 1e-9));
      expect(window.toWindowFraction(0.125), closeTo(0.0, 1e-9));
      expect(window.toWindowFraction(0.625), closeTo(1.0, 1e-9));
      expect(window.toWindowFraction(0.375), closeTo(0.5, 1e-9));
    });

    test('an unknown duration collapses to an empty, limit-less window', () {
      final window = resolveBgSeekWindow(duration: Duration.zero);
      expect(window.durationMs, 0);
      expect(window.hasLimit, isFalse);
    });

    test('an inverted pair collapses onto the ceiling', () {
      final window = resolveBgSeekWindow(
        duration: const Duration(minutes: 1),
        floorMs: 50000,
        ceilingMs: 10000,
      );
      expect(window.loMs, 10000);
      expect(window.hiMs, 10000);
    });

    test('out-of-range bounds are clamped into the file', () {
      final window = resolveBgSeekWindow(
        duration: const Duration(minutes: 1),
        floorMs: -5000,
        ceilingMs: 90000,
      );
      expect(window.loMs, 0);
      expect(window.hiMs, 60000);
      expect(window.hasLimit, isFalse);
    });
  });

  group('clampBgSeekMs', () {
    final window = resolveBgSeekWindow(
      duration: const Duration(minutes: 4),
      floorMs: 30000,
      ceilingMs: 150000,
    );

    test('inside the window is untouched', () {
      expect(clampBgSeekMs(window, 90000), 90000);
    });

    test('below the floor and above the ceiling stick to the edges', () {
      expect(clampBgSeekMs(window, 5000), 30000);
      expect(clampBgSeekMs(window, 200000), 150000);
    });

    test('a limit-less window only clamps into the file bounds', () {
      final open = resolveBgSeekWindow(duration: const Duration(minutes: 1));
      expect(open.hasLimit, isFalse);
      expect(clampBgSeekMs(open, 30000), 30000);
      expect(clampBgSeekMs(open, 999999), 60000);
    });

    test('the Duration helper mirrors the ms helper', () {
      expect(
        clampBgSeekDuration(window, const Duration(seconds: 1)),
        const Duration(milliseconds: 30000),
      );
    });
  });
}
