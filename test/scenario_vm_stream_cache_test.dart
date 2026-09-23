import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_excludes_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_explicit_items_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_sources_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_states_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenarios_dao.dart';
import 'package:iris/features/scenario_playback/model/db/repositories/scenario_repository.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_source.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_state.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_source_kind.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_resolver.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_source_provider.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/models/db/app_database.dart';

/// Counts provider traffic so a cache hit is observable as "zero new fetches".
class _SpyFolderProvider implements ScenarioSourceProvider {
  _SpyFolderProvider(this.inner);

  final ScenarioSourceProvider inner;
  int countCalls = 0;
  int fetchCalls = 0;
  final List<int> fetchOffsets = [];

  @override
  ScenarioSourceKind get kind => inner.kind;

  @override
  Future<int> count(ScenarioSource source, MediaNodeRepository nodeRepo) {
    countCalls++;
    return inner.count(source, nodeRepo);
  }

  @override
  Future<List<MediaNode>> fetch(
    ScenarioSource source,
    MediaNodeRepository nodeRepo, {
    required int offset,
    required int count,
    required ScenarioSortField sortField,
    required SortDirection sortDirection,
    required bool sourceInternalFirst,
  }) {
    fetchCalls++;
    fetchOffsets.add(offset);
    return inner.fetch(
      source,
      nodeRepo,
      offset: offset,
      count: count,
      sortField: sortField,
      sortDirection: sortDirection,
      sourceInternalFirst: sourceInternalFirst,
    );
  }
}

VirtualMediaRule _rule({List<String> paths = const ['A']}) => VirtualMediaRule(
      id: 'r1',
      name: 'R',
      matchMode: VmMatchMode.specifiedDirRecursive,
      paths: paths,
      boundary: VmBoundaryMode.ignoreDirs,
      useDurationCap: false,
      useCountCap: true,
      maxItemCount: 10,
      enabled: true,
    );

