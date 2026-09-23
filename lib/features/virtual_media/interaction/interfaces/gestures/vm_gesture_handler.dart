import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';

/// Gesture intents routed through virtual-aware translation.
/// Real media: delegate unchanged. Virtual: translate “single-media” gesture
/// into hidden-list operation (sequential single-file model).
abstract final class VmGestureHandler {
  static Future<void> onNext() async => _crossItem(forward: true);
  static Future<void> onPrev() async => _crossItem(forward: false);

  static Future<void> _crossItem({required bool forward}) async {
    if (VirtualMediaController.instance.isActive) {
      // Lightweight navigation: keep the queue + autoplay (the next feed
      // overwrites both) and the body's anchor so prev resumes it.
      await VirtualMediaController.instance.deactivateForNavigation();
    }
    await PlaybackProviderRegistry.step(forward: forward);
  }

  static Future<void> onSeek(Duration virtualPos,
      {required void Function(Duration local) rawSeek}) async {
    if (!VirtualMediaController.instance.isActive) {
      rawSeek(virtualPos);
      return;
    }
    await VirtualMediaController.instance
        .seekFromUi(virtualPos, rawSeek: rawSeek);
  }
}
