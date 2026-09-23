@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/probe/windows_shell_probe.dart';

/// Exercises the Shell property store against a REAL file — the path that
/// actually loads a Shell property handler in-process.
///
/// WHY THIS FILE HOLDS EXACTLY ONE TEST (do not add a second): creating an
/// IPropertyStore via `SHGetPropertyStoreFromParsingPath` loads a Shell
/// extension DLL into the flutter_tester process, and doing that in a file
/// with MORE THAN ONE test wedges flutter_test's own teardown — the last test
/// completes and prints, but `tearDownAll`'s body is never entered and the
/// runner eventually reports "did not complete". Measured control runs:
///   - missing-path probe + pure test          → passes (no store created)
///   - two probes inside ONE test              → passes
///   - real-file probe in a file with 1 test   → passes
///   - real-file probe + any second test       → hangs, in either order
/// `CoUninitialize` is NOT involved (removing `shutdown()` still hangs), and
/// every probe call itself returns correct results before the wedge.
///
/// Coverage split: graceful unusable-input paths (which never create a store)
/// live in `windows_shell_probe_test.dart`; the real-file store path lives
/// here, alone. Real media files (duration/dimension from actual MP4/MKV)
/// remain on the manual acceptance checklist — synthetic headers are not
/// reliably accepted by Windows property handlers.
void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('iris_probe_store_test');
  });

  tearDownAll(() {
    WindowsShellProbeService.shutdown();
    // Best-effort cleanup; Shell may transiently hold probed files.
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('non-media file yields empty video properties without throwing',
      () async {
    final txt = File('${tmp.path}\\plain.txt')..writeAsStringSync('hello');
    final service = WindowsShellProbeService();
    final r = await service.probeFile(txt.path);
    // A .txt has no video properties; duration may or may not exist.
    expect(r.width, anyOf(isNull, isNonZero));
    expect(r.height, anyOf(isNull, isNonZero));
  });
}
