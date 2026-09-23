import 'package:iris/features/media_library/model/db/adapters/media_node_drift_adapter.dart';
import 'package:iris/features/media_library/model/db/dao/for_page/media_node_page_query.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/db/app_database.dart' show MediaNodesTableCompanion;
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/path_conv.dart';

final areaKeyLog = AreaKeyLog(LogKeys.legacyDb);

/// Syncs a directory's filesystem listing into the media library DB.
///
/// Mirrors the recursive-scan semantics: directories become directory nodes,
/// playable files become file nodes, non-playable files (e.g. JSON) are
/// dropped, rows removed from the filesystem are deleted (dir → whole
/// subtree), and the browsed directory's aggregates (plus ancestors to the
/// storage root) are recomputed (D2a).
///
/// Shared by the files-paged browser and the media lib content store, so the
/// media lib "pathTree source tile" and "allDirs L2" behave like the files
/// paged browser (realtime getfiles → DB update).
class MediaNodeSyncService {
  /// Syncs [items] — the filesystem listing of [dirPath] — into the DB.
  ///
  /// [dirPath] is the canonical (slash-free) storage-relative directory whose
  /// DB `parent_path` will match the synced children. Returns the pre-sync
  /// direct children (used by the files-paged browser to capture durable
  /// playback progress). Errors are swallowed and logged.
  Future<List<MediaNode>> syncDirectory({
    required Storage storage,
    required List<FileItem> items,
    required List<String> dirPath,
  }) async {
    try {
      // Canonical (slash-free) storage-relative directory, per this method's
      // contract: the raw form (e.g. the WebDAV root `['/']`) would land
      // `parent_path` as an empty string instead of NULL and never match the
      // storage-root query.
      final parentPath = canonicalDbPath(dirPath.join('/'));
      final dao = DbModule.mediaNodesDao;

      final query = MediaNodePageQuery(
        page: 1,
        pageSize: 10000,
        storageId: storage.id,
        parentPath: parentPath.isEmpty ? null : parentPath,
      );
      final dbResult = await dao.getPagedNodes(query);
      final dbRows = dbResult.items;

      final fsByName = {for (final f in items) f.name: f};
      final dbByName = {for (final r in dbRows) r.path.last: r};

      // Upsert new / heal kind-mismatched rows (folders stored as file rows,
      // or files with a stale media type).
      final dirUpserts = <MediaNodesTableCompanion>[];
      final fileUpserts = <MediaNodesTableCompanion>[];
      for (final f in items) {
        final fullPath = parentPath.isEmpty ? f.name : '$parentPath/${f.name}';
        // pathConv keeps a SAF `content://` tree prefix as one segment so
        // media_nodes.path stays reversible for SAF rows.
        final fullPathList = pathConv(fullPath);
        final existing = dbByName[f.name];
        if (f.isDir) {
          if (existing == null || !existing.isDir) {
            dirUpserts.add(
              MediaNode.directory(
                id: '${storage.id}:$fullPath',
                storageId: storage.id,
                path: fullPathList,
                parentPath: parentPath.isEmpty ? null : parentPath,
                pathDepth: fullPathList.length,
                name: f.name,
                modifiedAt: f.lastModified,
                isPresent: true,
              ).toCompanion(),
            );
          }
        } else if (f.isPlayable) {
          final mediaType = _contentTypeToMediaType(f.type);
          final needsUpdate = existing == null ||
              existing.isDir ||
              existing.maybeMap(
                file: (file) => file.mediaType != mediaType,
                orElse: () => true,
              );
          if (needsUpdate) {
            fileUpserts.add(
              MediaNode.file(
                id: '${storage.id}:$fullPath',
                storageId: storage.id,
                path: fullPathList,
                parentPath: parentPath.isEmpty ? null : parentPath,
                pathDepth: fullPathList.length,
                name: f.name,
                mediaType: mediaType,
                sizeInBytes: f.size,
                // Persist the real SAF document URI so DB-resolved playback /
                // probe never rebuilds a mangled path. Plain rows keep null.
                uri: isSafPath(f.uri) ? f.uri : null,
                modifiedAt: f.lastModified,
                isPresent: true,
              ).toCompanion(),
            );
          }
        } else {
          // Non-playable file (JSON, ...) — remove any stale DB row.
          if (existing != null) {
            await dao.deleteNode(storage.id, fullPath);
          }
        }
      }
      if (dirUpserts.isNotEmpty) await dao.batchUpsert(dirUpserts);
      if (fileUpserts.isNotEmpty) await dao.batchUpsert(fileUpserts);

      // Removed from fs but still in DB → delete (dir → whole subtree).
      for (final r in dbRows) {
        if (fsByName.containsKey(r.path.last)) continue;
        final fullPath = r.path.join('/');
        if (r.isDir) {
          await dao.deleteByPathPrefix(storage.id, fullPath);
        } else {
          await dao.deleteNode(storage.id, fullPath);
        }
      }

      // D2a: back-recursive aggregate update (after both upserts and stale
      // deletes). The browsed directory's own node may not exist → ensure it.
      final repo = DbModule.nodeRepository;
      await repo.ensureDirNode(storageId: storage.id, dirPath: parentPath);
      await repo.recomputeDirAncestors(
        storageId: storage.id,
        startPath: parentPath,
      );

      return dbRows;
    } catch (e) {
      areaKeyLog.e('MediaNodeSyncService sync error: $e');
      return const [];
    }
  }

  /// Reconstructs the absolute filesystem path for [canonicalSegments] (a
  /// storage-relative canonical path that includes the storage base segments,
  /// e.g. `storage/emulated/0/a_all` on Android) from the storage's own
  /// [Storage.basePath] (e.g. `['/storage/emulated/0']`).
  ///
  /// `storage.getFiles` needs the absolute form on POSIX (leading `/`); on
  /// Windows the base path already carries the drive root.
  static List<String> absoluteDirPath(
    Storage storage,
    List<String> canonicalSegments,
  ) {
    final baseCanonical = canonicalDbPath(storage.basePath.join('/'));
    // pathConv keeps a SAF `content://` base as one segment so the relative
    // suffix under it is computed correctly.
    final baseSegs =
        baseCanonical.isEmpty ? const <String>[] : pathConv(baseCanonical);
    final isUnderBase = canonicalSegments.length >= baseSegs.length &&
        _isPrefix(baseSegs, canonicalSegments);
    final relative = isUnderBase
        ? canonicalSegments.sublist(baseSegs.length)
        : canonicalSegments;
    return [...storage.basePath, ...relative];
  }

  static bool _isPrefix(List<String> prefix, List<String> segments) {
    for (var i = 0; i < prefix.length; i++) {
      if (i >= segments.length || prefix[i] != segments[i]) return false;
    }
    return true;
  }

  MediaType _contentTypeToMediaType(ContentType ct) {
    switch (ct) {
      case ContentType.video:
        return MediaType.video;
      case ContentType.audio:
        return MediaType.audio;
      case ContentType.image:
      case ContentType.other:
        return MediaType.unknown;
    }
  }
}
