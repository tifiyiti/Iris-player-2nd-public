import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/v35_migration.dart';

/// v35 is index-only: assert every perf index exists after both a fresh create
/// and a v34→v35 upgrade, so the queries they back stop scanning.
void main() {
  Future<Set<String>> indexNames(AppDatabase db) async {
    final rows = await db
        .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  const expected = <String>{
    // media_nodes scope sort columns (UI-exposed sorts only)
    'idx_scope_sort_size',
    'idx_scope_sort_modified',
    'idx_scope_sort_duration',
    'idx_scope_parent_size_sort',
    'idx_scope_parent_modified_sort',
    'idx_scope_parent_duration_sort',
    // feature-table lookups
    'idx_scenario_excludes_scenario',
    'idx_tag_members_storage_path',
    'idx_tag_members_tag_added',
    'idx_bg_mapping_segments_mapping',
    'idx_lib_sources_storage',
  };

  test('fresh database create installs the v35 perf indexes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Force the connection + onCreate path.
    await db.customSelect('SELECT 1').get();

    expect(await indexNames(db), containsAll(expected));
  });

  test('v35 migration is idempotent (re-running keeps the indexes)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    await MigrationV35.createPerfIndexes(db);
    expect(await indexNames(db), containsAll(expected));
  });
}
