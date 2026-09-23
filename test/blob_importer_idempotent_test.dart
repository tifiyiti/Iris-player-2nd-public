import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/bridge/state_bridge.dart';
import 'package:iris/features/meta_settings/model/db/repositories/settings_db_repository.dart';
import 'package:iris/features/meta_settings/bridge/blob_importer.dart';
import 'package:iris/features/meta_settings/model/db/dao/settings_dao.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/store/app_state.dart';

import 'helpers/sqlite3_loader.dart';

void main() {
  ensureSqlite3Loaded();

  late AppDatabase db;
  late SettingsDbRepository repo;
  late LegacyBlobImporter importer;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsDbRepository(SettingsDao(db));
    importer = LegacyBlobImporter(repo);
  });
  tearDown(() => db.close());

  test('first import seeds rows; second import is a no-op', () async {
    final legacy = const AppState().copyWith(
      volume: 55,
      themeMode: ThemeMode.dark,
    ).toJson();

    expect(await repo.hasAnyValue(), isFalse);

    final firstRun = await importer.importIfNeeded(legacy);
    expect(firstRun, isTrue, reason: 'empty table → import must run');
    expect(await repo.hasAnyValue(), isTrue);

    // Simulate user edits AFTER migration; a re-import must not clobber them.
    await repo.saveRawValue('app.volume', '"99"');

    final secondRun = await importer.importIfNeeded(legacy);
    expect(secondRun, isFalse, reason: 'non-empty table → skip');

    final rows = await repo.loadRawValues();
    expect(rows['app.volume'], '"99"', reason: 'post-migration edit survives');
    expect(rows['app.themeMode'], '"dark"');
  });

  test('imported blob materializes back to the same state', () async {
    final original = const AppState().copyWith(
      volume: 12,
      playerBackend: PlayerBackend.fvp,
      snakeFineWindowSeconds: 7,
      reuseLastOrientation: true,
    );
    final legacyJson = original.toJson();

    await importer.importIfNeeded(legacyJson);

    final restored = StateBridge.materialize(await repo.loadRawValues());
    expect(restored, original);
  });

  test('empty legacy map imports nothing', () async {
    expect(await importer.importIfNeeded({}), isFalse);
    expect(await repo.hasAnyValue(), isFalse);
  });
}
