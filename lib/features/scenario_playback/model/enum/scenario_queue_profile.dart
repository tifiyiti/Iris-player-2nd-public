import 'package:flutter/widgets.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_queue_layout.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/utils/platform.dart';

/// Which screen shape the scenario play queue is being shown in.
///
/// The toolbar layout AND the V3 floating bar's spot are remembered PER PROFILE
/// (see [AppState.scenarioQueueLayoutFor]). A phone held sideways has room for
/// a different toolbar than the same phone held upright, and a desktop dock
/// panel is a third shape again. One shared value would mean rotating the phone
/// silently rearranges the toolbar the user just set up, and that fiddling on
/// the phone moves the desktop's dock panel.
enum ScenarioQueueProfile { desktop, portrait, landscape }

/// The profile the queue is being shown in RIGHT NOW.
///
/// Desktop is ONE bucket because a resized window has no stable rotation — the
/// same reason the control-group floating switch keeps a single desktop flag
/// instead of splitting by orientation. Phones split per orientation and defer
/// to [isLandscapeOrientation], so this and the control bar / player overlay
/// can never disagree about which orientation is in force.
ScenarioQueueProfile resolveScenarioQueueProfile({
  required bool mobile,
  required ScreenOrientation runtimeOrientation,
  required Orientation realOrientation,
}) {
  if (!mobile) return ScenarioQueueProfile.desktop;
  return isLandscapeOrientation(
    runtimeOrientation: runtimeOrientation,
    realOrientation: realOrientation,
  )
      ? ScenarioQueueProfile.landscape
      : ScenarioQueueProfile.portrait;
}

/// [resolveScenarioQueueProfile] for a surface that can read the ambient
/// [MediaQuery] — the single call every queue entry point (the page, the data
/// source's layout toggle, the settings editor) uses, so the three cannot drift.
ScenarioQueueProfile scenarioQueueProfileOf(
  BuildContext context, {
  required AppState state,
  bool? mobile,
}) =>
    resolveScenarioQueueProfile(
      mobile: mobile ?? isMobilePlatform,
      runtimeOrientation: state.runtimeOrientation,
      realOrientation: MediaQuery.orientationOf(context),
    );

/// Per-profile reads and writes on [AppState].
///
/// Freezed's generated `copyWith` takes named fields, so a profile-dispatched
/// write has to switch somewhere; doing it here keeps every caller
/// (`ScenarioQueuePage`, the data source's toggle, the settings editor) from
/// re-implementing the same three-way switch.
extension ScenarioQueueProfileState on AppState {
  ScenarioQueueLayout scenarioQueueLayoutFor(ScenarioQueueProfile profile) =>
      switch (profile) {
        ScenarioQueueProfile.desktop => scenarioQueueLayoutDesktop,
        ScenarioQueueProfile.portrait => scenarioQueueLayoutPortrait,
        ScenarioQueueProfile.landscape => scenarioQueueLayoutLandscape,
      };

  /// The remembered spot of the V3 floating bar. Only
  /// [ScenarioQueueLayout.v3] reads it; V1 and V2 have no floating bar, so their
  /// stored offsets are simply carried along untouched.
  Offset scenarioQueueBarOffsetFor(ScenarioQueueProfile profile) =>
      switch (profile) {
        ScenarioQueueProfile.desktop => scenarioQueueBarOffsetDesktop,
        ScenarioQueueProfile.portrait => scenarioQueueBarOffsetPortrait,
        ScenarioQueueProfile.landscape => scenarioQueueBarOffsetLandscape,
      };

  AppState withScenarioQueueLayout(
    ScenarioQueueProfile profile,
    ScenarioQueueLayout layout,
  ) =>
      switch (profile) {
        ScenarioQueueProfile.desktop =>
          copyWith(scenarioQueueLayoutDesktop: layout),
        ScenarioQueueProfile.portrait =>
          copyWith(scenarioQueueLayoutPortrait: layout),
        ScenarioQueueProfile.landscape =>
          copyWith(scenarioQueueLayoutLandscape: layout),
      };

  AppState withScenarioQueueBarOffset(
    ScenarioQueueProfile profile,
    Offset offset,
  ) =>
      switch (profile) {
        ScenarioQueueProfile.desktop =>
          copyWith(scenarioQueueBarOffsetDesktop: offset),
        ScenarioQueueProfile.portrait =>
          copyWith(scenarioQueueBarOffsetPortrait: offset),
        ScenarioQueueProfile.landscape =>
          copyWith(scenarioQueueBarOffsetLandscape: offset),
      };
}

/// The AUX row (under the `window.` prefix) each profile stores its toolbar
/// layout in, and the `"x,y"` row its V3 bar spot lives in.
///
/// The names are a storage contract, so they live next to the enum rather than
/// being spelled out at each call site.
extension ScenarioQueueProfileRows on ScenarioQueueProfile {
  String get layoutRow => switch (this) {
        ScenarioQueueProfile.desktop => 'scenarioQueueLayoutDesktop',
        ScenarioQueueProfile.portrait => 'scenarioQueueLayoutPortrait',
        ScenarioQueueProfile.landscape => 'scenarioQueueLayoutLandscape',
      };

  String get barOffsetRow => switch (this) {
        ScenarioQueueProfile.desktop => 'scenarioQueueBarOffsetDesktop',
        ScenarioQueueProfile.portrait => 'scenarioQueueBarOffsetPortrait',
        ScenarioQueueProfile.landscape => 'scenarioQueueBarOffsetLandscape',
      };
}
