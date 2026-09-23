import 'package:drift/drift.dart';

/// Sparse user overrides: a row exists only for settings the user changed.
///
/// Unchanged settings render from `setting_defs.defaultValue`. This split lets
/// shipping-side default changes reach everyone who never customized, while
/// explicit choices survive upgrades.
class SettingValuesTable extends Table {
  @override
  String get tableName => 'setting_values';

  /// References setting_defs.key.
  TextColumn get key => text()();

  /// ValueCodec-encoded value (type family declared by the def).
  TextColumn get value => text()();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}
