import 'package:iris/models/storages/storage.dart';

/// Identity of a family of entries that share the same wildcard pattern,
/// endpoint and account. Entries in one group differ ONLY by the machine they
/// resolve to, so they must never be auto-bound to the same host.
String webdavGroupKey(WebDAVStorage storage) =>
    '${storage.host}|${storage.port}|${storage.https}|${storage.username}';

/// Hosts currently claimed by OTHER entries in [current]'s group.
///
/// Only each sibling's active host (`resolvedHosts.first`) is claimed — that is
/// the machine the sibling is bound to right now. A resolver must treat these
/// as excluded so two same-credential entries end up on different machines
/// instead of silently collapsing onto one.
///
/// Entries LINKED into the same data scope (`data_scope_id`) are skipped: a
/// shared library is deliberately the same machine, so it must not exclude
/// itself. Only independent same-account entries still compete for hosts.
Set<String> claimedBySiblings(Storage current, Iterable<Storage> all) {
  if (current is! WebDAVStorage) return const <String>{};

  final key = webdavGroupKey(current);
  final myScope = current.dataScopeId ?? current.id;
  final claimed = <String>{};
  for (final storage in all) {
    if (storage is! WebDAVStorage) continue;
    if (storage.id == current.id) continue;
    if ((storage.dataScopeId ?? storage.id) == myScope) continue;
    if (webdavGroupKey(storage) != key) continue;
    final active = storage.resolvedHost;
    if (active != null && active.isNotEmpty) claimed.add(active);
  }
  return claimed;
}
