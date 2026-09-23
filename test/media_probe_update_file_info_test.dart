import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/db/app_database.dart';

/// Contract for the deep-probe write path (`updateFileMediaInfo`).
///
/// - Only explicitly provided fields are written; everything else on the
///   row is preserved.
/// - The repository variant repairs `totalDurationMs` up the ancestor
///   chain when a duration is written (mirrors [updateFileDuration]).
void main() {
  late AppDatabase db;
  late MediaNodesDao dao;
  late MediaNodeRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = MediaNodesDao(db);
    repo = MediaNodeRepository(dao);
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertFile(String path) async {
    final segments = path.split('/');
    await dao.insertNode(MediaNode.file(
      id: 'st1:$path',
      storageId: 'st1',
      path: segments,
      parentPath: segments.length == 1 ? null : segments.sublist(0, segments.length - 1).join('/'),
      pathDepth: segments.length,
      name: segments.last,
      mediaType: MediaType.video,
    ));
  }

  Future<Object?> readColumn(String column, String path) async {
    final row = await db.customSelect(
      'SELECT $column FROM media_nodes WHERE storage_id = ? AND path = ?',
      variables: [Variable.withString('st1'), Variable.withString(path)],
    ).getSingle();
    return row.data[column];
  }

  test('dao writes only the provided probe fields', () async {
    await insertFile('a.mp4');

    await dao.updateFileMediaInfo(
      storageId: 'st1',
      path: 'a.mp4',
      width: 1920,
      height: 1080,
      pixelCount: 2073600,
    );

    expect(await readColumn('width', 'a.mp4'), 1920);
    expect(await readColumn('height', 'a.mp4'), 1080);
    expect(await readColumn('pixel_count', 'a.mp4'), 2073600);
    expect(await readColumn('duration_ms', 'a.mp4'), isNull);

    await dao.updateFileMediaInfo(
      storageId: 'st1',
      path: 'a.mp4',
      durationMs: 42000,
    );

    expect(await readColumn('duration_ms', 'a.mp4'), 42000);
    // Previously written fields survive partial updates.
    expect(await readColumn('width', 'a.mp4'), 1920);
    expect(await readColumn('pixel_count', 'a.mp4'), 2073600);
  });

  test('repo writes repair ancestor duration aggregates', () async {
    await dao.insertNode(MediaNode.directory(
      id: 'st1:d',
      storageId: 'st1',
      path: const ['d'],
      pathDepth: 1,
      name: 'd',
    ));
    await insertFile('d/a.mp4');

    await repo.updateFileMediaInfo(
      storageId: 'st1',
      path: 'd/a.mp4',
      durationMs: 60000,
    );

    final dirTotal = await db.customSelect(
      'SELECT total_duration_ms FROM media_nodes WHERE storage_id = ? AND path = ?',
      variables: [Variable.withString('st1'), Variable.withString('d')],
    ).getSingle();
    expect(dirTotal.data['total_duration_ms'], 60000);
  });

  test('unknown path is a silent no-op', () async {
    await dao.updateFileMediaInfo(
      storageId: 'st1',
      path: 'missing.mp4',
      durationMs: 1,
    );
    final count = await db.customSelect(
      "SELECT COUNT(*) AS c FROM media_nodes WHERE path = 'missing.mp4'",
    ).getSingle();
    expect(count.data['c'], 0);
  });
}
