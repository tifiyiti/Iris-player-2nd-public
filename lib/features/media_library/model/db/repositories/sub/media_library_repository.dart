import 'package:iris/features/media_library/model/db/dao/media_lib_sources_dao.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';

class MediaLibrarySourcesRepository {
  MediaLibSourcesDao sourcesDao;

  MediaLibrarySourcesRepository(
    this.sourcesDao,
  );

  /// Retrieves all configured sources for a specific library tab.
  Future<List<MediaLibrarySource>> getSources(String libraryId) {
    return sourcesDao.getLibrarySources(libraryId);
  }

  /// Adds a new storage or directory source to a library.
  Future<void> addSource(MediaLibrarySource source) {
    final now = DateTime.now();
    return sourcesDao.upsertSource(
      source.copyWith(
        createdAt: source.createdAt ?? now,
        modifiedAt: now,
      ),
    );
  }

  /// Updates an existing source.
  ///
  /// Since your `MediaLibrarySource` model uses `path` (List<String>),
  /// "renaming" a source usually means updating its path array or updating
  /// its aggregate counts after a scan.
  Future<void> updateSource(MediaLibrarySource source) {
    return sourcesDao.updateSource(
      source.copyWith(
        modifiedAt: DateTime.now(),
      ),
    );
  }

  /// Removes a source from the library.
  Future<void> removeSource(int sourceId) {
    return sourcesDao.deleteSource(sourceId);
  }
}
