import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/db/dao/media_order_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_excludes_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_explicit_items_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_queue_index_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_shared_index_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_sources_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_states_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenarios_dao.dart';
import 'package:iris/features/scenario_playback/model/db/repositories/scenario_repository.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_source_kind.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_resolver.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_source_provider.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/models/db/app_database.dart';

/// The derived index is a cache: a rebuild must not keep the generation it
/// replaced, and deleting a scenario must drop its rows rather than leave them
/// for nobody to read or evict.
///
/// The shared index is the scenario's ONLY persisted representation, so the
/// storage-growth guard is about ITS rows: one blob per live build, never one per
/// rebuild.
void main() {
  late AppDatabase db;
  late ScenarioRepository scenarioRepo;
  late ScenarioQueueIndexDao indexDao;
  late MediaOrderDao orderDao;
  late ScenarioSharedIndexDao sharedDao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    scenarioRepo = ScenarioRepository(
      scenariosDao: ScenariosDao(db),
      sourcesDao: ScenarioSourcesDao(db),
      itemsDao: ScenarioExplicitItemsDao(db),
      excludesDao: ScenarioExcludesDao(db),
      statesDao: ScenarioStatesDao(db),
    );
    indexDao = ScenarioQueueIndexDao(db);
    orderDao = MediaOrderDao(db);
    sharedDao = ScenarioSharedIndexDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedMedia(int n) async {
    final dao = MediaNodesDao(db);
    for (var i = 0; i < n; i++) {
      final path = 'A/${i.toString().padLeft(4, '0')}.mp4';
      await dao.insertNode(
        MediaNode.file(
          id: path,
          storageId: 'st1',
          path: path.split('/'),
          name: path.split('/').last,
          mediaType: MediaType.video,
          durationMs: 60000,
        ),
      );
    }
  }

  Future<int> rowCount(String table) async {
    final row = await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle();
    return row.read<int>('c');
  }

  VirtualMediaRule mergeRule({int maxItemCount = 3}) => VirtualMediaRule(
        id: 'r1',
        name: 'R',
        matchMode: VmMatchMode.specifiedDirRecursive,
        paths: const ['A'],
        boundary: VmBoundaryMode.sameDirOnly,
        useDurationCap: false,
        useCountCap: true,
        maxItemCount: maxItemCount,
        enabled: true,
      );

  ScenarioResolver buildResolver() => ScenarioResolver(
        repo: scenarioRepo,
        nodeRepo: MediaNodeRepository(MediaNodesDao(db)),
        scopedMediaTypes: () => null,
        providers: {
          ScenarioSourceKind.folder:
              FolderSourceProvider(scopedMediaTypes: () => null),
        },
        vmRulesProvider: () async => [mergeRule()],
        queueIndexDao: indexDao,
        mediaOrderDao: orderDao,
        sharedIndexDao: sharedDao,
        mediaRevisionProvider: (_) async => 0,
      );

  Future<String> scenarioWithSource() async {
    final scenario = await scenarioRepo.createScenario(name: 'Anime');
    await scenarioRepo.addSource(
      scenarioId: scenario.id,
      storageId: 'st1',
      path: 'A',
      recursive: true,
    );
    return scenario.id;
  }

  test('a rebuild replaces the shared index generation instead of stacking one',
      () async {
    await seedMedia(6);
    final resolver = buildResolver();
    final id = await scenarioWithSource();

    await resolver.buildQueueIndex(id);
    expect(await rowCount('scenario_shared_index'), 1);

    await resolver.buildQueueIndex(id);

    // The evicted generation's blob is gone: one row, not one per rebuild.
    expect(await rowCount('scenario_shared_index'), 1);
    // Nothing outside the live generation survives.
    expect(
      await rowCount(
          'scenario_shared_index WHERE build_id NOT IN (SELECT build_id FROM scenario_queue_builds)'),
      0,
    );
  });

  test('deleting a scenario drops its derived index', () async {
    await seedMedia(6);
    final resolver = buildResolver();
    final id = await scenarioWithSource();
    await resolver.buildQueueIndex(id);
    expect(await rowCount('scenario_shared_index'), greaterThan(0));
    expect(await rowCount('scenario_queue_builds'), greaterThan(0));

    expect(await scenarioRepo.deleteScenario(id), isTrue);

    expect(await rowCount('scenario_shared_index'), 0);
    expect(await rowCount('scenario_queue_builds'), 0);
  });
}
