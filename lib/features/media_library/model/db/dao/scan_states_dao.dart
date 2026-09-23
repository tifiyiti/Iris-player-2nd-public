import 'package:drift/drift.dart';
import 'package:iris/features/media_library/model/db/tables/scan_states_table.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/storage_scope.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/utils/path_prefix_remap.dart';

part 'scan_states_dao.g.dart';

@DriftAccessor(tables: [ScanStatesTable])
class ScanStatesDao extends DatabaseAccessor<AppDatabase> with _$ScanStatesDaoMixin {
  ScanStatesDao(super.db);

  Future<ScanStatesTableData?> get(String storageId, String path) {
    final canonical = canonicalDbPath(path);
    return (select(scanStatesTable)
          ..where((t) =>
              t.dataScopeId.equals(StorageScope.of(storageId)) &
              t.path.equals(canonical)))
        .getSingleOrNull();
  }

  Future<void> upsert(ScanStatesTableCompanion entry) {
    return into(scanStatesTable).insertOnConflictUpdate(entry);
  }

  Future<void> deleteByKey(String storageId, String path) {
    final canonical = canonicalDbPath(path);
    return (delete(scanStatesTable)
          ..where((t) =>
              t.dataScopeId.equals(StorageScope.of(storageId)) &
              t.path.equals(canonical)))
        .go();
  }

  Future<List<ScanStatesTableData>> getByStorage(String storageId) {
    return (select(scanStatesTable)
          ..where((t) => t.dataScopeId.equals(StorageScope.of(storageId))))
        .get();
  }

  /// Deletes a scope's state rows by canonical scope id (no translation).
  Future<void> deleteByScopeId(String scopeId) {
    return (delete(scanStatesTable)
          ..where((t) => t.dataScopeId.equals(scopeId)))
        .go();
  }

  /// Re-points a scope's state rows to a surviving owner entry (see
  /// `MediaNodesDao.reassignStorageIdForScope`).
  Future<void> reassignStorageIdForScope({
    required String scopeId,
    required String newStorageId,
  }) {
    return (update(scanStatesTable)
          ..where((t) => t.dataScopeId.equals(scopeId)))
        .write(ScanStatesTableCompanion(storageId: Value(newStorageId)));
  }

  /// Rewrites the leading [oldBase] of every state row's `path` under
  /// [storageId] to [newBase] (drive-letter reassignment).
  Future<int> remapPathPrefix({
    required String storageId,
    required String oldBase,
    required String newBase,
  }) {
    final query = buildPathPrefixRemap(
      table: 'scan_states',
      keyColumn: 'data_scope_id',
      keyValue: StorageScope.of(storageId),
      oldBase: oldBase,
      newBase: newBase,
    );
    return customUpdate(
      query.sql,
      variables: query.variables,
      updates: {scanStatesTable},
    );
  }
}
