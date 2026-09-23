import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/player.dart';
import 'package:provider/provider.dart';

/// True when the shared control surface is currently retargeted to 副音.
///
/// A closed gate always reads as foreground — even against a stale target
/// flag — so deactivation can never leave the transport driving a dead bg.
bool isBackgroundControlTarget(BuildContext context) {
  return useBackgroundPlaybackStore().state.bgOwnsControls;
}

/// Resolves the player the shared controls should drive right now.
///
/// Foreground = the nearest `Provider<MediaPlayer>` (today's behavior,
/// untouched). Background (副音 enabled + target) = the secondary engine
/// bridged through [BackgroundPlaybackEngine.asMediaPlayer], clamped to the
/// published seek ceiling (仅当前 + 高同步 bound; null = free seek). The
/// keyboard hook lives ABOVE the subtree provider override, so it calls this
/// instead of reading [MediaPlayer] directly.
MediaPlayer resolveActivePlayer(BuildContext context) {
  final s = useBackgroundPlaybackStore().state;
  if (s.bgOwnsControls) {
    final engine = context.read<BackgroundPlaybackEngine>();
    return engine.asMediaPlayer(
      seekFloorMs: s.bgSeekFloorLocalMs,
      seekCeilingMs: s.bgSeekCeilingLocalMs,
    );
  }
  return context.read<MediaPlayer>();
}

/// Wraps one layer of the player Stack (gesture/controls overlays). While
/// 副音 is the control target it overrides [MediaPlayer] for its subtree with
/// the secondary engine's snapshot, so every existing control widget
/// (slider, play/pause, seek gestures, …) re-targets without modification;
/// otherwise the subtree keeps the foreground provider untouched.
class BackgroundTargetMediaScope extends HookWidget {
  const BackgroundTargetMediaScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = useBackgroundPlaybackStore();
    final isBgTarget =
        bg.select(context, (s) => s.bgOwnsControls);
    if (!isBgTarget) return child;
    final engine = context.read<BackgroundPlaybackEngine>();
    final floor = bg.select(context, (s) => s.bgSeekFloorLocalMs);
    final ceiling = bg.select(context, (s) => s.bgSeekCeilingLocalMs);
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) => Provider<MediaPlayer>.value(
        value: engine.asMediaPlayer(
          seekFloorMs: floor,
          seekCeilingMs: ceiling,
        ),
        child: child,
      ),
    );
  }
}
