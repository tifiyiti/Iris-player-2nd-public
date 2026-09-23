import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/player.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class VideoView extends HookWidget {
  const VideoView({
    super.key,
    required this.fit,
    this.mediaKey,
  });

  final BoxFit fit;
  final String? mediaKey;

  @override
  Widget build(BuildContext context) {
    final player = context.read<MediaPlayer>();

    // Windows AXTree-crash mitigation (#103808 family): the video surface is
    // pure pixels to assistive tech, yet it is the single largest source of
    // per-frame semantics churn — exclude it from the accessibility bridge.
    // Stage 3: keep the outer ExcludeSemantics node stable across file
    // switches — only the inner Video is keyed so the tree does not replace
    // the semantics boundary itself (avoids a dangling AXTree node on every switch).
    return ExcludeSemantics(
      child: switch (player) {
        MediaKitPlayer player => Video(
            key: mediaKey != null ? ValueKey(mediaKey) : null,
            controller: player.controller,
            controls: NoVideoControls,
            fit: fit == BoxFit.none ? BoxFit.contain : fit,
          ),
        FvpPlayer player => FittedBox(
            fit: fit,
            child: SizedBox(
              width: player.width,
              height: player.height,
              child: VideoPlayer(player.controller),
            ),
          ),
        _ => Container(),
      },
    );
  }
}
