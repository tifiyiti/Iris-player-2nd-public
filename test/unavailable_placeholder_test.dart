import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_source_kind.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/queue/paged_scenario_media_data_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// D28 (v5-D5/v6-D38): the resolver generates `available: false` placeholders
/// for empty/missing sources (folder & file kinds) that count into totalItems,
/// so the queue/preview can render them greyed and un-tappable.
void main() {
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  setUp(() async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
    await store.clearSources(sys.id);
    await store.clearExplicitItems(sys.id);
    await store.clearTemporaryExcludes(sys.id);
  });

  Future<void> seedFile(String storageId, String p) async {
    await DbModule.mediaNodesDao.deleteNode(storageId, p);
    final segments = p.split('/');
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'f:$storageId:$p',
      storageId: storageId,
      path: segments,
      name: segments.last,
      mediaType: MediaType.video,
    ));
  }

  test('empty folder source yields an available:false placeholder in totalItems',
      () async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await seedFile('s', 'a/x.mp4');
    await store.addSource(storageId: 's', path: 'a', recursive: true);
    await store.addSource(storageId: 's', path: 'zz-empty', recursive: true);

    final result = await store.resolvePageFor(sys.id, page: 0, pageSize: 50);
    expect(result.totalItems, 2);
    final placeholder = result.items.where((i) => !i.available).toList();
    expect(placeholder, hasLength(1));
    expect(placeholder.single.media.name, 'zz-empty');
  });

  test('missing file-kind source yields an available:false placeholder', () async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await seedFile('s', 'a/x.mp4');
    await store.addSource(storageId: 's', path: 'a', recursive: true);
    await store.addSource(
      storageId: 's',
      path: 'missing.mp4',
      recursive: false,
      kind: ScenarioSourceKind.file,
    );

    final result = await store.resolvePageFor(sys.id, page: 0, pageSize: 50);
    expect(result.totalItems, 2);
    expect(
      result.items.where((i) => !i.available).single.media.name,
      'missing.mp4',
    );
  });

  testWidgets('queue data source flags unavailable items for grey-out (D28)',
      (tester) async {
    // Elapse fake time first so drift executor deliveries complete for the
    // DB awaits below.
    await tester.pump(const Duration(milliseconds: 100));
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
    await seedFile('s', 'a/x.mp4');
    await store.addSource(storageId: 's', path: 'a', recursive: true);
    await store.addSource(storageId: 's', path: 'zz-empty', recursive: true);

    final result = await store.resolvePageFor(sys.id, page: 0, pageSize: 50);
    final ds = PagedScenarioMediaDataSource(scenarioId: sys.id);
    addTearDown(ds.dispose);
    await tester.pump(const Duration(milliseconds: 100));

    BuildContext? ctx;
    await tester.pumpWidget(
        Builder(builder: (context) {
      ctx = context;
      return const SizedBox.shrink();
    }));

    final unavailable = result.items.firstWhere((i) => !i.available);
    final available = result.items.firstWhere((i) => i.available);
    expect(ds.isItemUnavailable(ctx!, unavailable), isTrue);
    expect(ds.isItemUnavailable(ctx!, available), isFalse);
  });
}
