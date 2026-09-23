import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/v12_migration.dart';
import 'package:iris/models/db/migration/v14_migration.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'helpers/sqlite3_loader.dart';

void main() {
  ensureSqlite3Loaded();

  group('settings tables migration (schema v12)', () {
    test('fresh install creates the three metadata settings tables', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final Set<String> names = await _tableNames(db);
      expect(
        names,
        containsAll(<String>[
          'setting_defs',
          'setting_values',
          'feature_flags',
          // tag_play tables (schema v13)
          'video_tags',
          'video_tag_members',
          'video_tag_view_state',
          'video_tag_pin_preset',
        ]),
      );
      expect(db.schemaVersion, greaterThanOrEqualTo(17));
    });

    test('the three tables accept typed rows (roundtrip)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.customStatement(
        "INSERT INTO setting_defs (key, section, value_type, default_value, "
        "enum_values, widget_kind, editor_key, title_key, subtitle_key, "
        "platforms, sort_order) VALUES "
        "('app.themeMode', 'general', 'enumeration', 'system', "
        "'[\"system\",\"light\",\"dark\"]', 'enumPick', NULL, 'theme_mode', "
        "NULL, NULL, 10)",
      );

      await db.customStatement(
        "INSERT INTO setting_values (key, value, updated_at) VALUES "
        "('app.themeMode', 'dark', '2026-01-01 00:00:00.000')",
      );

      await db.customStatement(
        "INSERT INTO feature_flags (key, stage, default_enabled, user_override) "
        "VALUES ('scenario_playback', 'ga', 1, NULL)",
      );

      expect(await _scalar(db, 'SELECT COUNT(*) FROM setting_defs'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM setting_values'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM feature_flags'), 1);
    });

    test('MigrationV12.run is re-entrant (double run neither throws nor duplicates)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await MigrationV12(db).run(db.createMigrator());
      await MigrationV12(db).run(db.createMigrator());

      final List<String> defTables =
          (await _tableNames(db)).where((n) => n == 'setting_defs').toList();
      expect(defTables, hasLength(1));
    });

    test('upgrading a hand-built v11 database adds tables and preserves legacy rows', () async {
      final Directory tmpDir =
          await Directory.systemTemp.createTemp('iris_v12_upgrade');
      addTearDown(() => tmpDir.delete(recursive: true));
      final File file = File('${tmpDir.path}${Platform.pathSeparator}legacy.db');

      // Minimal stand-in for a pre-v12 database file.
      final sql.Database raw = sql.sqlite3.open(file.path);
      raw.execute('CREATE TABLE storage (id INTEGER PRIMARY KEY)');
      raw.execute('INSERT INTO storage (id) VALUES (42)');
      raw.execute('PRAGMA user_version = 11');
      raw.dispose();

      final db = AppDatabase(NativeDatabase(File(file.path)));
      addTearDown(db.close);

      // First statement opens the connection and runs the upgrade chain.
      final Set<String> names = await _tableNames(db);
      expect(
        names,
        containsAll(<String>['setting_defs', 'setting_values', 'feature_flags']),
      );

      final row = await db.customSelect('SELECT id FROM storage').getSingle();
      expect(row.read<int>('id'), 42);
    });
  });

  group('tag_play v14 migration (resume window column)', () {
    test('fresh install gives video_tags a nullable resume_window_minutes column',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final columns = await _columnNames(db, 'video_tags');
      expect(columns, contains('resume_window_minutes'));
    });

    test('MigrationV14.run is re-entrant (double run neither throws nor duplicates)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await MigrationV14(db).run(db.createMigrator());
      await MigrationV14(db).run(db.createMigrator());

      final columns = await _columnNames(db, 'video_tags');
      expect(columns.where((c) => c == 'resume_window_minutes'), hasLength(1));
    });

    test('upgrading a hand-built v13 database adds the column and preserves rows',
        () async {
      final Directory tmpDir =
          await Directory.systemTemp.createTemp('iris_v14_upgrade');
      addTearDown(() => tmpDir.delete(recursive: true));
      final File file = File('${tmpDir.path}${Platform.pathSeparator}legacy.db');

      // Minimal stand-in for a pre-v14 database: video_tags WITHOUT the
      // resume-window column, holding one existing tag row.
      final sql.Database raw = sql.sqlite3.open(file.path);
      raw.execute('CREATE TABLE video_tags ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'name TEXT NOT NULL, '
          'description TEXT NOT NULL DEFAULT \'\', '
          'created_at INTEGER NOT NULL, '
          'retention_minutes INTEGER NULL)');
      raw.execute(
          "INSERT INTO video_tags (name, description, created_at) VALUES "
          "('keep', '', 1700000000000)");
      raw.execute('PRAGMA user_version = 13');
      raw.dispose();

      final db = AppDatabase(NativeDatabase(File(file.path)));
      addTearDown(db.close);

      final columns = await _columnNames(db, 'video_tags');
      expect(columns, contains('resume_window_minutes'));

      final row = await db.customSelect(
        'SELECT name, resume_window_minutes FROM video_tags',
      ).getSingle();
      expect(row.read<String>('name'), 'keep');
      expect(row.readNullable<int>('resume_window_minutes'), isNull);
    });
  });

  // Regression: MigrationV38 reads storages_table, but a hand-built legacy file
  // need not contain it (nothing earlier in the upgrade chain creates it — only
  // onCreate does, for fresh installs). Unguarded, the whole open throws
  // `no such table: storages_table` and the database can never be upgraded.
  group('migration chain resilience (missing storages_table)', () {
    test('upgrading a database without storages_table does not throw', () async {
      final Directory tmpDir =
          await Directory.systemTemp.createTemp('iris_no_storages');
      addTearDown(() => tmpDir.delete(recursive: true));
      final File file = File('${tmpDir.path}${Platform.pathSeparator}legacy.db');

      final sql.Database raw = sql.sqlite3.open(file.path);
      raw.execute('CREATE TABLE storage (id INTEGER PRIMARY KEY)');
      raw.execute('INSERT INTO storage (id) VALUES (7)');
      raw.execute('PRAGMA user_version = 37');
      raw.dispose();

      final db = AppDatabase(NativeDatabase(File(file.path)));
      addTearDown(db.close);

      // Opening runs the v38..v45 tail of the chain; it must not abort.
      await expectLater(_tableNames(db), completes);
    });
  });
}

Future<Set<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<Set<String>> _columnNames(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<int> _scalar(AppDatabase db, String sql) async {
  final QueryRow row = await db.customSelect(sql).getSingle();
  return row.read<int>(row.data.keys.first);
}
