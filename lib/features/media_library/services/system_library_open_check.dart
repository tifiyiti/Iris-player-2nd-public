import 'package:iris/features/media_library/model/db/adapters/media_library.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/media_lib/media_library.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/features/media_library/services/sync_default_system_library.dart';
import 'package:iris/models/db/app_database_holder.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/logger.dart';

final areaKeyLog = AreaKeyLog(LogKeys.legacyDb);

/// Maintains the "one system lib per storage + one detached lib" architecture
/// (see scenario system-lib acceptance docs).
///
/// Note on shared data scopes: two entries the user linked into one media
/// library still get one `sys_<storageId>` lib EACH. That is intentional — a
/// user who deliberately added a duplicate entry for the same tree expects a
/// matching lib. Node rows are NOT duplicated: they are keyed by
/// `(data_scope_id, path)`, so both libs project the same single row set
/// (queries OR their sources and never double-count).
///
/// Idempotent; triggered on entering the MediaDb tab. Legacy mode
/// (`useLegacyStoragePersistence == true`) is a hard no-op so no DB rows are
/// written/migrated/deleted for legacy users.
class SystemLibraryOpenCheckService {
  SystemLibraryOpenCheckService._();

  /// Detached library id/name convention.
  static const String detachedLibId = 'sys_detached';
  static const String detachedLibName = 'Detached';

  /// System lib id for a storage: `sys_<storageId>`.
  static String systemLibIdFor(String storageId) => 'sys_$storageId';

  static Future<void>? _inFlight;

