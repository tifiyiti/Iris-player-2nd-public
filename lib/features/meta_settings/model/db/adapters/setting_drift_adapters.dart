import 'package:drift/drift.dart';
import 'package:iris/features/meta_settings/data/value_codec.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/feature_flag.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';
import 'package:iris/models/db/app_database.dart';

/// Drift ↔ freezed mappers for the metadata settings tables.
///
/// Follows the house adapter pattern (`storage_drift_adapter.dart`):
/// static `fromDb` + instance `toCompanion`, all conversion centralized here.
extension SettingDefDriftAdapter on SettingDef {
  static SettingDef fromDb(SettingDefsTableData row) => SettingDef(
        key: row.key,
        section: row.section,
        valueType: row.valueType,
        defaultValue: row.defaultValue,
        enumValues: ValueCodec.decodeStringList(row.enumValues),
        widgetKind: row.widgetKind,
        editorKey: row.editorKey,
        titleKey: row.titleKey,
        subtitleKey: row.subtitleKey,
        platforms: ValueCodec.decodeStringList(row.platforms),
        sortOrder: row.sortOrder,
      );

  SettingDefsTableCompanion toCompanion() => SettingDefsTableCompanion(
        key: Value(key),
        section: Value(section),
        valueType: Value(valueType),
        defaultValue: Value(defaultValue),
        enumValues: Value(enumValues.isEmpty
            ? null
            : ValueCodec.encode(SettingValueType.json, enumValues)),
        widgetKind: Value(widgetKind),
        editorKey: Value(editorKey),
        titleKey: Value(titleKey),
        subtitleKey: Value(subtitleKey),
        platforms: Value(platforms.isEmpty
            ? null
            : ValueCodec.encode(SettingValueType.json, platforms)),
        sortOrder: Value(sortOrder),
      );
}

extension FeatureFlagDriftAdapter on FeatureFlag {
  static FeatureFlag fromDb(FeatureFlagsTableData row) => FeatureFlag(
        key: row.key,
        stage: row.stage,
        defaultEnabled: row.defaultEnabled,
        userOverride: row.userOverride,
      );

  FeatureFlagsTableCompanion toCompanion() => FeatureFlagsTableCompanion(
        key: Value(key),
        stage: Value(stage),
        defaultEnabled: Value(defaultEnabled),
        userOverride: Value(userOverride),
      );
}
