import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/enum/tag_system_kind.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v25: system-reserved tag roles on `video_tags`.
///
/// Adds the nullable `system_kind` column (NULL = plain user tag, non-null =
/// system-owned role: 临时标记 / 永久收藏 / 副音备选). Existing databases
/// ADOPT matching-name rows to their roles once — row CREATION is deliberately
/// NOT part of the migration: 副音 is a meta-only feature, so reserved rows
/// only appear once the metadata gate is on (startup `ensureReservedTags()`
/// creates the missing roles idempotently). Creating them here would mutate
/// legacy (non-meta) installs and break schema-preservation tests that assert
/// the exact row set after an upgrade.
///
/// Name matching is a one-time, pragmatic legacy adoption — a user tag that
/// happened to carry a canonical name becomes reserved too. From v25 on the
/// role (kind), never the display name, is the identity.
///
/// Re-entrant: the column is added only when missing (PRAGMA table_info).
/// Fresh installs create the column via onCreate; the rows come from
/// `TagPlayRepository.ensureReservedTags()` at startup.
class MigrationV25 {
  final AppDatabase db;

  MigrationV25(this.db);

  Future<void> run(Migrator m) async {
    final columns = await _columnNames('video_tags');
    if (columns == null) {
      // Table absent (feature never enabled / legacy era) — nothing to do;
      // a later meta-era startup still runs ensureReservedTags() after the
      // table exists.
      return;
    }
    if (!columns.contains('system_kind')) {
      _log.i('MigrationV25: adding video_tags.system_kind');
      try {
        await m.addColumn(db.videoTagsTable, db.videoTagsTable.systemKind);
      } catch (e) {
        _log.w('MigrationV25: add column failed: $e');
        return;
      }
    }
    await _adoptLegacyRows();
  }

  /// One-time adoption: claim plain user rows whose name matches a canonical
  /// reserved name. The canonical description/policies are NOT rewritten here
  /// (they predate v25); startup ensureReservedTags() normalizes adopted rows.
  Future<void> _adoptLegacyRows() async {
    for (final role in TagSystemKind.values) {
      await db.customStatement(
        "UPDATE video_tags SET system_kind = ? "
        "WHERE system_kind IS NULL AND name = ?",
        <Object?>[role.name, role.canonicalName],
      );
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
