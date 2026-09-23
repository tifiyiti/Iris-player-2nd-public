import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/sideway_panel_layout.dart';

/// The sideway panel's dial span is derived from the NORMAL panel's live-measured
/// bottom-bar height (published through [sidewayBarHeight]), so swapping in the
/// APB editor's slider/bar contents can never move or resize the ring.
void main() {
  test('dial span uses the measured bar slot, independent of bar content', () {
    expect(dialSpanForPanel(totalH: 420), 420 - kSidewayBarSlotH - 8);
    expect(dialSpanForPanel(totalH: 420, barSlotH: 200), 420 - 200 - 8);
    expect(dialSpanForPanel(totalH: 420, gap: 0), 420 - kSidewayBarSlotH);
  });

  test('never goes negative on a cramped panel', () {
    expect(dialSpanForPanel(totalH: 100), 0);
    expect(dialSpanForPanel(totalH: 0), 0);
  });

  test('the published bar height starts at the fallback and drives the span',
      () {
    expect(sidewayBarHeight.value, kSidewayBarSlotH);
    sidewayBarHeight.value = 210;
    addTearDown(() => sidewayBarHeight.value = kSidewayBarSlotH);
    expect(
      dialSpanForPanel(totalH: 420, barSlotH: sidewayBarHeight.value),
      420 - 210 - 8,
    );
  });
}
