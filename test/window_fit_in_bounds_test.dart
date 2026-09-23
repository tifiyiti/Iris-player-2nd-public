import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/window_fit_mode.dart';
import 'package:iris/utils/window_resize_guard.dart';

/// Combined window-bounds contract: "fit the window to the video" AND "keep
/// the window fully on screen" must hold together, not as two racing hooks.
///
/// [resolveWindowBounds] composes the fit with a work-area position clamp so a
/// window near a screen edge can never be pushed partially off-screen.
void main() {
  const workArea = Rect.fromLTWH(0, 0, 2560, 1400);
  const minSize = Size(427, 240);

  group('resolveWindowBounds', () {
    test('near right edge: fit result stays fully inside the work area', () {
      const current = Rect.fromLTWH(1780, 100, 800, 600); // right = 2580 > 2560
      final r = resolveWindowBounds(
        videoPx: const Size(1280, 720),
        scaleFactor: 1.0,
        visibleFrame: workArea,
        dockChrome: 0,
        minWindowSize: minSize,
        currentBounds: current,
      );
      expect(r, isNotNull);
      expect(r!.width, 1280);
      expect(r.height, 720);
      expect(r.left, greaterThanOrEqualTo(workArea.left));
      expect(r.top, greaterThanOrEqualTo(workArea.top));
      expect(r.right, lessThanOrEqualTo(workArea.right));
      expect(r.bottom, lessThanOrEqualTo(workArea.bottom));
    });

    test('near left/top edge: fit result stays fully inside the work area', () {
      const current = Rect.fromLTWH(0, 0, 400, 300);
      final r = resolveWindowBounds(
        videoPx: const Size(1920, 1080),
        scaleFactor: 1.0,
        visibleFrame: workArea,
        dockChrome: 0,
        minWindowSize: minSize,
        currentBounds: current,
      )!;
      expect(r.left, greaterThanOrEqualTo(workArea.left));
      expect(r.top, greaterThanOrEqualTo(workArea.top));
      expect(r.right, lessThanOrEqualTo(workArea.right));
      expect(r.bottom, lessThanOrEqualTo(workArea.bottom));
    });

    test('near bottom-right corner: fully inside', () {
      const current = Rect.fromLTWH(2300, 1300, 800, 600);
      final r = resolveWindowBounds(
        videoPx: const Size(1280, 720),
        scaleFactor: 1.0,
        visibleFrame: workArea,
        dockChrome: 0,
        minWindowSize: minSize,
        currentBounds: current,
      )!;
      expect(r.right, lessThanOrEqualTo(workArea.right));
      expect(r.bottom, lessThanOrEqualTo(workArea.bottom));
    });

    test('multi-monitor visibleFrame offset is preserved', () {
      const second = Rect.fromLTWH(1920, 0, 1920, 1080);
      const current = Rect.fromLTWH(2000, 100, 400, 300);
      final r = resolveWindowBounds(
        videoPx: const Size(1280, 720),
        scaleFactor: 1.0,
        visibleFrame: second,
        dockChrome: 0,
        minWindowSize: minSize,
        currentBounds: current,
      )!;
      expect(r.left, greaterThanOrEqualTo(second.left));
      expect(r.right, lessThanOrEqualTo(second.right));
    });

    test('dock chrome keeps the whole window inside the cap', () {
      const current = Rect.fromLTWH(1780, 100, 1200, 600);
      final r = resolveWindowBounds(
        videoPx: const Size(3840, 2160),
        scaleFactor: 1.0,
        visibleFrame: workArea,
        dockChrome: 387,
        minWindowSize: minSize,
        currentBounds: current,
      )!;
      expect(r.width, lessThanOrEqualTo(workArea.width));
      expect(r.right, lessThanOrEqualTo(workArea.right));
      expect(r.bottom, lessThanOrEqualTo(workArea.bottom));
    });

    test('unknown video dimensions → null (no resize)', () {
      expect(
        resolveWindowBounds(
          videoPx: Size.zero,
          scaleFactor: 1.0,
          visibleFrame: workArea,
          dockChrome: 0,
          minWindowSize: minSize,
          currentBounds: const Rect.fromLTWH(0, 0, 100, 100),
        ),
        isNull,
      );
    });
  });

  group('shouldArmManualOverride', () {
    test('programmatic resize never arms the manual override', () {
      expect(
        shouldArmManualOverride(
          isProgrammatic: true,
          videoWidthPx: 1920,
          mode: WindowFitMode.fitVideo,
        ),
        isFalse,
      );
    });

    test('user resize with a known video under fitVideo arms it', () {
      expect(
        shouldArmManualOverride(
          isProgrammatic: false,
          videoWidthPx: 1920,
          mode: WindowFitMode.fitVideo,
        ),
        isTrue,
      );
    });

    test('unknown video never arms', () {
      expect(
        shouldArmManualOverride(
          isProgrammatic: false,
          videoWidthPx: 0,
          mode: WindowFitMode.fitVideo,
        ),
        isFalse,
      );
    });

    test('fixedWindow never arms', () {
      expect(
        shouldArmManualOverride(
          isProgrammatic: false,
          videoWidthPx: 1920,
          mode: WindowFitMode.fixedWindow,
        ),
        isFalse,
      );
    });
  });

  group('shouldClampKeepInBounds', () {
    bool run({bool isDesktop = true, bool hasEntry = true, bool keep = true, bool meta = true, bool fs = false, bool dragging = false, bool transitioning = false}) =>
        shouldClampKeepInBounds(
          isDesktop: isDesktop,
          hasEntry: hasEntry,
          keepInBounds: keep,
          metadataReady: meta,
          fullScreenOrMaximized: fs,
          isDragging: dragging,
          isTransitioning: transitioning,
        );

    test('all conditions met → clamp', () => expect(run(), isTrue));
    test('dragging → never clamp (scrub-drag window lock)', () {
      expect(run(dragging: true), isFalse);
    });
    test('fullscreen/maximized → no clamp', () => expect(run(fs: true), isFalse));
    test('mid window-state transition → no clamp', () {
      expect(run(transitioning: true), isFalse);
    });
    test('setting off → no clamp', () => expect(run(keep: false), isFalse));
    test('metadata gate off → no clamp', () => expect(run(meta: false), isFalse));
    test('no queue entry → no clamp', () => expect(run(hasEntry: false), isFalse));
    test('non-desktop → no clamp', () => expect(run(isDesktop: false), isFalse));
  });

  group('WindowResizeGuard', () {
    setUp(() => WindowResizeGuard.instance.reset());
    tearDown(() => WindowResizeGuard.instance.reset());

    test('isApplying is true during the action and through the settle window',
        () async {
      expect(WindowResizeGuard.instance.isApplying, isFalse);
      await WindowResizeGuard.instance.run(() async {
        expect(WindowResizeGuard.instance.isApplying, isTrue);
      });
      // The OS resize event arrives AFTER setBounds returns — the settle
      // window must keep the guard armed so it is not read as a user resize.
      expect(WindowResizeGuard.instance.isApplying, isTrue);
      WindowResizeGuard.instance.reset();
      expect(WindowResizeGuard.instance.isApplying, isFalse);
    });
  });
}
