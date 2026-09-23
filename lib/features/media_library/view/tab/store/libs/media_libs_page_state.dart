import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sort_by.dart';
import 'package:iris/features/media_library/view/tab/store/libs/media_libs_runtime_state.dart';

part 'media_libs_page_state.freezed.dart';
part 'media_libs_page_state.g.dart';

@freezed
abstract class MediaLibsPageState with _$MediaLibsPageState {
  const factory MediaLibsPageState({
    @Default(MediaLibsListSortBy.name) MediaLibsListSortBy sortBy,
    @Default(SortDirection.asc) SortDirection sortDirection,
    // RUNTIME STATE (Reactive, but ignored by storage)
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(MediaLibsRuntimeState())
    MediaLibsRuntimeState runtime,
  }) = _MediaLibsPageState;

  factory MediaLibsPageState.fromJson(Map<String, dynamic> json) =>
      _$MediaLibsPageStateFromJson(json);
}
