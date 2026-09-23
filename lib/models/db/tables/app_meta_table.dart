import 'package:drift/drift.dart';

/// Generic key/value store for small, cross-restart bookkeeping that is NOT a
/// user setting — e.g. the derived queue index's content revision and the
/// per-scenario signature of the persisted generation.
///
/// Kept deliberately tiny and untyped-string: readers parse what they wrote.
class AppMetaTable extends Table {
  @override
  String get tableName => 'app_meta';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
