import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/db/security/storage_cipher.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/db/storage_persistence.dart';
import 'package:iris/store/use_storage_store.dart';

import 'helpers/sqlite3_loader.dart';

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

/// A cipher/nonce pair that can never decrypt (random bytes with a bad MAC).
({String cipher, String nonce}) _undecryptableCipher() => (
      cipher: base64Encode(List<int>.generate(32, (i) => i)),
      nonce: base64Encode(List<int>.generate(12, (i) => 255 - i)),
    );

/// A remote row whose plaintext column is already cleared (the state every
/// encrypted row is in) and whose cipher is unreadable on this device.
Future<void> _seedLockedWebdavRow(String id) {
  final bad = _undecryptableCipher();
  return DbModule.storageDao.insert(
    StoragesTableCompanion.insert(
      id: id,
      type: StorageType.webdav.index,
      name: 'home-$id',
      basePath: '["/media"]',
      host: const Value('192.168.*.*'),
      resolvedHost: const Value('192.168.1.7'),
      resolvedHosts: const Value('["192.168.1.7","192.168.1.9"]'),
      port: const Value('5005'),
      username: const Value('u'),
      password: const Value(null),
      passwordCipher: Value(bad.cipher),
      passwordNonce: Value(bad.nonce),
      https: const Value(false),
      dataScopeId: const Value('scope-1'),
    ),
  );
}

/// A second, readable entry linked into the same data scope as the locked one.
Future<void> _seedPlaintextSiblingRow(String id, {required String scopeId}) {
  return DbModule.storageDao.insert(
    StoragesTableCompanion.insert(
      id: id,
      type: StorageType.webdav.index,
      name: 'sibling-$id',
      basePath: '["/"]',
      host: const Value('192.168.1.5'),
      port: const Value('8090'),
      username: const Value('u'),
      password: const Value('p'),
      https: const Value(false),
      dataScopeId: Value(scopeId),
    ),
  );
}

Future<void> _seedPlaintextWebdavRow(String id) {
  return DbModule.storageDao.insert(
    StoragesTableCompanion.insert(
      id: id,
      type: StorageType.webdav.index,
      name: 'home-$id',
      basePath: '["/"]',
      host: const Value('192.168.1.4'),
      port: const Value('8090'),
      username: const Value('u'),
      password: const Value('p'),
      https: const Value(false),
    ),
  );
}

Future<StoragesTableData> _row(String id) async {
  final rows = await DbModule.storageDao.getAll();
  return rows.firstWhere((r) => r.id == id);
}

Future<UnifiedStorageStore> _loadStore() async {
  final store = UnifiedStorageStore(
    legacyPersistence: _StubPersistence(),
    dbPersistence: _realDbPersistence(),
  );
  await store.initialized;
  return store;
}

