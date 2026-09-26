import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/search/store/use_media_lib_search_store.dart';
import 'package:iris/features/media_library/play_queue/backends/query_play_queue_backend.dart';
import 'package:iris/features/media_library/view/content/store/use_media_lib_content_store.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/kv/secure_kv.dart';
import 'package:iris/store/kv/use_kv_store.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Scenario store without the DB-backed scenario list refresh: the per-surface
/// page sizes are pure secure-storage state, so their load clamp is testable
/// without wiring a scenario table.
class _NoRefreshScenarioStore extends PlaybackScenarioStore {
  @override
  void onReady() {}
}

/// A page is materialized in memory, so the size is a memory budget, not a
/// preference. The prompt and every `changePageSize` clamp through
/// [clampPageSize], but the PERSISTED value arrives from disk without passing
/// either — a blob written while the prompt still allowed 100000 drives a
/// hundred thousand rows into the first fetchPage after an upgrade. Every store
/// that owns a page size must therefore clamp ON READ too, not just on change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  late AppDatabase db;
  late MemoryKvStore kv;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });
  tearDownAll(() => db.close);

  setUp(() {
    resetKvStoreForTest();
    kv = MemoryKvStore();
    setKvStoreForTest(kv);
  });

  tearDown(resetKvStoreForTest);

  Future<void> seed(String key, Map<String, dynamic> json) =>
      kv.write(key: key, value: jsonEncode(json));

  test('the content store clamps a persisted page size past the ceiling',
      () async {
    await seed('media_lib_content_state', {'pageSize': 50000});

    final store = MediaLibContentStore(
      nodeRepository: DbModule.nodeRepository,
      sourcesRepository: DbModule.sourcesRepository,
      facade: DbModule.mediaFacade,
    );
    await store.initialized;

    expect(store.state.pageSize, kMaxBrowserPageSize,
        reason: '50000 rows in one page is the freeze/OOM the ceiling exists '
            'to prevent — an upgrade must not walk straight into it');
  });

  test('the search store clamps a persisted page size past the ceiling',
      () async {
    await seed('media_lib_search_state', {'pageSize': 100000});

    final store = MediaLibSearchStore();
    await store.initialized;

    expect(store.state.pageSize, kMaxBrowserPageSize);
  });

  test('a persisted page size inside the range is left alone', () async {
    await seed('media_lib_content_state', {'pageSize': 300});

    final store = MediaLibContentStore(
      nodeRepository: DbModule.nodeRepository,
      sourcesRepository: DbModule.sourcesRepository,
      facade: DbModule.mediaFacade,
    );
    await store.initialized;

    expect(store.state.pageSize, 300,
        reason: 'the migration must not silently rewrite a legal preference');
  });

  test('the app store clamps the storage browser page size it loads',
      () async {
    await seed('app_state', {'storageBrowserPageSize': 50000});

    final store = AppStore();
    await store.initialized;

    expect(store.state.storageBrowserPageSize, kMaxBrowserPageSize);
  });

  test('an imported settings bundle gets the same clamp as a load', () async {
    final store = AppStore();
    await store.initialized;

    await store.importFromJson({'storageBrowserPageSize': 100000});

    expect(store.state.storageBrowserPageSize, kMaxBrowserPageSize,
        reason: 'an exported bundle from an older build carries the same '
            'out-of-range value as the blob it came from');
  });

  test('every scenario surface clamps its persisted page size', () async {
    await seed('playback_scenario_active_id', {
      'activeScenarioId': 's1',
      'playingScenarioQueuePageSize': 50000,
      'scenarioPreviewQueuePageSize': 100000,
      'scenarioManagePageSize': 50000,
    });

    final store = _NoRefreshScenarioStore();
    await store.initialized;

    expect(store.state.playingScenarioQueuePageSize, kMaxBrowserPageSize);
    expect(store.state.scenarioPreviewQueuePageSize, kMaxBrowserPageSize);
    expect(store.state.scenarioManagePageSize, kMaxBrowserPageSize);
    // The rest of the blob still applies — this is a page-size migration, not
    // a state reset.
    expect(store.state.activeScenarioId, 's1');
  });

  test('the queue backend clamps the items-per-page it loads', () async {
    // The queue page fetches immediately on open, so a stale 10000 would
    // materialize ten thousand rows before the user touched anything.
    await seed('query_play_queue_state', {
      'totalCount': 0,
      'itemsPerPage': 10000,
    });

    final backend = QueryPlayQueueBackend(
      nodeRepo: DbModule.nodeRepository,
      scopedMediaTypes: () => null,
    );
    await backend.initialized;

    expect(backend.itemsPerPage, kMaxBrowserPageSize);
  });

  test('the queue backend refuses to persist a size past the ceiling',
      () async {
    final backend = QueryPlayQueueBackend(
      nodeRepo: DbModule.nodeRepository,
      scopedMediaTypes: () => null,
    );
    await backend.initialized;

    await backend.setItemsPerPage(100000);

    expect(backend.itemsPerPage, kMaxBrowserPageSize,
        reason: 'the write path must agree with the read clamp, or the value '
            'it stores is rejected on the next launch');
  });
}
