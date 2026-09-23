/// Traversal guards for remote (WebDAV / FTP) storage request paths.
library;

/// True when a storage-relative path segment could escape the storage root.
///
/// WebDAV/FTP entries keep a **leading slash** in their base path — `['/']` is
/// the root and `['/media']` a subfolder — so a bare `'/'`, or a segment that
/// merely contains slashes, is legitimate and must NOT be rejected.
///
/// Only genuine traversal elements are unsafe: a `.`/`..` part between
/// separators, or a backslash that some servers would read as a separator.
///
/// The previous check rejected ANY segment containing `'/'`, which silently
/// broke the listing of every WebDAV/FTP storage created with the default
/// path: the request was dropped before it was ever sent, so the browser
/// showed an empty folder while the connection test (which never applied the
/// guard) succeeded.
bool isUnsafeRemotePathSegment(String segment) {
  if (segment.contains(r'\')) return true;
  for (final part in segment.split('/')) {
    if (part == '.' || part == '..') return true;
  }
  return false;
}

/// True when any element of [path] could escape the storage root.
bool hasUnsafeRemotePathSegment(Iterable<String> path) =>
    path.any(isUnsafeRemotePathSegment);
