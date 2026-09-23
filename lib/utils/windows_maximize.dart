import 'package:iris/utils/platform.dart';
import 'package:win32/win32.dart';

/// Test seam: replaces the win32 `IsZoomed` probe so widget/unit tests on a
/// non-Windows host can drive the fullscreen detour decision.
bool? debugWindowsIsZoomedOverride;

/// Test seam: replaces the direct `SC_RESTORE` post.
void Function(int hwnd)? debugWindowsRestoreOverride;

/// OS truth for 窗口全屏 that window_manager's `isMaximized()` misses.
///
/// window_manager reports maximize from `GetWindowPlacement().showCmd`, while
/// its native `SetFullScreen` branches on `IsZoomed()` (the `WS_MAXIMIZE`
/// style). The two can disagree, so a caller about to enter 画面全屏 must
/// consult the native style directly or it may skip the restore detour and
/// still deadlock the platform thread.
bool windowsIsZoomed(int hwnd) {
  final override = debugWindowsIsZoomedOverride;
  if (override != null) return override;
  if (!isWindows || hwnd == 0) return false;
  return IsZoomed(hwnd) != 0;
}

/// Posts `SC_RESTORE` straight to the window, bypassing window_manager's
/// `Unmaximize()` `showCmd` gate (which no-ops when `showCmd` and
/// `WS_MAXIMIZE` disagree).
void windowsRequestRestore(int hwnd) {
  final override = debugWindowsRestoreOverride;
  if (override != null) {
    override(hwnd);
    return;
  }
  if (!isWindows || hwnd == 0) return;
  PostMessage(hwnd, WM_SYSCOMMAND, SC_RESTORE, 0);
}
