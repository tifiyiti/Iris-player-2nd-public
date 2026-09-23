import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

/// PotPlayer-style keyboard OSD contribution (desktop-only, `osd.` AUX rows).
///
/// All keys live outside `app.%` so they survive the `replaceAllValues`
/// wipe; backing AppState fields are JsonKey-excluded and resolved via
/// `resolveOsd*` helpers. The gate is `DefVisibility('osd.')` — hidden in
/// legacy mode, degrading to no OSD.
abstract final class OsdSettingsContribution {
  static const List<SettingDef> defs = <SettingDef>[
    SettingDef(
      key: 'osd.enabled',
      section: SettingsSection.general,
      valueType: SettingValueType.bool,
      defaultValue: 'true',
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'osd_enabled',
      titleKey: 'osd_enabled',
      subtitleKey: 'osd_enabled_desc',
      iconKey: 'osd_enabled',
      groupHeaderKey: 'group_osd',
      platforms: ['windows', 'linux', 'macos'],
      sortOrder: 110,
    ),
    SettingDef(
      key: 'osd.visibilityMode',
      section: SettingsSection.general,
      valueType: SettingValueType.enumeration,
      defaultValue: 'always',
      enumValues: ['always', 'hideWhenControlVisible'],
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'osd_visibility_mode',
      titleKey: 'osd_visibility_mode',
      subtitleKey: 'osd_visibility_mode_desc',
      iconKey: 'osd_visibility_mode',
      platforms: ['windows', 'linux', 'macos'],
      sortOrder: 111,
    ),
    SettingDef(
      key: 'osd.hAlign',
      section: SettingsSection.general,
      valueType: SettingValueType.enumeration,
      defaultValue: 'right',
      enumValues: ['left', 'center', 'right'],
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'osd_h_align',
      titleKey: 'osd_h_align',
      subtitleKey: 'osd_h_align_desc',
      iconKey: 'osd_h_align',
      platforms: ['windows', 'linux', 'macos'],
      sortOrder: 112,
    ),
    SettingDef(
      key: 'osd.vAlign',
      section: SettingsSection.general,
      valueType: SettingValueType.enumeration,
      defaultValue: 'bottom',
      enumValues: ['top', 'middle', 'bottom'],
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'osd_v_align',
      titleKey: 'osd_v_align',
      subtitleKey: 'osd_v_align_desc',
      iconKey: 'osd_v_align',
      platforms: ['windows', 'linux', 'macos'],
      sortOrder: 113,
    ),
    SettingDef(
      key: 'osd.layout',
      section: SettingsSection.general,
      valueType: SettingValueType.enumeration,
      defaultValue: 'singleLine',
      enumValues: ['singleLine', 'twoLines'],
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'osd_layout',
      titleKey: 'osd_layout',
      subtitleKey: 'osd_layout_desc',
      iconKey: 'osd_layout',
      platforms: ['windows', 'linux', 'macos'],
      sortOrder: 114,
    ),
    SettingDef(
      key: 'osd.durationMs',
      section: SettingsSection.general,
      valueType: SettingValueType.int,
      defaultValue: '2000',
      clampMin: 800,
      clampMax: 5000,
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'osd_duration',
      titleKey: 'osd_duration',
      subtitleKey: 'osd_duration_desc',
      iconKey: 'osd_duration',
      platforms: ['windows', 'linux', 'macos'],
      sortOrder: 115,
    ),
  ];
}
