import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/view/widgets/editor_bindings.dart';
import 'package:iris/features/meta_settings/view/widgets/setting_editors.dart';

/// Domain guards locking the two P0 fixes:
///
/// 1. Generic-rendered rows (toggle/enumPick/slider) only understand the
///    `app.` snapshot (SettingRow._fieldOf + StateBridge + SettingsEngine).
///    Out-of-domain keys MUST be `custom` with an `editorKey` (see the
///    `_switchTile` contract note in editor_bindings.dart). The three
///    `virtualmedia.*` enumPick rows violated this and silently no-op'd.
/// 2. `security.transferLog` must be merged into the catalog (its binding +
///    visibility rule already wait for it) and reuse the existing
///    `transfer_audit_title` ARB entry (zero new title keys).
void main() {
  group('value-kind rows live in the app. domain', () {
    test('no toggle/enumPick/slider def outside app. namespace', () {
      final offenders = SettingsCatalog.defs
          .where((d) =>
              (d.widgetKind == SettingWidgetKind.toggle ||
                  d.widgetKind == SettingWidgetKind.enumPick ||
                  d.widgetKind == SettingWidgetKind.slider) &&
              !d.key.startsWith('app.'))
          .map((d) => '${d.key} (${d.widgetKind.name})')
          .toList();
      expect(offenders, isEmpty,
          reason: 'out-of-domain rows must be custom + editorKey, '
              'the generic renderer silently drops them');
    });

    test('every custom def has a registered editor binding', () {
      EditorBindings.ensureRegistered();
      final missing = SettingsCatalog.defs
          .where((d) => d.widgetKind == SettingWidgetKind.custom)
          .where((d) => SettingEditors.lookup(d.editorKey) == null)
          .map((d) => '${d.key} -> ${d.editorKey}')
          .toList();
      expect(missing, isEmpty,
          reason: 'custom rows without a binding render an inert placeholder');
    });
  });

  group('transfer audit entry', () {
    test('catalog contains security.transferLog', () {
      expect(
        SettingsCatalog.defs.any((d) => d.key == 'security.transferLog'),
        isTrue,
        reason: 'binding + visibility already wait for this def',
      );
    });

    test('transfer audit def reuses transfer_audit_title with a binding', () {
      EditorBindings.ensureRegistered();
      final def = SettingsCatalog.defs
          .singleWhere((d) => d.key == 'security.transferLog');
      expect(def.titleKey, 'transfer_audit_title');
      expect(def.editorKey, isNotNull);
      expect(SettingEditors.lookup(def.editorKey), isNotNull);
    });
  });
}
