import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/for_page/media_node_page_query.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/db/adapters/int32_blob_codec.dart';
import 'package:iris/features/scenario_playback/model/db/dao/media_order_dao.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/scenario_playback/resolver/shared_media_order.dart';
import 'package:iris/models/db/app_database.dart';

/// The shared order is the storage primitive of the shared-order index: a
/// scenario's base order must be a FILTERED SUBSEQUENCE of it. So the order is
/// checked against the provider's own query (it is built through it), and then
/// against the provider's path-scoped listings (the filtering promise).
void main() {
  late AppDatabase db;
  late MediaNodesDao nodesDao;
  late MediaNodeRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    nodesDao = MediaNodesDao(db);
    repo = MediaNodeRepository(nodesDao);
  });
  tearDown(() => db.close());

  Future<void> seed() async {
    // Names deliberately scrambled vs insertion order, and a NULL duration so
    // the NULLs-last rule is exercised.
    const files = <(String, int?)>[
      ('A/x.mp4', 300),
      ('A/y.mp4', 100),
      ('A/z.mp4', null),
      ('A/sub/p.mp4', 200),
      ('A/sub/q.mp4', 50),
      ('B/m.mp4', 400),
      ('B/n.mp4', 150),
    ];
    for (final (path, durationMs) in files) {
      await nodesDao.insertNode(MediaNode.file(
        id: path,
        storageId: 'st1',
        path: path.split('/'),
        name: path.split('/').last,
        mediaType: MediaType.video,
        durationMs: durationMs,
      ));
    }
  }

  const mediaTypes = <MediaType>[MediaType.video, MediaType.audio];

  /// The provider's own ordered listing for a (path, recursive) query, paged in
  /// small windows so the shared order must survive real pagination.
  Future<List<int>> providerListing({
    String? parentPath,
    bool recursive = true,
    bool matchAllInStorage = false,
    required ScenarioSortField sortField,
    required SortDirection dir,
    required bool pathGroupFirst,
  }) async {
    final ids = <int>[];
    var page = 1;
    while (true) {
      final result = await repo.getPagedNodes(MediaNodePageQuery(
        page: page,
        pageSize: 3,
        storageId: 'st1',
        parentPath: parentPath,
        nodeKind: MediaNodeKind.file,
        mediaTypes: mediaTypes,
        matchAllInStorage: matchAllInStorage,
        recursive: recursive,
        sortField: sortField.toMediaSortField(),
        sortDirection: dir,
        pathGroupFirst: pathGroupFirst,
        countTotal: false,
      ));
      if (result.items.isEmpty) break;
      ids.addAll(result.items.map((n) => int.parse(n.id)));
      if (result.items.length < 3) break;
      page++;
    }
    return ids;
  }

  Future<({Map<int, String> path, Map<int, String?> parent})> identity() async {
    final rows = await db
        .customSelect('SELECT id, path, parent_path FROM media_nodes')
        .get();
    return (
      path: {for (final r in rows) r.read<int>('id'): r.read<String>('path')},
      parent: {
        for (final r in rows) r.read<int>('id'): r.read<String?>('parent_path')
      },
    );
  }

  test('shared order equals the provider whole-storage listing', () async {
    await seed();
    for (final sortField in ScenarioSortField.values) {
      for (final dir in SortDirection.values) {
        for (final pgf in const [false, true]) {
          final shared = await SharedMediaOrder.build(
            repo,
            storageId: 'st1',
            sortField: sortField,
            sortDirection: dir,
            pathGroupFirst: pgf,
            mediaTypes: mediaTypes,
            chunk: 2,
          );
          final provider = await providerListing(
            matchAllInStorage: true,
            sortField: sortField,
            dir: dir,
            pathGroupFirst: pgf,
          );
          expect(shared, provider,
              reason: '$sortField/$dir/pgf=$pgf must match the provider');
        }
      }
    }
  });

  test('a path source is a filtered subsequence of the shared order', () async {
    await seed();
    final ids = await identity();
    for (final sortField in ScenarioSortField.values) {
      for (final dir in SortDirection.values) {
        for (final pgf in const [false, true]) {
          final shared = (await SharedMediaOrder.build(
            repo,
            storageId: 'st1',
            sortField: sortField,
            sortDirection: dir,
            pathGroupFirst: pgf,
            mediaTypes: mediaTypes,
            chunk: 2,
          ))
              .toList();

          // Recursive folder source rooted at 'A'.
          final recursive = shared
              .where((id) =>
                  ids.path[id] == 'A' || ids.path[id]!.startsWith('A/'))
              .toList();
          expect(
            recursive,
            await providerListing(
              parentPath: 'A',
              recursive: true,
              sortField: sortField,
              dir: dir,
              pathGroupFirst: pgf,
            ),
            reason: 'recursive A ($sortField/$dir/pgf=$pgf)',
          );

          // Non-recursive folder source: direct children of 'A' only.
          final direct =
              shared.where((id) => ids.parent[id] == 'A').toList();
          expect(
            direct,
            await providerListing(
              parentPath: 'A',
              recursive: false,
              sortField: sortField,
              dir: dir,
              pathGroupFirst: pgf,
            ),
            reason: 'direct children of A ($sortField/$dir/pgf=$pgf)',
          );
        }
      }
    }
  });

  test('orderKey distinguishes every input that changes the sequence', () {
    String key({
      String storage = 'st1',
      ScenarioSortField sortField = ScenarioSortField.name,
      SortDirection dir = SortDirection.asc,
      bool pgf = false,
      List<MediaType> types = const [MediaType.video, MediaType.audio],
    }) =>
        SharedMediaOrder.orderKey(
          storageId: storage,
          sortField: sortField,
          sortDirection: dir,
          pathGroupFirst: pgf,
          mediaTypes: types,
        );

    final base = key();
    expect(key(storage: 'st2'), isNot(base));
    expect(key(sortField: ScenarioSortField.durationMs), isNot(base));
    expect(key(dir: SortDirection.desc), isNot(base));
    expect(key(pgf: true), isNot(base));
    expect(key(types: const [MediaType.video]), isNot(base));
    // Media-type order must not matter (it is a set).
    expect(
      key(types: const [MediaType.audio, MediaType.video]),
      base,
    );
  });

  test('Int32BlobCodec round-trips (including negatives)', () {
    final values = Int32List.fromList([0, 1, -1, 2147483647, -2147483648, 42]);
    final bytes = Int32BlobCodec.encode(values);
    expect(bytes.length, values.length * 4);
    expect(Int32BlobCodec.decode(bytes), values);
    expect(Int32BlobCodec.decode(Uint8List(0)), isEmpty);
  });

  test('MediaOrderDao stores, reads and revision-guards an order', () async {
    final dao = MediaOrderDao(db);
    final ids = Int32List.fromList([5, 3, 9]);

    expect(await dao.read('k', mediaRev: 7), isNull);
    await dao.write('k', mediaRev: 7, ids: ids);
    expect(await dao.count(), 1);
    expect(await dao.read('k', mediaRev: 7), ids);
    // A stale revision must look absent so the caller rebuilds.
    expect(await dao.read('k', mediaRev: 8), isNull);

    await dao.write('k', mediaRev: 8, ids: Int32List.fromList([1]));
    expect(await dao.read('k', mediaRev: 8), Int32List.fromList([1]));
    expect(await dao.read('k', mediaRev: 7), isNull);

    await dao.deleteOrder('k');
    expect(await dao.read('k', mediaRev: 8), isNull);
    await dao.write('a', mediaRev: 1, ids: Int32List.fromList([1]));
    await dao.write('b', mediaRev: 1, ids: Int32List.fromList([2]));
    await dao.clearAll();
    expect(await dao.count(), 0);
  });
}
