@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/probe/windows_shell_probe.dart';

/// Regression guard for the Windows Shell-property PIDs.
///
/// `SHGetPropertyStoreFromParsingName` answers IPropertyStore lookups by the
/// property's REAL key inside its property set (propkey.h): a wrong PID makes
/// `GetValue` miss forever, so every Shell probe returns empty and recursive
/// scans / VM quick scans can never persist a duration (media_kit demux is the
/// only path that still works). These values are the authoritative
/// PKEY_Media_Duration (3), PKEY_Video_FrameWidth (3), PKEY_Video_FrameHeight
/// (4) PIDs from the Windows SDK — do not "tune" them.
void main() {
  test('media duration uses PKEY_Media_Duration (fmtid 64440490, pid 3)', () {
    expect(probeDurationFmtid, '{64440490-4C8B-11D1-8B70-080036B11A03}');
    expect(probeDurationPid, 3);
  });

  test('frame dimensions use PKEY_Video_FrameWidth/Height (pid 3/4)', () {
    expect(probeVideoFmtid, '{64440491-4C8B-11D1-8B70-080036B11A03}');
    expect(probeFrameWidthPid, 3);
    expect(probeFrameHeightPid, 4);
  });
}
