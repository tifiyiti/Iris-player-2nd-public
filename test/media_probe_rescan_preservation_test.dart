import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/adapters/media_node_drift_adapter.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/db/app_database.dart';

/// Rescan-preservation contract for deep-probe media info.
///
/// Scanner-constructed nodes carry no probe info; a rescan upsert of the
/// same node must NEVER wipe probed values (`duration_ms`, `width`,
/// `height`, `pixel_count`) — same rule as the playback_* progress
/// columns. Probed values are written exclusively via dedicated DAO
/// updates (scan probe / lazy playback backfill).
void main() {
  late AppDatabase db;
  late MediaNodesDao dao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = MediaNodesDao(db);
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  MediaFile scannerStyleFileNode() => MediaNode.file(
        id: 'st1:a.mp4',
        storageId: 'st1',
        path: const ['a.mp4'],
        pathDepth: 1,
        name: 'a.mp4',
        mediaType: MediaType.video,
        sizeInBytes: 12345,
      ) as MediaFile;

  Future<Map<String, Object?>> readProbeRow() async {
    final row = await db.customSelect(
      'SELECT duration_ms, width, height, pixel_count FROM media_nodes '
      'WHERE storage_id = ? AND path = ?',
      variables: [
        Variable.withString('st1'),
        Variable.withString('a.mp4'),
      ],
    ).getSingle();
    return {
      'duration_ms': row.data['duration_ms'],
      'width': row.data['width'],
      'height': row.data['height'],
      'pixel_count': row.data['pixel_count'],
    };
  }

  test('rescan upsert does not wipe duration_ms', () async {
    await dao.insertNode(scannerStyleFileNode());

    await db.customStatement(
      'UPDATE media_nodes SET duration_ms = ? WHERE storage_id = ? AND path = ?',
      [42000, 'st1', 'a.mp4'],
    );

    await dao.batchUpsert([scannerStyleFileNode().toCompanion()]);

    final row = await readProbeRow();
    expect(row['duration_ms'], 42000);
  });

  test('rescan upsert does not wipe width/height/pixel_count', () async {
    await dao.insertNode(scannerStyleFileNode());

    await db.customStatement(
      'UPDATE media_nodes SET width = ?, height = ?, pixel_count = ? '
      'WHERE storage_id = ? AND path = ?',
      [1920, 1080, 2073600, 'st1', 'a.mp4'],
    );

    await dao.batchUpsert([scannerStyleFileNode().toCompanion()]);

    final row = await readProbeRow();
    expect(row['width'], 1920);
    expect(row['height'], 1080);
    expect(row['pixel_count'], 2073600);
  });

  test('probed node persists values and derives pixel_count', () async {
    await dao.insertNode(scannerStyleFileNode());

    // Simulate a probed scanner node: carries real media info this time.
    final probed = scannerStyleFileNode().copyWith(
      durationMs: 42000,
      width: 1280,
      height: 720,
    );
    await dao.batchUpsert([probed.toCompanion()]);

    final row = await readProbeRow();
    expect(row['duration_ms'], 42000);
    expect(row['width'], 1280);
    expect(row['height'], 720);
    expect(row['pixel_count'], 1280 * 720);
  });

  test('companion presence: absent when unprobed, present when probed',
      () {
    final plain = scannerStyleFileNode().toCompanion();
    expect(plain.durationMs.present, isFalse);
    expect(plain.width.present, isFalse);
    expect(plain.height.present, isFalse);
    expect(plain.pixelCount.present, isFalse);

    final probed = scannerStyleFileNode()
        .copyWith(width: 640, height: 360)
        .toCompanion();
    expect(probed.width.present, isTrue);
    expect(probed.height.present, isTrue);
    expect(probed.pixelCount.present, isTrue);
    expect(probed.pixelCount.value, 640 * 360);
    // duration still absent → untouched by upsert.
    expect(probed.durationMs.present, isFalse);
  });
}
