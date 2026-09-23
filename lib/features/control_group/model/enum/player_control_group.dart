/// Ordered bottom control-bar button groups.
///
/// The one-handed side panel (and the phone portrait bottom bar) shows exactly
/// one group at a time. Values are cycled in declaration order via
/// [nextPlayerControlGroup]; new groups append at the END so previously
/// persisted values keep their meaning.
enum PlayerControlGroup {
  /// Group 1 — the legacy transport / secondary control row.
  playback,

  /// Group 2 — the 副音 quick-control surface (all [BackgroundQuickBar]
  /// buttons, independent of the standalone quick-bar switch).
  background,
}

/// Next group in declaration order, wrapping at the end.
///
/// The single authority for the toggle order: adding a group only requires a
/// new enum value, never a call-site switch.
PlayerControlGroup nextPlayerControlGroup(PlayerControlGroup current) {
  final List<PlayerControlGroup> values = PlayerControlGroup.values;
  return values[(current.index + 1) % values.length];
}
