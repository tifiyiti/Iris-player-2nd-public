import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';

part 'media_node_page_query.freezed.dart';
part 'media_node_page_query.g.dart';

@freezed
abstract class MediaNodePageQuery with _$MediaNodePageQuery {
  const MediaNodePageQuery._();

  const factory MediaNodePageQuery({
    required int page,
    @Default(100) int pageSize,
// Sorting
    @Default(MediaSortField.name) MediaSortField sortField,
    @Default(SortDirection.asc) SortDirection sortDirection,
    @Default(false) bool folderFirst,

    /// When true the ordering groups same-parent files into contiguous blocks:
    /// ORDER BY (parentPath, sortField, name). Used by scenario folder sources
    /// with 同目录连续 (sourceInternalFirst). Direction applies to parentPath
    /// and sortField together.
    @Default(false) bool pathGroupFirst,

    // Filtering
    @Default(null) String? storageId,
    @Default(null) String? parentPath,
    @Default(null) MediaNodeKind? nodeKind, // If null, returns both dirs and files
    @Default(null) MediaType? mediaType, // video, audio, or null for all

    /// Restricts to any of these media types (e.g. only playable video/audio
    /// for scenario folder sources). When both [mediaType] and [mediaTypes]
    /// are set the node must match either.
    @Default(null) List<MediaType>? mediaTypes,
    @Default(false) bool recursive, // If true and parentPath is set, match path prefix instead of exact parentPath

    /// When true and [storageId] is set with [parentPath] null, matches every
    /// node of the storage regardless of depth (entire-storage queries).
    @Default(false) bool matchAllInStorage,

    /// When true, directory rows without a playable (video/audio) descendant
    /// are excluded via a correlated EXISTS (pathTree "only dirs with
    /// media"). File rows pass through untouched. Scoped queries
    /// ([mediaTypes] non-empty) already hide out-of-scope dirs, so this only
    /// adds filtering to the unscoped path. Defaults to false.
    @Default(false) bool hideEmptyDirs,

    // Search
    @Default(null) String? searchQuery, // For the search results page

    /// When false, the DAO skips the `COUNT(*)` total and returns
    /// `totalItems`/`totalPages` as `-1` (unknown). Callers that already know
    /// the total (scenario source window fetches) use this to avoid a full
    /// filtered count per window. Never read the total when false.
    @Default(true) bool countTotal,
  }) = _MediaNodePageQuery;

  factory MediaNodePageQuery.fromJson(Map<String, dynamic> json) =>
      _$MediaNodePageQueryFromJson(json);

  int get offset => (page - 1) * pageSize;
}
