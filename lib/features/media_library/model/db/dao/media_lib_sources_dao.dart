import 'package:drift/drift.dart';
import 'package:iris/features/media_library/model/db/adapters/media_library_source_adapter.dart';
import 'package:iris/features/media_library/model/db/tables/media_lib_sources_table.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/utils/path_prefix_remap.dart';

part 'media_lib_sources_dao.g.dart';

@DriftAccessor(tables: [MediaLibSourcesTable])
class MediaLibSourcesDao extends DatabaseAccessor<AppDatabase> with _$MediaLibSourcesDaoMixin {
  MediaLibSourcesDao(super.db);

  Future<List<MediaLibrarySource>> getLibrarySources(String libraryId) async {
    final rows =
        await (select(mediaLibSourcesTable)..where((t) => t.libraryId.equals(libraryId))).get();

    return rows.map(MediaLibrarySourceAdapter.fromDb).toList();
  }

  Future<void> upsertSource(MediaLibrarySource source) {
    return into(mediaLibSourcesTable).insertOnConflictUpdate(
      source.toCompanion(),
    );
  }

  /// Updates an EXISTING source by primary key.
  ///
  /// [upsertSource] cannot be used for updates: its companion omits `id`, so
  /// drift's `insertOnConflictUpdate` (which only targets the primary key by
  /// default) never matches the existing row and instead collides with the
  /// `UNIQUE(library_id, storage_id, path)` constraint. Writing through a
  /// primary-key WHERE clause updates the intended row instead.
  Future<void> updateSource(MediaLibrarySource source) {
    return (update(mediaLibSourcesTable)
          ..where((t) => t.id.equals(source.id)))
        .write(source.toCompanion());
  }

  Future<void> deleteSource(int sourceId) {
    return (delete(mediaLibSourcesTable)..where((t) => t.id.equals(sourceId))).go();
  }

  // pre
  Future<void> deleteByLibrary(String libraryId) {
    return (delete(mediaLibSourcesTable)..where((t) => t.libraryId.equals(libraryId))).go();
  }

  Future<List<MediaLibSourcesTableData>> getByLibrary(String libraryId) {
    return (select(mediaLibSourcesTable)..where((t) => t.libraryId.equals(libraryId))).get();
  }

  Future<void> upsert(MediaLibSourcesTableCompanion entry) {
    return into(mediaLibSourcesTable).insertOnConflictUpdate(entry);
  }

  Future<void> deleteById(int id) {
    return (delete(mediaLibSourcesTable)..where((t) => t.id.equals(id))).go();
  }

  Future<List<MediaLibSourcesTableData>> getByStorageId(String storageId) {
    return (select(mediaLibSourcesTable)
          ..where((t) => t.storageId.equals(storageId)))
        .get();
  }

  /// Returns sources for [storageId] whose path overlaps with at least one
  /// of the given [rootPaths].  A source overlaps when:
  ///   - source.path is null  (covers entire storage)
  ///   - source.path is a prefix of a root path  (source is ancestor)
  ///   - a root path is a prefix of source.path  (source is descendant)
  ///   - source.path equals a root path exactly
  Future<List<MediaLibSourcesTableData>> getOverlappingSources(
    String storageId,
    List<String> rootPaths,
  ) async {
    final all = await getByStorageId(storageId);
    if (all.isEmpty) return all;

    final normalizedRoots = rootPaths
        .map(canonicalDbPath)
        .where((p) => p.isNotEmpty)
        .toList();

    return all.where((source) {
      if (source.path == null || source.path!.isEmpty) return true;
      final sp = source.path!;
      for (final root in normalizedRoots) {
        if (sp == root) return true;
        if (sp.startsWith('$root/')) return true;
        if (root.startsWith('$sp/')) return true;
      }
      return false;
    }).toList();
  }

  Future<void> updateSourceAggregates({
    required int sourceId,
    required int totalMediaCount,
    required int totalDirCount,
    required int totalItemCount,
    required int totalSizeInBytes,
    required int totalDurationMs,
  }) async {
    await (update(mediaLibSourcesTable)
          ..where((t) => t.id.equals(sourceId)))
        .write(MediaLibSourcesTableCompanion(
      totalMediaCount: Value(totalMediaCount),
      totalDirCount: Value(totalDirCount),
      totalItemCount: Value(totalItemCount),
      totalSizeInBytes: Value(totalSizeInBytes),
      totalDurationMs: Value(totalDurationMs),
      modifiedAt: Value(DateTime.now()),
    ));
  }

  /// Rewrites the leading [oldBase] of every source path for [storageId] to
  /// [newBase] (drive-letter reassignment). Whole-storage rows (`path == null`)
  /// are untouched.
  Future<int> remapPathPrefix({
    required String storageId,
    required String oldBase,
    required String newBase,
  }) {
    final query = buildPathPrefixRemap(
      table: 'media_lib_sources',
      keyColumn: 'storage_id',
      keyValue: storageId,
      oldBase: oldBase,
      newBase: newBase,
    );
    return customUpdate(
      query.sql,
      variables: query.variables,
      updates: {mediaLibSourcesTable},
    );
  }
}

/*
@DriftAccessor(tables: [MediaLibSourcesTable])
class MediaLibSourcesDao extends DatabaseAccessor<AppDatabase> with _$MediaLibSourcesDaoMixin {
  MediaLibSourcesDao(super.db);

  Future<List<MediaLibSourcesTableData>> getByLibrary(String libraryId) {
    return (select(mediaLibSourcesTable)..where((t) => t.libraryId.equals(libraryId))).get();
  }

  Future<void> insert(MediaLibSourcesTableCompanion entry) {
    return into(mediaLibSourcesTable).insert(entry);
  }

  Future<void> upsert(MediaLibSourcesTableCompanion entry) {
    return into(mediaLibSourcesTable).insertOnConflictUpdate(entry);
  }

  Future<void> deleteById(int id) {
    return (delete(mediaLibSourcesTable)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteByLibrary(String libraryId) {
    return (delete(mediaLibSourcesTable)..where((t) => t.libraryId.equals(libraryId))).go();
  }
}
*/