void main() {
  group('ScenarioResolver VM stream cache', () {
    late AppDatabase db;
    late ScenarioRepository scenarioRepo;
    late _SpyFolderProvider spy;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      scenarioRepo = ScenarioRepository(
        scenariosDao: ScenariosDao(db),
        sourcesDao: ScenarioSourcesDao(db),
        itemsDao: ScenarioExplicitItemsDao(db),
        excludesDao: ScenarioExcludesDao(db),
        statesDao: ScenarioStatesDao(db),
      );
    });

    tearDown(() async {
      await db.close();
    });

    ScenarioResolver buildResolver({
      List<VirtualMediaRule>? rules,
      int maxCachedItems = 5000,
    }) {
      spy = _SpyFolderProvider(
        FolderSourceProvider(scopedMediaTypes: () => null),
      );
      return ScenarioResolver(
        repo: scenarioRepo,
        nodeRepo: MediaNodeRepository(MediaNodesDao(db)),
        scopedMediaTypes: () => null,
        providers: {ScenarioSourceKind.folder: spy},
        vmRulesProvider: () async => rules ?? [_rule()],
        maxCachedItems: maxCachedItems,
      );
    }

    Future<void> seedMedia(
      List<(String storageId, String path)> files, {
      int? durationMs,
    }) async {
      final dao = MediaNodesDao(db);
      for (final (storageId, path) in files) {
        await dao.insertNode(
          MediaNode.file(
            id: path,
            storageId: storageId,
            path: path.split('/'),
            name: path.split('/').last,
            mediaType: MediaType.video,
            durationMs: durationMs,
          ),
        );
      }
    }

    Future<String> scenarioWithAnimeSource({
      PlaybackOrder order = PlaybackOrder.sequential,
      int? seed,
    }) async {
      final scenario = await scenarioRepo.createScenario(name: 'Anime');
      await scenarioRepo.addSource(
        scenarioId: scenario.id,
        storageId: 'st1',
        path: 'A',
        recursive: true,
      );
      if (order != PlaybackOrder.sequential) {
        await scenarioRepo.updateScenario(
          (await scenarioRepo.getScenario(scenario.id))!.copyWith(order: order),
        );
      }
      if (seed != null) {
        await scenarioRepo.updateState(
          ScenarioState(scenarioId: scenario.id, shuffleSeed: seed),
        );
      }
      return scenario.id;
    }

    test('second identical resolvePage serves from cache (no recount/refetch)',
        () async {
      await seedMedia([
        for (var i = 1; i <= 5; i++) ('st1', 'A/ep$i.mp4'),
      ], durationMs: 60000);
      // Non-matching rule keeps `merged == stream` so totalItems is observable.
      final resolver = buildResolver(rules: [_rule(paths: const ['NoMatch'])]);
      final id = await scenarioWithAnimeSource();

      final first =
          await resolver.resolvePage(scenarioId: id, page: 0, pageSize: 10);
      expect(first.totalItems, 5);
      final fetchAfterFirst = spy.fetchCalls;
      final countAfterFirst = spy.countCalls;
      expect(fetchAfterFirst, greaterThan(0));

      final second =
          await resolver.resolvePage(scenarioId: id, page: 0, pageSize: 10);
      expect(spy.fetchCalls, fetchAfterFirst);
      expect(spy.countCalls, countAfterFirst);
      expect(
        second.items.map((e) => e.mediaKey).toList(),
        first.items.map((e) => e.mediaKey).toList(),
      );
    });

    test('playbackVersion bump invalidates the cached stream', () async {
      await seedMedia([
        for (var i = 1; i <= 5; i++) ('st1', 'A/ep$i.mp4'),
      ], durationMs: 60000);
      final resolver = buildResolver();
      final id = await scenarioWithAnimeSource();

      await resolver.resolvePage(
          scenarioId: id, page: 0, pageSize: 10, playbackVersion: 0);
      final before = spy.fetchCalls;

      await resolver.resolvePage(
          scenarioId: id, page: 0, pageSize: 10, playbackVersion: 1);
      expect(spy.fetchCalls, greaterThan(before));

      final afterBump = spy.fetchCalls;
      await resolver.resolvePage(
          scenarioId: id, page: 0, pageSize: 10, playbackVersion: 1);
      expect(spy.fetchCalls, afterBump);
    });

    test('temporary overrides bypass the cache and never evict it', () async {
      await seedMedia([
        for (var i = 1; i <= 5; i++) ('st1', 'A/ep$i.mp4'),
      ], durationMs: 60000);
      final resolver = buildResolver();
      final id = await scenarioWithAnimeSource();

      final baseline =
          await resolver.resolvePage(scenarioId: id, page: 0, pageSize: 10);
      final beforeOverride = spy.fetchCalls;

      await resolver.resolvePage(
        scenarioId: id,
        page: 0,
        pageSize: 10,
        sortField: ScenarioSortField.modifiedAt,
      );
      expect(spy.fetchCalls, greaterThan(beforeOverride));

      final afterOverride = spy.fetchCalls;
      final again =
          await resolver.resolvePage(scenarioId: id, page: 0, pageSize: 10);
      expect(spy.fetchCalls, afterOverride);
      expect(
        again.items.map((e) => e.mediaKey).toList(),
        baseline.items.map((e) => e.mediaKey).toList(),
      );
    });

    test('shuffled full walk fetches each window once, not once per item',
        () async {
      const total = 450;
      await seedMedia([
        for (var i = 0; i < total; i++)
          ('st1', 'A/${i.toString().padLeft(4, '0')}.mp4'),
      ], durationMs: 60000);
      // Non-matching rule keeps `merged == stream` so totalItems stays 450.
      final resolver = buildResolver(rules: [_rule(paths: const ['NoMatch'])]);
      final id = await scenarioWithAnimeSource(
          order: PlaybackOrder.shuffled, seed: 7);

      final page =
          await resolver.resolvePage(scenarioId: id, page: 0, pageSize: 10);
      expect(page.totalItems, total);
      // Window size is 200 → ceil(450/200) == 3 fetches; the pre-fix random
      // access path would fetch ~450 windows.
      expect(spy.fetchCalls, lessThanOrEqualTo(3));
    });

    test('above the memory cap the stream is not cached but stays correct',
        () async {
      await seedMedia([
        for (var i = 1; i <= 5; i++) ('st1', 'A/ep$i.mp4'),
      ], durationMs: 60000);
      final resolver = buildResolver(maxCachedItems: 2);
      final id = await scenarioWithAnimeSource();

      final first =
          await resolver.resolvePage(scenarioId: id, page: 0, pageSize: 10);
      final afterFirst = spy.fetchCalls;

      final second =
          await resolver.resolvePage(scenarioId: id, page: 0, pageSize: 10);
      expect(spy.fetchCalls, greaterThan(afterFirst));
      expect(
        second.items.map((e) => e.mediaKey).toList(),
        first.items.map((e) => e.mediaKey).toList(),
      );
    });
  });
}
