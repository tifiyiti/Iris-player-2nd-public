import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/path_conv.dart';

/// `remapLeadingSegments` moves a segment path from one root to another only
/// when the leading segments match — the primitive behind favorites/history
/// re-keying on a drive-letter change.
void main() {
  test('replaces a matching leading prefix', () {
    expect(
      remapLeadingSegments(['D:', 'Movies', 'a.mp4'], ['D:'], ['E:']),
      ['E:', 'Movies', 'a.mp4'],
    );
  });

  test('replaces a multi-segment prefix', () {
    expect(
      remapLeadingSegments(['D:', 'Movies', 'a.mp4'], ['D:', 'Movies'], ['E:']),
      ['E:', 'a.mp4'],
    );
  });

  test('returns null when the prefix does not match', () {
    expect(
      remapLeadingSegments(['C:', 'Movies'], ['D:'], ['E:']),
      isNull,
    );
  });

  test('returns null when the path is shorter than the prefix', () {
    expect(remapLeadingSegments(['D:'], ['D:', 'Movies'], ['E:']), isNull);
  });

  test('an empty prefix never matches', () {
    expect(remapLeadingSegments(['D:', 'Movies'], [], ['E:']), isNull);
  });
}
