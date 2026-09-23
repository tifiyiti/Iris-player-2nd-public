import 'package:drift/drift.dart';

class ScanStatesTable extends Table {
  @override
  String get tableName => 'scan_states';

  TextColumn get storageId => text()();

  /// Canonical data scope (v31) — see `StoragesTable.dataScopeId`. Nullable
  /// only for pre-v31 rebuilds; writers set it and v31 back-fills legacy rows.
  TextColumn get dataScopeId => text().nullable()();

  TextColumn get path => text()();

  IntColumn get status => integer()();
  // 0: not scan
  // /1: scanning
  // /2: scan done
  DateTimeColumn get lastScannedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {dataScopeId, path};
}
