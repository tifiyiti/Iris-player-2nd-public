import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/play_queue/persistence/play_queue_persistence.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// Regression: Player.build reads `store.totalCount` during the very first
/// frame (title queue-index deps). On slow-IO devices that frame raced ahead
/// of the store's onReady(), hitting the uninitialized `late _activeBackend`
/// (device log 2026-08: LateInitializationError at startup). Any entry path
/// must be able to read queue stats BEFORE onReady — matching the existing
/// lazy-construction philosophy of `_ensureQueryBackend`.
///
/// The store constructor auto-starts PersistentStore._init(), so onReady()
/// fires on a microtask and needs DbModule wired (_ensureQueryBackend);
/// a throwaway in-memory DB keeps that lifecycle safe (same pattern as
/// query_play_queue_backend_test). The assertions below run synchronously —
/// strictly before that microtask — i.e. in the exact window that used to
/// throw.
class _NoopPersistence implements PlayQueuePersistence {
  @override
  Future<PlayQueueState?> load() async => null;

  @override
  Future<void> save(PlayQueueState state) async {}
}

void main() {
  late AppDatabase moduleDb;

  setUpAll(() {
    moduleDb = AppDatabase(NativeDatabase.memory());
    DbModule.init(moduleDb);
  });

  tearDownAll(() async {
    await moduleDb.close();
  });

  test('queue stats are readable before onReady (legacy empty semantics)',
      () {
    final store = UnifiedPlayQueueStore(
      legacyPersistence: _NoopPersistence(),
      queryPersistence: _NoopPersistence(),
    );

    // Legacy empty queue: no items yet; virtual pos -1 = index not found.
    expect(store.totalCount, 0);
    expect(store.currentVirtualPos, -1);
    expect(store.isQueryMode, isFalse);
  });
}
