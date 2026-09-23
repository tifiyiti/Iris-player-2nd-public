/// Lifetime of an exclude rule (C6/A6/E1).
enum ExcludeLifetime {
  /// Lives only on the SystemPlayingScenario workspace. Cleared on Override and
  /// never saved to a User Scenario.
  temporary,

  /// Survives within the current workspace and is copied to a User Scenario on
  /// Save As. Does NOT survive an Override (E1) — it is workspace state, not a
  /// permanent blacklist.
  persistent,
}
