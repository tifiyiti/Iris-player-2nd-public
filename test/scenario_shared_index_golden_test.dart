import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
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
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_resolver.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_members_dao.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/models/db/app_database.dart';

/// FROZEN reference for every INDEX-BACKED read path.
///
/// This is the harness ⑥ needs: the `shared == v43` parity tests used the v43 rows
/// as their oracle and ⑥ retires them, so the reference had to be recorded BEFORE
/// the v43 writes stopped — hence the goldens below were frozen while the two
/// representations still agreed item for item.
///
/// Freezing now asserts that every index-backed read is really served by the
/// shared index (`_assertIndexServed`): a golden must never be recorded from a
/// degraded state, where the tag view / counts / search would freeze as EMPTY.
///
///   `$env:IRIS_FREEZE_GOLDEN='1'; flutter test test/scenario_shared_index_golden_test.dart`
///
/// The fixtures deliberately cover the dimensions ⑥ could silently break: page
/// sweep + item identity/ranks/occurrences, the shuffle view, VM-merged rows,
/// the tag view, the tag∩scenario counts, and the VM search hits.
void main() {
  final freeze = Platform.environment['IRIS_FREEZE_GOLDEN'] == '1';

  for (final fixture in _fixtures) {
    test('golden: ${fixture.name}', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final nodesDao = MediaNodesDao(db);
      final nodeRepo = MediaNodeRepository(nodesDao);
      final repo = ScenarioRepository(
        scenariosDao: ScenariosDao(db),
        sourcesDao: ScenarioSourcesDao(db),
        itemsDao: ScenarioExplicitItemsDao(db),
        excludesDao: ScenarioExcludesDao(db),
        statesDao: ScenarioStatesDao(db),
      );
      final indexDao = ScenarioQueueIndexDao(db);
      final orderDao = MediaOrderDao(db);
      final sharedDao = ScenarioSharedIndexDao(db);
      final membersDao = VideoTagMembersDao(db);

      for (final file in fixture.files) {
        await nodesDao.insertNode(MediaNode.file(
          id: file,
          storageId: 'st1',
          path: file.split('/'),
          name: file.split('/').last,
          mediaType: MediaType.video,
          durationMs: 60000,
        ));
      }

      final scenario = await repo.createScenario(name: 'S');
      if (fixture.baseDirection != null) {
        // The persisted base order's direction is part of the DEFINITION, so it
        // has to be set before the build (unlike the read-time view).
        await repo.updateScenario(scenario.copyWith(
          sortDirection: fixture.baseDirection!,
        ));
      }
      for (final source in fixture.sources) {
        await repo.addSource(
          scenarioId: scenario.id,
          storageId: 'st1',
          path: source.path,
          recursive: source.recursive,
        );
      }
      for (final path in fixture.excludes) {
        await repo.addExcludeRule(
          scenarioId: scenario.id,
          rule: ScenarioExcludeRule(
            id: 0,
            scenarioId: scenario.id,
            kind: ExcludeRuleKind.media,
            storageId: 'st1',
            path: path,
          ),
        );
      }
      for (final path in fixture.tagMembers) {
        await membersDao.addMember(
          tagId: 1,
          storageId: 'st1',
          canonicalPath: path,
          addedAt: DateTime.now(),
        );
      }

      ScenarioResolver resolver({required bool shared}) => ScenarioResolver(
            repo: repo,
            nodeRepo: nodeRepo,
            scopedMediaTypes: () => null,
            vmRulesProvider: () async => fixture.maxItemCount == 0
                ? const <VirtualMediaRule>[]
                : [
                    VirtualMediaRule(
                      id: _ruleId,
                      name: 'R',
                      matchMode: VmMatchMode.specifiedDirRecursive,
                      paths: const ['A'],
                      boundary: VmBoundaryMode.sameDirOnly,
                      useDurationCap: false,
                      useCountCap: true,
                      maxItemCount: fixture.maxItemCount,
                      enabled: true,
                    ),
                  ],
            queueIndexDao: indexDao,
            mediaOrderDao: orderDao,
            sharedIndexDao: sharedDao,
            mediaRevisionProvider: (_) async => 0,
            tagMemberNodeIds: (tagId, addedAfter) =>
                membersDao.memberNodeIds(tagId, addedAfter: addedAfter),
            tagMembersByTag: (addedAfter) =>
                membersDao.memberNodeIdsByTag(addedAfter: addedAfter),
            useSharedIndexRead: shared,
          );

      // The build must produce BOTH representations; without the shared row every
      // comparison below would pass by silently falling back to v43.
      await resolver(shared: true).buildQueueIndex(scenario.id);
      final buildId = await indexDao.currentBuildId(scenario.id);
      expect(await sharedDao.read(buildId) != null, isTrue,
          reason: 'the fixture must be representable');

      if (freeze) {
        await _assertIndexServed(
            resolver(shared: true), scenario.id, buildId, fixture);
      }

      final lines = <String>[];
      await _trace(lines, resolver(shared: true), scenario.id, fixture);
      final text = '${lines.join('\n')}\n';
      final file = File(_goldenPath(fixture.name));
      if (freeze) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(text);
      } else {
        if (!file.existsSync()) {
          fail('missing golden ${file.path} — run with IRIS_FREEZE_GOLDEN=1');
        }
        expect(text, file.readAsStringSync(), reason: 'golden drift');
      }
    });
  }
}

