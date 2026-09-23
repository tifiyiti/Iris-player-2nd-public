import 'package:iris/features/background_playback/services/current_foreground_media_key.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';

/// Delegate the [PlaybackProviderRegistry] consults when the user actions
/// (next/prev/shuffle/repeat/stop) must drive the 副音 engine instead of the
/// foreground queue. Registered by [BackgroundPlaybackBootstrap].
abstract interface class BackgroundPlaybackRouter {
  bool get targetIsBackground;

  Future<void> step({required bool forward});

  Future<void> toggleShuffle();

  Future<void> toggleRepeat();

  Future<void> stop();
}

class BackgroundPlaybackRouterImpl implements BackgroundPlaybackRouter {
  @override
  bool get targetIsBackground {
    return useBackgroundPlaybackStore().state.bgOwnsControls;
  }

  @override
  Future<void> step({required bool forward}) async {
    await useBackgroundPlaybackStore().step(
      forward: forward,
      excludedKey: excludedForegroundKey(),
      userInitiated: true,
    );
  }

  @override
  Future<void> toggleShuffle() =>
      useBackgroundPlaybackStore().toggleShuffle();

  @override
  Future<void> toggleRepeat() => useBackgroundPlaybackStore().cycleBgRepeat();

  /// Stop on the background runtime = pause in place (the current file stays
  /// loaded; the queue is never reset by a stop).
  @override
  Future<void> stop() async {
    useBackgroundPlaybackStore().setPlaying(false);
  }
}
