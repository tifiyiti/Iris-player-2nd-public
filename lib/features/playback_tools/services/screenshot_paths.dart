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
/// - `''` (restore-default) renders [defaultLabel], never an empty row.
/// - `content://` tree URIs render their readable tail (`Download/Movies`);
///   a malformed URI degrades to [safFallbackLabel] instead of a raw dump.
/// - Plain paths render verbatim (the row itself ellipsizes).
///
/// Labels are passed in so this helper stays free of the localization layer.
String displayScreenshotDir(
  String stored, {
  required String defaultLabel,
  required String safFallbackLabel,
}) {
  final String s = stored.trim();
  if (s.isEmpty) return defaultLabel;
  if (isSafPath(s)) return safReadableRelative(s) ?? safFallbackLabel;
  return s;
}

/// Best-effort mapping of an Android SAF tree URI to a real filesystem path.
///
/// The screenshot writer uses plain `File` IO, so a picked SAF directory is
/// only usable once mapped to its filesystem location. With All-files access
/// granted this lets the custom dir work without native SAF writing. Returns
/// null when the volume cannot be mapped (cloud providers, unknown shapes) —
/// callers then keep the SAF URI and fall back to the default dir.
String? safTreeUriToPlainPath(String uri, {required String? primaryRoot}) {
  if (!isSafPath(uri)) return null;
  final Uri? parsed = Uri.tryParse(uri);
  if (parsed == null) return null;
  final List<String> segs = parsed.pathSegments;
  final int idx = segs.indexOf('tree');
  if (idx < 0 || idx + 1 >= segs.length) return null;
  // The tree document id is a single (percent-decoded) segment, e.g.
  // `primary:Download/Movies` or `1234-5678:Movies`.
  final String docId = segs[idx + 1];
  final int colon = docId.indexOf(':');
  if (colon <= 0) return null;
  final String volume = docId.substring(0, colon);
  final String rel = docId.substring(colon + 1);
  // `relative` docs are `/`-separated regardless of host; join segments so
  // the result uses the host separator.
  List<String> relSegs() =>
      rel.split('/').where((e) => e.isNotEmpty).toList();
  if (volume == 'primary') {
    if (primaryRoot == null || primaryRoot.isEmpty) return null;
    return p.joinAll([primaryRoot, ...relSegs()]);
  }
  // Non-primary volume (typically an SD card).
  return p.joinAll(['/storage', volume, ...relSegs()]);
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
