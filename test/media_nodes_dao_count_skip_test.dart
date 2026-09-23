import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/for_page/media_node_page_query.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/db/app_database.dart';

/// Window-fetch contract: when the caller already knows the total (scenario
/// source segments count once via `provider.count`), the per-window fetch must
/// be able to skip the redundant `COUNT(*)` without changing the returned rows.
void main() {
  late AppDatabase db;
  late MediaNodesDao dao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = MediaNodesDao(db);
    for (var i = 1; i <= 12; i++) {
      final name = 'v${i.toString().padLeft(2, '0')}.mp4';
      await dao.insertNode(MediaNode.file(
        id: 'st1:A/$name',
        storageId: 'st1',
        path: ['A', name],
        parentPath: 'A',
        pathDepth: 2,
        name: name,
        mediaType: MediaType.video,
      ));
    }
  });

  tearDown(() async {
    await db.close();
  });

  MediaNodePageQuery query({required bool countTotal}) => MediaNodePageQuery(
        page: 1,
        pageSize: 5,
        storageId: 'st1',
        parentPath: 'A',
        recursive: true,
        nodeKind: MediaNodeKind.file,
        mediaTypes: const [MediaType.video, MediaType.audio],
        sortField: MediaSortField.name,
        sortDirection: SortDirection.asc,
        countTotal: countTotal,
      );

  test('countTotal:false returns the same window rows as countTotal:true',
      () async {
    final withCount = await dao.getPagedNodes(query(countTotal: true));
    final withoutCount = await dao.getPagedNodes(query(countTotal: false));

    expect(withoutCount.items.map((e) => e.name),
        withCount.items.map((e) => e.name));
    expect(withoutCount.items, hasLength(5));
  });

  test('countTotal:true reports the real total', () async {
    final withCount = await dao.getPagedNodes(query(countTotal: true));
    expect(withCount.totalItems, 12);
    expect(withCount.totalPages, 3);
  });

  test('countTotal:false marks the total as unknown (-1)', () async {
    final withoutCount = await dao.getPagedNodes(query(countTotal: false));
    expect(withoutCount.totalItems, -1);
    expect(withoutCount.totalPages, -1);
  });
}
