import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/meta_settings/engine/browse_media_scope.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

/// Snapshot convenience over [resolveBrowseMediaScope] for non-widget callers
/// (stores, data sources, queue backends) that don't already hold an AppState.
///
/// The engine itself stays pure — no store access — so this lives separately:
/// widgets and stores holding a state snapshot must call the engine directly
/// with the state they have. Gate OFF degrades to `all`, keeping legacy-mode
/// runs unfiltered.
List<MediaType>? currentBrowseScopeMediaTypes() {
  final AppState app = useAppStore().state;
  return scopeMediaTypes(resolveBrowseMediaScope(
    app,
    metadataEnabled: app.useMetadataSettings && MetaSettingsModule.ready,
  ));
}

/// Same snapshot through [playableScopeMediaTypes] — for queries whose legacy
/// baseline already excluded non-playable rows (all → `[video, audio]`).
List<MediaType> currentPlayableScopeMediaTypes() {
  final AppState app = useAppStore().state;
  return playableScopeMediaTypes(resolveBrowseMediaScope(
    app,
    metadataEnabled: app.useMetadataSettings && MetaSettingsModule.ready,
  ));
}

/// Resolved scope enum itself — for filesystem-first surfaces filtering
/// through FileItem.matchesBrowseScope instead of a SQL mediaTypes list.
BrowseMediaScope currentBrowseMediaScope() {
  final AppState app = useAppStore().state;
  return resolveBrowseMediaScope(
    app,
    metadataEnabled: app.useMetadataSettings && MetaSettingsModule.ready,
  );
}
