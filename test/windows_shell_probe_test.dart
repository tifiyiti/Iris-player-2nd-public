@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/features/media_library/scan/probe/windows_shell_probe.dart';

/// Exercises the Windows Shell-property probe against graceful paths.
///
/// Covers only targets that never create an IPropertyStore: a nonexistent
/// path fails before any Shell property handler is loaded, so this file can
/// hold multiple tests safely. The real-file store path lives ALONE in
/// `windows_shell_probe_store_test.dart` — loading a Shell property handler
/// in a multi-test file wedges flutter_test's teardown (see that file's
/// header for the measured control runs).
///
/// Real media-file coverage (duration/dimension values from actual MP4/MKV)
/// belongs to the manual acceptance checklist: synthetic headers are not
/// reliably accepted by Windows property handlers.
void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('iris_probe_test');
  });

  tearDownAll(() {
    WindowsShellProbeService.shutdown();
    // Best-effort cleanup; Shell may transiently hold probed files.
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('missing path yields empty result without throwing', () async {
    final service = WindowsShellProbeService();
    final r = await service.probeFile(
        '${tmp.path}\\does_not_exist_9f3a.mp4');
    expect(r.durationMs, isNull);
    expect(r.width, isNull);
    expect(r.height, isNull);
    expect(r.pixelCount, isNull);
  });

  test('ProbeResult.pixelCount derives only when both sides known', () {
    expect(const ProbeResult(width: 1920, height: 1080).pixelCount,
        2073600);
    expect(const ProbeResult(width: 1920).pixelCount, isNull);
    expect(ProbeResult.empty.pixelCount, isNull);
  });
}
