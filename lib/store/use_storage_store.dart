import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:iris/store/kv/use_kv_store.dart';
import 'package:flutter_zustand/flutter_zustand.dart' as zustand;
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/storage_scope_key.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/db/storage_persistence.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/path_conv.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyStore);

Map<String, dynamic> _stripConnectionStatus(
    Map<String, dynamic> json) {
  final result = Map<String, dynamic>.from(json);
  result.remove('storageConnectionStatus');
  return result;
}

/// Most-recent-first union of WebDAV resolved hosts, capped at 5.
List<String> _mergeResolvedHosts(List<String> incoming, List<String> current) {
  final merged = <String>[];
  for (final host in [...incoming, ...current]) {
    if (host.isEmpty || merged.contains(host)) continue;
    merged.add(host);
    if (merged.length >= 5) break;
  }
  return merged;
}

  // not use now.
class StorageStore extends PersistentStore<StorageState> {
  StorageStore() : super(StorageState());

  Storage? findById(String id) => state.storages.firstWhereOrNull((storage) => storage.id == id);

  bool isConnected(String id) => state.storageConnectionStatus[id] ?? true;

  void markDisconnected(String id) {
    set(state.copyWith(
      storageConnectionStatus: {
        ...state.storageConnectionStatus,
        id: false,
      },
    ));
  }

  void markConnected(String id) {
    final updated = Map<String, bool>.from(state.storageConnectionStatus);
    updated.remove(id);
    set(state.copyWith(storageConnectionStatus: updated));
  }

  Future<void> addStorage(Storage storage) async {
    set(state.copyWith(storages: [...state.storages, storage]));
    await save(state);
  }

  Future<void> updateStorage(int index, Storage storage) async {
    if (index < 0 || index >= state.storages.length) {
      return;
    }

    set(state.copyWith(
        storages: [...state.storages]
          ..removeAt(index)
          ..insert(index, storage)));
    await save(state);
  }

  Future<void> removeStorage(Storage storage) async {
    set(state.copyWith(storages: [...state.storages]..remove(storage)));
    await save(state);
  }

  Future<void> addFavorite(Favorite favorite) async {
    set(state.copyWith(favorites: [...state.favorites, favorite]));
    await save(state);
  }

  Future<void> removeFavorite(Favorite favorite) async {
    set(state.copyWith(favorites: [...state.favorites]..remove(favorite)));
    await save(state);
  }

  Future<void> updateCurrentStorage(Storage? storage) async {
    set(state.copyWith(currentStorage: storage));
    await save(state);
  }

  Future<void> updateCurrentPath(List<String> path) async {
    set(state.copyWith(currentPath: path));
    await save(state);
  }

  @override
  Future<StorageState?> load() async {
    areaKeyLog.i('Loading StorageState');
    try {
      final storage = getKvStore();

      String? storageState = await storage.read(key: 'storage_state');
      if (storageState != null) {
        return StorageState.fromJson(
            _stripConnectionStatus(json.decode(storageState)));
      }
    } catch (e) {
      areaKeyLog.e('Error loading StorageState: $e');
    }
    return null;
  }

  @override
  Future<void> save(StorageState state) async {
    try {
      final storage = getKvStore();

      await storage.write(
          key: 'storage_state',
          value: json.encode(
              _stripConnectionStatus(state.toJson())));
    } catch (e) {
      areaKeyLog.e('Error saving StorageState: $e');
    }
  }

  Future<void> importFromJson(
    Map<String, dynamic> json, {
    required bool override,
  }) async {
    final imported =
        StorageState.fromJson(_stripConnectionStatus(json));

    final merged = state.copyWith(
      storages: override
          ? imported.storages
          : [...state.storages, ...imported.storages],
      favorites: override
          ? imported.favorites
          : [...state.favorites, ...imported.favorites],
    );

    set(merged);
    await save(merged);
  }

  Map<String, dynamic> exportToJson() {
    return _stripConnectionStatus(state.toJson());
  }
}

//StorageStore useStorageStore() => create(() => StorageStore());

// unified store factory

