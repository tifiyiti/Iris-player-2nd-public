import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v14: per-tag jump-back (resume) window.
///
/// Adds ONE nullable column `video_tags.resume_window_minutes`:
/// NULL = always attempt to resume the last played video of the tag view
/// (permanent), a positive value bounds the resume attempt to that window.
/// The former global resume-window setting is superseded by this per-tag
/// property.
///
/// Re-entrant: the column is only added when missing (guarded via
/// PRAGMA table_info).
class MigrationV14 {
  final AppDatabase db;

  MigrationV14(this.db);

  static const _column = 'resume_window_minutes';

  Future<void> run(Migrator m) async {
    final columns = await _columnNames('video_tags');
    if (columns == null) {
      // Table itself absent (fresh installs create it with the column via
      // onCreate); nothing to upgrade here.
      return;
    }
    if (columns.contains(_column)) return;

    _log.i('MigrationV14: adding video_tags.$_column');
    await db.customStatement(
      'ALTER TABLE video_tags ADD COLUMN $_column INTEGER NULL',
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
