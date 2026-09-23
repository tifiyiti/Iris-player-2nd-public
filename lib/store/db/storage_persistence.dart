import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:iris/models/db/repositories/favorites_db_repository.dart';
import 'package:iris/models/db/repositories/navigation_db_repository.dart';
import 'package:iris/models/db/repositories/storage_db_repository.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/kv/use_kv_store.dart';
import 'package:iris/utils/logger.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyStore);

abstract class StoragePersistence {
  Future<StorageState?> load();
  Future<void> save(StorageState state);
}

class SecureStoragePersistence implements StoragePersistence {
  @override
  Future<StorageState?> load() async {
    try {
      final storage = getKvStore();
      final raw = await storage.read(key: 'storage_state');
      if (raw == null) return null;
      return StorageState.fromJson(json.decode(raw));
    } catch (e) {
      areaKeyLog.e('SecureStorage load error: $e');
      return null;
    }
  }

  @override
  Future<void> save(StorageState state) async {
    try {
      final storage = getKvStore();
      await storage.write(
        key: 'storage_state',
        value: json.encode(state.toJson()),
      );
    } catch (e) {
      areaKeyLog.e('SecureStorage save error: $e');
    }
  }
}

class DbStoragePersistence implements StoragePersistence {
  final StorageDbRepository storageRepo;
  final FavoritesDbRepository favoritesRepo;
  final NavigationDbRepository navRepo;

  DbStoragePersistence({
    required this.storageRepo,
    required this.favoritesRepo,
    required this.navRepo,
  });

  @override
  Future<StorageState?> load() async {
    final storages = await storageRepo.getStorages();
    final favorites = await favoritesRepo.getFavorites();
    final nav = await navRepo.getNavigation();

    final currentStorage = nav?.currentStorageId == null
        ? null
        : storages.firstWhereOrNull((s) => s.id == nav!.currentStorageId);

    return StorageState(
      storages: storages,
      favorites: favorites,
      currentStorage: currentStorage,
      currentPath: nav?.currentPath ?? const [],
    );
  }

  @override
  Future<void> save(StorageState state) async {
    if (state.storages.isEmpty) {
      // Tripwire. The store gates saves on a successful load, so an empty list
      // here means "the user really has no storages left" — but this write is a
      // FULL REPLACE, so anything else reaching here (a partial/never-loaded
      // state) would silently drop every saved storage.
      final existing = await storageRepo.getStorages();
      if (existing.isNotEmpty) {
        areaKeyLog.w(
          'DbStoragePersistence.save: clearing ${existing.length} saved '
          'storage(s) with an empty in-memory list (legit only when the last '
          'one was removed)',
        );
      }
    }
    await storageRepo.replaceAllStorages(state.storages);
    await favoritesRepo.replaceAllFavorites(state.favorites);
    await navRepo.saveNavigation(
      currentStorageId: state.currentStorage?.id,
      currentPath: state.currentPath,
    );
    areaKeyLog.i("DbStoragePersistence SAVE: ${state.currentStorage?.id} ${state.currentPath}");
  }
}
