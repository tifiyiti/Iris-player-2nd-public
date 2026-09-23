import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v23: persisted SAF document URI on `media_nodes`.
///
/// Adds a nullable `uri` column holding the real `content://` document URI
/// for Android SAF rows (ordinary filesystem rows keep NULL and fall back to
/// `playableUri(path)` at read time). Written at browse/scan time from the
/// `FileItem.uri` that SAF listing returns; never rebuilt at runtime.
///
/// Also repairs legacy SAF rows whose `path`/`parent_path` were stored with
/// the `content://` scheme collapsed to `content:/` by the old
/// `canonicalDbPath` (`//` -> `/`), which made every read-side URI rebuild
/// produce a broken `/content:/...` form. Only `content:`-prefixed rows are
/// touched — local `/storage/...` and Windows drive/UNC paths are untouched.
///
/// Re-entrant: the column is added only when missing (PRAGMA table_info), and
/// the path repair is guarded so it never rewrites an already-correct row.
class MigrationV23 {
  final AppDatabase db;

  MigrationV23(this.db);

  Future<void> run(Migrator m) async {
    final columns = await _columnNames('media_nodes');
    if (columns == null) {
      // Fresh installs create the table with the column via onCreate.
      return;
    }

    if (!columns.contains('uri')) {
      _log.i('MigrationV23: adding media_nodes.uri');
      await db.customStatement(
        'ALTER TABLE media_nodes ADD COLUMN uri TEXT NULL',
      );
    }

    await _repairCollapsedContentPrefix();
  }

  /// Rewrites legacy `content:/authority/tree/...` paths (old canonical form
  /// after `//` collapse) back to the real `content://authority/tree/...`
  /// scheme prefix so `safSegmentsOf` can split them reversibly again.
  ///
  /// Also removes the junk directory chain the pre-fix recursive scan wrote
  /// for a SAF root (`content:`, `content:/authority`, ... rows from splitting
  /// the URI on '/') — those are unreachable garbage.
  Future<void> _repairCollapsedContentPrefix() async {
    // content:/X -> content://X  (repair collapsed scheme; 'content:/' is 9
    // chars, so substr(path, 10) keeps everything after the scheme). Guard
    // `path NOT LIKE 'content://%'` so a row that already carries the correct
    // scheme is never rewritten.
    await db.customStatement(
      "UPDATE media_nodes SET path = 'content://' || substr(path, 10), "
      "parent_path = CASE WHEN parent_path LIKE 'content:/%' "
      "THEN 'content://' || substr(parent_path, 10) ELSE parent_path END "
      "WHERE path LIKE 'content:/%' "
      "AND substr(path, 1, 9) = 'content:/'",
    );

    // Junk `content:`/`content:/` directory chains created by the pre-fix DFS
    // (scheme split into path segments). `content://` rows are the real ones.
    await db.customStatement(
      "DELETE FROM media_nodes WHERE path LIKE 'content:%' "
      "AND path NOT LIKE 'content://%'",
    );
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
