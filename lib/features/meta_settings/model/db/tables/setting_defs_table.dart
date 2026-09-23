import 'package:drift/drift.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';

/// Metadata registry: one row per setting — what a setting IS.
///
/// Authority lives in the typed Dart contribution lists
/// (`features/meta_settings/contributions/`); this table is the materialized,
/// queryable mirror seeded at startup. User choices live in `setting_values`
/// (sparse); feature visibility lives in `feature_flags`.
class SettingDefsTable extends Table {
  @override
  String get tableName => 'setting_defs';

  /// Dotted namespace key, e.g. 'app.themeMode'.
  TextColumn get key => text()();

  TextColumn get section => textEnum<SettingsSection>()();

  TextColumn get valueType => textEnum<SettingValueType>()();

  /// Type-encoded default (see ValueCodec). NULL means "no default declared";
  /// readers fall back to the typed facade's own default.
  TextColumn get defaultValue => text().nullable()();

  /// JSON array of enum value NAMES; required when valueType == enumeration.
  TextColumn get enumValues => text().nullable()();

  TextColumn get widgetKind => textEnum<SettingWidgetKind>()();

  /// Registry key of the hand-written editor; required for widgetKind ==
  /// custom, null otherwise.
  TextColumn get editorKey => text().nullable()();

  /// ARB key reused from the existing catalog (no new l10n keys this phase).
  TextColumn get titleKey => text()();

  /// Optional ARB key for the secondary line.
  TextColumn get subtitleKey => text().nullable()();

  /// JSON array of platforms ('android'|'windows'|'linux'|'macos'|'ios');
  /// NULL/empty = every platform.
  TextColumn get platforms => text().nullable()();

  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {key};
}
