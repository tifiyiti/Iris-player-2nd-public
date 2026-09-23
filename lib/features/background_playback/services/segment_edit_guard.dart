import 'package:iris/features/background_playback/store/use_background_playback_store.dart';

/// Single choke point for the A-中心-B editor's transport freeze.
///
/// While the editor is open the current fg/bg pair must not be swapped out from
/// under the span being adjusted: prev/next are no-ops on both runtimes, and
/// natural completion pauses instead of advancing to the next entry. Every
/// freeze site reads THIS so the rule has exactly one home — the store remains
/// the single source of truth for the flag itself.
abstract final class SegmentEditGuard {
  /// True while the A-B editor owns the current pair (transport frozen).
  static bool get transportFrozen =>
      useBackgroundPlaybackStore().state.segmentEditMode;
}
