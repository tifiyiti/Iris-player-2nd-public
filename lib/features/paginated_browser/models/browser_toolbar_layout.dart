/// Arrangement of a paginated browser's bottom toolbar.
///
/// - [responsive]: the original [DynamicResponsiveBar] — controls spread over
///   one row, two rows, or a wrap fallback depending on the measured width.
///   The default for every browser.
/// - [compactSingleLine]: a strictly single-row bar (the scenario queue's V2).
///   Keeps only sort, page navigation, total/per-page and go-to-current inline
///   and folds every other action into one overflow button.
/// - [floatingGrid]: no bottom bar at all (the scenario queue's V3). The same
///   controls as [compactSingleLine] render as a translucent, draggable grid of
///   square tiles floating OVER the list, which then takes the full height.
///
/// Opt-in per page, so a layout change can never leak into the eight other
/// browsers that share the responsive bar.
enum BrowserToolbarLayout { responsive, compactSingleLine, floatingGrid }
