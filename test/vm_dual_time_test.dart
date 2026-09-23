import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/interaction/ui/vm_dual_time.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';

VirtualSegment _seg(String name, int? durMs,
        {bool estimated = false}) =>
    VirtualSegment(
      mediaKey: 's:$name',
      storageId: 's',
      path: ['d', name],
      name: name,
      parentPath: 'd',
      durationMs: durMs,
      durationEstimated: estimated,
    );

VirtualMediaItem _threeBy100() => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|d|#1',
      rootPath: 'd',
      displayIndex: 1,
      displayName: 'd',
      segments: [_seg('a.mp4', 100000), _seg('b.mp4', 100000), _seg('c.mp4', 100000)],
    );

void main() {
  group('VmDualTime.resolve (total + sub for B-scheme dual display)', () {
    test('mid-item virtual 110s -> seg1 local 10s, total 300s, segDur 100s', () {
      final dual = VmDualTime.resolve(_threeBy100(), 110000);
      expect(dual.isVm, isTrue);
      expect(dual.showSub, isTrue);
      expect(dual.segIndex, 1);
      expect(dual.localMs, 10000);
      expect(dual.virtualMs, 110000);
      expect(dual.totalMs, 300000);
      expect(dual.segDurMs, 100000);
      expect(dual.isEstimated, isFalse);
    });

    test('exact boundary resolves to later segment (same as locate)', () {
      final dual = VmDualTime.resolve(_threeBy100(), 200000);
      expect(dual.segIndex, 2);
      expect(dual.localMs, 0);
    });

    test('past-end clamps to last segment end', () {
      final dual = VmDualTime.resolve(_threeBy100(), 999000);
      expect(dual.segIndex, 2);
      expect(dual.localMs, 100000);
      expect(dual.virtualMs, 300000);
    });

    test('negative clamps to first segment start', () {
      final dual = VmDualTime.resolve(_threeBy100(), -5000);
      expect(dual.segIndex, 0);
      expect(dual.localMs, 0);
      expect(dual.virtualMs, 0);
    });

    test('null item -> not VM, no sub row', () {
      final dual = VmDualTime.resolve(null, 5000);
      expect(dual.isVm, isFalse);
      expect(dual.showSub, isFalse);
      expect(dual.virtualMs, 5000);
    });

    test('single segment -> sub row hidden (sub == total)', () {
      final item = VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'r|d|#1',
        rootPath: 'd',
        displayIndex: 1,
        displayName: 'd',
        segments: [_seg('only.mp4', 60000)],
      );
      final dual = VmDualTime.resolve(item, 30000);
      expect(dual.isVm, isTrue);
      expect(dual.showSub, isFalse);
      expect(dual.localMs, 30000);
    });

    test('unknown sub duration -> segDurMs null, sub pair hidden', () {
      final item = VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'r|d|#1',
        rootPath: 'd',
        displayIndex: 1,
        displayName: 'd',
        segments: [_seg('a.mp4', 100000), _seg('b.mp4', null)],
      );
      final dual = VmDualTime.resolve(item, 100000);
      expect(dual.segIndex, 1);
      expect(dual.localMs, 0);
      expect(dual.segDurMs, isNull);
      // The position+duration pair is shown/hidden as one unit: with no
      // duration there is no usable sub row, so both collapse.
      expect(dual.showSub, isFalse);
    });

    test('estimated flag propagates from segment', () {
      final item = VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'r|d|#1',
        rootPath: 'd',
        displayIndex: 1,
        displayName: 'd',
        segments: [
          _seg('a.mp4', 100000),
          _seg('b.mp4', 60000, estimated: true)
        ],
      );
      final dual = VmDualTime.resolve(item, 120000);
      expect(dual.segIndex, 1);
      expect(dual.isEstimated, isTrue);
      expect(dual.segDurMs, 60000);
    });
  });

  group('VmDualTime.resolve second-grid alignment (vmDualTimeSync)', () {
    // Segment 0 lasts 100.9s so segment 1's start offset carries a 0.9s
    // fractional part — the exact case that makes the two labels tick apart.
    VirtualMediaItem fractional() => VirtualMediaItem(
          ruleId: 'r',
          scopeKey: 'r|d|#1',
          rootPath: 'd',
          displayIndex: 1,
          displayName: 'd',
          segments: [
            _seg('a.mp4', 100900),
            _seg('b.mp4', 100000),
            _seg('c.mp4', 100000),
          ],
        );

    // 110000 is 9.1s into segment 1 (offset 100.9s).
    test('exact -> raw values untouched', () {
      final dual = VmDualTime.resolve(fractional(), 110000,
          sync: VmDualTimeSyncMode.exact);
      expect(dual.virtualMs, 110000);
      expect(dual.localMs, 9100);
      expect(dual.displayVirtualMs, 110000);
      expect(dual.displayLocalMs, 9100);
    });

    test('subToTotal -> total exact, sub shifted onto the total grid', () {
      final dual = VmDualTime.resolve(fractional(), 110000,
          sync: VmDualTimeSyncMode.subToTotal);
      expect(dual.displayVirtualMs, 110000);
      // 9100 + 900 (fractional offset) => 10000.
      expect(dual.displayLocalMs, 10000);
      // Both second digits now land on the same boundary.
      expect(dual.displayLocalMs ~/ 1000,
          dual.displayVirtualMs ~/ 1000 - 100);
    });

    test('subToTotal clamps the sub at the segment duration', () {
      // Local 99.1s + 0.9s would be 100.0s; the last 200ms sits at 99.6s.
      final dual = VmDualTime.resolve(fractional(), 200000,
          sync: VmDualTimeSyncMode.subToTotal);
      expect(dual.localMs, 99100);
      expect(dual.displayLocalMs, 100000);
    });

    test('totalToSub -> sub exact, total shifted onto the sub grid', () {
      final dual = VmDualTime.resolve(fractional(), 110000,
          sync: VmDualTimeSyncMode.totalToSub);
      expect(dual.displayLocalMs, 9100);
      // 110000 - 900 (fractional offset) => 109100.
      expect(dual.displayVirtualMs, 109100);
    });

    test('non-VM resolve ignores sync (passthrough)', () {
      for (final mode in VmDualTimeSyncMode.values) {
        final dual = VmDualTime.resolve(null, 5000, sync: mode);
        expect(dual.displayVirtualMs, 5000);
        expect(dual.displayLocalMs, 0);
      }
    });
  });
}