class UnifiedStorageStore extends PersistentStore<StorageState> {
  final StoragePersistence legacyPersistence;
  final StoragePersistence dbPersistence;

  late StoragePersistence _activePersistence;
  bool _backendSelected = false;

  /// True once the FIRST load attempt finished — success OR failure. This is
  /// the UI readiness signal (the browser shows its spinner until then).
  bool _loaded = false;
  bool get loaded => _loaded;

  UnifiedStorageStore({
    required this.legacyPersistence,
    required this.dbPersistence,
    bool useLegacy = false,
  }) : super(StorageState());

  StoragePersistence get activePersistence => _activePersistence;

  @override
  Future<StorageState?> load() async {
    // Determine active persistence at first load
    if (!_backendSelected) {
      _activePersistence = dbPersistence; // default backend, can be switched later
      _backendSelected = true;
    }
    final readPersistence = _activePersistence;

    try {
      final rawState = await readPersistence.load();
      // A backend switch may have landed while this read was in flight
      // (e.g. AppStore.onReady racing the startup load). The switch already
      // published its own backend's state; applying this stale snapshot now
      // would display one backend's data while writing to the other.
      if (!identical(_activePersistence, readPersistence)) return null;
      // Reached only when the read did not throw, so the snapshot is
      // authoritative — even when it is empty, which is exactly what lets a
      // user-initiated "removed my last storage" persist. (The base store's
      // `loadOk` turns writes on under the same condition.)
      if (rawState == null) return null;
      return rawState.copyWith(storageConnectionStatus: const {});
    } finally {
      _loaded = true;
    }
  }

  @override
  Future<void> save(StorageState state) async {
    // Writes are a FULL REPLACE in the DB backend (delete-all + insert), so
    // persisting the default empty state of a store whose load never succeeded
    // would wipe every saved storage/favorite. `loadOk` is false forever in
    // that case, and this is the gate that matters.
    if (!loadOk) {
      areaKeyLog.w('skip save: storage store never loaded successfully');
      return;
    }
    await _activePersistence.save(
      state.copyWith(storageConnectionStatus: const {}),
    );
  }

  /// Switches the persistence backend.
  ///
  /// The new backend is read BEFORE becoming active: if that read throws, the
  /// current state, the active backend and the write gate all stay untouched,
  /// so a failed switch can never be followed by a write into the new backend.
  Future<void> switchBackend(bool useLegacy) async {
    final newPersistence = useLegacy ? legacyPersistence : dbPersistence;

    if (_backendSelected && identical(newPersistence, _activePersistence)) {
      return;
    }

    final StorageState? loaded;
    try {
      loaded = await newPersistence.load();
    } catch (e) {
      areaKeyLog.e(
        'switchBackend(useLegacy: $useLegacy) load failed; '
        'keeping the current backend: $e',
      );
      return;
    }

    _activePersistence = newPersistence;
    _backendSelected = true;
    if (loaded != null) {
      set(loaded.copyWith(storageConnectionStatus: const {}));
    }
  }

  /// Whether currently using legacy persistence
  bool get isUsingLegacy => identical(_activePersistence, legacyPersistence);

  /// Whether a storage is connected (runtime only, default true).
  bool isConnected(String id) => state.storageConnectionStatus[id] ?? true;

  /// Mark a storage as disconnected (runtime only, not persisted).
  void markDisconnected(String id) {
    set(state.copyWith(
      storageConnectionStatus: {
        ...state.storageConnectionStatus,
        id: false,
      },
    ));
  }

  /// Mark a storage as connected (remove runtime disconnected flag).
  void markConnected(String id) {
    final updated = Map<String, bool>.from(state.storageConnectionStatus);
    updated.remove(id);
    set(state.copyWith(storageConnectionStatus: updated));
  }

  // ---- Same API as StorageStore ----

  Storage? findById(String id) => state.storages.firstWhereOrNull((s) => s.id == id);

