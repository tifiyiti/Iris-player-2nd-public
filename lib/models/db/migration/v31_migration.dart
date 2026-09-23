import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v31: canonical **data scope** for the media library.
///
/// Adds `storages_table.data_scope_id` (NULL = independent; the entry's own id
/// is its scope) and re-keys the media-library bookkeeping tables from
/// `(storage_id, path)` to `(data_scope_id, path)`:
///   * `media_nodes`   — UNIQUE moved to `(data_scope_id, path)`
///   * `scan_queue`    — UNIQUE moved to `(data_scope_id, path)`
///   * `scan_states`   — PRIMARY KEY moved to `(data_scope_id, path)`
///
/// `storage_id` columns are intentionally KEPT (the entry that wrote the row,
/// used for playback/auth resolution). All rows are back-filled with
/// `data_scope_id = storage_id`, i.e. every existing entry keeps its own
/// library — behaviour is unchanged until entries are explicitly linked.
///
/// The three keyed tables require a constraint change, so they are rebuilt
/// (rename → create → copy → drop, the v4 pattern). The copy intersects the
/// generated and legacy column sets, so it tolerates column drift and is
/// re-entrant (a table already carrying `data_scope_id` is skipped).
class MigrationV31 {
  final AppDatabase db;
  MigrationV31(this.db);

  Future<void> run(Migrator m) async {
    await _addStoragesColumn(m);

    await _rebuildWithScope(
      m,
      table: 'media_nodes',
      tableInfo: db.mediaNodesTable,
    );
    await _rebuildWithScope(
      m,
      table: 'scan_queue',
      tableInfo: db.scanQueueTable,
    );
    await _rebuildWithScope(
      m,
      table: 'scan_states',
      tableInfo: db.scanStatesTable,
    );

    await createScopeIndexes(db);
  }

  Future<void> _addStoragesColumn(Migrator m) async {
    final cols = await _columnNames('storages_table');
    if (cols == null) return; // table absent on a broken DB — nothing to do
    if (cols.contains('data_scope_id')) return;
    _log.i('MigrationV31: adding storages_table.data_scope_id');
    try {
      await m.addColumn(db.storagesTable, db.storagesTable.dataScopeId);
    } catch (e) {
      _log.w('MigrationV31: add storages_table.data_scope_id failed: $e');
    }
  }

  /// Rebuilds [table] so its keyed constraint lives on `data_scope_id`, copying
  /// every shared column and mapping `storage_id` → `data_scope_id`.
  ///
  /// If the column already exists it is NOT rebuilt: an in-chain rebuild
  /// migration (v9/v15/v23) creates the table from the latest schema, so the
  /// constraint is already scope-keyed but every row still carries a NULL
  /// scope. In that case only the back-fill runs.
  Future<void> _rebuildWithScope(
    Migrator m, {
    required String table,
    required TableInfo tableInfo,
  }) async {
    final cols = await _columnNames(table);
    if (cols == null) return; // feature table never created — nothing to do

    if (!cols.contains('data_scope_id')) {
      final tmp = '_old_$table';
      _log.i('MigrationV31: rebuilding $table keyed by data_scope_id');
      await db.customStatement('DROP TABLE IF EXISTS $tmp');
      await db.customStatement('ALTER TABLE $table RENAME TO $tmp');
      await m.createTable(tableInfo);

      final newCols = await _columnNames(table) ?? <String>{};
      // Intersect: everything the old table has that the new table also
      // declares, excluding the brand-new scope column (filled from storage_id).
      final oldCols = await _columnNames(tmp) ?? <String>{};
      final shared = <String>[
        for (final c in newCols)
          if (c != 'data_scope_id' && oldCols.contains(c)) c,
      ];
      if (!shared.contains('storage_id')) {
        _log.w('MigrationV31: $tmp lacks storage_id; dropping legacy table');
        await db.customStatement('DROP TABLE $tmp');
        return;
      }

      final String targetList = [...shared, 'data_scope_id'].join(', ');
      final String selectList =
          [...shared, 'storage_id AS data_scope_id'].join(', ');
      await db.customStatement(
        'INSERT INTO $table ($targetList) SELECT $selectList FROM $tmp',
      );
      await db.customStatement('DROP TABLE $tmp');
      return;
    }

    // Column present: still back-fill legacy NULL scopes (see doc above).
    if (cols.contains('storage_id')) {
      await db.customStatement(
        'UPDATE $table SET data_scope_id = storage_id '
        'WHERE data_scope_id IS NULL',
      );
    }
  }

  /// Scope-keyed indexes mirroring the v4 set. The unique index on
  /// `(data_scope_id, path)` is created implicitly by the table constraint, so
  /// only the secondary lookup paths are added here. Idempotent (`IF NOT
  /// EXISTS`), safe to call from `onCreate` too.
  static Future<void> createScopeIndexes(AppDatabase db) async {
    final statements = <String>[
      'CREATE INDEX IF NOT EXISTS idx_scope_parent ON media_nodes(data_scope_id, parent_path);',
      'CREATE INDEX IF NOT EXISTS idx_scope_parent_name ON media_nodes(data_scope_id, parent_path, name);',
      'CREATE INDEX IF NOT EXISTS idx_scope_parent_name_sort ON media_nodes(data_scope_id, parent_path, normalized_name);',
      'CREATE INDEX IF NOT EXISTS idx_scope_depth ON media_nodes(data_scope_id, path_depth);',
      'CREATE INDEX IF NOT EXISTS idx_scan_queue_scope_status ON scan_queue(data_scope_id, status, depth);',
    ];
    for (final stmt in statements) {
      try {
        await db.customStatement(stmt);
      } catch (e) {
        _log.w('MigrationV31: index failed: $e');
      }
    }
  }

  /// Best-effort repair for rows that somehow carry a NULL scope (the v31
  /// migration back-fills, and every writer sets the column, so this is a
  /// safety net for a regression or a pre-v31 in-chain rebuild). Idempotent;
  /// a NULL scope is invisible to every scope-keyed query *and* bypasses the
  /// `UNIQUE(data_scope_id, path)` constraint (SQLite treats NULLs as
  /// distinct), so healing it keeps the shared-library invariant intact.
  static Future<void> backfillNullScopes(AppDatabase db) async {
    for (final table in const ['media_nodes', 'scan_queue', 'scan_states']) {
      try {
        await db.customStatement(
          'UPDATE $table SET data_scope_id = storage_id '
          'WHERE data_scope_id IS NULL',
        );
      } catch (e) {
        _log.w('MigrationV31: null-scope backfill on $table failed: $e');
      }
    }
  }

  Future<Set<String>?> _columnNames(String table) async {
    final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: <Variable>[Variable.withString(table)],
    ).get();
    if (tables.isEmpty) return null;
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }
}