void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  setUp(() async {
    StorageCipher.resetForTest();
    StorageCipher.keyReadTimeout = const Duration(seconds: 5);
    for (final row in await DbModule.storageDao.getAll()) {
      await DbModule.storageDao.deleteById(row.id);
    }
  });

  tearDown(() async {
    for (final row in await DbModule.storageDao.getAll()) {
      await DbModule.storageDao.deleteById(row.id);
    }
  });

  test('an undecryptable row stays a WebDAV entry (never degrades to none)',
      () async {
    await _seedLockedWebdavRow('s1');

    final store = await _loadStore();

    expect(store.loadOk, isTrue);
    expect(store.state.storages, hasLength(1));
    final s = store.state.storages.single;
    expect(s, isA<WebDAVStorage>(),
        reason: 'a locked entry must not be rewritten as a local storage');
    final w = s as WebDAVStorage;
    expect(w.type, StorageType.webdav);
    expect(w.host, '192.168.*.*');
    expect(w.port, '5005');
    expect(w.username, 'u');
    expect(w.resolvedHosts, ['192.168.1.7', '192.168.1.9']);
    expect(w.dataScopeId, 'scope-1');

    expect(DbModule.storageRepo.hasLockedStorages, isTrue);
    expect(DbModule.storageRepo.lockedStorages.keys, contains('s1'));
  });

  test('a save after a failed decrypt must not rewrite the locked row',
      () async {
    await _seedLockedWebdavRow('s1');
    final before = await _row('s1');

    final store = await _loadStore();
    // Any ordinary action triggers a FULL REPLACE write.
    await store.updateCurrentPath(['/media']);
    await store.updateCurrentStorage(store.state.storages.single);

    final after = await _row('s1');
    expect(after.type, before.type);
    expect(after.host, before.host);
    expect(after.port, before.port);
    expect(after.username, before.username);
    expect(after.passwordCipher, before.passwordCipher,
        reason: 'the original cipher must survive a failed decrypt');
    expect(after.passwordNonce, before.passwordNonce);
    expect(after.resolvedHosts, before.resolvedHosts,
        reason: 'the DHCP/wildcard host cache must never be clobbered');
    expect(after.dataScopeId, before.dataScopeId);
  });

  test('re-entering the password unlocks the row and keeps the host cache',
      () async {
    await _seedLockedWebdavRow('s1');

    final store = await _loadStore();
    final placeholder = store.state.storages.single as WebDAVStorage;

    final edited = placeholder.copyWith(password: 'newpw');
    await store.updateStorage(0, edited);

    final after = await _row('s1');
    expect(after.password, isNull, reason: 'plaintext column stays cleared');
    expect(
      await StorageCipher.decrypt(after.passwordCipher!, after.passwordNonce!),
      'newpw',
    );
    expect(after.resolvedHosts, '["192.168.1.7","192.168.1.9"]',
        reason: 're-authentication must not drop the resolved-host cache');
    expect(after.dataScopeId, 'scope-1');
    expect(DbModule.storageRepo.hasLockedStorages, isFalse);
  });

  test('a host broadcast never unlocks or rewrites a locked sibling',
      () async {
    await _seedLockedWebdavRow('s1');
    await _seedPlaintextSiblingRow('s2', scopeId: 'scope-1');

    final store = await _loadStore();
    expect(store.state.storages, hasLength(2));
    final before = await _row('s1');

    await store.updateWebdavResolvedHosts('s2', const <String>['192.168.1.55']);

    final after = await _row('s1');
    expect(after.passwordCipher, before.passwordCipher,
        reason: 'a background host broadcast must not clobber the cipher');
    expect(after.resolvedHosts, before.resolvedHosts);
    expect(DbModule.storageRepo.isLockedId('s1'), isTrue);
    expect((await _row('s2')).resolvedHosts, contains('192.168.1.55'));
  });

  test('removing a locked entry still deletes its row', () async {
    await _seedLockedWebdavRow('s1');
    final store = await _loadStore();

    await store.removeStorage(store.state.storages.single);

    expect(await DbModule.storageDao.getAll(), isEmpty);
    expect(DbModule.storageRepo.hasLockedStorages, isFalse);
  });

  test('a readable cipher row is not locked and keeps its password', () async {
    final enc = await StorageCipher.encrypt('secret');
    await DbModule.storageDao.insert(
      StoragesTableCompanion.insert(
        id: 'ok',
        type: StorageType.webdav.index,
        name: 'ok',
        basePath: '["/"]',
        host: const Value('192.168.1.4'),
        port: const Value('8090'),
        username: const Value('u'),
        password: const Value(null),
        passwordCipher: Value(enc.cipher),
        passwordNonce: Value(enc.nonce),
        https: const Value(false),
      ),
    );

    final store = await _loadStore();

    expect(store.state.storages.single, isA<WebDAVStorage>());
    expect((store.state.storages.single as WebDAVStorage).password, 'secret');
    expect(DbModule.storageRepo.hasLockedStorages, isFalse);
  });

  test('plaintext legacy rows are unaffected', () async {
    await _seedPlaintextWebdavRow('legacy');

    final store = await _loadStore();

    expect((store.state.storages.single as WebDAVStorage).password, 'p');
    expect(DbModule.storageRepo.hasLockedStorages, isFalse);
  });
}
