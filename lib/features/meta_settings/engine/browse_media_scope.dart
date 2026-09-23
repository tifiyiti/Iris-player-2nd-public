import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/store/app_state.dart';

/// Single consumption funnel of the browse-media-scope setting.
///
/// Every browsing surface resolves its filter here instead of reading
/// [AppState.browseMediaScope] raw: when the metadata-settings subsystem is
/// unavailable the scope degrades to [BrowseMediaScope.all], so legacy-mode
/// runs behave exactly as before the feature existed (the option is absent,
/// nothing is filtered).
///
/// Pure functions only — no store access — so call sites can pass whatever
/// gate snapshot they already hold (mirrors resolveKeyboardScheme).

BrowseMediaScope resolveBrowseMediaScope(
  AppState state, {
  required bool metadataEnabled,
}) =>
    metadataEnabled ? state.browseMediaScope : BrowseMediaScope.all;

/// SQL-facing projection: `all` yields null (no mediaTypes predicate at all,
/// preserving existing query plans), a narrowed scope yields its single type.
List<MediaType>? scopeMediaTypes(BrowseMediaScope scope) => switch (scope) {
      BrowseMediaScope.all => null,
      BrowseMediaScope.videoOnly => const [MediaType.video],
      BrowseMediaScope.audioOnly => const [MediaType.audio],
    };

/// SQL-facing projection for queries whose legacy baseline already excluded
/// non-playable rows (`[video, audio]`, keeping MediaType.unknown junk out).
/// `all` keeps that baseline instead of degrading to null — the scope can
/// only narrow visibility, never widen it past the playable filter.
List<MediaType> playableScopeMediaTypes(BrowseMediaScope scope) => switch (scope) {
      BrowseMediaScope.all => const [MediaType.video, MediaType.audio],
      BrowseMediaScope.videoOnly => const [MediaType.video],
      BrowseMediaScope.audioOnly => const [MediaType.audio],
    };
