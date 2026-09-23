import 'dart:ui';
import 'package:flutter/painting.dart' show BoxFit;
import 'package:iris/l10n/app_localizations.dart';

/// Per-platform video display modes (metadata-settings era).
///
/// Windows/desktop and phone intentionally use SEPARATE enums: their video
/// pipelines cannot be fully equivalent. Desktop windows are resizable, so
/// two original-size semantics exist there; a phone window is fixed by the
/// OS, so original-size modes would be meaningless (the platform cycles keep
/// the legacy BoxFit trio).
///
/// Persisted EXCLUSIVELY as `video.` AUX Drift rows — JsonKey-excluded on
/// [AppState]; metadata gate OFF keeps the legacy `fit` BoxFit cycle as the
/// single source of truth and these enums are never consulted.
enum DesktopVideoDisplayMode {
  contain,
  fill,
  cover,
  adaptiveOriginal,
  forcedOriginal,
}

enum MobileVideoDisplayMode { contain, fill, cover }

/// Desktop cycle: legacy trio + the two original-size modes (PotPlayer
/// parity: 画面比例适应 → 原始尺寸(自适应) → 原始尺寸(100%)).
DesktopVideoDisplayMode nextDesktopVideoDisplayMode(
  DesktopVideoDisplayMode current,
) {
  switch (current) {
    case DesktopVideoDisplayMode.contain:
      return DesktopVideoDisplayMode.fill;
    case DesktopVideoDisplayMode.fill:
      return DesktopVideoDisplayMode.cover;
    case DesktopVideoDisplayMode.cover:
      return DesktopVideoDisplayMode.adaptiveOriginal;
    case DesktopVideoDisplayMode.adaptiveOriginal:
      return DesktopVideoDisplayMode.forcedOriginal;
    case DesktopVideoDisplayMode.forcedOriginal:
      return DesktopVideoDisplayMode.contain;
  }
}

/// Mobile cycle: the legacy BoxFit trio only.
MobileVideoDisplayMode nextMobileVideoDisplayMode(
  MobileVideoDisplayMode current,
) {
  switch (current) {
    case MobileVideoDisplayMode.contain:
      return MobileVideoDisplayMode.fill;
    case MobileVideoDisplayMode.fill:
      return MobileVideoDisplayMode.cover;
    case MobileVideoDisplayMode.cover:
      return MobileVideoDisplayMode.contain;
  }
}

/// Display-mode labels (localized). Shared by the control-bar button, the
/// keyboard executor and the window-fit button so every surface reports the
/// SAME name.
String desktopVideoDisplayModeLabel(
        DesktopVideoDisplayMode mode, AppLocalizations t) =>
    switch (mode) {
      DesktopVideoDisplayMode.contain => t.disp_contain,
      DesktopVideoDisplayMode.fill => t.disp_fill,
      DesktopVideoDisplayMode.cover => t.disp_cover,
      DesktopVideoDisplayMode.adaptiveOriginal => t.disp_adaptive,
      DesktopVideoDisplayMode.forcedOriginal => t.disp_forced,
    };

String mobileVideoDisplayModeLabel(
        MobileVideoDisplayMode mode, AppLocalizations t) =>
    switch (mode) {
      MobileVideoDisplayMode.contain => t.disp_contain,
      MobileVideoDisplayMode.fill => t.disp_fill,
      MobileVideoDisplayMode.cover => t.disp_cover,
    };

/// Resolves the BoxFit the video pipeline renders with for a desktop display
/// mode, given the video's logical (DPI-scaled) pixel size and the viewport.
///
/// - [DesktopVideoDisplayMode.adaptiveOriginal]: smaller than (or equal to)
///   the viewport → 1:1 original size ([BoxFit.none]); larger → fit the
///   viewport ([BoxFit.contain]) — the window-fit mode (desktop) may instead
///   grow the window, in which case the video stays 1:1 anyway.
/// - [DesktopVideoDisplayMode.forcedOriginal]: always 1:1; when the video is
///   larger than the window it gets truncated (clipped) by design.
/// - Unknown video dimensions degrade [adaptiveOriginal] to contain
///   ([forcedOriginal] keeps none — the player's 0-size guard already
///   renders the window-sized fallback in that case).
BoxFit resolveDesktopDisplayBoxFit({
  required DesktopVideoDisplayMode mode,
  required Size videoLogicalSize,
  required Size windowSize,
}) {
  switch (mode) {
    case DesktopVideoDisplayMode.contain:
      return BoxFit.contain;
    case DesktopVideoDisplayMode.fill:
      return BoxFit.fill;
    case DesktopVideoDisplayMode.cover:
      return BoxFit.cover;
    case DesktopVideoDisplayMode.adaptiveOriginal:
      if (videoLogicalSize.isEmpty) return BoxFit.contain;
      final bool fitsWindow = videoLogicalSize.width <= windowSize.width &&
          videoLogicalSize.height <= windowSize.height;
      return fitsWindow ? BoxFit.none : BoxFit.contain;
    case DesktopVideoDisplayMode.forcedOriginal:
      return BoxFit.none;
  }
}

/// Mobile variant — the trio maps straight through (a phone has no
/// resizable window, so original-size modes do not exist there).
BoxFit resolveMobileDisplayBoxFit({
  required MobileVideoDisplayMode mode,
  required Size videoLogicalSize,
  required Size windowSize,
}) {
  switch (mode) {
    case MobileVideoDisplayMode.contain:
      return BoxFit.contain;
    case MobileVideoDisplayMode.fill:
      return BoxFit.fill;
    case MobileVideoDisplayMode.cover:
      return BoxFit.cover;
  }
}
