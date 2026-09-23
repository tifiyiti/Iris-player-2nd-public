@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';

/// Shell handlers for exotic containers return present-but-absurd
/// dimensions (e.g. height 667040 for a 720p file, A/B-pinned on real
/// files); persisting those corrupts resolution sorting. Absurd values
/// must be nulled before write-back. Duration is untouched (callers
/// already require positive values).
void main() {
  test('absurd dimensions are nulled, sane values kept', () {
    final r = sanitizeProbeResult(
        const ProbeResult(durationMs: 1559445, width: 1280, height: 667040));
    expect(r.durationMs, 1559445);
    expect(r.width, 1280);
    expect(r.height, isNull);
    expect(r.pixelCount, isNull);
  });

  test('zero and negative dimensions are nulled', () {
    final r = sanitizeProbeResult(
        const ProbeResult(durationMs: 1000, width: 0, height: -720));
    expect(r.width, isNull);
    expect(r.height, isNull);
  });

  test('sane result is returned unchanged', () {
    const r = ProbeResult(durationMs: 1000, width: 1280, height: 720);
    final sane = sanitizeProbeResult(r);
    expect(sane.durationMs, 1000);
    expect(sane.width, 1280);
    expect(sane.height, 720);
    expect(sane.pixelCount, 1280 * 720);
  });

  test('empty result stays empty', () {
    expect(sanitizeProbeResult(ProbeResult.empty).pixelCount, isNull);
  });
}
