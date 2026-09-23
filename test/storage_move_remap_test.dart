import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_storage_store.dart';

/// Store-level side effects of a drive-letter move: the "current storage" and
/// browse location follow the entry, and only that entry's favorites move.
LocalStorage _local({required String id, required List<String> basePath}) =>
    LocalStorage(
      id: id,
      type: StorageType.internal,
      name: id,
      basePath: basePath,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    final store = useStorageStore();
    await store.initialized;
    for (final s in [...store.state.storages]) {
      await store.removeStorage(s);
    }
    for (final f in [...store.state.favorites]) {
      await store.removeFavorite(f);
    }
    await store.updateCurrentStorage(null);
    await store.updateCurrentPath(const []);
  });

  test('updateStorage refreshes currentStorage when its entry moves', () async {
    final store = useStorageStore();
    await store.addStorage(_local(id: 'sid', basePath: ['D:']));
    await store.updateCurrentStorage(store.findById('sid'));

    final index = store.state.storages.indexWhere((s) => s.id == 'sid');
    await store.updateStorage(index, _local(id: 'sid', basePath: ['E:']));

    expect(store.state.currentStorage?.basePath, ['E:']);
  });

  test('updateStorage leaves an unrelated currentStorage alone', () async {
    final store = useStorageStore();
    await store.addStorage(_local(id: 'a', basePath: ['D:']));
    await store.addStorage(_local(id: 'b', basePath: ['D:']));
    await store.updateCurrentStorage(store.findById('a'));

    final index = store.state.storages.indexWhere((s) => s.id == 'b');
    await store.updateStorage(index, _local(id: 'b', basePath: ['E:']));

    expect(store.state.currentStorage?.id, 'a');
  });

  test('remapCurrentPath moves the browse location to the new letter', () async {
    final store = useStorageStore();
    await store.addStorage(_local(id: 'sid', basePath: ['E:']));
    await store.updateCurrentStorage(store.findById('sid'));
    await store.updateCurrentPath(const ['D:', 'Movies']);

    await store.remapCurrentPath(
        storageId: 'sid', oldBase: 'D:', newBase: 'E:');

    expect(store.state.currentPath, ['E:', 'Movies']);
  });

  test('remapCurrentPath is a no-op for a different current storage', () async {
    final store = useStorageStore();
    await store.addStorage(_local(id: 'other', basePath: ['E:']));
    await store.updateCurrentStorage(store.findById('other'));
    await store.updateCurrentPath(const ['D:', 'Movies']);

    await store.remapCurrentPath(
        storageId: 'sid', oldBase: 'D:', newBase: 'E:');

    expect(store.state.currentPath, ['D:', 'Movies']);
  });

  test('remapFavorites moves only the matching storage favorites', () async {
    final store = useStorageStore();
    await store.addFavorite(Favorite(storageId: 'sid', path: ['D:', 'Movies']));
    await store
        .addFavorite(Favorite(storageId: 'other', path: ['D:', 'Other']));

    await store.remapFavorites(storageId: 'sid', oldBase: 'D:', newBase: 'E:');

    expect(
      store.state.favorites.firstWhere((f) => f.storageId == 'sid').path,
      ['E:', 'Movies'],
    );
    expect(
      store.state.favorites.firstWhere((f) => f.storageId == 'other').path,
      ['D:', 'Other'],
    );
  });
}