const String _ruleId = '00000000-0000-4000-8000-000000000000';
const int _pageSize = 4;

/// Asserts every index-backed read is ACTUALLY served by the shared index, so a
/// golden can never be recorded from a silently DEGRADED state.
///
/// The old precondition was `shared == v43`, and the v43 rows are retired, so what
/// has to hold instead is that the read paths really resolve from the shared
/// index rather than falling back to the walk. The hole this closes is concrete:
/// `_trace` writes `view=${(view ?? const [])…}`, an empty `counts=` and no `hit`
/// lines, so a declined tag view / count / search would be frozen as if an empty
/// result were the contract.
///
/// `indexedTotalCount` is the canary: it goes through the same decode + order
/// lookup every other index-backed path does, so a null there means they are all
/// degrading.
Future<void> _assertIndexServed(
  ScenarioResolver resolver,
  String scenarioId,
  int buildId,
  _Fixture fixture,
) async {
  final indexedTotal = await resolver.indexedTotalCount(buildId);
  expect(indexedTotal, isNotNull,
      reason: 'freeze: the shared index must decode and resolve its orders');

  final probe = await resolver.resolvePageIndexed(
      scenarioId: scenarioId,
      page: 0,
      pageSize: _pageSize,
      order: fixture.order,
      shuffleSeed: fixture.seed,
      sortDirection: fixture.readDirection);
  expect(probe.totalItems, indexedTotal,
      reason: 'freeze: the page total must be the index total');

  if (probe.totalItems > 0) {
    final first = await resolver.resolveItemAtIndex(scenarioId, 0,
        order: fixture.order,
        shuffleSeed: fixture.seed,
        sortDirection: fixture.readDirection);
    expect(first, isNotNull, reason: 'freeze: the seek must be served');
    expect(
      await resolver.resolveItemByOccurrenceFor(
          scenarioId: scenarioId, occurrence: first!.occurrenceId),
      isNotNull,
      reason: 'freeze: occurrence recovery must be served',
    );
  }

  expect(await resolver.resolveTagViewIndexed(scenarioId: scenarioId, tagId: 1),
      isNotNull,
      reason: 'freeze: the tag view must come from the shared index');
  expect(await resolver.tagIntersectionCountsFor(scenarioId), isNotNull,
      reason: 'freeze: the tag counts must come from the shared index');
  expect(await resolver.searchVmGroupsIndexed(scenarioId), isNotNull,
      reason: 'freeze: the VM search must come from the shared index');
}

