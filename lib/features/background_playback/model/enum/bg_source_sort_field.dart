/// Per-rule candidate ordering.
///
/// [tagAddedAt] is the tag-added timestamp (tag sources default to it,
/// newest first). Unknown/absent values sort LAST regardless of direction.
enum BgSourceSortField {
  /// When the media was added to the tag (tag / tag-filtered sources).
  tagAddedAt,

  /// File name.
  name,

  /// Full path.
  path,

  /// Probe duration.
  duration,

  /// Filesystem modified time.
  modifiedAt,

  /// File size.
  size,
}
