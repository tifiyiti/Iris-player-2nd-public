import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/search/model/search_scope.dart';

part 'media_search_state.freezed.dart';
part 'media_search_state.g.dart';

/// Persisted search-page preferences (F-010 / §6.1).
///
/// The single persistence entry of the search feature. [lastScope] is only
/// echoed in the scope menu (grayed, read-only) and never overrides the
/// context-derived default scope (F-007). [respectExcludes] has no effect in
/// the media-library context (the modifier UI is scenario-only, F-010).
@freezed
abstract class MediaLibSearchState with _$MediaLibSearchState {
  const factory MediaLibSearchState({
    @Default(<String>[]) List<String> history,
    @Default(50) int pageSize,
    SearchScope? lastScope,
    @Default(false) bool respectExcludes,
  }) = _MediaLibSearchState;

  factory MediaLibSearchState.fromJson(Map<String, dynamic> json) =>
      _$MediaLibSearchStateFromJson(json);
}
