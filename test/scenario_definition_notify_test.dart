import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_sources_data_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// Regression: a scenario-definition edit made OUTSIDE the queue page (the
/// Sources / Manage "Remove", which is how a user restores an excluded item)
/// must still tell the playback layer the effective queue changed. Otherwise
/// the player chrome keeps a stale prev/next visibility (it only re-resolves on
/// `playbackVersion`) while an open queue list — re-fetched on
/// `sourceScanRevision` / re-opened — moves on, until a full rebuild (rotation)
/// fixes it.
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
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  tearDownAll(() => db.close());

  const storageId = 'st-def';

  Future<void> seed(String folder, String name) async {
    await DbModule.mediaNodesDao.deleteNode(storageId, '$folder/$name');
    final segments = '$folder/$name'.split('/');
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'f:$storageId:$folder/$name',
      storageId: storageId,
      path: segments,
      name: segments.last,
      mediaType: MediaType.video,
    ));
  }

  Future<String> resetWorkspace() async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
    await store.clearSources(sys.id);
    await store.clearExplicitItems(sys.id);
    await store.clearExcludes(sys.id);
    return sys.id;
  }

  test('notifyDefinitionChanged bumps BOTH re-resolution signals', () async {
    final store = usePlaybackScenarioStore();
    final beforePlayback = store.state.playbackVersion;
    final beforeScan = store.state.sourceScanRevision;

    await store.notifyDefinitionChanged();

    expect(store.state.playbackVersion, greaterThan(beforePlayback),
        reason: 'player chrome (prev/next visibility) re-resolves off this');
    expect(store.state.sourceScanRevision, greaterThan(beforeScan),
        reason: 'open queue lists re-fetch off this');
  });

  test('Manage Remove notifies playback and drops the rule', () async {
    final store = usePlaybackScenarioStore();
    final id = await resetWorkspace();
    await store.addSource(storageId: storageId, path: 'f1', recursive: true);
    await seed('f1', 'a.mp4');
    await store.addExcludeRule(ScenarioExcludeRule(
      id: 0,
      scenarioId: id,
      kind: ExcludeRuleKind.media,
      storageId: storageId,
      path: 'f1/a.mp4',
    ));
    expect(await store.getExcludeRules(id), hasLength(1));

    final ds = PagedScenarioSourcesDataSource(
      scenarioId: id,
      embeddedInStoragesDb: false,
    );
    await ds.load();
    final exclude = ds.items.firstWhere(
      (i) => i.kind == ScenarioManageItemKind.exclude,
    );

    final beforePlayback = store.state.playbackVersion;
    final beforeScan = store.state.sourceScanRevision;
    await ds.removeItem(exclude);

    expect(store.state.playbackVersion, greaterThan(beforePlayback),
        reason: 'the player chrome must re-resolve after a Manage Remove');
    expect(store.state.sourceScanRevision, greaterThan(beforeScan),
        reason: 'an open queue list must re-fetch after a Manage Remove');
    expect(await store.getExcludeRules(id), isEmpty,
        reason: 'the removed rule is gone');
    ds.dispose();
  });

  test('indexedTotalCount re-reads the current definition, not a stale build',
      () async {
    final store = usePlaybackScenarioStore();
    final id = await resetWorkspace();
    await store.addSource(storageId: storageId, path: 'd1', recursive: true);
    await seed('d1', 'a.mp4');
    await seed('d1', 'b.mp4');
    // Media landed in the DB: a scan would bump the per-storage revision, which
    // is what makes the persisted shared order current (mirrors production).
    await store.bumpSourceScanRevision(storages: {storageId});
    // Prime the in-memory build cache so a stale read is actually possible.
    await store.ensureQueueIndex(id);

    expect(await store.indexedTotalCount(), 2);

    // A definition edit with NO explicit ensureQueueIndex in between: the
    // cached in-memory build id is now stale and must not be served.
    await store.addExcludeRule(ScenarioExcludeRule(
      id: 0,
      scenarioId: id,
      kind: ExcludeRuleKind.media,
      storageId: storageId,
      path: 'd1/a.mp4',
    ));

    expect(await store.indexedTotalCount(), 1,
        reason: 'indexedTotalCount must reflect the current definition');
  });
}
