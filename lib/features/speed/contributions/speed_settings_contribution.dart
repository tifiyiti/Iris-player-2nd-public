import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

abstract final class SpeedSettingsContribution {
  static const List<SettingDef> defs = <SettingDef>[
    SettingDef(
      key: 'speed.gestureMode',
      section: SettingsSection.play,
      valueType: SettingValueType.enumeration,
      defaultValue: 'dualAxis',
      enumValues: ['singleAxis', 'dualAxis'],
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'speed_gesture_mode',
      titleKey: 'speed_gesture_mode',
      subtitleKey: 'speed_gesture_mode_desc',
      iconKey: 'speed_gesture_mode',
      // Joins the gestures block led by `app.phoneLandscapeSliderType`; only
      // the leader carries groupHeaderKey.
      platforms: ['android'],
      sortOrder: 42,
    ),
    // Playback-speed picker shape (more menu / control-bar RATE). Dual-wheel
    // is the metadata-era default; `list` restores the legacy flat 0.1 menu.
    // Dual-platform: the more menu serves phones/portrait and the control-bar
    // RATE button serves tablet/desktop, so both need the new picker.
    SettingDef(
      key: 'speed.rateMode',
      section: SettingsSection.play,
      valueType: SettingValueType.enumeration,
      defaultValue: 'dualWheel',
      enumValues: ['dualWheel', 'list'],
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'speed_rate_mode',
      titleKey: 'speed_rate_mode',
      subtitleKey: 'speed_rate_mode_desc',
      iconKey: 'speed_rate_mode',
      // Same gestures block as `speed.gestureMode`; only the block leader
      // (`app.phoneLandscapeSliderType`) carries groupHeaderKey.
      platforms: ['android', 'windows', 'linux', 'macos'],
      sortOrder: 43,
    ),
  ];
}
