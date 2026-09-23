import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

/// Screenshot save-directory contribution (per-platform `screenshot.` AUX).
///
/// Two defs — mobile and desktop carry SEPARATE rows so a phone↔desktop
/// settings transfer never clobbers the other side with a foreign shape
/// (`content://` is meaningless on desktop and vice versa; the transfer
/// policy filters them per direction). `''` (the default) means the
/// platform default dir (Android public `Pictures/IRIS Screenshots`,
/// portable `<root>/screenshots`, installed `<pictures>/IRIS`).
abstract final class ScreenshotSettingsContribution {
  static const List<SettingDef> defs = <SettingDef>[
    SettingDef(
      key: 'screenshot.mobileDir',
      section: SettingsSection.play,
      valueType: SettingValueType.string,
      defaultValue: '',
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'screenshot_save_path_mobile',
      titleKey: 'screenshot_save_path',
      subtitleKey: 'screenshot_save_path_desc',
      iconKey: 'screenshot_save_path',
      platforms: ['android', 'ios'],
      sortOrder: 103,
    ),
    SettingDef(
      key: 'screenshot.desktopDir',
      section: SettingsSection.play,
      valueType: SettingValueType.string,
      defaultValue: '',
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'screenshot_save_path_desktop',
      titleKey: 'screenshot_save_path',
      subtitleKey: 'screenshot_save_path_desc',
      iconKey: 'screenshot_save_path',
      platforms: ['windows', 'linux', 'macos'],
      // Desktop tools block tail (after `keybind.editorEntry`); each row in
      // this file keeps a distinct sortOrder — Dart's sort is unstable, so
      // tied sortOrders reshuffle when the catalog grows.
      sortOrder: 104,
    ),
  ];
}
