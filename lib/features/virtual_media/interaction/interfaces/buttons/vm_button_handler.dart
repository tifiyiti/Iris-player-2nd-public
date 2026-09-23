import 'package:iris/features/virtual_media/interaction/virtual_media_interaction_facade.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';

/// Button intents routed through the virtual/real facade.
abstract final class VmButtonHandler {
  static Future<void> playPause({
    required bool isPlaying,
    required Future<void> Function() play,
    required Future<void> Function() pause,
  }) =>
      VirtualMediaInteractionFacade.handlePlayPause(
        isPlaying: isPlaying,
        realPlay: play,
        realPause: pause,
      );

  static Future<void> stop() =>
      VirtualMediaInteractionFacade.handleStop(
        realStop: () => PlaybackProviderRegistry.stop(),
      );

  /// Next / Prev always cross virtual bodies (spec §4).
  static Future<void> nextPrev({required bool forward}) async {
    if (VirtualMediaController.instance.isActive) {
      // Lightweight deactivation: the next feed overwrites the queue +
      // autoplay, so the heavy `stop` (empty-queue flash, autoplay off/on)
      // must not run here. The body's anchor is kept so prev resumes it.
      await VirtualMediaController.instance.deactivateForNavigation();
    }
    await PlaybackProviderRegistry.step(forward: forward);
  }
}
