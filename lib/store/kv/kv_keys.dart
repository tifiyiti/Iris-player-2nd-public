/// Central registry of every KV key the app persists through [KvStore].
///
/// Single source of truth for:
/// - call-site literals (import these instead of raw strings),
/// - portable-mode routing ([secretKeys]),
/// - first-run import enumeration ([all]).
abstract final class KvKeys {
  // ── Credential-bearing (machine-bound, NEVER migrate/portable) ──
  /// StorageState JSON — contains WebDAV/FTP credentials.
  static const String storageState = 'storage_state';

  // ── Ordinary application state (portable) ──
  static const String appState = 'app_state';
  static const String historyState = 'history_state';
  static const String playQueueState = 'playQueue_state';
  static const String queryPlayQueueState = 'query_play_queue_state';
  static const String playbackScenarioActiveId = 'playback_scenario_active_id';
  static const String mediaLibContentState = 'media_lib_content_state';
  static const String mediaLibsPageState = 'media_libs_page_state';
  static const String mediaLibSelection = 'media_lib_selection';
  static const String mediaLibSearchState = 'media_lib_search_state';
  static const String recursiveScanState = 'recursive_scan_state';
  static const String playbackScenariosSelection =
      'playback_scenarios_selection';

  /// 副音播放 state (queue + volume ratios + rate/shuffle/repeat prefs).
  /// Session fields (enabled/index/target) never reach the JSON.
  static const String backgroundPlaybackState = 'bg_playback_state';

  /// One-handed bottom control-group switch (selected group + floating
  /// button visibility/position). Survives restarts, travels with portable
  /// mode.
  static const String controlGroupState = 'control_group_state';

  // ── Internal markers (never imported, not part of `all`) ──

  /// One-shot import into this portable folder already completed.
  static const String internalImportDone = 'portable.import.done';

  /// User explicitly declined the one-shot import for this folder.
  static const String internalImportSkipped = 'portable.import.skipped';

  /// Keys holding credentials; they stay in machine-bound encrypted
  /// secure storage even in portable mode (the encryption key lives in the
  /// Windows Credential Manager and cannot travel with the folder).
  ///
  /// NOTE: with the metadata-settings era ON, WebDAV/FTP passwords live in
  /// the Drift DB itself (StoragesTable.password, plaintext since its
  /// introduction) — that DB travels with portable mode by design; this set
  /// only governs legacy-blob keys.
  static const Set<String> secretKeys = {storageState};

  /// Every known migratable application key, in stable enumeration order.
  static const List<String> all = [
    appState,
    historyState,
    playQueueState,
    queryPlayQueueState,
    playbackScenarioActiveId,
    mediaLibContentState,
    mediaLibsPageState,
    mediaLibSelection,
    mediaLibSearchState,
    recursiveScanState,
    playbackScenariosSelection,
    backgroundPlaybackState,
    controlGroupState,
  ];
}
