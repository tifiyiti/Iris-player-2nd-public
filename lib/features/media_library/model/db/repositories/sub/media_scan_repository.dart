import 'package:iris/features/media_library/model/db/adapters/media_node_drift_adapter.dart';
import 'package:iris/features/media_library/model/db/adapters/scan_state_drift_adapter.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/dao/scan_states_dao.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/scan_state.dart';
import 'package:iris/models/db/app_database.dart';

class ScanStateRepository {
  final AppDatabase _db;
  final ScanStatesDao _scanDao;
  final MediaNodesDao _nodesDao;

  ScanStateRepository({
    required AppDatabase db,
    required ScanStatesDao scanDao,
    required MediaNodesDao nodesDao,
  })  : _db = db,
        _scanDao = scanDao,
        _nodesDao = nodesDao;

  // --- Scan State Queries ---

  /// Retrieves the current scan status for a specific path.
  Future<ScanState?> getScanState({
    required String storageId,
    required List<String> path,
  }) async {
    final row = await _scanDao.get(storageId, path.join('/'));
    return row != null ? ScanStateDriftAdapter.fromDb(row) : null;
  }

  // --- Atomic Sync Operations (Deep Methods) ---

  /// Synchronizes a directory by replacing its children atomically.
  /// All-or-nothing: if any step fails, the transaction rolls back.
  Future<void> syncDirectory({
    required String storageId,
    required List<String> path,
    required List<MediaNode> scannedNodes,
  }) async {
    final parentPathString = path.join('/');

    await _db.transaction(() async {
      // 1. Delete existing children under this path
      await _nodesDao.deleteByPathPrefix(storageId, parentPathString);

      // 2. Batch upsert the newly discovered nodes
      if (scannedNodes.isNotEmpty) {
        final companions = scannedNodes.map((e) => e.toCompanion()).toList();
        await _nodesDao.batchUpsert(companions);
      }

      // 3. Record that this path has been successfully synchronized
      await _updateStatus(
        storageId: storageId,
        path: path,
        status: ScanStatus.done,
      );
    });
  }

  /// Sets a directory's state to 'scanning'.
  Future<void> markAsScanning({
    required String storageId,
    required List<String> path,
  }) {
    return _updateStatus(
      storageId: storageId,
      path: path,
      status: ScanStatus.scanning,
    );
  }

  // --- Private Helpers (Information Hiding) ---

  /// Internal helper to unify how ScanState is persisted.
  ///
  /// Hides the 'Companion' and 'DateTime' logic from the caller.
  Future<void> _updateStatus({
    required String storageId,
    required List<String> path,
    required ScanStatus status,
  }) {
    final state = ScanState(
      storageId: storageId,
      path: path,
      status: status,
      lastScannedAt: DateTime.now(),
    );
    return _scanDao.upsert(state.toCompanion());
  }
}
