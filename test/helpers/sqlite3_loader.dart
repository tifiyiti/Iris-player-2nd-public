import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

/// Host-side sqlite3 loading for drift tests.
///
/// `flutter test` runs on the dev host WITHOUT the platform-plugin bundling
/// step, so `sqlite3_flutter_libs` never supplies its DLL here (it only
/// lands in `build/windows/...` output, which is why the APP itself works).
///
/// Resolution order:
///  1. default dynamic-library resolution (PATH / working directory);
///  2. auto-discovery inside `<projectRoot>/build/windows/**` — any DLL the
///     Windows build produced (runner or sqlite3_flutter_libs plugin dir);
///  3. `IRIS_SQLITE3_DLL` environment variable (explicit override).
///
/// Fails loudly when nothing resolves so DB-backed tests skip silently
/// NEVER happens.
void ensureSqlite3Loaded() {
  if (!Platform.isWindows) return;
  try {
    DynamicLibrary.open('sqlite3.dll');
    return;
  } catch (_) {
    // fall through to discovery
  }

  final discovered = _discoverInBuildOutput();
  if (discovered != null) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open(discovered),
    );
    return;
  }

  final configured = Platform.environment['IRIS_SQLITE3_DLL'];
  if (configured != null && configured.isNotEmpty && File(configured).existsSync()) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open(configured),
    );
    return;
  }

  fail(
    'sqlite3.dll not resolvable on this host. Run `flutter build windows` '
    'once (so build/windows/** contains a bundled sqlite3.dll), or set '
    'IRIS_SQLITE3_DLL to an absolute path of one.',
  );
}

String? _discoverInBuildOutput() {
  final root = Directory('build');
  if (!root.existsSync()) return null;
  try {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File &&
          entity.uri.pathSegments.last.toLowerCase() == 'sqlite3.dll') {
        return entity.path;
      }
    }
  } on FileSystemException {
    return null;
  }
  return null;
}
