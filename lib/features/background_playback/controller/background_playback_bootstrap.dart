import 'package:iris/features/background_playback/controller/background_playback_router.dart';
import 'package:iris/features/background_playback/services/background_candidate_source.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';
import 'package:iris/features/tag_play/playback/tag_voice_candidate_source.dart';

/// One-time startup wiring of the 副音 playback subsystem (called right after
/// [PlaybackProviderRegistry.init] in app_startup):
/// - registers the background router so foreground nav actions retarget while
///   the control target is the background engine;
/// - registers the 「副音备选」tag candidate source for launch/refresh.
abstract final class BackgroundPlaybackBootstrap {
  static bool _done = false;

  static void init() {
    if (_done) return;
    _done = true;
    PlaybackProviderRegistry.registerBackgroundRouter(
      BackgroundPlaybackRouterImpl(),
    );
    BackgroundCandidateSources.register(TagVoiceCandidateSource());
  }

  /// Test hook.
  static void resetForTests() => _done = false;
}
