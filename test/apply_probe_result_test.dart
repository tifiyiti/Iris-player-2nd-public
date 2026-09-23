import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/features/media_library/scan/service/recursive_scan_service.dart';

/// Merge semantics of [applyProbeResult]:
/// probe values fill gaps; existing values are never downgraded by a
/// "could not read" (null) outcome; non-file nodes pass through.
void main() {
  MediaFile fileNode({int? durationMs, int? width, int? height}) =>
      MediaNode.file(
        id: 'st1:a.mp4',
        storageId: 'st1',
        path: const ['a.mp4'],
        pathDepth: 1,
        name: 'a.mp4',
        mediaType: MediaType.video,
        durationMs: durationMs,
        width: width,
        height: height,
      ) as MediaFile;

  test('fills missing fields from probe result', () {
    final merged = applyProbeResult(
      fileNode(),
      const ProbeResult(durationMs: 1000, width: 640, height: 360),
    ) as MediaFile;

    expect(merged.durationMs, 1000);
    expect(merged.width, 640);
    expect(merged.height, 360);
  });

  test('existing values are never downgraded by null probe fields', () {
    final merged = applyProbeResult(
      fileNode(durationMs: 5000, width: 1920, height: 1080),
      const ProbeResult(durationMs: null, width: null, height: null),
    ) as MediaFile;

    expect(merged.durationMs, 5000);
    expect(merged.width, 1920);
    expect(merged.height, 1080);
  });

  test('probe result overwrites stale values when it has real data', () {
    final merged = applyProbeResult(
      fileNode(durationMs: 5000),
      const ProbeResult(durationMs: 6000),
    ) as MediaFile;

    expect(merged.durationMs, 6000);
  });

  test('directory nodes pass through untouched', () {
    final dir = MediaNode.directory(
      id: 'st1:d',
      storageId: 'st1',
      path: const ['d'],
      pathDepth: 1,
      name: 'd',
    );
    expect(
        identical(
            applyProbeResult(dir, const ProbeResult(width: 1, height: 1)),
            dir),
        isTrue);
  });
}
