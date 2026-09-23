import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:iris/utils/logger.dart';
import 'package:path/path.dart' as p;

final areaKeyLog = AreaKeyLog(LogKeys.legacyUtil);

/// Why a requested portable layout was rejected at init time.
enum PortableFallbackReason {
  /// The `userdata` root next to the exe could not be created or written
  /// (typical when the folder was extracted into a read-only location such
  /// as Program Files). The app degrades to installed-mode paths.
  dataDirNotWritable,
}

/// Resolved portable data layout: everything lives under one movable root.
class PortableLayout {
  const PortableLayout({required this.rootPath});

  /// `<exeDir>/userdata`
  final String rootPath;

  /// Drift database directory (`<root>/db`).
  String get dbDirPath => p.join(rootPath, 'db');

  /// KV settings directory (`<root>/settings`).
  String get settingsDirPath => p.join(rootPath, 'settings');
}

/// Pure decision core of the portable-mode detection.
///
/// Portable mode requires ALL of:
/// - a platform where "next to the exe" is meaningful (Windows desktop),
/// - no `IRIS_NO_PORTABLE=1` escape hatch in the environment,
/// - not running sandboxed as an MSIX package (read-only WindowsApps),
/// - a `portable.flag` marker file sitting next to the executable.
///
/// Returns `null` for installed mode.
PortableLayout? resolvePortableLayout({
  required bool platformSupported,
  required bool forceDisabled,
  required bool storeSandboxed,
  required bool markerExists,
  required String exeDirPath,
}) {
  if (!platformSupported || forceDisabled || storeSandboxed || !markerExists) {
    return null;
  }
  return PortableLayout(rootPath: p.join(exeDirPath, AppPaths.userDataDirName));
}

/// Central resolver for the app's data locations.
///
/// Portable mode is decided ONCE at startup ([init]) before any database or
/// store initialization; every consumer afterwards just reads [isPortable] /
/// [layout]. When the portable root turns out to be unwritable, the app
/// degrades to installed-mode paths and records why in [fallbackReason]
/// (surfaced to the user as a one-time dialog after runApp).
abstract final class AppPaths {
  /// Marker file that switches the app into portable mode.
  static const String markerFileName = 'portable.flag';

  /// Directory (next to the exe) holding all portable user data.
  static const String userDataDirName = 'userdata';

  /// Environment escape hatch to force installed mode for debugging.
  static const String portableDisableEnvVar = 'IRIS_NO_PORTABLE';

  static bool _initialized = false;
  static bool _portable = false;
  static PortableLayout? _layout;
  static PortableFallbackReason? _fallbackReason;

  /// Whether startup resolved a usable portable layout.
  static bool get isPortable => _portable;

  /// Non-null iff [isPortable]; exposes the resolved sub-directories.
  static PortableLayout? get layout => _layout;

  /// Why portable mode was rejected despite a marker being present.
  static PortableFallbackReason? get fallbackReason => _fallbackReason;

  /// Decides the mode and prepares the portable directories. Must be called
  /// once, BEFORE any database / store initialization. No-op on non-Windows
  /// platforms and in later calls.
  static Future<void> init({@visibleForTesting Directory? exeDirOverride}) async {
    if (_initialized) return;
    _initialized = true;

    // Guard dart:io Platform access (throws on web).
    if (kIsWeb || !Platform.isWindows) return;

    final exeDirPath =
        exeDirOverride?.path ?? File(Platform.resolvedExecutable).parent.path;

    final markerFile = File(p.join(exeDirPath, markerFileName));
    final bool markerExists = await markerFile.exists();

    final layout = resolvePortableLayout(
      platformSupported: true,
      forceDisabled: Platform.environment[portableDisableEnvVar] == '1',
      storeSandboxed: exeDirPath.contains('WindowsApps'),
      markerExists: markerExists,
      exeDirPath: exeDirPath,
    );
    if (layout == null) {
      if (markerExists) {
        areaKeyLog.i(
            'portable.flag present but portable mode disabled/sandboxed '
            '(env=$portableDisableEnvVar, sandboxed=${exeDirPath.contains('WindowsApps')})');
      }
      return;
    }

    try {
      await Directory(layout.rootPath).create(recursive: true);
      await Directory(layout.dbDirPath).create(recursive: true);
      await Directory(layout.settingsDirPath).create(recursive: true);

      // Writability probe — cheap and definitive.
      final probe = File(p.join(layout.rootPath, '.write-probe'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
    } catch (e) {
      areaKeyLog.e('Portable root unusable, falling back to installed '
          'mode: $e');
      _fallbackReason = PortableFallbackReason.dataDirNotWritable;
      return;
    }

    _layout = layout;
    _portable = true;
    areaKeyLog.i('Portable mode active: ${layout.rootPath}');
  }

  /// Clears all resolved state (test isolation only).
  @visibleForTesting
  static void resetForTest() {
    _initialized = false;
    _portable = false;
    _layout = null;
    _fallbackReason = null;
  }
}
