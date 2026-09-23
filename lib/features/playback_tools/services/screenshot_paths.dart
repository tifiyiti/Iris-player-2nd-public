import 'package:iris/utils/path_conv.dart';
import 'package:path/path.dart' as p;

/// Platform-savvy screenshot directory helpers.
///
/// Pitfalls inherited from the media-path history (lib/utils/path_conv.dart):
/// - SAF `content://` URIs must never pass through `p.normalize` or be split
///   on `/` — the scheme would collapse into `/content:/...` and the stored
///   row becomes unwritable. SAF input is stored verbatim; display goes
///   through [displayScreenshotDir] (`safReadableRelative`).
/// - Windows drive/UNC shapes: join with `p.join`, never string-concat a
///   separator; `..`/`.` segments are rejected at input time (same rule as
///   `pathConv`), not silently normalized away at write time.
/// - The portable root may be unwritable (Program Files, MSIX sandbox) — the
///   resolver degrades to the OS pictures dir instead of throwing
///   (mirrors `AppPaths.fallbackReason`).

/// Display name of the Android public screenshots folder.
const String kAndroidScreenshotFolder = 'IRIS Screenshots';

/// Display name of the desktop installed-mode screenshots folder.
const String kDesktopScreenshotFolder = 'IRIS';

/// Portable-mode screenshots subdir under the portable root.
const String kPortableScreenshotSubdir = 'screenshots';

/// Pure resolution of the platform default screenshots directory.
///
/// - Android: `<picturesDir>/IRIS Screenshots` (public gallery-visible dir).
/// - Portable desktop with a usable root: `<portableRoot>/screenshots`.
/// - Everything else: `<picturesDir>/IRIS` (portable requested but root
///   missing degrades here instead of throwing).
String defaultScreenshotSubdir({
  required bool isAndroid,
  required bool isPortable,
  required String? portableRoot,
  required String picturesDir,
}) {
  if (isAndroid) return p.join(picturesDir, kAndroidScreenshotFolder);
  if (isPortable && portableRoot != null && portableRoot.isNotEmpty) {
    return p.join(portableRoot, kPortableScreenshotSubdir);
  }
  return p.join(picturesDir, kDesktopScreenshotFolder);
}

/// Effective directory: non-blank custom wins, otherwise the platform
/// default. Pure so the capture pipeline stays unit-testable.
String resolveScreenshotDirName({
  required String customDir,
  required String defaultDir,
}) {
  return customDir.trim().isEmpty ? defaultDir : customDir.trim();
}

/// Human-intuitive rendering of a stored screenshots directory.
///
/// - `''` (restore-default) renders the default label, never an empty row.
/// - `content://` tree URIs render their readable tail (`Download/Movies`);
///   a malformed URI degrades to a generic label instead of a raw dump.
/// - Plain paths render verbatim (the row itself ellipsizes).
String displayScreenshotDir(String stored) {
  final String s = stored.trim();
  if (s.isEmpty) return '默认目录';
  if (isSafPath(s)) return safReadableRelative(s) ?? '已选系统目录';
  return s;
}

/// Validates pasted/typed input into a storable directory string.
///
/// Returns `''` for empty input (restore-default) and `null` for rejected
/// input (traversal, desktop `content://`, unparseable). SAF tree URIs are
/// kept verbatim on Android; plain paths are normalized with `p.normalize`.
/// Callers surface `null` as an explanatory dialog, never a SnackBar.
String? normalizeScreenshotInput(String raw, {required bool isAndroid}) {
  final String s = raw.trim();
  if (s.isEmpty) return '';
  if (isSafPath(s)) return isAndroid ? s : null;
  // Reject `..` on the RAW segments before `p.normalize` resolves them
  // away: `pathConv` alone misses collapsible shapes (`/a/../b` → `/b`),
  // and the check must behave identically on every host OS.
  final List<String> rawSegs = s.split(RegExp(r'[/\\]+'));
  if (rawSegs.any((e) => e == '..')) return null;
  if (pathConv(s).isEmpty) return null;
  return p.normalize(s);
}