  /// Runs the open-check once per entry; concurrent calls join the in-flight
  /// run instead of executing again (re-entrancy guard, D1).
  static Future<void> openCheck() {
    // D15/F131: legacy mode is a hard no-op.
    if (useAppStore().state.useLegacyStoragePersistence) {
      return Future.value();
    }

    final running = _inFlight;
    if (running != null) return running;

    final future = _run();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  static Future<void> _run() async {
    try {
      final storages = await DbModule.storageRepo.getStorages();
      final storageById = {for (final s in storages) s.id: s};

      // D10: migrate legacy `local_lib` first (transactional), then reload.
      final legacyLib = await DbModule.mediaLibsDao.getById(systemLibraryId);
      if (legacyLib != null) {
        await _migrateLegacyLib(storageById);
      }

      // D3: ensure the detached lib exists.
      await _ensureDetachedLib();

      // Re-read after migration so the per-storage loop sees fresh state.
      final existingLibs = await DbModule.mediaLibsDao.getAll();

      // Per-storage: ensure system lib + storage source + name sync (D2/D12/D14),
      // drop any detached source for this id when the storage is present (D5),
      // and normalize legacy (pre-canonicalization) node paths.
      for (final storage in storages) {
        if (storage.type == StorageType.none) continue;
        await _ensureSystemLib(storage);
        await _removeDetachedSourceForStorage(storage.id);
        try {
          await DbModule.nodeRepository.repairLegacyPaths(storage.id);
        } catch (e) {
          areaKeyLog.e('Legacy path repair error for ${storage.id}: $e');
        }
      }

      // Detached conversion: `sys_<id>` libs whose storage no longer exists (D5).
      final sysLibs = existingLibs.where((l) => l.id != detachedLibId).toList();
      for (final lib in sysLibs) {
        final sid = _storageIdFromSystemLib(lib.id);
        if (sid == null) continue;
        if (!storageById.containsKey(sid)) {
          await _convertToDetached(lib.id, sid);
        }
      }
    } catch (e) {
      // D8: silent degradation — never block the list / content.
      areaKeyLog.e('SystemLibraryOpenCheckService open-check error: $e');
    }
  }

  /// Extracts the storage id from a `sys_<storageId>` lib id; null if the id is
  /// not a per-storage system lib (detached, legacy, user libs).
  static String? _storageIdFromSystemLib(String libId) {
    const prefix = 'sys_';
    if (!libId.startsWith(prefix)) return null;
    final sid = libId.substring(prefix.length);
    return sid.isEmpty ? null : sid;
  }

  // ── Per-storage system lib ──

  static Future<void> _ensureSystemLib(Storage storage) async {
    final libId = systemLibIdFor(storage.id);
    final existing = await DbModule.mediaLibsDao.getById(libId);
    final now = DateTime.now();

    if (existing == null) {
      await DbModule.mediaLibsDao.upsert(
        MediaLibrary(
          id: libId,
          name: storage.name,
          type: MediaLibraryType.system,
          createdAt: now,
          updatedAt: now,
        ).toCompanion(),
      );
    } else if (existing.name != storage.name) {
      // D14: keep the lib name in sync with the current storage name.
      await DbModule.mediaLibsDao.upsert(
        MediaLibrary(
          id: libId,
          name: storage.name,
          type: MediaLibraryType.system,
          createdAt: existing.createdAt ?? now,
          updatedAt: now,
        ).toCompanion(),
      );
    }

    // D12: self-heal — exactly one `path==null/kind=storage` source; drop any
    // non-storage source that leaked into this system lib.
    await _selfHealSystemSource(libId, storage.id, storage.name);
  }

  /// Ensures the storage-level source for [libId] and removes any source that
  /// is not `(path==null, kind=storage)`.
  static Future<void> _selfHealSystemSource(
    String libId,
    String storageId,
    String storageName,
  ) async {
    final sources = await DbModule.mediaLibSourcesDao.getLibrarySources(libId);

    MediaLibrarySource? storageSource;
    for (final source in sources) {
      if (source.path == null && source.kind == MediaSourceKind.storage) {
        storageSource = source;
      } else {
        // Defensive legacy cleanup: directory/file sources under a system lib.
        await DbModule.mediaLibSourcesDao.deleteSource(source.id);
      }
    }

    if (storageSource == null) {
      final now = DateTime.now();
      await DbModule.mediaLibSourcesDao.upsertSource(
        MediaLibrarySource(
          id: 0,
          libraryId: libId,
          storageId: storageId,
          path: null,
          name: storageName,
          kind: MediaSourceKind.storage,
          createdAt: now,
        ),
      );
    }
  }

  // ── Detached lib & conversion ──

  static Future<void> _ensureDetachedLib() async {
    final existing = await DbModule.mediaLibsDao.getById(detachedLibId);
    if (existing == null) {
      final now = DateTime.now();
      await DbModule.mediaLibsDao.upsert(
        MediaLibrary(
          id: detachedLibId,
          name: detachedLibName,
          type: MediaLibraryType.system,
          createdAt: now,
          updatedAt: now,
        ).toCompanion(),
      );
    }
  }

  /// Removes the detached source for [storageId] when the storage is present
  /// again (D5 dedup).
  static Future<void> _removeDetachedSourceForStorage(String storageId) async {
    final rows = await DbModule.mediaLibSourcesDao.getByStorageId(storageId);
    for (final row in rows) {
      if (row.libraryId == detachedLibId) {
        await DbModule.mediaLibSourcesDao.deleteById(row.id);
      }
    }
  }

  /// Converts a removed storage's system lib into an detached source (D5).
  /// Nodes are never deleted — they are re-homed under the detached lib.
  static Future<void> _convertToDetached(String libId, String storageId) async {
    await _ensureDetachedLib();

    final now = DateTime.now();
    await DbModule.mediaLibSourcesDao.upsertSource(
      MediaLibrarySource(
        id: 0,
        libraryId: detachedLibId,
        storageId: storageId,
        path: null,
        name: 'Detached: $storageId',
        kind: MediaSourceKind.storage,
        createdAt: now,
      ),
    );

    // Drop the system lib + its sources (nodes untouched).
    await DbModule.mediaLibSourcesDao.deleteByLibrary(libId);
    await DbModule.mediaLibsDao.deleteById(libId);
  }

  // ── Legacy `local_lib` migration (D10, transactional) ──

  static Future<void> _migrateLegacyLib(
    Map<String, Storage> storageById,
  ) async {
    final db = AppDatabaseHolder.instance;
    await db.transaction(() async {
      final legacySources =
          await DbModule.mediaLibSourcesDao.getByLibrary(systemLibraryId);

      for (final source in legacySources) {
        // `path != null` sub-directory/file sources are dropped.
        if (source.path != null && source.path!.isNotEmpty) continue;

        final present = storageById.containsKey(source.storageId);
        if (present) {
          // Storage still exists → its system lib (create if missing) owns it.
          final libId = systemLibIdFor(source.storageId);
          final lib = await DbModule.mediaLibsDao.getById(libId);
          if (lib == null) {
            final now = DateTime.now();
            await DbModule.mediaLibsDao.upsert(
              MediaLibrary(
                id: libId,
                name: storageById[source.storageId]!.name,
                type: MediaLibraryType.system,
                createdAt: now,
                updatedAt: now,
              ).toCompanion(),
            );
          }
          final libSources =
              await DbModule.mediaLibSourcesDao.getLibrarySources(libId);
          final already = libSources.any(
            (s) => s.path == null && s.kind == MediaSourceKind.storage,
          );
          if (!already) {
            final now = DateTime.now();
            await DbModule.mediaLibSourcesDao.upsertSource(
              MediaLibrarySource(
                id: 0,
                libraryId: libId,
                storageId: source.storageId,
                path: null,
                name: storageById[source.storageId]!.name,
                kind: MediaSourceKind.storage,
                createdAt: now,
              ),
            );
          }
        } else {
          // Storage gone → detached lib owns it (no `sys_<id>` is created).
          final detachedLib = await DbModule.mediaLibsDao.getById(detachedLibId);
          if (detachedLib == null) {
            final now = DateTime.now();
            await DbModule.mediaLibsDao.upsert(
              MediaLibrary(
                id: detachedLibId,
                name: detachedLibName,
                type: MediaLibraryType.system,
                createdAt: now,
                updatedAt: now,
              ).toCompanion(),
            );
          }
          final detachedSources =
              await DbModule.mediaLibSourcesDao.getLibrarySources(detachedLibId);
          final already = detachedSources.any(
            (s) => s.storageId == source.storageId && s.path == null,
          );
          if (!already) {
            final now = DateTime.now();
            await DbModule.mediaLibSourcesDao.upsertSource(
              MediaLibrarySource(
                id: 0,
                libraryId: detachedLibId,
                storageId: source.storageId,
                path: null,
                name: 'Detached: ${source.storageId}',
                kind: MediaSourceKind.storage,
                createdAt: now,
              ),
            );
          }
        }
      }

      // Remove the legacy lib + its sources.
      await DbModule.mediaLibSourcesDao.deleteByLibrary(systemLibraryId);
      await DbModule.mediaLibsDao.deleteById(systemLibraryId);
    });
  }
}
