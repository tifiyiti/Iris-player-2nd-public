import 'package:drift/drift.dart';

/// Manual picks added to a [ScenariosTable] (C4). Explicit items are NOT
/// sources. A single user multi-select operation = one batchId group of rows,
/// ordered by addOrder, with uiSortKey capturing the UI sort value at add time.
class ScenarioExplicitItemsTable extends Table {
  @override
  String get tableName => 'scenario_explicit_items';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get scenarioId => text()();

  /// Groups one user operation (multi-select / trailing add-to-queue).
  TextColumn get batchId => text().nullable()();

  TextColumn get storageId => text()();

  TextColumn get path => text()();

  /// Future: mediaId-based identity. Prefer when present (A8).
  IntColumn get mediaId => integer().nullable()();

  /// Add-time timeline within the batch.
  IntColumn get addOrder => integer().withDefault(const Constant(0))();

  /// UI sort value at add time (replay as-added order).
  TextColumn get uiSortKey => text().nullable()();

  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => ['UNIQUE(scenario_id, storage_id, path)'];
}
