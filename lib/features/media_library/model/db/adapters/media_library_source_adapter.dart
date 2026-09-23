import 'package:drift/drift.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/path_conv.dart';

extension MediaLibrarySourceAdapter on MediaLibrarySource {
  static MediaLibrarySource fromDb(MediaLibSourcesTableData row) {
    return MediaLibrarySource(
      id: row.id,
      libraryId: row.libraryId,
      storageId: row.storageId,
      path: row.path == null ? null : pathConv(row.path!),
      name: row.name,
      pathDepth: row.pathDepth,
      kind: row.mediaSourceKind,
      totalMediaCount: row.totalMediaCount,
      totalDirCount: row.totalDirCount,
      totalItemCount: row.totalItemCount,
      totalSizeInBytes: row.totalSizeInBytes,
      totalDurationMs: row.totalDurationMs,
      modifiedAt: row.modifiedAt,
      createdAt: row.createdAt,
    );
  }

  MediaLibSourcesTableCompanion toCompanion() {
    return MediaLibSourcesTableCompanion.insert(
      libraryId: libraryId,
      storageId: storageId,
      // path: Value(path?.join('/')),  // legacy: caller-slash-dependent
      path: Value(path == null ? null : canonicalDbPath(path!.join('/'))), // unified
      name: Value(name),
      pathDepth: Value(pathDepth),
      mediaSourceKind: Value(kind),
      totalMediaCount: Value(totalMediaCount),
      totalDirCount: Value(totalDirCount),
      totalItemCount: Value(totalItemCount),
      totalSizeInBytes: Value(totalSizeInBytes),
      totalDurationMs: Value(totalDurationMs),
      modifiedAt: Value(modifiedAt),
      createdAt: Value(createdAt),
    );
  }
}
