/// Actions a focused playlist-style list (the scenario queue / preview) can
/// perform, aligned with PotPlayer's `PL >` (playlist) context menu.
///
/// The list OWNS these keys while it holds keyboard focus, so the same keys do
/// not also drive the global player (e.g. `↑/↓` must move the list cursor, not
/// change volume). Actions with no IRIS equivalent are mapped and consumed as
/// no-ops so the global binding cannot fire either (see [kPotPlayerPlaylistMap]).
enum PlaylistAction {
  // Navigation
  cursorUp,
  cursorDown,
  cursorFirst,
  cursorLast,

  // Selection
  selectAll,
  invertSelection,

  // Playback
  play,

  // Remove
  removeSelected,
  removeUnselected,
  removeMissing,

  // Sort
  sortAscending,
  sortDescending,
  sortByFolder,
  sortByName,
  sortBySize,
  sortByDuration,
  sortByDate,
  sortRandom,

  // Information / navigation of the media
  fileInformation,
  openLocation,
  search,

  // Playlist / queue / sources
  savePlaylist,
  openPlaylist,
  closePlaylist,
  addToPlaybackQueue,
  addFiles,
  addFolder,
  addUrl,
  detectDurations,

  // Consumed no-ops (no IRIS equivalent — pressing does nothing, and must not
  // fall through to a conflicting global shortcut).
  copy,
  paste,
  pasteRecent,
  editTitle,
  renameFile,
  albumNew,
  albumEdit,
  albumDelete,
}
