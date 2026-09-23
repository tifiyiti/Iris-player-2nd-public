import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

/// Media-library scan preferences contribution.
///
/// Only genuine PREFERENCES belong here. The rest of RecursiveScanState is
/// runtime progress data owned by the scan service and is deliberately not
/// representable in settings metadata.
abstract final class ScanSettingsContribution {
  static const String groupHeaderKey = 'group_scan';

  static const List<SettingDef> defs = <SettingDef>[
    SettingDef(
      key: 'scan.autoCloseDelay',
      section: SettingsSection.general,
      valueType: SettingValueType.double,
      defaultValue: '2.5', // == RecursiveScanState.autoCloseDelay @Default
      writable: true,
      clampMin: 0,
      clampMax: 15, // == RecursiveScanStore.updateAutoCloseDelay clamp
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'scan_auto_close',
      titleKey: 'scan_auto_close',
      subtitleKey: 'scan_auto_close_desc',
      iconKey: 'scan_auto_close',
      groupHeaderKey: groupHeaderKey,
      sortOrder: 120,
    ),
    SettingDef(
      key: 'scan.rescanReminderMinutes',
      section: SettingsSection.general,
      valueType: SettingValueType.int,
      defaultValue: '120', // == ScanRescanReminder.defaultMinutes
      writable: true,
      clampMin: 0,
      clampMax: 24 * 60, // up to 24h
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'scan_rescan_reminder',
      titleKey: 'scan_rescan_reminder',
      subtitleKey: 'scan_rescan_reminder_desc',
      iconKey: 'scan_auto_close',
      sortOrder: 121,
    ),
  ];
}
