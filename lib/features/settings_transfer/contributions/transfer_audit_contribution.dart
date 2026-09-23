import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

abstract final class TransferAuditContribution {
  static const List<SettingDef> defs = [
    SettingDef(
      key: 'security.transferLog',
      section: SettingsSection.general,
      valueType: SettingValueType.json,
      widgetKind: SettingWidgetKind.custom,
      editorKey: 'password_transfer_log',
      titleKey: 'transfer_audit_title',
      subtitleKey: 'transfer_audit_log_desc',
      // Data block tail (led by `data.exportEntry`): the audit log belongs
      // with import/export, not dangling under the Advanced group.
      sortOrder: 26,
    ),
  ];
}
