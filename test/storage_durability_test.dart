import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/db/storage_persistence.dart';
import 'package:iris/store/use_storage_store.dart';

import 'helpers/sqlite3_loader.dart';

/// DB persistence whose READ fails — the exact condition that used to wipe
/// `storages_table`: the store fell back to its default (empty) state and any
/// later save replaced the whole table with that empty list.
class _LoadThrowingDbPersistence extends DbStoragePersistence {
  _LoadThrowingDbPersistence()
      : super(
          storageRepo: DbModule.storageRepo,
          favoritesRepo: DbModule.favoritesRepo,
          navRepo: DbModule.navRepo,
        );

  @override
  Future<StorageState?> load() async => throw StateError('db unavailable');
}

/// Inert legacy backend (never used by these cases).
class _StubPersistence implements StoragePersistence {
  @override
  Future<StorageState?> load() async => null;

  @override
  Future<void> save(StorageState state) async {}
}

DbStoragePersistence _realDbPersistence() => DbStoragePersistence(
      storageRepo: DbModule.storageRepo,
      favoritesRepo: DbModule.favoritesRepo,
      navRepo: DbModule.navRepo,
    );

Future<void> _seedWebdavRow(String id) {
  return DbModule.storageDao.insert(
    StoragesTableCompanion.insert(
      id: id,
      type: StorageType.webdav.index,
      name: id,
      basePath: '["/"]',
      host: const Value('192.168.1.4'),
      resolvedHost: const Value('192.168.1.4'),
      resolvedHosts: const Value('["192.168.1.4"]'),
      port: const Value('8090'),
      username: const Value('u'),
      password: const Value('p'),
      https: const Value(false),
    ),
  );
}

void main() {
  ensureSqlite3Loaded();

  // DbModule's statics are initialized once per process.
  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  // Clean slate between cases (the seeded ids are the only rows we create).
  setUp(() async {
    await DbModule.storageDao.deleteById('s1');
    await DbModule.storageDao.deleteById('s2');
  });

  test('a failed load must not let a save wipe the storage table', () async {
    await _seedWebdavRow('s1');
    await _seedWebdavRow('s2');
    expect(await DbModule.storageDao.getAll(), hasLength(2));

    final store = UnifiedStorageStore(
      legacyPersistence: _StubPersistence(),
      dbPersistence: _LoadThrowingDbPersistence(),
    );
    await store.initialized;

    expect(store.loadOk, isFalse);
    expect(store.loaded, isTrue, reason: 'UI readiness still resolves');
    expect(store.state.storages, isEmpty);

    // Ordinary actions that persist would previously have replaced the whole
    // table with the never-loaded (empty) state.
    await store.updateCurrentPath(['/']);
    await store.updateCurrentStorage(null);

    final rows = await DbModule.storageDao.getAll();
    expect(rows, hasLength(2), reason: 'saved storages must survive');
    expect(rows.map((r) => r.id), containsAll(<String>['s1', 's2']));
  });

  test('a successful load still persists a user-initiated removal', () async {
    await _seedWebdavRow('s1');

    final store = UnifiedStorageStore(
      legacyPersistence: _StubPersistence(),
      dbPersistence: _realDbPersistence(),
    );
    await store.initialized;

    expect(store.loadOk, isTrue);
    expect(store.state.storages, hasLength(1));

    await store.removeStorage(store.state.storages.single);

    expect(await DbModule.storageDao.getAll(), isEmpty,
        reason: 'an authoritative empty list must remain persistable');
  });
}
