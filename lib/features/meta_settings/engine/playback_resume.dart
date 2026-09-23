import 'package:iris/models/store/app_state.dart';

/// Single consumption funnel of the resume-on-startup setting.
///
/// Startup-resume paths resolve their autoplay decision here instead of
/// reading [AppState.resumeOnStartup] raw: when the metadata-settings
/// subsystem is unavailable the decision degrades to `true` — the row is
/// absent (hidden via DefVisibility) and the expected behavior (reopen the
/// app → the last media continues) holds.
///
/// Pure functions only — no store access — so call sites can pass whatever
/// gate snapshot they already hold (mirrors resolveBrowseMediaScope).
///
/// NEVER read the session flag [AppState.autoPlay] for this decision: it is
/// the runtime "media session has play intent" latch, force-reset to false
/// on every load, so it is always false exactly when this decision runs.
bool resolveResumeOnStartup(
  AppState state, {
  required bool metadataEnabled,
}) =>
    metadataEnabled ? state.resumeOnStartup : true;

/// Single consumption funnel of the custom-desktop-entry autoplay decision.
///
/// A COLD launch (the app was not running; Android delivered the shortcut
/// extra) follows the same startup-resume policy as the default icon, so an
/// entry never disagrees with the normal entry about whether to start playing.
/// A WARM launch (the shortcut was tapped while the app already owns a live
/// player session) preserves the player's CURRENT play intent: a paused player
/// stays paused, a playing player keeps playing. Shortcut activation switches
/// scenario/tag only — it must never force a paused session to play.
bool resolveEntryAutoplay(
  AppState state, {
  required bool coldStart,
  required bool metadataEnabled,
}) =>
    coldStart
        ? resolveResumeOnStartup(state, metadataEnabled: metadataEnabled)
        : state.autoPlay;
