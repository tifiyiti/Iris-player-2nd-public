import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart' as log;
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
import 'package:iris/features/scenario_playback/model/domain/scenario_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_source.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_source_kind.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_resolver.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_source_provider.dart';
import 'package:iris/features/scenario_playback/resolver/shared_base_order.dart';
import 'package:iris/features/scenario_playback/resolver/shared_index_codec.dart';
import 'package:iris/features/scenario_playback/resolver/shared_row_overlay.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/models/db/app_database.dart';

/// The BUILD side of the shared-order index: a scenario the representation can
/// express must get a shared index that reproduces the v43 queue exactly, and
/// one it cannot (placeholder segment, explicit item) must get NONE rather than
/// a wrong one.
void main() {
  group('shared index build (v44)', () {
    late AppDatabase db;
    late ScenarioRepository repo;
    late ScenarioQueueIndexDao indexDao;
    late MediaOrderDao orderDao;
    late ScenarioSharedIndexDao sharedDao;

    const mediaRev = 7;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = ScenarioRepository(
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
        await dao.insertNode(MediaNode.file(
          id: path,
          storageId: 'st1',
          path: path.split('/'),
          name: path.split('/').last,
          mediaType: MediaType.video,
          durationMs: 60000,
        ));
      }
    }

    Future<void> seedSub(int n) async {
      final dao = MediaNodesDao(db);
      for (var i = 0; i < n; i++) {
        final path = 'A/sub/${i.toString().padLeft(4, '0')}.mp4';
        await dao.insertNode(MediaNode.file(
          id: path,
          storageId: 'st1',
          path: path.split('/'),
          name: path.split('/').last,
          mediaType: MediaType.video,
          durationMs: 60000,
        ));
      }
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

    ScenarioResolver buildResolver({
      List<VirtualMediaRule>? rules,
      bool wireShared = true,
      Map<ScenarioSourceKind, ScenarioSourceProvider>? providers,
    }) =>
        ScenarioResolver(
          repo: repo,
          nodeRepo: MediaNodeRepository(MediaNodesDao(db)),
          scopedMediaTypes: () => null,
          providers: providers ??
              {
                ScenarioSourceKind.folder:
                    FolderSourceProvider(scopedMediaTypes: () => null),
              },
          vmRulesProvider: () async => rules ?? const [],
          queueIndexDao: indexDao,
          mediaOrderDao: wireShared ? orderDao : null,
          sharedIndexDao: wireShared ? sharedDao : null,
          mediaRevisionProvider: (_) async => mediaRev,
        );

    Future<String> scenarioWithSource() async {
      final scenario = await repo.createScenario(name: 'Anime');
      await repo.addSource(
        scenarioId: scenario.id,
        storageId: 'st1',
        path: 'A',
        recursive: true,
      );
      return scenario.id;
    }

    /// Decodes the persisted shared index and reconstructs the visible queue.
    Future<({List<QueueEntryRow> rows, SharedRowOverlay overlay})> load(
        int buildId) async {
      final blobs = (await sharedDao.read(buildId))!;
      final slices = <SharedOrderSlice>[];
      for (final s in SharedIndexCodec.decodeSlices(blobs.slices)) {
        final order = await orderDao.read(s.orderKey, mediaRev: s.mediaRev);
        expect(order, isNotNull, reason: 'order ${s.orderKey} must be cached');
        slices.add(
            SharedOrderSlice(orderKey: s.orderKey, order: order!, bits: s.bits));
      }
      final base = SharedBaseOrder(
        slices: slices,
        accepted: SharedIndexCodec.decodeBitmap(blobs.accepted),
      );
      final overlay = SharedRowOverlay(
        baseCount: blobs.baseCount,
        absorbed: SharedIndexCodec.decodeBitmap(blobs.absorbed),
        groupRows: SharedIndexCodec.decodeGroups(blobs.groupRows),
        placeholders: SharedIndexCodec.decodePlaceholders(blobs.placeholders),
        occurrence: SharedIndexCodec.decodeIntMap(blobs.occurrence),
        flags: SharedIndexCodec.decodeIntMap(blobs.flags),
      );
      return (rows: overlay.toEntries(base), overlay: overlay);
    }

    test('a DESC scenario is representable too: the shared order runs the same '
        'direction as the provider', () async {
      // The slice's `record` walks the provider's element order and requires the
      // shared-order position to ascend. A DESC base direction makes the shared
      // order list nodes in DESCENDING position order, so a guard that ignores
      // the direction rejects the SECOND element and silently drops the whole
      // index — turning every DESC scenario into a legacy-walk fallback.
      await seedMedia(10);
      final resolver = buildResolver();
      final id = await scenarioWithSource();
      await repo.updateScenario(
          (await repo.getScenario(id))!.copyWith(sortDirection: SortDirection.desc));

      final buildId = await resolver.buildQueueIndex(id);
      expect(await sharedDao.read(buildId), isNotNull,
          reason: 'a DESC folder source must be representable');

      // …and the index really serves it (the page is the DESC order).
      final page = await resolver.resolvePageIndexed(
          scenarioId: id, page: 0, pageSize: 50);
      expect(page.items.map((e) => e.media.name).toList(), [
        for (var i = 9; i >= 0; i--) '000$i.mp4',
      ]);
    });

    test('a folder-only scenario with VM groups writes a shared index that '
        'describes the queue it serves', () async {
      await seedMedia(40);
      final resolver = buildResolver(rules: [mergeRule()]);
      final id = await scenarioWithSource();
      final buildId = await resolver.buildQueueIndex(id);

      final blobs = await sharedDao.read(buildId);
      expect(blobs, isNotNull,
          reason: 'a folder-only scenario must be representable');
      expect(blobs!.baseCount, await indexDao.visibleBaseCount(id, buildId));

      final loaded = await load(buildId);
      expect(loaded.rows.where((r) => r.isGroup), isNotEmpty);

      // The row space partitions the base slots: one visible row per accepted
      // element, and every remaining rank absorbed into a group row. A row on an
      // absorbed rank (or a slot with no row and no absorption) would be a hole
      // the page windows would silently skip.
      expect(
        loaded.rows.map((r) => r.anchorRank).toList(),
        isNot(isEmpty),
        reason: 'rows must exist',
      );
      expect(
        loaded.rows.map((r) => r.anchorRank).toList(),
        loaded.rows.map((r) => r.anchorRank).toList()..sort(),
        reason: 'rows are enumerated in anchor order',
      );
      expect(loaded.rows.length + loaded.overlay.absorbed.count, blobs.baseCount);

      // The resolver serves exactly those rows: one page slot per row, numbered
      // densely from 0 (the anchors are where the rows are STORED, the numbers
      // are the positions the user reads).
      final page = await resolver.resolvePageIndexed(
          scenarioId: id, page: 0, pageSize: blobs.baseCount);
      expect(page.totalItems, loaded.rows.length);
      expect(page.items, hasLength(loaded.rows.length));
      expect(
        page.items.map((e) => e.virtualIndex).toSet(),
        {for (var i = 0; i < loaded.rows.length; i++) i},
        reason: 'every visible row is served exactly once, in display order',
      );

      // Every group keeps a rule-ordered member list of its chunk's shape, and
      // its anchor is a visible rank.
      final visibleRanks = loaded.rows.map((r) => r.anchorRank).toSet();
      for (final group in loaded.overlay.groupRows) {
        expect(group.members, isNotEmpty);
        expect(group.members.length, lessThanOrEqualTo(mergeRule().maxItemCount));
        expect(visibleRanks, contains(group.anchorRank));
        expect(group.toMemberRows().map((m) => m.mediaNodeId).toList(),
            group.members.toList());
      }
      // The shared order was cached for reuse by the next build.
      expect(await orderDao.count(), 1);
      expect(await orderDao.read(
              (SharedIndexCodec.decodeSlices(blobs.slices)).single.orderKey,
              mediaRev: mediaRev),
          isNotNull);
    });

    test('overlapping sources + exclude are representable and describe the '
        'queue they serve', () async {
      await seedMedia(10);
      await seedSub(4);
      final resolver = buildResolver();
      final id = await scenarioWithSource();
      await repo.addSource(
        scenarioId: id,
        storageId: 'st1',
        path: 'A/sub',
        recursive: true,
      );
      await repo.addExcludeRule(
        scenarioId: id,
        rule: ScenarioExcludeRule(
          id: 0,
          scenarioId: id,
          kind: ExcludeRuleKind.media,
          storageId: 'st1',
          path: 'A/0003.mp4',
        ),
      );
      final buildId = await resolver.buildQueueIndex(id);
      final blobs = await sharedDao.read(buildId);
      expect(blobs, isNotNull);

      final loaded = await load(buildId);
      // The excluded file is not in the slice-selected space at all, and the
      // overlap is accepted twice (the default policy allows duplicates).
      expect(loaded.rows.length + loaded.overlay.absorbed.count, blobs!.baseCount);
      expect(
        loaded.rows.map((r) => r.anchorRank).toList(),
        loaded.rows.map((r) => r.anchorRank).toList()..sort(),
      );
      final page = await resolver.resolvePageIndexed(
          scenarioId: id, page: 0, pageSize: blobs.baseCount);
      expect(page.items.map((e) => e.virtualIndex).toSet(),
          loaded.rows.map((r) => r.anchorRank).toSet());
    });

    test('a provider with a different ORDER is refused by the gate, not '
        'silently reordered', () async {
      await seedMedia(20);
      final id = await scenarioWithSource();
      // Same SET, reversed order within each fetch window. The slice bitmap
      // enumerates positions ascending, so accepting this would silently
      // reorder the base order (wrong page / mis-anchored group).
      final resolver = buildResolver(providers: {
        ScenarioSourceKind.folder: _ReversingFolderProvider(
          FolderSourceProvider(scopedMediaTypes: () => null),
        ),
      });
      final buildId = await resolver.buildQueueIndex(id);

      expect(await sharedDao.read(buildId), isNull,
          reason: 'the ORDER invariant must refuse a reordered provider');
      expect(await indexDao.visibleBaseCount(id, buildId), isNotNull,
          reason: 'the build meta row is still written (the reads degrade)');
    });

    test('a gate refusal reports WHY in the log (no silent degradation)',
        () async {
      // The gate's rejections used to be silent: a large scenario would lose its
      // indexed semantics with no line anywhere naming the invariant that broke.
      // This pins the diagnostic (a reason line), so the field failure class is
      // always explainable.
      await seedMedia(20);
      final id = await scenarioWithSource();
      final resolver = buildResolver(providers: {
        ScenarioSourceKind.folder: _ReversingFolderProvider(
          FolderSourceProvider(scopedMediaTypes: () => null),
        ),
      });

      final records = <log.LogRecord>[];
      log.hierarchicalLoggingEnabled = true;
      final sub =
          log.Logger('log.media_probe').onRecord.listen(records.add);
      addTearDown(sub.cancel);
      log.Logger('log.media_probe').level = log.Level.ALL;

      await resolver.buildQueueIndex(id);

      final line = records
          .map((r) => r.message)
          .where((m) => m.contains('unrepresentable'))
          .join('\n');
      expect(line, isNotEmpty, reason: 'a refusal must always be logged');
      expect(line, contains('reason='), reason: 'the line must name the cause');
      expect(line, contains('provider order != shared order'));
    });

    test('an explicit item is NOT representable: no shared index is persisted',
        () async {
      await seedMedia(5);
      final resolver = buildResolver();
      final id = await scenarioWithSource();
      await repo.addExplicitItem(
        scenarioId: id,
        storageId: 'st1',
        path: 'A/0000.mp4',
      );
      final buildId = await resolver.buildQueueIndex(id);

      expect(await sharedDao.read(buildId), isNull,
          reason: 'the virtual space has an explicit segment');
      expect(await indexDao.visibleBaseCount(id, buildId), isNotNull,
          reason: 'the build meta row is written so the reads can degrade');
    });

    test('an empty source is NOT representable: no shared index', () async {
      await seedMedia(2);
      final resolver = buildResolver();
      final id = await scenarioWithSource();
      await repo.addSource(
        scenarioId: id,
        storageId: 'st1',
        path: 'zz-empty',
        recursive: true,
      );
      final buildId = await resolver.buildQueueIndex(id);
      expect(await sharedDao.read(buildId), isNull,
          reason: 'the virtual space has a placeholder segment');
    });

    test('a stale media revision is not served: the order is rebuilt',
        () async {
      await seedMedia(5);
      final resolver = buildResolver();
      final id = await scenarioWithSource();
      await resolver.buildQueueIndex(id);
      expect(await orderDao.count(), 1);

      final key = (SharedIndexCodec.decodeSlices(
              (await sharedDao.read(await indexDao.currentBuildId(id)))!.slices))
          .single
          .orderKey;
      // A reader keyed on a different revision must see NO order (the guard),
      // never a stale sequence against fresh bitmaps.
      expect(await orderDao.read(key, mediaRev: mediaRev + 1), isNull);
    });

    test('without the shared tables wired only the build meta row is persisted',
        () async {
      await seedMedia(5);
      final resolver = buildResolver(wireShared: false);
      final id = await scenarioWithSource();
      final buildId = await resolver.buildQueueIndex(id);
      expect(await sharedDao.read(buildId), isNull);
      expect(await orderDao.count(), 0);
      expect(await indexDao.visibleBaseCount(id, buildId), isNotNull);
    });

    test('rebuilding evicts the previous shared index, never stacking one',
        () async {
      await seedMedia(5);
      final resolver = buildResolver();
      final id = await scenarioWithSource();
      final first = await resolver.buildQueueIndex(id);
      final second = await resolver.buildQueueIndex(id);
      expect(second, isNot(first));
      // Rebuilding evicted the previous generation; its shared index must not
      // accumulate.
      expect(await sharedDao.read(first), isNull);
      expect(await sharedDao.read(second), isNotNull);
      expect(await sharedDao.count(), 1);
    });
  });
}

/// A folder provider that returns each fetch window REVERSED: the same set in a
/// different order. Only a test seam — it exists to prove the shared index's
/// gate rejects a reordered provider (see the ORDER invariant in
/// `_SharedIndexDraft.record`) instead of silently reordering the base order.
class _ReversingFolderProvider implements ScenarioSourceProvider {
  const _ReversingFolderProvider(this._inner);

  final ScenarioSourceProvider _inner;

  @override
  ScenarioSourceKind get kind => _inner.kind;

  @override
  Future<int> count(ScenarioSource source, MediaNodeRepository nodeRepo) =>
      _inner.count(source, nodeRepo);

  @override
  Future<List<MediaNode>> fetch(
    ScenarioSource source,
    MediaNodeRepository nodeRepo, {
    required int offset,
    required int count,
    required ScenarioSortField sortField,
    required SortDirection sortDirection,
    required bool sourceInternalFirst,
  }) async {
    final items = await _inner.fetch(
      source,
      nodeRepo,
      offset: offset,
      count: count,
      sortField: sortField,
      sortDirection: sortDirection,
      sourceInternalFirst: sourceInternalFirst,
    );
    return items.reversed.toList();
  }
}
