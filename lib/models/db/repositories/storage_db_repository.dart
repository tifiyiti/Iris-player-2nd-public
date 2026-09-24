import 'package:drift/drift.dart';
import 'package:iris/models/db/adapters/storage_drift_adapter.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/dao/storage_dao.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

class StorageDbRepository {
  final StorageDao dao;
  StorageDbRepository(this.dao);

  /// Entries whose password could not be decrypted, keyed by id, holding the
  /// exact placeholder object handed to the store.
  ///
  /// Writes are a FULL REPLACE (delete-all + insert), so re-persisting such a
  /// placeholder would clobber the stored cipher and every connection field.
  /// While that same object is still what the store holds, the row is spared;
  /// an actual edit (new password) or a removal releases it.
  final Map<String, Storage> _locked = <String, Storage>{};

  /// Ids and in-memory placeholders of locked entries. Empty when every row
  /// decrypted cleanly.
  Map<String, Storage> get lockedStorages => Map.unmodifiable(_locked);

  bool get hasLockedStorages => _locked.isNotEmpty;

  /// Whether [id] is an entry whose password could not be decrypted. Its row
  /// must stay untouched until the user re-enters the password.
  bool isLockedId(String id) => _locked.containsKey(id);

  Future<List<Storage>> getStorages() async {
    final rows = await dao.getAll();
    _locked.clear();
    final out = <Storage>[];
    for (final row in rows) {
      final decoded = await StorageDriftAdapter.fromDbDecoded(row);
      if (decoded.passwordLocked) {
        _locked[decoded.storage.id] = decoded.storage;
      }
      out.add(decoded.storage);
    }
    if (_locked.isNotEmpty) {
      _log.w('storages_table: ${_locked.length} entry(ies) locked — password '
          'undecryptable on this device; rows kept as-is: ${_locked.keys}');
    }
    return out;
  }

  Future<void> addStorage(Storage storage) async {
    if (_isLockedPlaceholder(storage)) {
      _log.w('addStorage: refusing to overwrite locked storage ${storage.id}');
      return;
    }
    _locked.remove(storage.id);
    final companion = await storage.toCipherCompanion();
    return dao.insert(companion);
  }

  Future<void> updateInsertStorage(Storage storage) async {
    if (_isLockedPlaceholder(storage)) {
      _log.w(
          'updateInsertStorage: refusing to overwrite locked storage ${storage.id}');
      return;
    }
    _locked.remove(storage.id);
    final companion = await storage.toCipherCompanion();
    return dao.upsert(companion);
  }

  Future<void> removeStorage(String id) {
    _locked.remove(id);
    return dao.deleteById(id);
  }

  Future<void> replaceAllStorages(List<Storage> storages) async {
    final preserveIds = _stillLockedIds(storages);
    final companions = <StoragesTableCompanion>[];
    for (final s in storages) {
      // Locked placeholders are skipped: the row is kept verbatim.
      if (preserveIds.contains(s.id)) continue;
      companions.add(await s.toCipherCompanion());
    }
    await dao.replaceAll(companions, preserveIds: preserveIds);
    // An edited or removed placeholder no longer protects its row.
    _locked.removeWhere((id, placeholder) => !preserveIds.contains(id));
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
        if (_isLockedPlaceholder(s)) continue;
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

  bool _isLockedPlaceholder(Storage storage) =>
      _locked[storage.id] == storage;

  /// Ids whose locked placeholder is still exactly what the caller holds —
  /// value equality, so plain list copies / state rebuilds keep the lock while
  /// an actual edit (new password, changed host) releases it.
  Set<String> _stillLockedIds(List<Storage> storages) {
    final present = <String, Storage>{for (final s in storages) s.id: s};
    return <String>{
      for (final entry in _locked.entries)
        if (present[entry.key] == entry.value) entry.key,
    };
  }
}
