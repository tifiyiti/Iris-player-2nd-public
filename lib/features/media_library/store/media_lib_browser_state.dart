import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/store/browser_open_mode.dart';

part 'media_lib_browser_state.freezed.dart';
part 'media_lib_browser_state.g.dart';

@freezed
abstract class MediaLibBrowserState with _$MediaLibBrowserState {
  const factory MediaLibBrowserState({
    @Default(BrowserOpenMode.tabs) BrowserOpenMode openMode,
    @Default(1) int lastActiveTab,
  }) = _MediaLibBrowserState;

  factory MediaLibBrowserState.fromJson(Map<String, dynamic> json) =>
      _$MediaLibBrowserStateFromJson(json);
}
