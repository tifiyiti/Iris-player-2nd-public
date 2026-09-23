import 'dart:async';

import 'package:flutter/foundation.dart';

/// Cross-hook coordination for PICTURE-FULLSCREEN / WINDOW-MAXIMIZE
/// transitions (desktop).
///
/// On Windows, 画面全屏 is implemented by the same native maximize machinery as
/// 窗口全屏, so one transition emits a burst of `maximize` / `unmaximize` /
/// `enter-full-screen` / `leave-full-screen` events. Without a shared
/// "transition in flight" flag two things break:
///   * [useWindowMaximized]'s listener mirrors a transient maximize event into
///     the store and loses the real 窗口全屏 state;
///   * the resize / keep-in-bounds hooks may issue `setBounds` mid-transition.
///
/// Every native window-state change goes through [run]; the listener and the
/// effects skip while [isTransitioning], then the caller reconciles the store
/// from OS truth once the settle window has drained the queued events.
class WindowTransitionGuard {
  WindowTransitionGuard._();

  static final WindowTransitionGuard instance = WindowTransitionGuard._();

  bool _transitioning = false;
  Timer? _timer;

  /// True while a window-state transition is in flight, or within the settle
  /// window after it returned (late native events arrive asynchronously).
  bool get isTransitioning => _transitioning;

  /// Runs [action] with the transition flag armed for its duration plus
  /// [settle], so native events queued behind the async method channel are
  /// still seen as "programmatic".
  Future<T> run<T>(
    Future<T> Function() action, {
    Duration settle = const Duration(milliseconds: 400),
  }) async {
    _transitioning = true;
    _timer?.cancel();
    try {
      return await action();
    } finally {
      _timer?.cancel();
      _timer = Timer(settle, () => _transitioning = false);
    }
  }

  @visibleForTesting
  void reset() {
    _timer?.cancel();
    _timer = null;
    _transitioning = false;
  }
}

/// Whether entering picture fullscreen must first restore (unmaximize) the
/// window.
///
/// Windows: window_manager's native `SetFullScreen` hangs when the window is
/// maximized — it strips `WS_MAXIMIZEBOX` from a zoomed window and forces a
/// `SWP_FRAMECHANGED` reposition, which deadlocks the platform thread. Routing
/// through the not-maximized path avoids that branch; the caller records the
/// flag so exiting fullscreen can re-maximize.
bool shouldDetourThroughRestore({
  required bool entering,
  required bool currentlyMaximized,
}) =>
    entering && currentlyMaximized;

/// Whether entering picture fullscreen must first normalize the window out of
/// 窗口全屏, combining BOTH native truths.
///
/// [reportedMaximized] is window_manager's `isMaximized()`
/// (`GetWindowPlacement().showCmd == SW_MAXIMIZE`); [zoomed] is win32
/// `IsZoomed()`, i.e. the `WS_MAXIMIZE` style that window_manager's native
/// `SetFullScreen` actually branches on. The two can disagree — when they do,
/// the detour used to be skipped (reported false) while the native call still
/// took the deadlocking maximized branch (zoomed true). Treating either signal
/// as "must restore" closes that gap.
bool needsRestoreBeforeFullScreen({
  required bool entering,
  required bool reportedMaximized,
  required bool zoomed,
}) =>
    entering && (reportedMaximized || zoomed);

/// Reconciles the two store flags from OS truth.
///
/// Invariant: `isWindowMaximized` = 窗口全屏, i.e. maximized while NOT in
/// picture fullscreen. On Windows a picture-fullscreen window also reports
/// `isMaximized() == true` (it borrows the native maximize machinery), so the
/// raw result must be masked by the fullscreen flag or 画面全屏 would be
/// misreported as 窗口全屏.
({bool isFullScreen, bool isWindowMaximized}) reconcileWindowFlags({
  required bool nativeFullScreen,
  required bool nativeMaximized,
}) =>
    (
      isFullScreen: nativeFullScreen,
      isWindowMaximized: !nativeFullScreen && nativeMaximized,
    );
