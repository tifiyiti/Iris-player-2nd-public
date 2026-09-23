import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/view/content/model/lib_content_item.dart';
import 'package:iris/features/media_library/view/tab/store/libs/enum/load_state.dart';

part 'media_lib_content_runtime_state.freezed.dart';

@freezed
abstract class MediaLibContentRuntimeState with _$MediaLibContentRuntimeState {
  const factory MediaLibContentRuntimeState({
    @Default(LoadState.initial) LoadState state,
    @Default([]) List<LibContentItem> items,
    @Default(1) int currentPage,
    @Default(1) int totalPages,
    @Default(0) int totalItems,
    Object? error,
  }) = _MediaLibContentRuntimeState;
}
