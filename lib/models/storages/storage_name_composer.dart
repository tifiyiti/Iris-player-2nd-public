import 'package:iris/models/storages/storage_name_prefs.dart';

/// A saved storage paired with its id, used to keep composed default names
/// collision-free while letting the entry being edited keep its own name.
typedef StorageNameEntry = ({String id, String name});

/// Builds the previewable default storage name from the enabled [tags], in the
/// order the user lit them.
///
/// Each component contributes its trimmed value only when non-empty; the `port`
/// tag contributes nothing on a default port (the caller resolves that via
/// [isDefaultPort]). When every enabled component is empty the name degrades to
/// [host] so add-mode never previews a blank label.
String composeStorageName({
  required List<StorageNameTag> tags,
  required String separator,
  required String typeLabel,
  required String username,
  required String host,
  required String port,
  required bool isDefaultPort,
  required String pathLast,
}) {
  final parts = <String>[];
  for (final tag in tags) {
    final raw = switch (tag) {
      StorageNameTag.type => typeLabel,
      StorageNameTag.account => username,
      StorageNameTag.host => host,
      StorageNameTag.port => isDefaultPort ? '' : port,
      StorageNameTag.path => pathLast,
    };
    final value = raw.trim();
    if (value.isNotEmpty) parts.add(value);
  }
  if (parts.isEmpty) return host.trim();
  return parts.join(separator);
}

/// Last non-empty path segment across [basePath] entries, ignoring bare `/`
/// separators (a root-only path yields `''`).
String storageNameLastPathSegment(Iterable<String> basePath) {
  final segments = basePath.toList(growable: false);
  for (final segment in segments.reversed) {
    final pieces = segment.split('/');
    for (final piece in pieces.reversed) {
      final value = piece.trim();
      if (value.isNotEmpty) return value;
    }
  }
  return '';
}

/// WebDAV default port: 443 under https, 80 otherwise (empty counts as default).
bool isDefaultWebDavPort(String port, bool https) {
  final value = port.trim();
  if (value.isEmpty) return true;
  return https ? value == '443' : value == '80';
}

/// FTP default port: 21 (empty counts as default).
bool isDefaultFtpPort(String port) {
  final value = port.trim();
  return value.isEmpty || value == '21';
}

/// Returns [base] when it is free, otherwise appends ` (2)`, ` (3)`… until it
/// no longer collides with [existing].
///
/// The rule applies to every candidate — composed defaults and hand-typed
/// names alike. The entry whose id equals [excludeId] is ignored so an edited
/// storage can keep its own name.
String uniqueStorageName(
  String base,
  Iterable<StorageNameEntry> existing, {
  String? excludeId,
}) {
  final trimmed = base.trim();
  if (trimmed.isEmpty) return '';
  final taken = <String>{
    for (final entry in existing)
      if (excludeId == null || entry.id != excludeId) entry.name,
  };
  if (!taken.contains(trimmed)) return trimmed;
  var suffix = 2;
  while (taken.contains('$trimmed ($suffix)')) {
    suffix++;
  }
  return '$trimmed ($suffix)';
}
