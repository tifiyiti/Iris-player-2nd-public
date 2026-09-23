import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/model/db/dao/for_page/media_node_page_query.dart';
import 'package:iris/models/db/app_database.dart';

/// NULLS-LAST contract for probe-able sort fields.
///
/// Files without probed info (duration / resolution) must always sort
/// AFTER files with info — regardless of asc/desc direction. This is the
/// scan-probe UX promise made in the scan options dialog.
void main() {
  late AppDatabase db;
  late MediaNodesDao dao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = MediaNodesDao(db);
    await dao.insertNode(MediaNode.file(
      id: 'st1:/a.mp4', storageId: 'st1', path: const ['a.mp4'],
      parentPath: null, pathDepth: 1, name: 'a.mp4',
      mediaType: MediaType.video,
      // no duration, no resolution → unprobed
    ));
    await dao.insertNode(MediaNode.file(
      id: 'st1:/b.mp4', storageId: 'st1', path: const ['b.mp4'],
      parentPath: null, pathDepth: 1, name: 'b.mp4',
      mediaType: MediaType.video,
      durationMs: 1000, width: 640, height: 360,
    ));
    await dao.insertNode(MediaNode.file(
      id: 'st1:/c.mp4', storageId: 'st1', path: const ['c.mp4'],
      parentPath: null, pathDepth: 1, name: 'c.mp4',
      mediaType: MediaType.video,
      durationMs: 3000, width: 1920, height: 1080,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> names(MediaSortField field, SortDirection dir) async {
    final page = await dao.getPagedNodes(MediaNodePageQuery(
      page: 1,
      pageSize: 10,
      sortField: field,
      sortDirection: dir,
      nodeKind: MediaNodeKind.file,
    ));
    return page.items.map((n) => n.name).toList();
  }

  test('durationMs asc puts unprobed last', () async {
    expect(await names(MediaSortField.durationMs, SortDirection.asc),
        ['b.mp4', 'c.mp4', 'a.mp4']);
  });

  test('durationMs desc also puts unprobed last', () async {
    expect(await names(MediaSortField.durationMs, SortDirection.desc),
        ['c.mp4', 'b.mp4', 'a.mp4']);
  });

  test('pixelCount asc puts unprobed last', () async {
    expect(await names(MediaSortField.pixelCount, SortDirection.asc),
        ['b.mp4', 'c.mp4', 'a.mp4']);
  });

  test('pixelCount desc also puts unprobed last', () async {
    expect(await names(MediaSortField.pixelCount, SortDirection.desc),
        ['c.mp4', 'b.mp4', 'a.mp4']);
  });
}
