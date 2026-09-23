import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/db/adapters/int32_blob_codec.dart';
import 'package:iris/features/scenario_playback/model/db/tables/media_orders_table.dart';
import 'package:iris/models/db/app_database.dart';

part 'media_order_dao.g.dart';

/// Persistence for the shared media orders (schema v44).
///
/// These are a rebuildable cache keyed by `SharedMediaOrder.orderKey`; the
/// revision guard makes a stale order look absent so the caller rebuilds.
@DriftAccessor(tables: [MediaOrdersTable])
class MediaOrderDao extends DatabaseAccessor<AppDatabase>
    with _$MediaOrderDaoMixin {
  MediaOrderDao(super.db);

  /// The stored order for [orderKey], or null when absent OR built against a
  /// different [mediaRev] — a stale order must be rebuilt, never served.
  Future<Int32List?> read(String orderKey, {required int mediaRev}) async {
    final row = await customSelect(
      'SELECT media_rev, ids FROM media_orders WHERE order_key = ?',
      variables: [Variable.withString(orderKey)],
    ).getSingleOrNull();
    if (row == null) return null;
    if (row.read<int>('media_rev') != mediaRev) return null;
    return Int32BlobCodec.decode(row.read<Uint8List>('ids'));
  }

  Future<void> write(
    String orderKey, {
    required int mediaRev,
    required Int32List ids,
  }) async {
    await customInsert(
      'INSERT OR REPLACE INTO media_orders (order_key, media_rev, n, ids) '
      'VALUES (?, ?, ?, ?)',
      variables: [
        Variable.withString(orderKey),
        Variable.withInt(mediaRev),
        Variable.withInt(ids.length),
        Variable.withBlob(Int32BlobCodec.encode(ids)),
      ],
    );
  }

  /// Removes one stored order (named to avoid Drift's `delete(Table)`).
  Future<void> deleteOrder(String orderKey) async {
    await customUpdate(
      'DELETE FROM media_orders WHERE order_key = ?',
      variables: [Variable.withString(orderKey)],
      updates: {mediaOrdersTable},
    );
  }

  /// Drops every stored order (a media rescan invalidates all of them).
  Future<void> clearAll() async {
    await customUpdate('DELETE FROM media_orders',
        updates: {mediaOrdersTable});
  }

  Future<int> count() async {
    final row =
        await customSelect('SELECT COUNT(*) AS c FROM media_orders').getSingle();
    return row.read<int>('c');
  }
}
