import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/v30_migration.dart';

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

  group('bg_mapping_segments v30 repair migration', () {
    test('fresh install already has the v27 columns', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final columns = await _columns(db, _kSegments);
      expect(columns, contains('fg_percent'));
      expect(columns, contains('bg_percent'));
    });

    test('re-adds the columns to a database stamped past the broken v27',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Simulate a database that upgraded across the broken v27: the columns
      // are missing even though the schema version already says otherwise.
      await db.customStatement('ALTER TABLE $_kSegments DROP COLUMN fg_percent');
      await db.customStatement('ALTER TABLE $_kSegments DROP COLUMN bg_percent');
      expect(await _columns(db, _kSegments), isNot(contains('fg_percent')));

      await MigrationV30(db).run(db.createMigrator());

      final columns = await _columns(db, _kSegments);
      expect(columns, contains('fg_percent'));
      expect(columns, contains('bg_percent'));
    });

    test('is re-entrant and leaves a populated timeline usable', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.customStatement('ALTER TABLE $_kSegments DROP COLUMN fg_percent');
      await db.customStatement('ALTER TABLE $_kSegments DROP COLUMN bg_percent');

      await MigrationV30(db).run(db.createMigrator());
      await MigrationV30(db).run(db.createMigrator());

      final columns = await _columns(db, _kSegments);
      expect(columns.where((c) => c == 'fg_percent'), hasLength(1));
      expect(columns.where((c) => c == 'bg_percent'), hasLength(1));

      // The exact statement that used to throw
      // "no column named fg_percent" must now succeed.
      await db.customStatement(
        "INSERT INTO $_kMappings (id, storage_id, path) "
        "VALUES (1, 'local', 'Anime/Ep01.mp4')",
      );
      await db.customStatement(
        "INSERT INTO $_kSegments "
        "(mapping_id, action, fg_start_ms, fg_end_ms, fg_percent, bg_percent) "
        "VALUES (1, 'playMedia', 0, 1000, 30, 100)",
      );
      final row = await db
          .customSelect('SELECT fg_percent, bg_percent FROM $_kSegments')
          .getSingle();
      expect(row.read<int>('fg_percent'), 30);
      expect(row.read<int>('bg_percent'), 100);
    });
  });
}