  /// Resolves the entry that supplies endpoint/credentials for a node row whose
  /// stored `storage_id` is [nodeStorageId]. A shared-scope node keeps its
  /// scope's id, which may be deleted while the node survives; prefer
  /// [viewingId] when it shares the node's scope (freshest resolved host), then
  /// that entry, then any surviving scope member. See [resolveStorageForNode].
  Storage? resolveStorageForNodeId(String nodeStorageId, {String? viewingId}) =>
      resolveStorageForNode(
        storages: state.storages,
        viewingId: viewingId,
        nodeStorageId: nodeStorageId,
      );

  Future<void> addStorage(Storage storage) async {
    set(state.copyWith(storages: [...state.storages, storage]));
    await save(state);
  }

  Future<void> updateStorage(int index, Storage storage) async {
    if (index < 0 || index >= state.storages.length) return;
    final previous = state.storages[index];
    final newList = [...state.storages]
      ..removeAt(index)
      ..insert(index, storage);

    // Keep the persisted "current storage" pointer in sync with an edit (e.g. a
    // drive-letter move) instead of leaving it on the stale base path.
    final current = state.currentStorage;
    final nextCurrent =
        (current != null && current.id == storage.id) ? storage : current;

    // If the edit moved this entry out of its old data scope and no other entry
    // still maps to that scope, its node/scan rows become unreachable (the
    // entry itself no longer resolves there, and deletion deliberately keeps
    // last-owner rows). Drop them instead of leaving a permanent stray set.
    final oldScope = previous.dataScopeId ?? previous.id;
    final newScope = storage.dataScopeId ?? storage.id;
    final oldScopeStillUsed = newScope == oldScope ||
        newList.any((s) => (s.dataScopeId ?? s.id) == oldScope);

    set(state.copyWith(storages: newList, currentStorage: nextCurrent));
    await save(state);

    if (!oldScopeStillUsed) {
      await _purgeScope(oldScope);
    }
  }

  /// Physically removes every node/scan row of a canonical [scopeId] that no
  /// entry maps to anymore.
  Future<void> _purgeScope(String scopeId) async {
    try {
      await DbModule.mediaNodesDao.deleteByScopeId(scopeId);
      await DbModule.scanQueueDao.clearByScopeId(scopeId);
      await DbModule.scanStatesDao.deleteByScopeId(scopeId);
    } catch (e) {
      areaKeyLog.w('purge unreachable scope $scopeId failed: $e');
    }
  }

  /// Records newly resolved WebDAV host(s) for the scope that [id] belongs to,
  /// keeping a short most-recent-first history (cap 5). Recent hosts are tried
  /// before any scan, so a DHCP shuffle is usually recovered without
  /// discovery.
  ///
  /// Two entries linked into one data scope (shared library) share this cache:
  /// whichever entry resolves a host pushes it to every member, so the whole
  /// group follows the machine — wildcards AND fixed-IP entries (a fixed entry
  /// prefers the shared host and still falls back to its configured `host`).
  ///
  /// No-op when [id] is unknown, is not a WebDAV entry, or the merged order is
  /// unchanged.
  Future<void> updateWebdavResolvedHosts(String id, List<String> hosts) async {
    final index = state.storages.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final current = state.storages[index];
    if (current is! WebDAVStorage) return;

    final scopeId = current.dataScopeId ?? current.id;
    final newList = [...state.storages];
    var changed = false;
    for (var i = 0; i < newList.length; i++) {
      final member = newList[i];
      if (member is! WebDAVStorage) continue;
      if ((member.dataScopeId ?? member.id) != scopeId) continue;
      final merged = _mergeResolvedHosts(hosts, member.resolvedHosts);
      if (const ListEquality<String>().equals(merged, member.resolvedHosts)) {
        continue;
      }
      newList[i] = member.copyWith(resolvedHosts: merged);
      changed = true;
    }
    if (!changed) return;

    set(state.copyWith(storages: newList));
    await save(state);
  }

