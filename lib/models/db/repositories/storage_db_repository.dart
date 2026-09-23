import 'package:drift/drift.dart';
import 'package:iris/models/db/adapters/storage_drift_adapter.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/dao/storage_dao.dart';
import 'package:iris/models/storages/storage.dart';

class StorageDbRepository {
  final StorageDao dao;
  StorageDbRepository(this.dao);

  Future<List<Storage>> getStorages() async {
    final rows = await dao.getAll();
    final out = <Storage>[];
    for (final row in rows) {
      out.add(await StorageDriftAdapter.fromDbAsync(row));
    }
    return out;
  }

  Future<void> addStorage(Storage storage) async {
    final companion = await storage.toCipherCompanion();
    return dao.insert(companion);
  }

  Future<void> updateInsertStorage(Storage storage) async {
    final companion = await storage.toCipherCompanion();
    return dao.upsert(companion);
  }

  Future<void> removeStorage(String id) {
    return dao.deleteById(id);
  }

  Future<void> replaceAllStorages(List<Storage> storages) async {
    final companions = <StoragesTableCompanion>[];
    for (final s in storages) {
      companions.add(await s.toCipherCompanion());
    }
    return dao.replaceAll(companions);
  }

  Future<void> replaceLocalStorages(List<Storage> storages) async {
    await dao.db.transaction(() async {
      await (dao.delete(dao.storagesTable)
            ..where((t) => t.type.isIn([
                  StorageType.internal.index,
                  StorageType.network.index,
                  StorageType.usb.index,
                  StorageType.sdcard.index,
                ])))
          .go();

      for (final s in storages) {
        await dao.upsert(await s.toCipherCompanion());
      }
    });
  }

  /// One-time sweep: encrypt any remaining plaintext `password` rows into
  /// cipher columns. Idempotent; safe to call on every startup.
  Future<int> migratePlaintextPasswords() async {
    final rows = await dao.getAll();
    var migrated = 0;
    for (final row in rows) {
      if (row.password == null || row.password!.isEmpty) continue;
      if (row.passwordCipher != null && row.passwordNonce != null) continue;
      final storage = StorageDriftAdapter.fromDb(row);
      final cipherCompanion = await storage.toCipherCompanion();
      await dao.upsert(cipherCompanion);
      migrated++;
    }
    return migrated;
  }
}
