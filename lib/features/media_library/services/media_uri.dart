import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/webdav.dart' show isIPv4WildcardHost;
import 'package:iris/utils/path_conv.dart';

/// Whether [storage]'s host pattern still has to be resolved before it can be
/// dialled.
///
/// A wildcard entry with an empty cache would otherwise produce a URL carrying
/// `192.168.*.*`, which no player can open — callers resolve once (recording the
/// host) and rebuild the address.
bool webdavNeedsResolution(WebDAVStorage storage) =>
    isIPv4WildcardHost(storage.host) && storage.resolvedHosts.isEmpty;

/// Playable/probe URL for a WebDAV node, built from the entry's CURRENT
/// endpoint.
///
/// The host is `resolvedHost ?? host`, so a wildcard entry follows its most
/// recent resolution: neither a DHCP change nor a different resolved candidate
/// leaves a stale address baked into the database. Scheme, port and the
/// storage-relative path come from the entry, and credentials are NOT embedded
/// — the player hooks attach `storage.getAuth()` as a request header.
String webdavPlayableUri(
  WebDAVStorage storage,
  List<String> canonicalSegments,
) {
  final canonical = canonicalDbPath(canonicalSegments.join('/'));
  final segments = canonical.isEmpty ? const <String>[] : pathConv(canonical);
  return Uri(
    scheme: storage.https ? 'https' : 'http',
    host: storage.resolvedHost ?? storage.host,
    port: int.tryParse(storage.port),
    pathSegments: segments,
  ).toString();
}

/// Relative playable address for an FTP node.
///
/// FTP playback goes through the local `MediaStream` proxy: producers put this
/// RELATIVE form into `FileItem.uri` and the player entry points prepend
/// `MediaStream().url` (see `use_media_kit_player`, `use_fvp_player` and
/// `background_playback_engine`). Credentials travel as the `getAuth()` request
/// header, never in the URL. The shape matches `getFTPFiles`' listing URIs
/// (leading `/` inside `path`), so live and DB-resolved items agree.
String ftpPlayableUri(FTPStorage storage, List<String> canonicalSegments) {
  final canonical = canonicalDbPath(canonicalSegments.join('/'));
  return Uri.encodeFull(
    'ftp?host=${storage.host}&port=${storage.port}&path=/$canonical',
  );
}

/// Playable/probe address for a `media_nodes` row.
///
/// The DB stores the storage-relative PATH as the identity; a remote address is
/// DERIVED here so the list keeps the DB as its single source while staying
/// valid when the host moves. Precedence:
///
///  1. a persisted [uri] (SAF `content://` documents — the path alone cannot
///     rebuild them);
///  2. a remote entry — WebDAV via [webdavPlayableUri] (absolute), FTP via
///     [ftpPlayableUri] (relative, proxy-prefixed by the player);
///  3. otherwise the local path form ([playableUri]).
String mediaNodePlayableUri(
  Storage? storage,
  List<String> segments, {
  String? uri,
}) {
  if (uri != null && uri.isNotEmpty) return uri;
  if (storage is WebDAVStorage) return webdavPlayableUri(storage, segments);
  if (storage is FTPStorage) return ftpPlayableUri(storage, segments);
  return playableUri(segments);
}
