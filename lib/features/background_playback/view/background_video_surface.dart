import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/app_state.dart' show PlayerBackend;
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

/// Secondary (副音) video surface — mounted inside the player Stack above the
/// foreground render. While `showBgVideo` is OFF it must stay an ALL-positioned
/// child (the player Stack contract — see frame_tools_float_panel); the
/// hidden branch is a `Positioned.fill` with an empty box.
///
/// The surface renders the background engine's raw controllers directly (the
/// foreground [VideoView] never sees this engine), mirroring video_view.dart.
class BackgroundPlaybackVideoSurface extends HookWidget {
  const BackgroundPlaybackVideoSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final bg = useBackgroundPlaybackStore();
    // 全屏切换制 (fullscreen is the only implemented BgVideoLayout): the
    // surface shows the 副音 frame full-bleed while the DISPLAY target is 副音
    // (sub_media §5.3) — deliberately independent of the CONTROL target, so
    // watching the 副音 picture while driving the foreground stays possible.
    // showBgVideo persists independently — it just arms the capability.
    final visible = bg.select(
      context,
      (s) => s.bgOwnsDisplay && s.showBgVideo,
    );
    if (!visible) {
      return const Positioned.fill(
        child: ExcludeSemantics(child: SizedBox.shrink()),
      );
    }
    final engine = context.read<BackgroundPlaybackEngine>();
    final file = engine.file;
    final controller = engine.mediaKitVideoController;
    if (file == null ||
        !(file.type == ContentType.video || file.type == ContentType.audio)) {
      return const Positioned.fill(
        child: ExcludeSemantics(child: SizedBox.shrink()),
      );
    }
    // The engine can be disposing / swapping backends while this surface is
    // still visible; never dereference a null controller (that red-screens).
    if (engine.backend == PlayerBackend.mediaKit && controller == null) {
      return const Positioned.fill(
        child: ExcludeSemantics(child: SizedBox.shrink()),
      );
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: switch (engine.backend) {
          PlayerBackend.mediaKit => media_kit_video.Video(
              key: const ValueKey('background_video_surface'),
              controller: controller!,
              controls: media_kit_video.NoVideoControls,
              fit: BoxFit.contain,
            ),
          PlayerBackend.fvp => _FvpBackgroundSurface(engine: engine),
        },
      ),
    );
  }
}

/// fvp's VideoPlayer needs an explicit sized box; derive it from the decoded
/// frame (fall back to 16:9 before the controller reports dimensions).
class _FvpBackgroundSurface extends StatelessWidget {
  const _FvpBackgroundSurface({required this.engine});

  final BackgroundPlaybackEngine engine;

  @override
  Widget build(BuildContext context) {
    final c = engine.fvpVideoController;
    if (c == null) return const SizedBox.shrink();
    final size = c.value.size;
    final aspect = size.width > 0 && size.height > 0
        ? size.width / size.height
        : 16 / 9;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: VideoPlayer(c),
      ),
    );
  }
}
