import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/db/migration/v37_migration.dart';

import 'helpers/sqlite3_loader.dart';

/// Schema v37 contract: `storages_table` gains the stable `volume_id` column
/// used to match a re-mounted disk to its existing entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  Future<Set<String>> storageColumns() async {
    final rows = await db.customSelect('PRAGMA table_info(storages_table)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  test('schemaVersion advanced to 37', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(37));
  });

  test('storages_table carries volume_id', () async {
    expect(await storageColumns(), contains('volume_id'));
  });

  test('MigrationV37 is re-entrant (no-op when the column exists)', () async {
    await MigrationV37(db).run(db.createMigrator());
    expect(await storageColumns(), contains('volume_id'));
  });

  test('a storage row round-trips volume_id', () async {
    await db.customInsert(
      'INSERT INTO storages_table (id, type, name, base_path, volume_id) '
      'VALUES (?, ?, ?, ?, ?)',
      variables: [
        Variable.withString('sid'),
        Variable.withInt(1),
        Variable.withString('Movies (E:)'),
        Variable.withString('["E:"]'),
        Variable.withString('vol:g'),
      ],
    );
    final row = await db
        .customSelect('SELECT volume_id FROM storages_table WHERE id = ?',
            variables: [Variable.withString('sid')])
        .getSingle();
    expect(row.read<String?>('volume_id'), 'vol:g');
  });
}
