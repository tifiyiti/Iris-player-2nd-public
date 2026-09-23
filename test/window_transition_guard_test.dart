import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/window_transition_guard.dart';
import 'package:iris/utils/windows_maximize.dart';

void main() {
  group('reconcileWindowFlags', () {
    test('windowed: neither fullscreen nor maximized', () {
      final flags = reconcileWindowFlags(
        nativeFullScreen: false,
        nativeMaximized: false,
      );
      expect(flags.isFullScreen, isFalse);
      expect(flags.isWindowMaximized, isFalse);
    });

    test('窗口全屏: maximized while not fullscreen', () {
      final flags = reconcileWindowFlags(
        nativeFullScreen: false,
        nativeMaximized: true,
      );
      expect(flags.isFullScreen, isFalse);
      expect(flags.isWindowMaximized, isTrue);
    });

    test('画面全屏 from windowed: fullscreen supersedes maximize', () {
      final flags = reconcileWindowFlags(
        nativeFullScreen: true,
        nativeMaximized: false,
      );
      expect(flags.isFullScreen, isTrue);
      expect(flags.isWindowMaximized, isFalse);
    });

    test(
      '画面全屏 from 窗口全屏: native maximize is masked off window-fullscreen '
      '(Windows borrows the maximize machinery)',
      () {
        final flags = reconcileWindowFlags(
          nativeFullScreen: true,
          nativeMaximized: true,
        );
        expect(flags.isFullScreen, isTrue);
        expect(flags.isWindowMaximized, isFalse);
      },
    );
  });

  group('shouldDetourThroughRestore', () {
    test('entering from maximized → detour (unmaximize first)', () {
      expect(
        shouldDetourThroughRestore(entering: true, currentlyMaximized: true),
        isTrue,
      );
    });

    test('entering from windowed → no detour', () {
      expect(
        shouldDetourThroughRestore(entering: true, currentlyMaximized: false),
        isFalse,
      );
    });

    test('exiting never detours', () {
      expect(
        shouldDetourThroughRestore(entering: false, currentlyMaximized: true),
        isFalse,
      );
      expect(
        shouldDetourThroughRestore(entering: false, currentlyMaximized: false),
        isFalse,
      );
    });
  });

  group('needsRestoreBeforeFullScreen', () {
    test('entering from 窗口全屏 via window_manager truth → restore', () {
      expect(
        needsRestoreBeforeFullScreen(
          entering: true,
          reportedMaximized: true,
          zoomed: false,
        ),
        isTrue,
      );
    });

    test('entering where only win32 IsZoomed is true → restore (the mismatch)',
        () {
      // window_manager's showCmd-based isMaximized() says false while the
      // native WS_MAXIMIZE style (what SetFullScreen branches on) is set.
      expect(
        needsRestoreBeforeFullScreen(
          entering: true,
          reportedMaximized: false,
          zoomed: true,
        ),
        isTrue,
      );
    });

    test('entering from windowed on both truths → no restore', () {
      expect(
        needsRestoreBeforeFullScreen(
          entering: true,
          reportedMaximized: false,
          zoomed: false,
        ),
        isFalse,
      );
    });

    test('exiting never restores', () {
      for (final reported in [true, false]) {
        for (final zoomed in [true, false]) {
          expect(
            needsRestoreBeforeFullScreen(
              entering: false,
              reportedMaximized: reported,
              zoomed: zoomed,
            ),
            isFalse,
          );
        }
      }
    });
  });

  group('windows_maximize seams', () {
    tearDown(() {
      debugWindowsIsZoomedOverride = null;
      debugWindowsRestoreOverride = null;
    });

    test('windowsIsZoomed honors the test override', () {
      debugWindowsIsZoomedOverride = true;
      expect(windowsIsZoomed(123), isTrue);
      debugWindowsIsZoomedOverride = false;
      expect(windowsIsZoomed(123), isFalse);
    });

    test('windowsRequestRestore honors the test override', () {
      var restored = 0;
      debugWindowsRestoreOverride = (hwnd) => restored = hwnd;
      windowsRequestRestore(456);
      expect(restored, 456);
    });
  });

  group('WindowTransitionGuard', () {
    setUp(WindowTransitionGuard.instance.reset);
    tearDown(WindowTransitionGuard.instance.reset);

    test('isTransitioning is true during the action and through the settle window',
        () async {
      expect(WindowTransitionGuard.instance.isTransitioning, isFalse);
      await WindowTransitionGuard.instance.run(() async {
        expect(WindowTransitionGuard.instance.isTransitioning, isTrue);
      });
      // Native events arrive AFTER the method-channel future returns — the
      // settle window must keep the guard armed so the listener ignores them.
      expect(WindowTransitionGuard.instance.isTransitioning, isTrue);
      WindowTransitionGuard.instance.reset();
      expect(WindowTransitionGuard.instance.isTransitioning, isFalse);
    });

    test('returns the action result', () async {
      final result = await WindowTransitionGuard.instance.run(() async => 42);
      expect(result, 42);
      WindowTransitionGuard.instance.reset();
    });
  });
}