/// Records every index-backed read for one fixture.
Future<void> _trace(
  List<String> out,
  ScenarioResolver res,
  String scenarioId,
  _Fixture fixture,
) async {
  Future<ScenarioResolvePage> page(int p) => res.resolvePageIndexed(
      scenarioId: scenarioId,
      page: p,
      pageSize: _pageSize,
      order: fixture.order,
      shuffleSeed: fixture.seed,
      sortDirection: fixture.readDirection);

  out.add('== pages');
  final probe = await page(0);
  out.add('total=${probe.totalItems}');
  final pages = (probe.totalItems / _pageSize).ceil().clamp(1, 60);
  for (var p = 0; p < pages; p++) {
    for (final item in (await page(p)).items) {
      out.add('p$p ${_itemLine(item)}');
    }
  }

  out.add('== ordinals');
  for (var i = 0; i < probe.totalItems; i++) {
    final item = await res.resolveItemAtIndex(scenarioId, i,
        order: fixture.order,
        shuffleSeed: fixture.seed,
        sortDirection: fixture.readDirection);
    out.add('i=$i ${item == null ? 'null' : _itemLine(item)}');
  }

  out.add('== occurrences');
  for (var i = 0; i < probe.totalItems; i++) {
    final item = await res.resolveItemAtIndex(scenarioId, i,
        order: fixture.order,
        shuffleSeed: fixture.seed,
        sortDirection: fixture.readDirection);
    if (item == null) continue;
    final byOccurrence = await res.resolveItemByOccurrenceFor(
        scenarioId: scenarioId,
        occurrence: item.occurrenceId,
        order: fixture.order,
        shuffleSeed: fixture.seed,
        sortDirection: fixture.readDirection);
    out.add('o=$i ${byOccurrence?.media.name ?? 'null'}|v=${byOccurrence?.virtualIndex}');
  }

  out.add('== tag');
  final view = await res.resolveTagViewIndexed(scenarioId: scenarioId, tagId: 1);
  out.add('view=${(view ?? const []).map((e) => e.media.name).join(',')}');
  final counts = await res.tagIntersectionCountsFor(scenarioId);
  final sorted = (counts ?? const <int, int>{}).entries
      .map((e) => '${e.key}:${e.value}')
      .toList()
    ..sort();
  out.add('counts=${sorted.join(',')}');

  out.add('== search');
  final hits =
      await res.searchVmGroupsIndexed(scenarioId) ?? const <VmSearchGroupHit>[];
  for (final hit in hits) {
    out.add('hit ${hit.scopeKey}|${hit.title}|segs=${hit.segmentCount}'
        '|ms=${hit.totalDurationMs}|${hit.path}|o=${hit.occurrenceIndex}');
  }
}

String _itemLine(EffectivePlaybackItem item) =>
    '${item.media.name}|v=${item.virtualIndex}'
    '|o=${item.occurrenceId.occurrenceIndex}'
    '|m=${item.virtualMerged}|segs=${item.vmSegmentCount}'
    '|ms=${item.vmTotalDurationMs}|x=${item.explicit}'
    '|d=${item.duplicated}|a=${item.available}'
    '|org=${item.origins.map((o) => o.sourceId).join(',')}';

String _goldenPath(String name) =>
    'test/helpers/golden/shared_index/$name.txt';

class _Fixture {
  const _Fixture({
    required this.name,
    required this.files,
    required this.sources,
    this.excludes = const [],
    this.maxItemCount = 0,
    this.order,
    this.seed,
    this.baseDirection,
    this.readDirection,
    this.tagMembers = const [],
  });

  final String name;
  final List<String> files;
  final List<({String path, bool recursive})> sources;
  final List<String> excludes;
  final int maxItemCount;
  final PlaybackOrder? order;
  final int? seed;

  /// Direction of the PERSISTED base order (shapes the slices + accepted
  /// bitmap), applied to the scenario before the build.
  final SortDirection? baseDirection;

  /// Read-time direction view. Only a SHUFFLED view honours it (it rotates the
  /// permutation); a non-shuffled queue has its direction baked into the base
  /// order at build time, so setting this there would be a silent no-op.
  final SortDirection? readDirection;
  final List<String> tagMembers;
}

final _fixtures = <_Fixture>[
  _Fixture(
    name: 'plain_folder_asc',
    files: [for (var i = 0; i < 6; i++) 'A/000$i.mp4'],
    sources: const [(path: 'A', recursive: true)],
  ),
  _Fixture(
    name: 'shuffled_overlapping_sources',
    files: [
      for (var i = 0; i < 6; i++) 'A/000$i.mp4',
      for (var i = 0; i < 3; i++) 'A/sub/000$i.mp4',
    ],
    sources: const [
      (path: 'A', recursive: true),
      (path: 'A/sub', recursive: true),
    ],
    excludes: const ['A/0003.mp4'],
    order: PlaybackOrder.shuffled,
    seed: 7,
    // Honoured for a shuffled view: it rotates the permutation.
    readDirection: SortDirection.desc,
  ),
  _Fixture(
    name: 'vm_groups_merged_desc_base',
    files: [for (var i = 0; i < 9; i++) 'A/000$i.mp4'],
    sources: const [(path: 'A', recursive: true)],
    maxItemCount: 3,
    baseDirection: SortDirection.desc,
    tagMembers: const ['A/0001.mp4', 'A/0004.mp4'],
  ),
];
