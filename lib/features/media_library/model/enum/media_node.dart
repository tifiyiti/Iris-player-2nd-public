enum MediaNodeKind {
  directory,
  file,
}

enum MediaSortField {
  name,

  path,

  modifiedAt,
  createdAt,

  sizeInBytes,
  durationMs,

  /// Deep-probe resolution metric (width × height). NULLs (not probed)
  /// always sort last regardless of direction.
  pixelCount,

  directMediaCount,
  directDirCount,
  directItemCount,

  totalMediaCount,
  totalDirCount,
  totalItemCount,

  totalSizeInBytes,
  totalDurationMs,
}
