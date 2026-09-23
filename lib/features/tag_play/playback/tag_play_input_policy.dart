/// Availability of the tag-play numeric input bar.
///
/// Desktop ALWAYS shows it — the numpad entry keys prefill the operator and
/// there is no touch equivalent, so hiding it would strand the shortcut.
/// Phones/tablets default to hidden (direct tapping is the natural gesture)
/// but the user may opt in per device via `tagplay.inputBar`.
bool resolveTagPlayInputBarEnabled({
  required bool stored,
  required bool isDesktop,
}) =>
    isDesktop || stored;
