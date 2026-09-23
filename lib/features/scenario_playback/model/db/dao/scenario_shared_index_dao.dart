import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/db/tables/scenario_shared_index_table.dart';
import 'package:iris/models/db/app_database.dart';

part 'scenario_shared_index_dao.g.dart';

/// The raw blobs of one persisted shared-order index (decoded by
/// `SharedIndexCodec`). Kept as plain bytes so this layer stays format-agnostic.
class ScenarioSharedIndexBlobs {
  const ScenarioSharedIndexBlobs({
    required this.baseCount,
    required this.slices,
    required this.accepted,
    required this.absorbed,
    required this.groupRows,
    required this.placeholders,
    required this.occurrence,
    required this.flags,
  });

  final int baseCount;
  final Uint8List slices;
  final Uint8List accepted;
  final Uint8List absorbed;
  final Uint8List groupRows;
  final Uint8List placeholders;
  final Uint8List occurrence;
  final Uint8List flags;
}

/// Persistence for the shared-order derived index (schema v44).
///
/// A rebuildable cache keyed by the scenario's build id: it lives and dies with
/// the `scenario_queue_builds` meta row of that id (its GC drops every blob no
/// live build owns).
@DriftAccessor(tables: [ScenarioSharedIndexTable])
class ScenarioSharedIndexDao extends DatabaseAccessor<AppDatabase>
    with _$ScenarioSharedIndexDaoMixin {
  ScenarioSharedIndexDao(super.db);

  Future<void> write(
    int buildId, {
    required int baseCount,
    required Uint8List slices,
    required Uint8List accepted,
    required Uint8List absorbed,
    required Uint8List groupRows,
    required Uint8List placeholders,
    required Uint8List occurrence,
    required Uint8List flags,
  }) async {
    await customInsert(
      'INSERT OR REPLACE INTO scenario_shared_index '
      '(build_id, base_count, slices, accepted, absorbed, group_rows, '
      'placeholders, occurrence, flags) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withInt(buildId),
        Variable.withInt(baseCount),
        Variable.withBlob(slices),
        Variable.withBlob(accepted),
        Variable.withBlob(absorbed),
        Variable.withBlob(groupRows),
        Variable.withBlob(placeholders),
        Variable.withBlob(occurrence),
        Variable.withBlob(flags),
      ],
    );
  }

  Future<ScenarioSharedIndexBlobs?> read(int buildId) async {
    final row = await customSelect(
      'SELECT base_count, slices, accepted, absorbed, group_rows, '
      'placeholders, occurrence, flags FROM scenario_shared_index '
      'WHERE build_id = ?',
      variables: [Variable.withInt(buildId)],
    ).getSingleOrNull();
    if (row == null) return null;
    return ScenarioSharedIndexBlobs(
      baseCount: row.read<int>('base_count'),
      slices: row.read<Uint8List>('slices'),
      accepted: row.read<Uint8List>('accepted'),
      absorbed: row.read<Uint8List>('absorbed'),
      groupRows: row.read<Uint8List>('group_rows'),
      placeholders: row.read<Uint8List>('placeholders'),
      occurrence: row.read<Uint8List>('occurrence'),
      flags: row.read<Uint8List>('flags'),
    );
  }

  Future<void> deleteBuild(int buildId) async {
    await customUpdate(
      'DELETE FROM scenario_shared_index WHERE build_id = ?',
      variables: [Variable.withInt(buildId)],
      updates: {scenarioSharedIndexTable},
    );
  }

  /// Drops every shared index whose build id is no longer live.
  Future<void> gcStaleGenerations() async {
    await customUpdate(
      'DELETE FROM scenario_shared_index WHERE build_id NOT IN '
      '(SELECT build_id FROM scenario_queue_builds)',
      updates: {scenarioSharedIndexTable},
    );
  }

  Future<int> count() async {
    final row = await customSelect(
            'SELECT COUNT(*) AS c FROM scenario_shared_index')
        .getSingle();
    return row.read<int>('c');
  }
}
