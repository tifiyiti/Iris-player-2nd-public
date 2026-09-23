import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/window_transition_guard.dart';
import 'package:window_manager/window_manager.dart';

/// Registers a [WindowListener] that mirrors the OS maximized state into
/// [PlayerUiState.isWindowMaximized] (窗口全屏).
///
/// Completes the three-state model: 窗口非全屏 = !isFullScreen &&
/// !isWindowMaximized / 窗口全屏 = isWindowMaximized / 画面全屏 =
/// isFullScreen. Native maximize paths that never pass through the title-bar
/// button (Win+Up snap, double-click on the drag area in some themes) land
/// here reactively — the one-shot `FutureBuilder(isMaximized)` in the window
/// buttons could not track them.
///
/// Fullscreen events are ignored while picture-fullscreen is active: on
/// Windows `setFullScreen` toggles the same native maximize machinery, and
/// 画面全屏 must not be misreported as 窗口全屏.
void useWindowMaximized() {
  useEffect(() {
    if (!isDesktop) return null;

    // Seed from the OS once (app may start restored into a maximized window).
    () async {
      try {
        final bool maximized = await windowManager.isMaximized();
        if (usePlayerUiStore().state.isFullScreen) return;
        usePlayerUiStore().setWindowMaximized(maximized);
      } catch (_) {}
    }();

    final listener = _MaximizeListener();
    windowManager.addListener(listener);
    return () => windowManager.removeListener(listener);
  }, const []);
}

class _MaximizeListener extends WindowListener {
  @override
  void onWindowMaximize() {
    // A programmatic fullscreen/maximize transition emits maximize/unmaximize
    // on the shared Windows machinery; ignore the burst and let the store's
    // reconcile() publish the settled OS truth.
    if (WindowTransitionGuard.instance.isTransitioning) return;
    if (usePlayerUiStore().state.isFullScreen) return;
    usePlayerUiStore().setWindowMaximized(true);
  }

  @override
  void onWindowUnmaximize() {
    if (WindowTransitionGuard.instance.isTransitioning) return;
    if (usePlayerUiStore().state.isFullScreen) return;
    usePlayerUiStore().setWindowMaximized(false);
  }
}
