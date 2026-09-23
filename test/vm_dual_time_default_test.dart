import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';
import 'package:iris/features/virtual_media/contributions/virtual_media_settings_contribution.dart';
import 'package:iris/features/virtual_media/interaction/ui/vm_dual_time.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/models/store/app_state.dart';

/// Product default: the B-scheme dual-time second grid aligns the SUB row to
/// the (exact) TOTAL by default (`subToTotal`), not `exact`. Existing stored
/// rows are untouched — this only pins the fresh-install defaults the three
/// resolution layers must agree on (AppState, SettingDef, VmDualTime.resolve).
VirtualSegment _seg(String name, int? durMs) => VirtualSegment(
      mediaKey: 's:$name',
      storageId: 's',
      path: ['d', name],
      name: name,
      parentPath: 'd',
      durationMs: durMs,
    );

/// Segment 0 lasts 100.9s so segment 1's start offset carries a 0.9s
/// fractional part — the exact case the sync mode corrects.
VirtualMediaItem _fractional() => VirtualMediaItem(
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

void main() {
  test('AppState defaults dual-time sync to subToTotal', () {
    expect(const AppState().vmDualTimeSync, VmDualTimeSyncMode.subToTotal);
  });

  test('SettingDef default matches AppState (subToTotal)', () {
    final def = VirtualMediaSettingsContribution.defs
        .firstWhere((d) => d.key == 'virtualmedia.dualTimeSync');
    expect(def.defaultValue, 'subToTotal');
  });

  test('VmDualTime.resolve omitting sync applies the subToTotal grid', () {
    final dual = VmDualTime.resolve(_fractional(), 110000);
    expect(dual.displayVirtualMs, 110000);
    // 9100 local + 900 fractional offset => 10000 on the total's grid.
    expect(dual.displayLocalMs, 10000);
  });

  test('SettingDef ordering/keys unchanged by the default flip', () {
    final keys = VirtualMediaSettingsContribution.defs
        .map((SettingDef d) => d.key)
        .toList();
    expect(keys, contains('virtualmedia.dualTimeSync'));
  });
}
