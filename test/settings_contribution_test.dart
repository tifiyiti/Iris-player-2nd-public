import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/app_settings_contribution.dart';
import 'package:iris/features/meta_settings/contributions/merger.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';
import 'package:iris/models/store/app_state.dart';

void main() {
  group('SettingsContributionMerger contract', () {
    test('app contribution passes validation and merges ordered', () {
      final merged = SettingsContributionMerger.merge([
        AppSettingsContribution.defs,
      ]);

      expect(merged.length, AppSettingsContribution.defs.length);
      // (section, sortOrder) ordering.
      for (var i = 1; i < merged.length; i++) {
        final a = merged[i - 1];
        final b = merged[i];
        final order = a.section.index.compareTo(b.section.index) != 0
            ? a.section.index.compareTo(b.section.index)
            : a.sortOrder.compareTo(b.sortOrder);
        expect(order, lessThanOrEqualTo(0),
            reason: '${a.key} must sort before/at ${b.key}');
      }
    });

    test('duplicate keys fail fast', () {
      const def = SettingDef(
        key: 'app.dup',
        section: SettingsSection.general,
        valueType: SettingValueType.bool,
        widgetKind: SettingWidgetKind.toggle,
        titleKey: 't',
        sortOrder: 1,
      );
      expect(
        () => SettingsContributionMerger.merge([[def, def]]),
        throwsArgumentError,
      );
    });

    test('duplicate sortOrder within a section fails fast, but the same '
        'sortOrder in different sections is allowed', () {
      const a = SettingDef(
        key: 'app.a',
        section: SettingsSection.general,
        valueType: SettingValueType.bool,
        widgetKind: SettingWidgetKind.toggle,
        titleKey: 't',
        sortOrder: 5,
      );
      const b = SettingDef(
        key: 'app.b',
        section: SettingsSection.general,
        valueType: SettingValueType.bool,
        widgetKind: SettingWidgetKind.toggle,
        titleKey: 't',
        sortOrder: 5,
      );
      const c = SettingDef(
        key: 'app.c',
        section: SettingsSection.play,
        valueType: SettingValueType.bool,
        widgetKind: SettingWidgetKind.toggle,
        titleKey: 't',
        sortOrder: 5,
      );
      expect(
        () => SettingsContributionMerger.merge([
          [a, b]
        ]),
        throwsArgumentError,
      );
      expect(
        SettingsContributionMerger.merge([
          [a, c]
        ]).length,
        2,
      );
    });

    test('enumeration requires enumValues; custom requires editorKey; '
        'editorKey forbidden on value kinds', () {
      const badEnum = SettingDef(
        key: 'x.badEnum',
        section: SettingsSection.play,
        valueType: SettingValueType.enumeration,
        widgetKind: SettingWidgetKind.enumPick,
        titleKey: 't',
        sortOrder: 1,
      );
      const badCustom = SettingDef(
        key: 'x.badCustom',
        section: SettingsSection.play,
        valueType: SettingValueType.json,
        widgetKind: SettingWidgetKind.custom,
        titleKey: 't',
        sortOrder: 2,
      );
      const badEditorOnToggle = SettingDef(
        key: 'x.badEditor',
        section: SettingsSection.play,
        valueType: SettingValueType.bool,
        widgetKind: SettingWidgetKind.toggle,
        editorKey: 'nope',
        titleKey: 't',
        sortOrder: 3,
      );
      const unknownPlatform = SettingDef(
        key: 'x.badPlatform',
        section: SettingsSection.play,
        valueType: SettingValueType.bool,
        widgetKind: SettingWidgetKind.toggle,
        platforms: ['win32'],
        titleKey: 't',
        sortOrder: 4,
      );

      expect(() => SettingsContributionMerger.merge([[badEnum]]),
          throwsArgumentError);
      expect(() => SettingsContributionMerger.merge([[badCustom]]),
          throwsArgumentError);
      expect(() => SettingsContributionMerger.merge([[badEditorOnToggle]]),
          throwsArgumentError);
      expect(() => SettingsContributionMerger.merge([[unknownPlatform]]),
          throwsArgumentError);
    });
  });

  group('AppSettingsContribution invariants', () {
    late final List<SettingDef> defs;

    setUpAll(() => defs = AppSettingsContribution.defs);

    test('gate def exists, defaults ON (meta-driven install default), '
        'lives on General', () {
      // Requirement #5: the gate DEF moved inside the Legacy 兼容 entry;
      // the gate itself ships ON and the entry lives on General.
      final legacyEntry =
          defs.singleWhere((d) => d.key == 'legacy.compatEntry');
      expect(legacyEntry.section, SettingsSection.general);
      expect(const AppState().useMetadataSettings, isTrue);
    });

    test('every bool/int/double/string/enumeration default decodes cleanly '
        '(defaults are codec-valid)', () {
      for (final d in defs) {
        switch (d.valueType) {
          case SettingValueType.bool:
            final ok = d.defaultValue == null ||
                d.defaultValue == 'false' ||
                d.defaultValue == 'true';
            expect(ok, isTrue,
                reason: '${d.key}: bool default must be "false"/"true"/null');
          case SettingValueType.int:
            if (d.defaultValue != null) {
              expect(int.tryParse(d.defaultValue!), isNotNull,
                  reason: '${d.key}: int default malformed');
            }
          case SettingValueType.double:
            if (d.defaultValue != null) {
              expect(double.tryParse(d.defaultValue!), isNotNull,
                  reason: '${d.key}: double default malformed');
            }
          case SettingValueType.enumeration:
            expect(d.defaultValue, anyOf(isNull, isIn(d.enumValues)),
                reason: '${d.key}: enum default not among declared values');
          case SettingValueType.string:
          case SettingValueType.json:
            break;
        }
      }
    });

    test('platform filters only use android/desktop vocabulary', () {
      for (final d in defs) {
        for (final p in d.platforms) {
          expect(['android', 'windows', 'linux', 'macos'], contains(p));
        }
      }
    });
  });
}
