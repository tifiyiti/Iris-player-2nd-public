import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/scenario_playback/playback/scenario_playback_provider.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';

/// Locate-path contract: recovering the current item's effective index must
/// NOT re-resolve the item by walking the whole occurrence stream. The
/// persisted occurrence id + `currentVirtualPos` hint are sufficient; a store
/// whose [PlaybackScenarioStore.getCurrentItem] throws proves the dependency is
/// gone.
class _NoWalkStore extends PlaybackScenarioStore {
  @override
  Future<EffectivePlaybackItem?> getCurrentItem() async {
    throw StateError(
        'getCurrentItem (full occurrence walk) must not run in the locate path');
  }
}

void main() {
  late AppDatabase db;
  late _NoWalkStore store;
  late ScenarioPlaybackProvider provider;

  setUpAll(() {
    db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    await db.customStatement('DELETE FROM media_nodes');
    await db.customStatement('DELETE FROM scenario');
    await db.customStatement('DELETE FROM scenario_sources');
    await db.customStatement('DELETE FROM scenario_explicit_items');
    await db.customStatement('DELETE FROM scenario_excludes');
    await db.customStatement('DELETE FROM scenario_state');
    store = _NoWalkStore();
    await store.initialized;
    provider = ScenarioPlaybackProvider(store: store);
  });

  tearDown(() async {
    await store.dispose();
  });

  Future<void> seedMedia(List<(String storageId, String path)> files) async {
    final dao = MediaNodesDao(db);
    for (final (storageId, path) in files) {
      await dao.insertNode(
        MediaNode.file(
          id: path,
          storageId: storageId,
          path: path.split('/'),
          name: path.split('/').last,
          mediaType: MediaType.video,
        ),
      );
    }
  }

  Future<String> newScenario() async {
    final s = await DbModule.scenarioRepo.createScenario(name: 'S');
    await store.setActiveScenario(s.id);
    return s.id;
  }

  test('establishCurrentPosition resolves via the persisted hint without a '
      'full occurrence walk', () async {
    await seedMedia([
      ('st1', 'A/ep01.mp4'),
      ('st1', 'A/ep02.mp4'),
      ('st1', 'A/ep03.mp4'),
    ]);
    final id = await newScenario();
    await DbModule.scenarioRepo.addSource(
        scenarioId: id, storageId: 'st1', path: 'A', recursive: true);

    await store.setCurrentItem(
      occurrence:
          const PlaybackOccurrenceId(storageId: 'st1', path: 'A/ep02.mp4'),
      virtualPos: 1,
    );

    expect(await provider.establishCurrentPosition(), 1);
    expect((await store.getState(id))?.currentVirtualPos, 1);
  });

  test('next/previous work without a full occurrence walk', () async {
    await seedMedia([
      ('st1', 'A/ep01.mp4'),
      ('st1', 'A/ep02.mp4'),
      ('st1', 'A/ep03.mp4'),
    ]);
    final id = await newScenario();
    await DbModule.scenarioRepo.addSource(
        scenarioId: id, storageId: 'st1', path: 'A', recursive: true);

    await store.setCurrentItem(
      occurrence:
          const PlaybackOccurrenceId(storageId: 'st1', path: 'A/ep02.mp4'),
      virtualPos: 1,
    );

    expect((await provider.next())?.path, 'A/ep03.mp4');
    expect((await provider.previous())?.path, 'A/ep02.mp4');
  });
}
