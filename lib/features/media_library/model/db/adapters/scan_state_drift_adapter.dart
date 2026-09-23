import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/storage_scope.dart';
import 'package:iris/features/media_library/model/media_lib/scan_state.dart';
import 'package:iris/utils/path_conv.dart';

extension ScanStateDriftAdapter on ScanState {
  static ScanState fromDb(ScanStatesTableData row) {
    return ScanState(
      storageId: row.storageId,
      path: pathConv(row.path),
      status: ScanStatus.values[row.status],
      lastScannedAt: row.lastScannedAt,
    );
  }

  ScanStatesTableCompanion toCompanion() {
    return ScanStatesTableCompanion.insert(
      storageId: storageId,
      dataScopeId: Value(StorageScope.of(storageId)),
      path: path.join('/'),
      status: status.index,
      lastScannedAt: Value(lastScannedAt),
    );
  }
}
