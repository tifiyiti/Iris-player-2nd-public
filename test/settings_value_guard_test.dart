import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/engine/value_guard.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

void main() {
  group('ValueGuard.clamp enforcement (metadata-declared bounds)', () {
    // app.seekStepSeconds moved to control bar (SeekStepButton horizontal
    // dialog); its 1..120 clamp stays on the store mutator. Use a synthetic
    // int def mirroring that contract plus the real scan double def.
    const step = SettingDef(
      key: 'app.seekStepSeconds',
      section: SettingsSection.play,
      valueType: SettingValueType.int,
      defaultValue: '5',
      writable: true,
      clampMin: 1,
      clampMax: 120,
      widgetKind: SettingWidgetKind.slider,
      editorKey: 'seek_step_seconds',
      titleKey: 'seek_step_seconds',
      subtitleKey: 'seek_step_seconds_desc',
      sortOrder: 46,
    );
    final scan =
        SettingsCatalog.defs.singleWhere((d) => d.key == 'scan.autoCloseDelay');

    test('int field clamps into [1, 120] — matching typed mutator', () {
      expect(ValueGuard.coerce(step, 0), 1);
      expect(ValueGuard.coerce(step, 999), 120);
      expect(ValueGuard.coerce(step, 42), 42);
    });

    test('double field clamps into [0, 15] — matching typed mutator', () {
      expect(ValueGuard.coerce(scan, -1.0), 0.0);
      expect(ValueGuard.coerce(scan, 99.0), 15.0);
      expect(ValueGuard.coerce(scan, 2.5), 2.5);
      // int payload coerced to double (JSON may decode whole doubles as int)
      expect(ValueGuard.coerce(scan, 3), 3.0);
    });

    test('non-finite numbers are rejected, never clamped/rounded', () {
      // NaN/Infinity must fail closed: the int path calls .round(), which
      // throws UnsupportedError on NaN instead of rejecting the write.
      expect(ValueGuard.coerce(step, double.nan), isNull);
      expect(ValueGuard.coerce(step, double.infinity), isNull);
      expect(ValueGuard.coerce(step, double.negativeInfinity), isNull);
      expect(ValueGuard.coerce(scan, double.nan), isNull);
      expect(ValueGuard.coerce(scan, double.infinity), isNull);
    });
  });

  group('ValueGuard type/whitelist rejection', () {
    const def = SettingDef(
      key: 'x.e',
      section: SettingsSection.play,
      valueType: SettingValueType.enumeration,
      enumValues: ['a', 'b'],
      widgetKind: SettingWidgetKind.enumPick,
      titleKey: 't',
      sortOrder: 1,
    );
    const boolDef = SettingDef(
      key: 'x.b',
      section: SettingsSection.play,
      valueType: SettingValueType.bool,
      widgetKind: SettingWidgetKind.toggle,
      titleKey: 't',
      sortOrder: 2,
    );

    test('enum rejects names outside the whitelist', () {
      expect(ValueGuard.coerce(def, 'a'), 'a');
      expect(ValueGuard.coerce(def, 'bogus'), isNull);
      expect(ValueGuard.coerce(def, 1), isNull);
    });

    test('bool rejects non-bool payloads, null always rejected', () {
      expect(ValueGuard.coerce(boolDef, true), isTrue);
      expect(ValueGuard.coerce(boolDef, 'true'), isNull);
      expect(ValueGuard.coerce(boolDef, null), isNull);
    });
  });
}
