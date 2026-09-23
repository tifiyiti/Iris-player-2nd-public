/// How the resolver handles duplicate media (C5/A3/E3).
///
/// This is the ONLY duplicate-handling concept. `duplicateHandling` is
/// forbidden anywhere in the codebase.
enum DuplicatePolicy {
  /// The same mediaRef may appear multiple times (duplicated=true on repeats).
  allowDuplicate,

  /// The resolver keeps only the first occurrence of each mediaRef.
  deduplicate,
}
