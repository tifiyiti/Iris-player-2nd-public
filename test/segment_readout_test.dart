import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/view/segment_abp_slider.dart';

/// The A/B readouts report the UNUSED bg time, always with a `-` sign (the
/// spec's "丢失了多少 bg 时间"): the old `+mm:ss` overflow form is gone.
void main() {
  test('lead readout is "-mm:ss" for unused bg before A, empty at/under 0', () {
    expect(segmentLeadReadout(0), '');
    expect(segmentLeadReadout(-1), '');
    expect(segmentLeadReadout(30000), '-00:30');
    expect(segmentLeadReadout(3661000), '-1:01:01');
  });

  test('tail readout is always "-mm:ss" (never a "+" overflow form)', () {
    expect(segmentTailReadout(0), '');
    expect(segmentTailReadout(10000), '', reason: 'raw overflow is not shown');
    expect(segmentTailReadout(-50000), '-00:50');
  });
}
