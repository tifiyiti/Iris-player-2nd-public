import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/adapters/storage_drift_adapter.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/v29_migration.dart';

import 'helpers/sqlite3_loader.dart';

/// Drift's generated name for [StoragesTable].
const String _kTable = 'storages_table';

Future<Set<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void main() {
  ensureSqlite3Loaded();

  group('storages v29 migration', () {
    test('fresh install has a nullable resolved_hosts column', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      expect(await _columns(db, _kTable), contains('resolved_hosts'));
    });

    test('adds the missing column and back-fills the legacy single value', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Simulate a pre-v29 table.
      await db.customStatement('ALTER TABLE $_kTable DROP COLUMN resolved_hosts');
      expect(await _columns(db, _kTable), isNot(contains('resolved_hosts')));

      await db.customStatement(
        "INSERT INTO $_kTable (id, type, name, base_path, resolved_host) "
        "VALUES ('s1', 5, 'nas', '[\"/\"]', '192.168.1.7')",
      );

      await MigrationV29(db).run(db.createMigrator());

      final row = await db
          .customSelect("SELECT resolved_hosts FROM $_kTable WHERE id = 's1'")
          .getSingle();
      expect(row.read<String>('resolved_hosts'), '["192.168.1.7"]');
    });

    test('is re-entrant and never clobbers an existing list', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.customStatement(
        "INSERT INTO $_kTable (id, type, name, base_path, resolved_host, resolved_hosts) "
        "VALUES ('s1', 5, 'nas', '[\"/\"]', '192.168.1.7', '[\"192.168.1.9\"]')",
      );

      await MigrationV29(db).run(db.createMigrator());
      await MigrationV29(db).run(db.createMigrator());

      final columns = await _columns(db, _kTable);
      expect(columns.where((c) => c == 'resolved_hosts'), hasLength(1));

      final row = await db
          .customSelect("SELECT resolved_hosts FROM $_kTable WHERE id = 's1'")
          .getSingle();
      expect(row.read<String>('resolved_hosts'), '["192.168.1.9"]');
    });
  });

  group('decodeResolvedHosts', () {
    test('prefers the JSON list', () {
      expect(
        StorageDriftAdapter.decodeResolvedHosts('["a","b"]', 'z'),
        ['a', 'b'],
      );
    });

    test('falls back to the legacy single value', () {
      expect(
        StorageDriftAdapter.decodeResolvedHosts(null, '192.168.1.7'),
        ['192.168.1.7'],
      );
    });

    test('ignores corrupt or empty payloads', () {
      expect(
        StorageDriftAdapter.decodeResolvedHosts('{oops', 'legacy'),
        ['legacy'],
      );
      expect(StorageDriftAdapter.decodeResolvedHosts('[]', 'legacy'), ['legacy']);
      expect(StorageDriftAdapter.decodeResolvedHosts(null, null), isEmpty);
    });
  });
}
