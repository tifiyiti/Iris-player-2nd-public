import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/storage_volume_reconciler.dart';

LocalStorage _local({
  required String id,
  required String name,
  required List<String> basePath,
  String? volumeId,
}) =>
    LocalStorage(
      id: id,
      type: StorageType.internal,
      name: name,
      basePath: basePath,
      volumeId: volumeId,
    );

void main() {
  group('planStorageVolumeReconcile', () {
    test('matches the same volume under a new letter and moves the entry',
        () async {
      final existing = [
        _local(
            id: 'old',
            name: 'Movies (D:)',
            basePath: ['D:'],
            volumeId: 'vol:g'),
      ];
      final scanned = [
        _local(
            id: 'fresh',
            name: 'Movies (E:)',
            basePath: ['E:'],
            volumeId: 'vol:g'),
      ];

      final plan = await planStorageVolumeReconcile(
        scanned: scanned,
        existing: existing,
        resolveVolumeId: (_) async => null,
      );

      expect(plan.adds, isEmpty);
      expect(plan.moves, hasLength(1));
      final move = plan.moves.single;
      expect(move.existing.id, 'old');
      expect(move.updated.id, 'old', reason: 'entry keeps its id/scope');
      expect(move.updated.basePath, ['E:']);
      expect(move.updated.volumeId, 'vol:g');
      expect(move.oldBase, 'D:');
      expect(move.newBase, 'E:');
    });

    test('a disk with no persisted entry is added', () async {
      final plan = await planStorageVolumeReconcile(
        scanned: [
          _local(
              id: 'fresh',
              name: 'New (E:)',
              basePath: ['E:'],
              volumeId: 'vol:new'),
        ],
        existing: const [],
        resolveVolumeId: (_) async => null,
      );

      expect(plan.moves, isEmpty);
      expect(plan.adds, hasLength(1));
      expect(plan.adds.single.id, 'fresh');
    });

    test('same id (legacy, no volume id) is a no-op', () async {
      final entry =
          _local(id: 'same', name: 'X (D:)', basePath: ['D:']);
      final plan = await planStorageVolumeReconcile(
        scanned: [_local(id: 'same', name: 'X (D:)', basePath: ['D:'])],
        existing: [entry],
        resolveVolumeId: (_) async => null,
      );

      expect(plan.moves, isEmpty);
      expect(plan.adds, isEmpty);
    });

    test('backfills a missing volume id from the mounted base path', () async {
      final plan = await planStorageVolumeReconcile(
        scanned: const [],
        existing: [
          _local(id: 'old', name: 'X (D:)', basePath: ['D:']),
        ],
        resolveVolumeId: (root) async => root == 'D:' ? 'vol:g' : null,
      );

      expect(plan.adds, isEmpty);
      expect(plan.moves, hasLength(1));
      final move = plan.moves.single;
      expect(move.updated.id, 'old');
      expect(move.updated.volumeId, 'vol:g');
      expect(move.oldBase, move.newBase, reason: 'base path unchanged');
    });

    test('a volume is matched at most once across duplicates', () async {
      final existing = [
        _local(id: 'a', name: 'X (D:)', basePath: ['D:'], volumeId: 'vol:g'),
        _local(id: 'b', name: 'X (E:)', basePath: ['E:'], volumeId: 'vol:g'),
      ];
      final plan = await planStorageVolumeReconcile(
        scanned: [
          _local(
              id: 'fresh',
              name: 'X (F:)',
              basePath: ['F:'],
              volumeId: 'vol:g'),
        ],
        existing: existing,
        resolveVolumeId: (_) async => null,
      );

      expect(plan.adds, isEmpty);
      expect(plan.moves, hasLength(1));
    });
  });
}
