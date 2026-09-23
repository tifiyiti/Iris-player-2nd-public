import 'package:iris/features/media_library/model/db/adapters/media_library.dart';
import 'package:iris/features/media_library/model/db/adapters/media_library_source_adapter.dart';
import 'package:iris/features/media_library/model/db/dao/media_lib_sources_dao.dart';
import 'package:iris/features/media_library/model/db/dao/media_libs_dao.dart';
import 'package:iris/features/media_library/model/media_lib/media_library.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/models/db/app_database.dart';

class LibraryRepository {
  final AppDatabase _db;
  final MediaLibsDao _libsDao;
  final MediaLibSourcesDao _sourcesDao;

  LibraryRepository({
    required AppDatabase db,
    required MediaLibsDao libsDao,
    required MediaLibSourcesDao sourcesDao,
  })  : _db = db,
        _libsDao = libsDao,
        _sourcesDao = sourcesDao;

  /// Retrieves all configured libraries from the database.
  Future<List<MediaLibrary>> getLibraries() async {
    final rows = await _libsDao.getAll();
    return rows.map(MediaLibraryDriftAdapter.fromDb).toList();
  }

  /// Fetches a specific library by its unique ID.
  Future<MediaLibrary?> getLibraryById(String id) async {
    final row = await _libsDao.getById(id);
    return row != null ? MediaLibraryDriftAdapter.fromDb(row) : null;
  }

  /// Creates or updates a library definition.
  Future<void> upsertLibrary(MediaLibrary library) async {
    final now = DateTime.now();

    final existing = await getLibraryById(library.id);

    final next = existing == null
        ? library.copyWith(
            createdAt: now,
            updatedAt: now,
          )
        : library.copyWith(
            createdAt: existing.createdAt,
            updatedAt: now,
          );

    await _libsDao.upsert(next.toCompanion());
  }

  /// Deletes a library and all associated source definitions.
  ///
  /// Without delete media nodes.
  Future<void> deleteLibrary(String libraryId) async {
    await _db.transaction(() async {
      await _sourcesDao.deleteByLibrary(libraryId);
      await _libsDao.deleteById(libraryId);
    });
  }

  // --- Source Management ---

  /// Retrieves all physical storage sources linked to a specific library.
  Future<List<MediaLibrarySource>> getSources(String libraryId) async {
    final rows = await _sourcesDao.getByLibrary(libraryId);
    return rows.map(MediaLibrarySourceAdapter.fromDb).toList();
  }

  /// Adds or updates a data source (e.g., a specific folder on a drive).
  Future<void> upsertSource(MediaLibrarySource source) {
    return _sourcesDao.upsert(source.toCompanion());
  }

  /// Removes a source from the library configuration.
  Future<void> removeSource(int sourceId) {
    return _sourcesDao.deleteById(sourceId);
  }
}
