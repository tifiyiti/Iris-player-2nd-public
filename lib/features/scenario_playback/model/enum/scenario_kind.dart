/// The kind of a Scenario row (C2/A1).
///
/// The SystemPlayingScenario is still a [Scenario] — only its [ScenarioKind]
/// differs. There is no parallel "SystemPlayingScenario" domain class.
enum ScenarioKind {
  /// The single current-playing workspace row. Never deleted, never shown as a
  /// normal saved scenario. `version` is always null (E4).
  systemPlaying,

  /// A custom desktop entry's OWN independently saved "system playing"
  /// workspace. One row per independent entry (id held by the entry), created
  /// lazily on first launch. Never shown as a normal saved scenario, never
  /// deleted through the scenario UI; removed only with its owning entry.
  entryWorkspace,

  /// A user-saved playback plan. Never connects to the Player directly; it is
  /// loaded into the systemPlaying row via Override/Append/Copy/Sync.
  userSaved,
}
