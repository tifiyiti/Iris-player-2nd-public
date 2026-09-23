import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/media_lib/media_library.dart';
import 'package:iris/features/media_library/view/tab/store/libs/enum/load_state.dart';

part 'media_libs_runtime_state.freezed.dart';
part 'media_libs_runtime_state.g.dart';

@freezed
abstract class MediaLibsRuntimeState with _$MediaLibsRuntimeState {
  const factory MediaLibsRuntimeState({
    @Default(LoadState.initial) LoadState state,
    @Default([]) List<MediaLibrary> libraries,
    Object? error,
  }) = _MediaLibsRuntimeState;

  factory MediaLibsRuntimeState.fromJson(Map<String, dynamic> json) =>
      _$MediaLibsRuntimeStateFromJson(json);
}
