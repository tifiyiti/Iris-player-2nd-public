/// Search scope of the independent search page (F-007).
enum SearchScope {
  /// Union of all context sources (lib library sources / scenario sources),
  /// respecting each source's `recursive` flag, plus explicit items.
  allSources,

  /// Recursive search of the located directory (storageId + parentPath).
  currentDirRecursive,

  /// Direct-children-only search of the located directory.
  currentDirDirect,
}

/// The browsing context the search was entered from; drives the first-time
/// default scope (§2.3) and the location data snapshot (F-001).
enum SearchEntryContext {
  /// Media library pathTree root = the sources list (no location).
  libPathTreeRoot,

  /// Media library pathTree at a non-root directory.
  libPathTreeDir,

  /// Media library All Media view (no location).
  libAllMedia,

  /// Media library All Directories L1 root (no location).
  libAllDirsL1,

  /// Media library All Directories L2 (selected directory).
  libAllDirsL2,

  /// Scenario sources (Layer-1) root — scenario full-source union.
  scenarioSourcesRoot,

  /// Scenario browse (Layer-2) — located at the browsed storage/dir (three
  /// states: root / storage level / concrete path, v6-D1).
  scenarioBrowse,

  /// Scenario queue (resolved effective queue) — scenario full-source union
  /// plus explicit items, same sources as `scenarioSourcesRoot`.
  scenarioQueue,
}
