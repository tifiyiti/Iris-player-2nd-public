import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:iris/models/storages/storage.dart';

/// A matched existing entry that already owns a data scope the candidate can
/// join: the new entry will share [scopeId] (its media library) instead of
/// storing a duplicate node tree.
typedef StorageScopeMatch = ({Storage storage, String scopeId});

/// The data scope id of [storage] (its own id when independent).
String storageDataScopeId(Storage storage) => storage.dataScopeId ?? storage.id;

/// Finds an existing entry whose account **and** path tree are the same as (or
/// contain / are contained by) [candidate]'s, so the two can share one library.
///
/// Account match (per type):
///   * WebDAV — port, https, username equal and host patterns OVERLAP. Host
///     overlap compares the configured host plus every resolved host, so a
///     wildcard entry and a concrete-IP entry for the same machine match
///     without any network access.
///   * FTP — port, username equal and hosts overlap.
/// Local storages never share (they return `null`).
///
/// Path-tree match is equality or containment (one basePath is a prefix of the
/// other), since both map onto the same server-root-relative node paths.
StorageScopeMatch? findSharedScope(
  Storage candidate,
  Iterable<Storage> existing,
) {
  if (candidate is LocalStorage) return null;
  for (final other in existing) {
    if (other.id == candidate.id) continue;
    if (!_sameAccount(candidate, other)) continue;
    if (!_pathsRelated(candidate.basePath, other.basePath)) continue;
    return (storage: other, scopeId: storageDataScopeId(other));
  }
  return null;
}

/// Resolves which entry should supply the endpoint/credentials for a node row
/// whose stored `storage_id` is [nodeStorageId].
///
/// A shared-scope node keeps the SCOPE's id (its canonical identity), but that
/// entry may be deleted while the node survives, or it may hold a staler
/// resolved host than the entry the user is currently browsing. Precedence:
///  1. [viewingId] when it belongs to the node's scope (freshest endpoint);
///  2. the entry named by [nodeStorageId] itself;
///  3. any surviving member of the node's scope;
///  4. `null` (caller degrades, e.g. to a local-address fallback).
Storage? resolveStorageForNode({
  required Iterable<Storage> storages,
  String? viewingId,
  required String nodeStorageId,
}) {
  String scopeOf(Storage s) => s.dataScopeId ?? s.id;
  final owner = storages.firstWhereOrNull((s) => s.id == nodeStorageId);
  final scope = owner?.dataScopeId ?? nodeStorageId;

  final viewing =
      viewingId == null ? null : storages.firstWhereOrNull((s) => s.id == viewingId);
  if (viewing != null && scopeOf(viewing) == scope) return viewing;

  if (owner != null) return owner;
  return storages.firstWhereOrNull((s) => scopeOf(s) == scope);
}

/// Repairs data-scope links on freshly imported entries after they are merged
/// into [merged]: an imported `dataScopeId` whose target id is absent from the
/// merged set is re-resolved against the surviving entries (first same-tree
/// match) or cleared to independent. Entries already present locally keep their
/// links untouched.
///
/// Prevents cross-device imports from carrying a dangling scope id (pointing at
/// an id that never came along) that would otherwise yield a permanently empty
/// shared library.
List<Storage> repairImportedScopes({
  required List<Storage> merged,
  required Iterable<Storage> imported,
}) {
  final importedIds = {for (final s in imported) s.id};
  return [
    for (final s in merged)
      if (!importedIds.contains(s.id) || s.dataScopeId == null)
        s
      else
        _repairImportedScope(s, merged),
  ];
}

Storage _repairImportedScope(Storage storage, List<Storage> merged) {
  final targetExists = merged.any(
    (o) => o.id != storage.id && o.id == storage.dataScopeId,
  );
  if (targetExists) return storage;
  final match = findSharedScope(
    storage,
    merged.where((o) => o.id != storage.id),
  );
  return _withDataScope(storage, match?.scopeId);
}

Storage _withDataScope(Storage storage, String? scopeId) => storage.map(
      local: (s) => s.copyWith(dataScopeId: scopeId),
      webdav: (s) => s.copyWith(dataScopeId: scopeId),
      ftp: (s) => s.copyWith(dataScopeId: scopeId),
    );

bool _sameAccount(Storage a, Storage b) {
  if (a is WebDAVStorage && b is WebDAVStorage) {
    if (a.port != b.port || a.https != b.https || a.username != b.username) {
      return false;
    }
    return _hostsOverlap(_webdavHosts(a), _webdavHosts(b));
  }
  if (a is FTPStorage && b is FTPStorage) {
    if (a.port != b.port || a.username != b.username) return false;
    return _hostsOverlap(<String>[a.host], <String>[b.host]);
  }
  return false;
}

List<String> _webdavHosts(WebDAVStorage s) => <String>[s.host, ...s.resolvedHosts];

/// True when any host on one side matches any host on the other: equal concrete
/// hosts, or two IPv4 wildcard patterns that can describe the same address.
bool _hostsOverlap(List<String> a, List<String> b) {
  for (final x in a) {
    for (final y in b) {
      if (_hostMatches(x, y)) return true;
    }
  }
  return false;
}

bool _hostMatches(String a, String b) {
  final left = a.trim().toLowerCase();
  final right = b.trim().toLowerCase();
  if (left.isEmpty || right.isEmpty) return false;
  if (left == right) return true;
  if (!left.contains('*') && !right.contains('*')) return false;

  final lp = left.split('.');
  final rp = right.split('.');
  if (lp.length != 4 || rp.length != 4) return false;
  for (var i = 0; i < 4; i++) {
    if (lp[i] == '*' || rp[i] == '*') continue;
    if (lp[i] != rp[i]) return false;
  }
  return true;
}

bool _pathsRelated(List<String> a, List<String> b) {
  final sa = _segments(a);
  final sb = _segments(b);
  final shared = math.min(sa.length, sb.length);
  for (var i = 0; i < shared; i++) {
    if (sa[i] != sb[i]) return false;
  }
  // One list is a prefix of the other (equal lists included).
  return true;
}

List<String> _segments(List<String> basePath) => basePath
    .join('/')
    .split('/')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList(growable: false);
