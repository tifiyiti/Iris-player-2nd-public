import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/window_fit_mode.dart';

/// Part B: Windows-only window-fit mode.
///
/// [WindowFitMode.fitVideo] sizes the window to the video's resolution 1:1
/// (DPI-aware) on every video open/switch; when the video is larger than the
/// work area the window equals the work-area size (still NOT maximized) and
/// the video letterboxes — the video area excludes the dock chrome, and the
/// result never drops below the window minimum size.
void main() {
  group('WindowFitMode cycle', () {
    test('fitVideo → fixedWindow → fitVideo', () {
      expect(nextWindowFitMode(WindowFitMode.fitVideo), WindowFitMode.fixedWindow);
      expect(nextWindowFitMode(WindowFitMode.fixedWindow), WindowFitMode.fitVideo);
    });
  });

  group('computeVideoFitBounds', () {
    // 1920x1080 physical px video on a 100% scale display.
    const workArea = Rect.fromLTWH(0, 0, 2560, 1400); // logical
    const current = Rect.fromLTWH(320, 160, 1280, 720);
    const minSize = Size(427, 240);

    test('small video: window = video size 1:1, centered on old bounds', () {
      final rect = computeVideoFitBounds(
        videoPx: const Size(1280, 720),
        scaleFactor: 1.0,
        visibleFrame: workArea,
        dockChrome: 0,
        minWindowSize: minSize,
        currentBounds: current,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 1280);
      expect(rect.height, 720);
      expect(rect.left, current.left + (current.width - 1280) / 2);
      expect(rect.top, current.top + (current.height - 720) / 2);
    });

    test('DPI: 150% scale divides physical pixels into logical size', () {
      final rect = computeVideoFitBounds(
        videoPx: const Size(1920, 1080),
        scaleFactor: 1.5,
        visibleFrame: workArea,
        dockChrome: 0,
        minWindowSize: minSize,
        currentBounds: current,
      );
      expect(rect!.width, 1280);
      expect(rect.height, 720);
    });

    test('too large: window caps at the work-area size (NOT maximized)', () {
      final rect = computeVideoFitBounds(
        videoPx: const Size(3840, 2160),
        scaleFactor: 1.0,
        visibleFrame: workArea,
        dockChrome: 0,
        minWindowSize: minSize,
        currentBounds: current,
      );
      // Aspect-preserving cap: fills the binding dimension exactly and never
      // exceeds the work area in either axis (window stays non-maximized).
      expect(rect!.width, lessThanOrEqualTo(workArea.width));
      expect(rect.height, workArea.height);
    });

    test('dock chrome is added to the window width, not the video height', () {
      final rect = computeVideoFitBounds(
        videoPx: const Size(1280, 720),
        scaleFactor: 1.0,
        visibleFrame: workArea,
        dockChrome: 387, // 380 panel + 7 chrome
        minWindowSize: minSize,
        currentBounds: current,
      );
      expect(rect!.width, 1280 + 387);
      expect(rect.height, 720);
    });

    test('capped window still reserves the dock chrome inside the work area',
        () {
      // 4K video + dock: width capped to work area, height = width/aspect
      // ratio of the VIDEO only (letterbox via contain), chrome stays within
      // the cap because the cap IS the window size.
      final rect = computeVideoFitBounds(
        videoPx: const Size(3840, 2160),
        scaleFactor: 1.0,
        visibleFrame: workArea,
        dockChrome: 387,
        minWindowSize: minSize,
        currentBounds: current,
      );
      expect(rect!.width, lessThanOrEqualTo(workArea.width));
      expect(rect.height, lessThanOrEqualTo(workArea.height));
    });

    test('never smaller than the window minimum size', () {
      final rect = computeVideoFitBounds(
        videoPx: const Size(320, 180),
        scaleFactor: 1.0,
        visibleFrame: workArea,
        dockChrome: 0,
        minWindowSize: minSize,
        currentBounds: current,
      );
      expect(rect!.width, greaterThanOrEqualTo(minSize.width));
      expect(rect.height, greaterThanOrEqualTo(minSize.height));
    });

    test('unknown video dimensions → null (no resize)', () {
      expect(
        computeVideoFitBounds(
          videoPx: Size.zero,
          scaleFactor: 1.0,
          visibleFrame: workArea,
          dockChrome: 0,
          minWindowSize: minSize,
          currentBounds: current,
        ),
        isNull,
      );
    });

    test('work area smaller than minimum size → clamped to minimum', () {
      final rect = computeVideoFitBounds(
        videoPx: const Size(3840, 2160),
        scaleFactor: 1.0,
          visibleFrame: const Rect.fromLTWH(0, 0, 300, 200),
        dockChrome: 0,
        minWindowSize: minSize,
        currentBounds: current,
      );
      expect(rect!.width, minSize.width);
      expect(rect.height, minSize.height);
    });
  });
}
