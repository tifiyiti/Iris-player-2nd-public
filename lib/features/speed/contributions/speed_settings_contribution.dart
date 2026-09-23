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
  ];
}
