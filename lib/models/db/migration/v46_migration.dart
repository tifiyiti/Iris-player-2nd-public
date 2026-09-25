import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v46: `media_nodes.modified_at` moves from epoch SECONDS to epoch
/// MILLISECONDS.
///
/// Drift's default `dateTime()` mapping truncates to whole seconds, so files
/// written within the same second compared equal and the queue fell back to a
/// name tie-break instead of their real order. The column is re-typed through
/// [EpochMillisConverter]; its SQLite affinity stays INTEGER, so only the stored
/// values have to be rescaled — no table rebuild.
///
/// The `< 100000000000` bound makes the step re-entrant: epoch seconds are
/// ~1.7e9 today while epoch milliseconds are ~1.7e12, so a second run finds
/// nothing to rescale instead of multiplying by 1000 again.
///
/// It also clears the persisted shared orders (`media_orders`). Those blobs
/// encode the OLD ORDER BY (no deterministic tail, NULLs-first on one query
/// path, second-precision timestamps) and their keys now carry a new format
/// version, so they can never be read again — dropping them keeps a large
/// library from carrying multi-megabyte orphans.
class MigrationV46 {
  final AppDatabase db;

  MigrationV46(this.db);

  /// Epoch milliseconds for any date after 1973 exceed 1e11; epoch seconds never
  /// do. Values at or above the bound are therefore already milliseconds.
  static const int _millisFrom = 100000000000;

  Future<void> run(Migrator m) async {
    try {
      // A hand-built / partial legacy database can legitimately lack a feature
      // table — the same tolerance the index-creation steps get. A missing
      // `media_nodes` simply has nothing to rescale.
      if (await _tableExists('media_nodes')) {
        await db.customStatement(
          'UPDATE media_nodes SET modified_at = modified_at * 1000 '
          'WHERE modified_at IS NOT NULL AND modified_at < $_millisFrom',
        );
      }

      if (await _tableExists('media_orders')) {
        await db.customStatement('DELETE FROM media_orders');
      }
    } catch (e) {
      // Do NOT swallow: a half-scaled column would order the queue by a mix of
      // seconds and milliseconds. Rethrowing aborts the open before drift stamps
      // the new version, so the database stays on 45 and the next open retries.
      _log.e('MigrationV46: rescaling modified_at to milliseconds failed', e);
      rethrow;
    }
  }

  Future<bool> _tableExists(String name) async {
    final row = await db.customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(name)],
    ).getSingleOrNull();
    return row != null;
  }
}
