/// How the generic settings renderer materializes a def into UI.
///
/// One widget kind per row family; each kind is its own HookWidget so per-row
/// hook chains stay fixed regardless of list shape (hook-order discipline).
enum SettingWidgetKind {
  /// Boolean row: trailing checkbox + row tap toggles (legacy house style).
  toggle,

  /// Enum row: tap opens the shared radio dialog (showEnumRadioDialog).
  enumPick,

  /// Numeric row with a slider editor.
  slider,

  /// Fully hand-written interaction dispatched via `editorKey`
  /// (e.g. gesture-region editor). The metadata system never invents
  /// behavior here; it only routes.
  custom,
}
