import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/background_runtime_scope.dart';
import 'package:iris/features/background_playback/view/mapping_scope.dart';
import 'package:iris/features/virtual_media/interaction/controller/virtual_bg_link.dart';
import 'package:iris/hooks/player/use_fvp_player.dart';
import 'package:iris/hooks/player/use_media_kit_player.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/player.dart';
import 'package:iris/pages/player/player_focus_shell.dart';
import 'package:provider/provider.dart';

class PlayerView extends HookWidget {
  const PlayerView({super.key, required this.playerBackend});

  final PlayerBackend playerBackend;

  @override
  Widget build(BuildContext context) {
    final Widget player = switch (playerBackend) {
      PlayerBackend.mediaKit => const _MediaKitPlayerHost(),
      PlayerBackend.fvp => const _FvpPlayerHost(),
    };
    // WHY the shell: the picture must be able to take the keyboard focus the
    // queue list grabbed (see PlayerFocusShell) — otherwise `↑/↓` keep driving
    // the list after the user clicked the video. Wrapping HERE covers both
    // backends and the whole player subtree (video, gesture layer, controls,
    // title bar) in one place.
    return PlayerFocusShell(child: player);
  }
}

/// Wraps the player with the 副音 runtime observer — but only while the
/// secondary engine actually exists (preload ON, or 副音 running). When the
/// user turned the preload off and 副音 is idle, the provider is absent and the
/// observer must not be mounted (it reads the engine).
Widget _withBackgroundRuntime(BuildContext context, Widget player) {
  final hasEngine = useBackgroundPlaybackStore().select(
    context,
    (s) => s.enabled || s.keepWarmPlayer,
  );
  if (!hasEngine) return player;
  // The VM link rides inside the 副音 runtime scope so it can drive the 副音
  // store on VM block/video transitions (VM may import bg; bg must not import
  // VM).
  return BackgroundRuntimeScope(child: VmSubAudioLinkScope(child: player));
}

class _MediaKitPlayerHost extends HookWidget {
  const _MediaKitPlayerHost();

  @override
  Widget build(BuildContext context) {
    final player = useMediaKitPlayer(context);
    return Provider<MediaPlayer>.value(
      value: player,
      child: MappingScope(
        child: _withBackgroundRuntime(
          context,
          const Player(key: ValueKey('media_kit_player')),
        ),
      ),
    );
  }
}

class _FvpPlayerHost extends HookWidget {
  const _FvpPlayerHost();

  @override
  Widget build(BuildContext context) {
    final player = useFvpPlayer(context);
    return Provider<MediaPlayer>.value(
      value: player,
      child: MappingScope(
        child: _withBackgroundRuntime(
          context,
          const Player(key: ValueKey('fvp_player')),
        ),
      ),
    );
  }
}
