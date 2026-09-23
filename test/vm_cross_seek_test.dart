import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/features/virtual_media/resolver/vm_resolver.dart';

VirtualSegment _seg(String name, int durMs) => VirtualSegment(
      mediaKey: 's:$name',
      storageId: 's',
      path: ['d', name],
      name: name,
      parentPath: 'd',
      durationMs: durMs,
    );

VirtualMediaRule _rule({
  int maxMinutes = 120,
  int maxCount = 30,
  bool useDur = true,
  bool useCnt = true,
}) =>
    VirtualMediaRule(
      id: 'r',
      name: 'r',
      matchMode: VmMatchMode.specifiedDirRecursive,
      paths: const ['d'],
      maxDurationMinutes: maxMinutes,
      maxItemCount: maxCount,
      useDurationCap: useDur,
      useCountCap: useCnt,
      // Hard-cap chunking focus: keep per-file exclusion out of the fixture.
      useExcludeOverlong: false,
      skipSingleSegment: false,
    );

void main() {
  group('vm rule defaults (single-player P0)', () {
    test('defaults are 120min / 32 items', () {
      const r = VirtualMediaRule(id: 'x', name: 'x');
      expect(r.maxDurationMinutes, 120);
      expect(r.maxItemCount, kVmDefaultMaxItemCount);
    });
  });

  group('vm chunk hard caps (32 items / 5h, even unchecked)', () {
    test('150 tiny segments with NO caps still chunk at hard count cap', () {
      final lib = [for (var i = 0; i < 150; i++) _seg('f$i.mp4', 60 * 1000)];
      final items = resolveVirtualMedia(
        rules: [_rule(useDur: false, useCnt: false)],
        library: lib,
      );
      expect(items.length, greaterThan(1));
      for (final it in items) {
        expect(it.segments.length, lessThanOrEqualTo(kVmHardMaxItemCount));
      }
    });

    test('unchecked duration still bounded by 5h hard cap', () {
      // 10 x 60min = 10h total, no caps checked -> must split at 300min.
      final lib = [for (var i = 0; i < 10; i++) _seg('g$i.mp4', 60 * 60 * 1000)];
      final items = resolveVirtualMedia(
        rules: [_rule(useDur: false, useCnt: false)],
        library: lib,
      );
      expect(items.length, greaterThan(1));
      for (final it in items) {
        expect(it.totalDurationMs, lessThanOrEqualTo(300 * 60 * 1000));
      }
    });
  });

  group('vm cross-seek locate contract', () {
    test('locate preserves intra-segment offset for pending seek', () {
      final item = VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'r|d|#1',
        rootPath: 'd',
        displayIndex: 1,
        displayName: 'd',
        segments: [_seg('a.mp4', 10000), _seg('b.mp4', 10000)],
      );
      // 12s virtual -> segment 1 at local 2000ms: the jump must carry 2000,
      // never restart at 0 (the 0%-flash regression).
      final (idx, local) = item.locate(12000);
      expect(idx, 1);
      expect(local, 2000);
    });
  });
}