  Future<void> removeStorage(Storage storage) async {
    // Nodes are scope-owned: if a linked sibling survives, re-point the shared
    // rows to it BEFORE dropping this entry, so playback resolves a live owner.
    final scope = storage.dataScopeId ?? storage.id;
    final survivor = state.storages.firstWhereOrNull(
      (s) => s.id != storage.id && (s.dataScopeId ?? s.id) == scope,
    );

    set(state.copyWith(storages: [...state.storages]..remove(storage)));
    await save(state);

    if (survivor != null) {
      try {
        await DbModule.mediaNodesDao.reassignStorageIdForScope(
          scopeId: scope,
          newStorageId: survivor.id,
        );
        await DbModule.scanQueueDao.reassignStorageIdForScope(
          scopeId: scope,
          newStorageId: survivor.id,
        );
        await DbModule.scanStatesDao.reassignStorageIdForScope(
          scopeId: scope,
          newStorageId: survivor.id,
        );
      } catch (e) {
        areaKeyLog.w('reassign scope $scope to ${survivor.id} failed: $e');
      }
    }
  }

  Future<void> addFavorite(Favorite favorite) async {
    set(state.copyWith(favorites: [...state.favorites, favorite]));
    await save(state);
  }

  Future<void> removeFavorite(Favorite favorite) async {
    set(state.copyWith(favorites: [...state.favorites]..remove(favorite)));
    await save(state);
  }

  /// Moves every favorite whose path sits under a storage's [oldBase] to
  /// [newBase] (drive-letter reassignment). No-op and no save when nothing
  /// matched.
  Future<void> remapFavorites({
    required String storageId,
    required String oldBase,
    required String newBase,
  }) async {
    final oldSegs = pathConv(oldBase);
    final newSegs = pathConv(newBase);
    if (oldSegs.isEmpty) return;
    var changed = false;
    final next = <Favorite>[];
    for (final f in state.favorites) {
      if (f.storageId != storageId) {
        next.add(f);
        continue;
      }
      final remapped = remapLeadingSegments(f.path, oldSegs, newSegs);
      if (remapped == null) {
        next.add(f);
        continue;
      }
      changed = true;
      next.add(f.copyWith(path: remapped));
    }
    if (!changed) return;
    set(state.copyWith(favorites: next));
    await save(state);
  }

  /// Moves the persisted browse location to a storage's new base path when that
  /// storage is the current one (drive-letter reassignment). No-op and no save
  /// when the location is not under [oldBase].
  Future<void> remapCurrentPath({
    required String storageId,
    required String oldBase,
    required String newBase,
  }) async {
    if (state.currentStorage?.id != storageId) return;
    final oldSegs = pathConv(oldBase);
    final newSegs = pathConv(newBase);
    if (oldSegs.isEmpty) return;
    final remapped = remapLeadingSegments(state.currentPath, oldSegs, newSegs);
    if (remapped == null) return;
    set(state.copyWith(currentPath: remapped));
    await save(state);
  }

  Future<void> updateCurrentStorage(Storage? storage) async {
    set(state.copyWith(currentStorage: storage));
    await save(state);
  }

  Future<void> updateCurrentPath(List<String> path) async {
    set(state.copyWith(currentPath: path));
    await save(state);
  }

  /// Import JSON, merge or override
  Future<void> importFromJson(
    Map<String, dynamic> json, {
    required bool override,
  }) async {
    final imported =
        StorageState.fromJson(_stripConnectionStatus(json));

    final mergedStorages = override
        ? imported.storages
        : [...state.storages, ...imported.storages];

    // A cross-device import may carry a dataScopeId that no longer maps to any
    // entry; repair dangling links before persisting so the import never
    // creates an unreachable shared library.
    final repairedStorages = repairImportedScopes(
      merged: mergedStorages,
      imported: imported.storages,
    );

    final merged = state.copyWith(
      storages: repairedStorages,
      favorites: override
          ? imported.favorites
          : [...state.favorites, ...imported.favorites],
    );

    set(merged);
    await save(merged);
  }

  /// Export to JSON
  Map<String, dynamic> exportToJson() {
    return _stripConnectionStatus(state.toJson());
  }
}

UnifiedStorageStore useStorageStore() => zustand.create(() => UnifiedStorageStore(
      legacyPersistence: SecureStoragePersistence(),
      dbPersistence: DbStoragePersistence(
        storageRepo: DbModule.storageRepo,
        favoritesRepo: DbModule.favoritesRepo,
        navRepo: DbModule.navRepo,
      ),
    ));
