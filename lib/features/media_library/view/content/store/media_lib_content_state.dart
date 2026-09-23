import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/view/content/model/media_lib_content_mode.dart';

part 'media_lib_content_state.freezed.dart';
part 'media_lib_content_state.g.dart';

@freezed
abstract class MediaLibContentState with _$MediaLibContentState {
  const factory MediaLibContentState({
    // Persisted (UI-related, not per-library)
    @Default(MediaLibContentMode.pathTree) MediaLibContentMode viewMode,
    @Default(MediaSortField.name) MediaSortField sortField,
    @Default(SortDirection.asc) SortDirection sortDirection,
    @Default(500) int pageSize,
    @Default(0) int requestedPage,
    @Default(true) bool folderFirst,
    @Default(true) bool showDeleteConfirmDialog,
    @Default(false) bool allDirsRecursive,
    @Default(true) bool allDirsHideEmpty,
    // Path-tree "only show dirs with media" (default ON, dirs only).
    @Default(true) bool pathTreeHideEmpty,

    // Transient (not persisted)
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(null) String? currentLibraryId,

    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(null) String? currentStorageId,

    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(null) String? currentSourceRootPath,

    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(null) String? currentParentPath,

    // AllDirs L2 selection (transient, not persisted)
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(null) String? allDirsSelectedStorageId,

    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(null) String? allDirsSelectedPath,

    // L1 page preserved while inside L2 (transient, not persisted)
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(null) int? allDirsL1Page,

    // Set when setLibrary auto-entered a single-source system lib: the
    // sources page was skipped, so navigating up from the source root must
    // return to the lib list instead of revealing the skipped page.
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(false) bool autoSkippedSources,
  }) = _MediaLibContentState;

  factory MediaLibContentState.fromJson(Map<String, dynamic> json) =>
      _$MediaLibContentStateFromJson(json);
}
