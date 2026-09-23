import 'package:iris/features/meta_settings/model/db/adapters/setting_drift_adapters.dart';
import 'package:iris/features/meta_settings/model/db/dao/settings_dao.dart';
import 'package:iris/features/meta_settings/model/feature_flag.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';
import 'package:iris/models/db/app_database.dart'
    show SettingValuesTableCompanion;

/// Repository over the metadata settings tables.
///
/// Thin mapping layer following the house pattern (constructor-injected DAO,
/// rows ↔ domain models). Callers speak in terms of [SettingDef]/[FeatureFlag]
/// and raw encoded value strings; encoding itself is ValueCodec's job.
class SettingsDbRepository {
  final SettingsDao dao;
  SettingsDbRepository(this.dao);

  // ── defs ──

  Future<List<SettingDef>> getDefs() async {
    final rows = await dao.getAllDefs();
    return rows.map(SettingDefDriftAdapter.fromDb).toList();
  }

  /// Seeds/upserts a contribution batch (startup mirror sync).
  Future<void> seedDefs(List<SettingDef> defs) {
    return dao.upsertDefs(defs.map((d) => d.toCompanion()).toList());
  }

  // ── values ──

  /// Loads every stored override as key → encoded value.
  Future<Map<String, String>> loadRawValues() async {
    final rows = await dao.getAllValues();
    return {for (final r in rows) r.key: r.value};
  }

  Future<void> saveRawValue(String key, String encoded) {
    return dao.upsertValue(
      SettingValuesTableCompanion.insert(key: key, value: encoded),
    );
  }

  Future<bool> hasAnyValue() async => !await dao.valuesEmpty();

  /// Upserts a small set of changed rows (incremental metadata write path).
  Future<void> upsertRawValues(List<SettingValuesTableCompanion> entries) =>
      dao.upsertValues(entries);

  /// Atomically replaces all `app.*` snapshot overrides; auxiliary-domain
  /// rows (e.g. `scan.*`) are preserved. Blob-import path relies on this too:
  /// the legacy blob encodes only AppState fields, i.e. exactly that dialect.
  Future<void> replaceAllRawEntries(
          List<SettingValuesTableCompanion> entries) =>
      dao.replaceAllValues(entries);

  /// Drops only the `app.*` snapshot overrides. Auxiliary-only domains have
  /// the DB as their only persistence route, so they MUST survive a gate-OFF
  /// rollback (they are restored to the live state again on gate-ON).
  Future<void> clearAppValues() => dao.clearAppValues();

  /// Drops every override (test/migration helper; NOT the gate-off path).
  Future<void> clearValues() => dao.clearValues();

  // ── flags ──

  Future<FeatureFlag?> getFlag(String key) async {
    final row = await dao.getFlag(key);
    return row == null ? null : FeatureFlagDriftAdapter.fromDb(row);
  }

  /// Seeds/upserts the shipped flag rows (startup mirror sync).
  Future<void> seedFlags(List<FeatureFlag> flags) {
    return dao.upsertFlags(flags.map((f) => f.toCompanion()).toList());
  }

  Future<void> saveFlag(FeatureFlag flag) {
    return dao.upsertFlag(flag.toCompanion());
  }
}
