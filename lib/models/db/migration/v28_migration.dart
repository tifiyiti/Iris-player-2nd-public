import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v28: 副音 candidate-source rules table.
///
/// Creates `bg_source_rules` when missing (fresh installs get it via
/// onCreate). Re-entrant. Existing rules that used to live in the
/// `BackgroundPlaybackState.sources` KV JSON are imported separately by
/// `BgSourceBootstrap` (AUX-marker guarded) — the migration itself only
/// ensures the table exists.
class MigrationV28 {
  final AppDatabase db;

  MigrationV28(this.db);

  Future<void> run(Migrator m) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: <Variable>[Variable.withString('bg_source_rules')],
    ).get();
    if (rows.isEmpty) {
      _log.i('MigrationV28: creating bg_source_rules');
      await m.createTable(db.bgSourceRulesTable);
    }
  }
}
