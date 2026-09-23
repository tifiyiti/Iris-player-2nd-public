import 'dart:ui';

/// Windows-only window-fit mode (metadata-settings era).
///
/// Orthogonal to — and HIGHER priority than — the video display mode: when
/// [WindowFitMode.fitVideo] is active (and the window is neither maximized
/// nor picture-fullscreen), every video open/switch resizes the window to
/// the video's resolution 1:1, so the display mode effectively renders at
/// native size. [WindowFitMode.fixedWindow] keeps the current window size
/// and hands rendering decisions back to the display mode.
///
/// Persisted EXCLUSIVELY as the `window.fitMode` AUX Drift row
/// (JsonKey-excluded on [AppState]); metadata gate OFF keeps the legacy
/// `autoResize` blob path untouched.
enum WindowFitMode {
  /// Force window-fit-video on every video open/switch (default).
  fitVideo,

  /// Keep the current window size; the video display mode decides rendering.
  fixedWindow,
}

WindowFitMode nextWindowFitMode(WindowFitMode current) =>
    current == WindowFitMode.fitVideo
        ? WindowFitMode.fixedWindow
        : WindowFitMode.fitVideo;

/// True when an `onWindowResize` event must arm the per-video manual override
/// (temporary [WindowFitMode.fixedWindow]). Programmatic bounds changes are
/// excluded via the shared [WindowResizeGuard]; unknown videos have nothing
/// to fit; only [WindowFitMode.fitVideo] has a fit to suppress.
bool shouldArmManualOverride({
  required bool isProgrammatic,
  required double videoWidthPx,
  required WindowFitMode mode,
}) =>
    !isProgrammatic &&
    videoWidthPx > 0 &&
    mode == WindowFitMode.fitVideo;

/// Keep-in-bounds gate. Folded into a pure predicate so the scrub-drag window
/// lock ([shouldSkipResizeDuringDrag]) is guaranteed to also freeze the clamp —
/// a drag across segments must never move the window. [isTransitioning] freezes
/// it across a fullscreen/maximize transition too, while the OS flags are still
/// settling and the store may momentarily disagree with the native window.
bool shouldClampKeepInBounds({
  required bool isDesktop,
  required bool hasEntry,
  required bool keepInBounds,
  required bool metadataReady,
  required bool fullScreenOrMaximized,
  required bool isDragging,
  bool isTransitioning = false,
}) =>
    isDesktop &&
    hasEntry &&
    keepInBounds &&
    metadataReady &&
    !fullScreenOrMaximized &&
    !isDragging &&
    !isTransitioning;

/// Computes the target window bounds for a 1:1 video fit.
///
/// - [videoPx]: decoded video resolution in physical pixels.
/// - [scaleFactor]: display DPI scale (physical → logical division).
/// - [visibleFrame]: the screen work area in LOGICAL units (taskbar excluded,
///   origin included so multi-monitor offsets survive) — "the
///   window-fullscreen size". A video larger than this caps the window at the
///   work area while the window stays NOT maximized; the video letterboxes
///   inside the video area (window minus [dockChrome]).
/// - [dockChrome]: logical width of the right playlist dock (panel + chrome)
///   that is part of the window but not part of the video surface.
/// - [minWindowSize]: the app's window minimum size — the result never goes
///   below it (a work area smaller than the minimum clamps to the minimum).
///
/// This only caps the SIZE; the returned rect is centered over [currentBounds]
/// and may sit partially off-screen. Use [resolveWindowBounds] when the result
/// must also stay fully inside [visibleFrame].
///
/// Returns null when the video dimensions are unknown (no resize).
Rect? computeVideoFitBounds({
  required Size videoPx,
  required double scaleFactor,
  required Rect visibleFrame,
  required double dockChrome,
  required Size minWindowSize,
  required Rect currentBounds,
}) {
  if (videoPx.isEmpty || scaleFactor <= 0) return null;

  Size videoLogical =
      Size(videoPx.width / scaleFactor, videoPx.height / scaleFactor);

  // Cap to the work area: the window may equal the window-fullscreen size
  // but never becomes maximized (spec). The video area (window minus dock)
  // keeps the video aspect ratio; contain letterboxes any residue.
  if (videoLogical.width + dockChrome > visibleFrame.width) {
    final double cappedVideoWidth = visibleFrame.width - dockChrome;
    videoLogical = Size(cappedVideoWidth, cappedVideoWidth * videoLogical.height / videoLogical.width);
  }
  if (videoLogical.height > visibleFrame.height) {
    videoLogical = Size(
      videoLogical.width * visibleFrame.height / videoLogical.height,
      visibleFrame.height,
    );
  }

  final double windowWidth = videoLogical.width + dockChrome;
  final double windowHeight = videoLogical.height;

  final double clampedWidth = windowWidth.clamp(minWindowSize.width, double.infinity);
  final double clampedHeight = windowHeight.clamp(minWindowSize.height, double.infinity);

  // Center the new bounds over the current ones so the window grows/shrinks
  // in place instead of jumping to the screen origin.
  return Rect.fromLTWH(
    currentBounds.left + (currentBounds.width - clampedWidth) / 2,
    currentBounds.top + (currentBounds.height - clampedHeight) / 2,
    clampedWidth,
    clampedHeight,
  );
}

/// Clamps [windowBounds] so it stays fully inside [visibleFrame].
///
/// [visibleFrame] is the screen work area in LOGICAL units (taskbar excluded,
/// already divided by scaleFactor — same contract as [computeVideoFitBounds]).
/// The window size is preserved; only position is adjusted. If the window is
/// larger than the work area it is pinned to visibleFrame's origin (no shrink).
Rect clampWindowToVisibleBounds({
  required Rect windowBounds,
  required Rect visibleFrame,
}) {
  if (visibleFrame.isEmpty) return windowBounds;
  double left;
  if (windowBounds.width > visibleFrame.width) {
    left = visibleFrame.left;
  } else {
    left = windowBounds.left.clamp(
      visibleFrame.left,
      visibleFrame.right - windowBounds.width,
    );
  }
  double top;
  if (windowBounds.height > visibleFrame.height) {
    top = visibleFrame.top;
  } else {
    top = windowBounds.top.clamp(
      visibleFrame.top,
      visibleFrame.bottom - windowBounds.height,
    );
  }
  return Rect.fromLTWH(left, top, windowBounds.width, windowBounds.height);
}

/// Single source of truth for the "fit video AND stay on screen" contract.
///
/// Composes the 1:1 fit ([computeVideoFitBounds]) with the work-area position
/// clamp ([clampWindowToVisibleBounds]). Keeping both in one function is what
/// guarantees the two behaviors cannot race: any caller that resizes the
/// window gets an already-pulled-in rect, so the fit can never push the window
/// off-screen.
///
/// Returns null when the video dimensions are unknown (no resize).
Rect? resolveWindowBounds({
  required Size videoPx,
  required double scaleFactor,
  required Rect visibleFrame,
  required double dockChrome,
  required Size minWindowSize,
  required Rect currentBounds,
}) {
  final Rect? fit = computeVideoFitBounds(
    videoPx: videoPx,
    scaleFactor: scaleFactor,
    visibleFrame: visibleFrame,
    dockChrome: dockChrome,
    minWindowSize: minWindowSize,
    currentBounds: currentBounds,
  );
  if (fit == null) return null;
  return clampWindowToVisibleBounds(
    windowBounds: fit,
    visibleFrame: visibleFrame,
  );
}
