import 'package:drift/drift.dart';
import 'package:iris/features/meta_settings/model/db/tables/feature_flags_table.dart';
import 'package:iris/features/meta_settings/model/db/tables/setting_defs_table.dart';
import 'package:iris/features/meta_settings/model/db/tables/setting_values_table.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

part 'settings_dao.g.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

@DriftAccessor(
  tables: [SettingDefsTable, SettingValuesTable, FeatureFlagsTable],
)
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  // ── defs ──

  Future<List<SettingDefsTableData>> getAllDefs() {
    return select(settingDefsTable).get();
  }

  /// Upserts a whole contribution batch in one transaction (seed path).
  Future<void> upsertDefs(List<SettingDefsTableCompanion> entries) {
    return batch((b) => b.insertAllOnConflictUpdate(settingDefsTable, entries));
  }

  // ── values ──

  Future<List<SettingValuesTableData>> getAllValues() {
    return select(settingValuesTable).get();
  }

  Future<void> upsertValue(SettingValuesTableCompanion entry) {
    return into(settingValuesTable).insertOnConflictUpdate(entry);
  }

  /// Upserts a handful of changed rows in one batch.
  ///
  /// The metadata write path diffs the new snapshot against the last persisted
  /// one, so a single toggle writes ONE row instead of delete+reinserting the
  /// whole `app.*` set (which ran on the UI isolate on every keystroke/tap).
  Future<void> upsertValues(List<SettingValuesTableCompanion> entries) {
    if (entries.isEmpty) return Future<void>.value();
    return batch(
        (b) => b.insertAllOnConflictUpdate(settingValuesTable, entries));
  }

  /// Atomically replaces the `app.*` snapshot rows (state persist path).
  ///
  /// Namespace-scoped BY DESIGN: auxiliary domains (`scan.*`) are single-key
  /// upserts owned by their own bridges and MUST survive every snapshot
  /// rewrite — a whole-table wipe would silently demote the DB from being
  /// authoritative for those preferences.
  Future<void> replaceAllValues(List<SettingValuesTableCompanion> entries) {
    return transaction(() async {
      if (entries.isEmpty) {
        // Tripwire: an empty snapshot wipes every app.* override. Legitimate
        // only when the state genuinely has none; anything else means the
        // store persisted its default state over real settings.
        final rows = await (select(settingValuesTable)
              ..where((t) => t.key.like('app.%')))
            .get();
        if (rows.isNotEmpty) {
          _log.w('setting_values: replaceAllValues got an EMPTY snapshot but '
              '${rows.length} app.* row(s) exist — clearing them all');
        }
      }
      final wipe = delete(settingValuesTable)
        ..where((t) => t.key.like('app.%'));
      await wipe.go();
      for (final e in entries) {
        await into(settingValuesTable).insert(e);
      }
    });
  }

  /// Drops only the `app.*` snapshot rows (gate-off cleanup).
  ///
  /// The blob becomes authoritative for those fields in legacy mode, and
  /// [replaceAllValues] can rebuild them on gate-ON, so they are the safe
  /// rollback surface. Auxiliary-only domains (`dialring.`, `keybind.`,
  /// `tagplay.`, `identity.`, `bg.`, …) are JsonKey-excluded from the blob and
  /// have this table as their ONLY persistence route — wiping them here would
  /// destroy user data that gate-ON can never restore. Scope matters.
  Future<void> clearAppValues() {
    return (delete(settingValuesTable)..where((t) => t.key.like('app.%'))).go();
  }

  /// Drops EVERY override row, including auxiliary-only domains.
  ///
  /// Test/migration helper ONLY — never use this for the gate transition (it
  /// would permanently destroy AUX-only data). See [clearAppValues].
  Future<void> clearValues() => delete(settingValuesTable).go();

  Future<void> upsertFlags(List<FeatureFlagsTableCompanion> entries) {
    return batch(
        (b) => b.insertAllOnConflictUpdate(featureFlagsTable, entries));
  }

  /// True when no user override exists yet — the blob importer's idempotence
  /// guard: import only into an empty value table.
  Future<bool> valuesEmpty() async {
    final countExp = settingValuesTable.key.count();
    final query = selectOnly(settingValuesTable)..addColumns([countExp]);
    final row = await query.getSingle();
    return (row.read(countExp) ?? 0) == 0;
  }

  Future<String?> getValue(String key) async {
    final query = select(settingValuesTable)..where((t) => t.key.equals(key));
    final row = await query.getSingleOrNull();
    return row?.value;
  }

  // ── flags ──

  Future<List<FeatureFlagsTableData>> getAllFlags() {
    return select(featureFlagsTable).get();
  }

  Future<FeatureFlagsTableData?> getFlag(String key) {
    final query = select(featureFlagsTable)..where((t) => t.key.equals(key));
    return query.getSingleOrNull();
  }

  Future<void> upsertFlag(FeatureFlagsTableCompanion entry) {
    return into(featureFlagsTable).insertOnConflictUpdate(entry);
  }
}
