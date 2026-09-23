import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

/// tag_play settings contribution (`tagplay.` AUX rows).
///
/// Every value lives in the tag-play store, not the `app.` snapshot, so the
/// rows are `custom` and bound in editor_bindings.dart. Hidden entirely while
/// the feature is unavailable via the existing `tagplay.` DefVisibility rule.
abstract final class TagPlaySettingsContribution {
  static const List<SettingDef> defs = <SettingDef>[
    SettingDef(
      key: 'tagplay.inputBar',
      section: SettingsSection.general,
      valueType: SettingValueType.bool,
      defaultValue: 'false',
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'tagplay_input_bar',
      titleKey: 'set_tag_play_input_bar',
      subtitleKey: 'set_tag_play_input_bar_desc',
      groupHeaderKey: 'group_tag_play',
      sortOrder: 190,
    ),
    // The hardware-key command banner is desktop-only, mirroring the
    // sheet: phones never render it, so the row is hidden there too.
    SettingDef(
      key: 'tagplay.inputHint',
      section: SettingsSection.general,
      valueType: SettingValueType.bool,
      defaultValue: 'true',
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'tagplay_input_hint',
      titleKey: 'set_tag_play_input_hint',
      subtitleKey: 'set_tag_play_input_hint_desc',
      platforms: ['windows', 'linux', 'macos'],
      sortOrder: 191,
    ),
    SettingDef(
      key: 'tagplay.viewStackEnabled',
      section: SettingsSection.general,
      valueType: SettingValueType.bool,
      defaultValue: 'false',
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'tagplay_view_stack',
      titleKey: 'set_tag_play_view_stack',
      subtitleKey: 'set_tag_play_view_stack_desc',
      sortOrder: 192,
    ),
  ];
}
