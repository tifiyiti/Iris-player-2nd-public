import 'package:iris/features/media_library/services/media_uri.dart';
import 'package:iris/features/webdav_discovery/services/webdav_connect_coordinator.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_storage_store.dart';

/// A WebDAV item's play-ready address, or the reason it could not be produced.
class WebdavPlaybackTarget {
  const WebdavPlaybackTarget(this.uri, {this.failure});

  /// Absolute playable URL; null when [failure] is set.
  final String? uri;

  /// Non-null when the entry's host could not be resolved.
  final WebDavResolveOutcome? failure;
}

/// Makes a queued WebDAV item playable.
///
/// A wildcard entry whose host was never resolved is resolved once here (and the
/// host is recorded on the entry), then the address is rebuilt from the STORAGE
/// RECORD rather than from a URL that may have been baked in earlier — so
/// playback follows the current endpoint and a DHCP move does not break it.
Future<WebdavPlaybackTarget> webdavPlaybackTarget(
  WebDAVStorage storage,
  List<String> path,
) async {
  var current = storage;

  if (webdavNeedsResolution(current)) {
    final outcome = await webdavConnectCoordinator().resolveDetailed(current);
    if (!outcome.ok) return WebdavPlaybackTarget(null, failure: outcome);

    final refreshed = useStorageStore().findById(current.id);
    if (refreshed is WebDAVStorage) current = refreshed;
    if (webdavNeedsResolution(current)) {
      // Reported a host but the entry still carries no cache — treat as failed
      // rather than dialling the wildcard.
      return WebdavPlaybackTarget(null, failure: outcome);
    }
  }

  return WebdavPlaybackTarget(webdavPlayableUri(current, path));
}
