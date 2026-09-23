import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/db/storage_scope.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_storage_store.dart';

WebDAVStorage _webdav({
  required String id,
  String? dataScopeId,
  List<String> resolvedHosts = const <String>[],
}) =>
    WebDAVStorage(
      id: id,
      name: id,
      host: '192.168.*.*',
      resolvedHosts: resolvedHosts,
      basePath: const <String>['/'],
      port: '5005',
      username: 'u',
      password: 'p',
      https: false,
      dataScopeId: dataScopeId,
    );

MediaNode _node(String storageId, String path) {
  final segments = path.split('/');
  return MediaNode.file(
    id: '$storageId:$path',
    storageId: storageId,
    path: segments,
    parentPath:
        segments.length == 1 ? null : segments.sublist(0, segments.length - 1).join('/'),
    pathDepth: segments.length,
    name: segments.last,
    mediaType: MediaType.video,
  );
}

Future<int> _scopeNodeCount(AppDatabase db, String scopeId) async {
  final row = await db
      .customSelect(
        "SELECT COUNT(*) c FROM media_nodes WHERE data_scope_id = ?",
        variables: [Variable.withString(scopeId)],
      )
      .getSingle();
  return row.read<int>('c');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  setUp(() async {
    final store = useStorageStore();
    await store.initialized;
    for (final storage in [...store.state.storages]) {
      await store.removeStorage(storage);
    }
  });

  test('resolved hosts broadcast to every entry sharing the scope', () async {
    final store = useStorageStore();
    await store.addStorage(_webdav(id: 'a'));
    await store.addStorage(_webdav(id: 'b', dataScopeId: 'a'));

    await store.updateWebdavResolvedHosts('b', const ['192.168.1.9']);

    expect((store.findById('a') as WebDAVStorage).resolvedHosts,
        const ['192.168.1.9']);
    expect((store.findById('b') as WebDAVStorage).resolvedHosts,
        const ['192.168.1.9']);
  });

  test('independent entries never share resolved hosts', () async {
    final store = useStorageStore();
    await store.addStorage(_webdav(id: 'a'));
    await store.addStorage(_webdav(id: 'c'));

    await store.updateWebdavResolvedHosts('c', const ['10.0.0.9']);

    expect((store.findById('a') as WebDAVStorage).resolvedHosts, isEmpty);
    expect((store.findById('c') as WebDAVStorage).resolvedHosts,
        const ['10.0.0.9']);
  });

  test('removing the scope owner re-points shared nodes to a survivor',
      () async {
    final store = useStorageStore();
    await store.addStorage(_webdav(id: 'a'));
    await store.addStorage(_webdav(id: 'b', dataScopeId: 'a'));

    // Node keyed by the canonical scope 'a' (identity resolver in tests).
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'a:x/v.mp4',
      storageId: 'a',
      path: const ['x', 'v.mp4'],
      name: 'v.mp4',
      mediaType: MediaType.video,
    ));

    await store.removeStorage(store.findById('a')!);

    final row = await DbModule.mediaNodesDao.getByPath('a', 'x/v.mp4');
    expect(row, isNotNull);
    expect(row!.storageId, 'b'); // re-pointed to the surviving owner
    expect(row.dataScopeId, 'a'); // scope identity unchanged
  });

  test('removing an independent entry leaves its nodes untouched', () async {
    final store = useStorageStore();
    await store.addStorage(_webdav(id: 'a'));
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'a:y/v.mp4',
      storageId: 'a',
      path: const ['y', 'v.mp4'],
      name: 'v.mp4',
      mediaType: MediaType.video,
    ));

    StorageScope.reset();
    await store.removeStorage(store.findById('a')!);

    final row = await DbModule.mediaNodesDao.getByPath('a', 'y/v.mp4');
    expect(row!.storageId, 'a');
  });

  test('moving an entry out of its old scope purges the unreachable rows',
      () async {
    final store = useStorageStore();
    await store.addStorage(_webdav(id: 'pa')); // scope 'pa' (own id)
    await DbModule.mediaNodesDao.insertNode(_node('pa', 'purge/v.mp4'));
    expect(await _scopeNodeCount(db, 'pa'), 1);

    final index = store.state.storages.indexWhere((s) => s.id == 'pa');
    await store.updateStorage(index, _webdav(id: 'pa', dataScopeId: 'other'));

    expect(await _scopeNodeCount(db, 'pa'), 0); // old-scope rows purged
  });

  test('moving one entry keeps a shared scope while a sibling remains',
      () async {
    final store = useStorageStore();
    await store.addStorage(_webdav(id: 'ka'));
    await store.addStorage(_webdav(id: 'kb', dataScopeId: 'ka'));
    await DbModule.mediaNodesDao.insertNode(_node('ka', 'keep/v.mp4'));

    final index = store.state.storages.indexWhere((s) => s.id == 'kb');
    await store.updateStorage(index, _webdav(id: 'kb'));

    expect(await _scopeNodeCount(db, 'ka'), 1); // 'ka' still owns it
  });
}
