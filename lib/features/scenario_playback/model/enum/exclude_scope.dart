/// Scope of an exclude rule (C6/F1).
enum ExcludeScope {
  /// Only prunes media that originate from a specific [scenario_sources] row.
  /// Requires `sourceId`.
  source,

  /// Prunes media regardless of which source produced them.
  scenario,
}
