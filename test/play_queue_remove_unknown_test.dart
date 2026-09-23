import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/play_queue/persistence/play_queue_persistence.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// Removing a queue item that the backend no longer holds (stale tile after
/// a shuffle/replacement) must be a silent no-op — never a RangeError from
/// indexing `playQueue[-1]`.
class _NoopPersistence implements PlayQueuePersistence {
  @override
  Future<PlayQueueState?> load() async => null;

  @override
  Future<void> save(PlayQueueState state) async {}
}

FileItem _f(String name) =>
    FileItem(name: name, uri: 'file:///$name', path: [name]);

void main() {
  late AppDatabase moduleDb;

  setUpAll(() {
    moduleDb = AppDatabase(NativeDatabase.memory());
    DbModule.init(moduleDb);
  });

  tearDownAll(() async {
    await moduleDb.close();
  });

  test('removing an unknown item is a silent no-op', () async {
    final store = UnifiedPlayQueueStore(
      legacyPersistence: _NoopPersistence(),
      queryPersistence: _NoopPersistence(),
    );
    await store.initialized;
    // Pin the in-memory backend: the default AppState routes onReady to the
    // query backend, which has its own remove path.
    await store.switchBackend(true);
    await store.add([_f('a.mp4'), _f('b.mp4')]);
    expect(store.totalCount, 2);

    await store.remove(PlayQueueItem(file: _f('ghost.mp4'), index: 99));

    expect(store.totalCount, 2);
    await store.dispose();
  });
}
