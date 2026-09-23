import 'package:drift/drift.dart';

/// Persistent BFS queue for extremely large recursive scans (50w scale).
///
/// Each row is one directory discovered but not yet fully scanned.
/// `status = pending|scanning|done|error`. The queue survives process death,
/// so a killed scan can resume by re-reading `pending` rows.
///
/// This replaces the in-memory `depthPaths` JSON (which OOMs at 50w).
/// `RecursiveScanState.depthPaths` remains as a memory view for UI/compat
/// but is lazily hydrated from this table for resume.
class ScanQueueTable extends Table {
  @override
  String get tableName => 'scan_queue';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get storageId => text()();

  /// Canonical data scope (v31) — see `StoragesTable.dataScopeId`. Rows of two
  /// entries linked into one scope share a single queue so the same tree is
  /// never scanned twice. Nullable only for pre-v31 rebuilds; writers set it.
  TextColumn get dataScopeId => text().nullable()();

  /// Canonical DB path (no leading slash, e.g. `a/b/c`). Root is "".
  TextColumn get path => text()();

  IntColumn get depth => integer()();

  /// pending | scanning | done | error
  TextColumn get status => text().withDefault(const Constant('pending'))();

  DateTimeColumn get discoveredAt =>
      dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
        'UNIQUE(data_scope_id, path)',
      ];
}
