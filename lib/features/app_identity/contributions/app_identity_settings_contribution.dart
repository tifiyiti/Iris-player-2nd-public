import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

/// App-identity settings contribution: ONE action row that opens the
/// custom-desktop-entries manager. Entry data itself lives in `identity.*`
/// AUX rows (see [AppIdentityStore]) — deliberately not representable as
/// setting values, exactly like the scan-progress precedent.
abstract final class AppIdentitySettingsContribution {
  static const List<SettingDef> defs = <SettingDef>[
    SettingDef(
      key: 'identity.editorEntry',
      section: SettingsSection.general,
      valueType: SettingValueType.json,
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'app_identity_entries',
      titleKey: 'identity_entries',
      subtitleKey: 'identity_entries_desc',
      iconKey: 'identity_entries',
      // Custom desktop entries are an Android home-screen feature only, filed
      // under the data block (led by `data.exportEntry`).
      platforms: ['android'],
      sortOrder: 24,
    ),
  ];
}
