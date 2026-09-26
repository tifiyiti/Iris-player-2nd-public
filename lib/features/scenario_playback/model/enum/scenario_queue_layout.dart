/// Toolbar layout of the scenario play queue.
///
/// - [v1]: the original responsive bar (`DynamicResponsiveBar`) — actions
///   spread across one or two rows depending on the available width.
/// - [v2]: a strictly single-row bar that keeps only sort, page navigation,
///   total/per-page, and go-to-current, folding every other action into one
///   overflow button.
/// - [v3]: the same control set as [v2] rendered as a floating grid of square
///   tiles OVER the list. No bottom bar exists at all, so the list takes the
///   full height; the bar is translucent, always visible and draggable.
///
/// Persisted BY NAME as the `window.scenarioQueueLayout*` AUX rows, so the value
/// names are a storage contract: renaming one requires a data migration. There is
/// no single default — the shipped default is PER SCREEN SHAPE (landscape v3,
/// the other two v2; see `AppState.scenarioQueueLayout*`), and it applies only
/// when nothing is stored, so an install that already chose keeps its choice.
/// See `ScenarioQueueProfile` for the per-screen-shape split.
enum ScenarioQueueLayout { v1, v2, v3 }

/// The layout the toggle button switches TO.
///
/// A three-step cycle, so the single queue-wide toggle reaches every layout
/// without growing a submenu; the button renders the label of the layout it
/// moves TO, which is why this is not an index into a list.
ScenarioQueueLayout nextScenarioQueueLayout(ScenarioQueueLayout current) =>
    switch (current) {
      ScenarioQueueLayout.v1 => ScenarioQueueLayout.v2,
      ScenarioQueueLayout.v2 => ScenarioQueueLayout.v3,
      ScenarioQueueLayout.v3 => ScenarioQueueLayout.v1,
    };
