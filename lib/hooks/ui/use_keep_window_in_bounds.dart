import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/models/store/window_fit_mode.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/store/use_scrub_drag_store.dart';
import 'package:iris/utils/drag_window_lock.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/window_resize_guard.dart';
import 'package:iris/utils/window_transition_guard.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart';

/// Ensures the desktop window stays fully inside the visible work area when
/// switching videos. Users may drag the window off-screen freely — the next
/// video (any queue entry change, audio or video) pulls it back if enabled.
///
/// Meta-driven: only active when `window.keepInBounds` is true and the
/// metadata gate is on; otherwise no-op (feature entirely absent in legacy).
///
/// Re-checks on the same signals the fit hook reacts to (entry URI and decoded
/// size) so the clamp lands AFTER a resize, not before it. The scrub-drag
/// window lock applies here too: [shouldClampKeepInBounds] freezes the clamp
/// while any slider drag is in flight, so a cross-segment drag never moves the
/// window (see [shouldSkipResizeDuringDrag]).
void useKeepWindowInBounds() {
  final context = useContext();

  final keepInBounds = useAppStore().select(context, (s) => s.keepWindowInBounds);
  final useMetadata = useAppStore().select(context, (s) => s.useMetadataSettings);
  final isFullScreen = usePlayerUiStore().select(context, (s) => s.isFullScreen);
  final isMaximized = usePlayerUiStore().select(context, (s) => s.isWindowMaximized);
  final videoWidth = usePlayerUiStore().select(context, (s) => s.videoWidth);
  final videoHeight = usePlayerUiStore().select(context, (s) => s.videoHeight);
  // Same drag lock as the fit hook — a merged/cross-segment seek drag must
  // never move the window mid-gesture.
  final isDragging = useScrubDragStore().select(
    context,
    (s) => shouldSkipResizeDuringDrag(
      isScrubbing: s.isScrubbing,
      isHolding: s.isHolding,
    ),
  );

  // Queue entry identity — uri is stable, avoids object equality churn.
  final fileUri = usePlayQueueStore().select(context, (state) {
    final idx = state.playQueue.indexWhere((e) => e.index == state.currentIndex);
    if (idx == -1) return null;
    return state.playQueue[idx].file.uri;
  });

  useEffect(() {
    final bool shouldClamp = shouldClampKeepInBounds(
      isDesktop: isDesktop,
      hasEntry: fileUri != null,
      keepInBounds: keepInBounds,
      metadataReady: useMetadata && MetaSettingsModule.ready,
      fullScreenOrMaximized: isFullScreen || isMaximized,
      isDragging: isDragging,
      isTransitioning: WindowTransitionGuard.instance.isTransitioning,
    );
    if (!shouldClamp) return null;

    () async {
      try {
        final screen = await getCurrentScreen();
        if (screen == null) return;
        final double scale = screen.scaleFactor;
        if (scale <= 0) return;
        final Rect visibleFrame = Rect.fromLTWH(
          screen.visibleFrame.left / scale,
          screen.visibleFrame.top / scale,
          screen.visibleFrame.width / scale,
          screen.visibleFrame.height / scale,
        );
        if (visibleFrame.isEmpty) return;
        final Rect current = await windowManager.getBounds();
        final Rect clamped = clampWindowToVisibleBounds(
          windowBounds: current,
          visibleFrame: visibleFrame,
        );
        if ((clamped.left - current.left).abs() < 1 &&
            (clamped.top - current.top).abs() < 1) {
          return;
        }
        if (await windowManager.isFullScreen() || await windowManager.isMaximized()) {
          return;
        }
        // Shared guard: never let the clamp arm the fit hook's manual override.
        await WindowResizeGuard.instance.run(
          () => windowManager.setBounds(clamped, animate: true),
        );
      } catch (_) {
        // Best-effort desktop guard — never surface to UI.
      }
    }();

    return null;
  }, [
    fileUri,
    videoWidth,
    videoHeight,
    keepInBounds,
    useMetadata,
    isFullScreen,
    isMaximized,
    isDragging,
  ]);
}
