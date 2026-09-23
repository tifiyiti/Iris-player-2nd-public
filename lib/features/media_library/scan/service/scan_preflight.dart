import 'package:iris/features/webdav_discovery/services/webdav_connect_coordinator.dart';
import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/storages/file_list_result.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/webdav.dart';
import 'package:iris/store/use_storage_store.dart';

/// Outcome of preparing a storage for a recursive scan.
///
/// [ok] carries the storage the scan must dial — the resolved entry for a
/// wildcard WebDAV host, otherwise the original storage. A failure carries the
/// classified reason so the caller can explain it (never a silent no-op) and
/// must NOT start the scan.
class ScanPreflightResult {
  const ScanPreflightResult._({
    required this.storage,
    this.errorKind,
    this.errorDetail,
  });

  const ScanPreflightResult.ready(Storage storage) : this._(storage: storage);

  const ScanPreflightResult.failed({
    required StorageListErrorKind errorKind,
    required String? errorDetail,
  }) : this._(storage: null, errorKind: errorKind, errorDetail: errorDetail);

  final Storage? storage;
  final StorageListErrorKind? errorKind;
  final String? errorDetail;

  bool get ok => storage != null;
}

/// Lists a storage directory, reporting failures through [FileListResult].
typedef ScanPreflightList = Future<FileListResult> Function(
    Storage storage, List<String> path);

/// Resolves a wildcard WebDAV entry, excluding [excludeHosts] from discovery.
typedef ScanPreflightResolve = Future<WebDavResolveOutcome> Function(
    WebDAVStorage storage, Set<String> excludeHosts);

/// Reads the freshest persisted entry for [storageId] (the resolver records the
/// resolved host on it). Null when absent.
typedef ScanPreflightReadback = Storage? Function(String storageId);

Future<FileListResult> _defaultList(Storage storage, List<String> path) =>
    storage.getFilesDetailed(path);

Future<WebDavResolveOutcome> _defaultResolve(
        WebDAVStorage storage, Set<String> excludeHosts) =>
    webdavConnectCoordinator()
        .resolveDetailed(storage, excludeHosts: excludeHosts);

Storage? _defaultReadback(String storageId) =>
    useStorageStore().findById(storageId);

/// Pings a storage's live root before a recursive scan so an unreachable or
/// unauthorized host fails up front (with a classified reason) instead of
/// producing an empty scan.
///
/// This is the entry-side half of the "offline never deletes" contract: the
/// scanner also refuses to treat a failed listing as an empty directory, but a
/// preflight lets the UI explain the cause before any work starts.
///
/// Local storages are returned as-is (no network to validate). Wildcard WebDAV
/// entries are resolved to a concrete host first; a resolved-but-empty root
/// listing is treated as unreachable (the cache may point at the wrong
/// machine), so the DB snapshot is never purged.
Future<ScanPreflightResult> prepareStorageForScan(
  Storage storage, {
  ScanPreflightList? list,
  ScanPreflightResolve? resolve,
  ScanPreflightReadback? readback,
}) async {
  final listDir = list ?? _defaultList;

  // Only WebDAV/FTP classify listing failures. SAF `network` storages share
  // the local listing path, so they are returned as-is.
  final needsPreflight = storage.type == StorageType.webdav ||
      storage.type == StorageType.ftp;
  if (!needsPreflight) return ScanPreflightResult.ready(storage);

  var target = storage;

  if (target is WebDAVStorage && isIPv4WildcardHost(target.host)) {
    final resolveFn = resolve ?? _defaultResolve;
    final readbackFn = readback ?? _defaultReadback;

    final outcome = await resolveFn(target, const <String>{});
    if (!outcome.ok) {
      return ScanPreflightResult.failed(
        errorKind: outcome.errorKind ?? StorageListErrorKind.unreachable,
        errorDetail: outcome.errorDetail,
      );
    }
    target = _resolvedEntry(target, outcome.host!, readbackFn);
  }

  final result = await listDir(target, target.basePath);
  if (!result.hasError) {
    // A wildcard whose cached host answers but serves an EMPTY root is
    // suspicious: the cache may point at a different machine (shared/anonymous
    // credentials + a wide pattern). Re-resolve while ignoring the cache and
    // retry once; if still empty, treat as unreachable (never as proven-empty),
    // because the scan would otherwise purge this storage's snapshot rows.
    if (result.items.isEmpty &&
        target is WebDAVStorage &&
        isIPv4WildcardHost(target.host) &&
        target.resolvedHosts.isNotEmpty) {
      final resolveFn = resolve ?? _defaultResolve;
      final readbackFn = readback ?? _defaultReadback;

      final retryOutcome =
          await resolveFn(target, {...target.resolvedHosts});
      if (retryOutcome.ok) {
        final retryTarget =
            _resolvedEntry(target, retryOutcome.host!, readbackFn);
        final retry = await listDir(retryTarget, retryTarget.basePath);
        if (!retry.hasError && retry.items.isNotEmpty) {
          return ScanPreflightResult.ready(retryTarget);
        }
      }
      return const ScanPreflightResult.failed(
        errorKind: StorageListErrorKind.unreachable,
        errorDetail:
            'wildcard root listed empty; no other candidate host answered',
      );
    }
    return ScanPreflightResult.ready(target);
  }

  return ScanPreflightResult.failed(
    errorKind: result.errorKind ?? StorageListErrorKind.unknown,
    errorDetail: result.errorDetail,
  );
}

/// Prefers the persisted entry (the resolver records the resolved host there)
/// and falls back to a host-pinned copy when the store has not caught up.
WebDAVStorage _resolvedEntry(
  WebDAVStorage original,
  String host,
  ScanPreflightReadback readback,
) {
  final stored = readback(original.id);
  if (stored is WebDAVStorage) return stored;
  return original.copyWith(host: host);
}
