import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/models/enums/webdav_scan_mode.dart';
import 'package:iris/models/store/app_state.dart';

/// The strategy switch that keeps the legacy serial scan reachable while the
/// discovery path is the install default.
void main() {
  final def =
      SettingsCatalog.defs.singleWhere((d) => d.key == 'app.webDavScanMode');

  group('app.webDavScanMode meta-setting', () {
    test('declares both strategies and defaults to discovery', () {
      expect(def.valueType, SettingValueType.enumeration);
      expect(def.widgetKind, SettingWidgetKind.enumPick);
      expect(def.enumValues, ['discovery', 'legacyScan']);
      expect(def.defaultValue, 'discovery');
    });

    test('default matches the AppState default and serializes by name', () {
      expect(const AppState().webDavScanMode, WebDavScanMode.discovery);
      expect(const AppState().toJson()['webDavScanMode'], 'discovery');
    });

    test('stays in the app. domain so the generic renderer applies', () {
      // Out-of-domain value rows must be custom + editorKey, which would make
      // this row a silent no-op (see settings_domain_guard_test).
      expect(def.key.startsWith('app.'), isTrue);
      expect(def.editorKey, isNull);
    });
  });
}
