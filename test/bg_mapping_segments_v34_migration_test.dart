import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/v34_migration.dart';

import 'helpers/sqlite3_loader.dart';

/// Drift's generated names for the 副音 mapping tables.
const String _kSegments = 'bg_mapping_segments_table';
const String _kMappings = 'bg_mappings_table';

Future<Set<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void main() {
  ensureSqlite3Loaded();

  group('bg_mapping_segments v34 activation migration', () {
    test('fresh install already has the activation columns', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final columns = await _columns(db, _kSegments);
      expect(columns, contains('is_active'));
      expect(columns, contains('active_seq'));
    });

    test('adds the columns and backfills active_seq from the row id', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Simulate a pre-v34 database: no activation columns.
      await db.customStatement('ALTER TABLE $_kSegments DROP COLUMN is_active');
      await db.customStatement('ALTER TABLE $_kSegments DROP COLUMN active_seq');
      expect(await _columns(db, _kSegments), isNot(contains('is_active')));

      await db.customStatement(
        "INSERT INTO $_kMappings (id, storage_id, path) "
        "VALUES (1, 'local', 'Anime/Ep01.mp4')",
      );
      await db.customStatement(
        "INSERT INTO $_kSegments (id, mapping_id, action, fg_start_ms, fg_end_ms) "
        "VALUES (7, 1, 'playMedia', 0, 1000)",
      );

      await MigrationV34(db).run(db.createMigrator());

      final columns = await _columns(db, _kSegments);
      expect(columns, contains('is_active'));
      expect(columns, contains('active_seq'));

      final row = await db
          .customSelect('SELECT is_active, active_seq FROM $_kSegments')
          .getSingle();
      expect(row.read<int>('is_active'), 1);
      // Backfilled from the id so the previous relative order survives.
      expect(row.read<int>('active_seq'), 7);
    });

    test('is re-entrant', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.customStatement('ALTER TABLE $_kSegments DROP COLUMN is_active');
      await db.customStatement('ALTER TABLE $_kSegments DROP COLUMN active_seq');

      await MigrationV34(db).run(db.createMigrator());
      await MigrationV34(db).run(db.createMigrator());

      final columns = await _columns(db, _kSegments);
      expect(columns.where((c) => c == 'is_active'), hasLength(1));
      expect(columns.where((c) => c == 'active_seq'), hasLength(1));
    });
  });
}
