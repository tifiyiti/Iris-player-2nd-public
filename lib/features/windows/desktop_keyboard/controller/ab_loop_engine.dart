import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:iris/app_shutdown.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/features/windows/desktop_keyboard/store/ab_loop_state.dart';
import 'package:iris/features/windows/desktop_keyboard/store/ab_loop_store.dart';
import 'package:iris/models/player.dart';

export 'package:iris/features/windows/desktop_keyboard/store/ab_loop_state.dart'
    show AbEvent;

/// Maps a raw engine tick onto the timeline the A/B points live on.
///
/// Points are set from `MediaPlayer.position`, which is VIRTUAL while a VM
/// session is active — but the bound live source (`player.stream.position` /
/// fvp poll) is raw local. Without translation the loop compares coordinates
/// from two different axes and never (or wrongly) fires past segment 0.
/// Returns null when the tick must be ignored (segment switch in flight: the
/// new file reports pre-seek 0 and must never trigger a loop-back).
Duration? abEffectivePosition(
  Duration raw, {
  int? vmOffsetMs,
  bool suppress = false,
}) {
  if (suppress) return null;
  if (vmOffsetMs == null) return raw;
  return Duration(milliseconds: vmOffsetMs + raw.inMilliseconds);
}

/// Watches playback position and performs the loop-back seek.
///
/// Player hooks bind the engine to their LIVE position source on mount
/// ([attach]) and unbind on dispose ([detach]) — lifecycle-driven, so a
/// backend swap can never leave the loop riding a disposed player, and
/// detaching wipes stale points instead of carrying them into whatever
/// plays next. Executors are created per key event; all cross-event state
/// (points, armed flag, the binding itself) lives here / in [AbLoopStore].
class AbLoopEngine {
  AbLoopEngine._();

  static final AbLoopEngine instance = AbLoopEngine._();

  MediaPlayer? _seekTarget;
  StreamSubscription<Duration>? _positionSub;
  Timer? _poll;

  /// Bind to the live player.
  ///
  /// [precise] — native position stream (media_kit). [pollSource] — a live
  /// position GETTER polled coarsely; fvp/video_player wrappers expose no
  /// position stream and are immutable snapshots, but the closure reads the
  /// current controller, so every tick sees real progress. [player] supplies
  /// only the loop-back seek: its closures target the native player, so
  /// calling them stays safe even after the wrapper was rebuilt.
  void attach({
    required MediaPlayer player,
    Stream<Duration>? precise,
    Duration Function()? pollSource,
  }) {
    _unbind();
    _seekTarget = player;
    if (precise != null) {
      _positionSub = precise.listen(_tick);
    } else if (pollSource != null && !kIsWeb) {
      _poll = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _tick(pollSource()),
      );
    }
  }

  /// Unbind and wipe points — nothing bound means nothing may loop.
  void detach() {
    _unbind();
    _seekTarget = null;
    reset();
  }

  void _tick(Duration rawPosition) {
    // Shutdown fence: detach() rides a widget cleanup that a window close
    // never runs, so this tick can outlive the player — a loop-back seek here
    // would hit a player mid-dispose (media_kit asserts "[Player] has been
    // disposed"). Teardown never loops.
    if (AppShutdown.isActive) return;
    final state = useAbLoopStore().state;
    final a = state.pointA;
    final b = state.pointB;
    // Degenerate bounds (B <= A) can never form a section — skip instead of
    // seek-storming on every tick (belt-and-braces beside abReduce).
    if (!state.enabled || a == null || b == null || b <= a) return;
    // VM sessions expose virtual A/B but feed raw ticks: translate first.
    // A switch in flight reports pre-seek 0 — never loop on it.
    Duration effective = rawPosition;
    try {
      final vm = VirtualMediaController.instance;
      if (vm.isActive && vm.state.item != null) {
        final mapped = abEffectivePosition(
          rawPosition,
          vmOffsetMs: vm.currentOffsetMs,
          suppress: vm.state.transitioning,
        );
        if (mapped == null) return;
        effective = mapped;
      }
    } catch (_) {
      effective = rawPosition;
    }
    if (effective >= b) {
      _seekTarget?.seek(a);
    }
  }

  /// Reducer entry point used by keyboard/gesture dispatchers.
  void dispatch(AbEvent event, Duration position) {
    final store = useAbLoopStore();
    store.apply(abReduce(store.state, event, position));
  }

  /// Wipes points whenever playback leaves the current media (prev/next/
  /// close/restart), mirroring PotPlayer's per-item loop scope.
  void reset() {
    useAbLoopStore().apply(const AbLoopState());
  }

  void _unbind() {
    _positionSub?.cancel();
    _positionSub = null;
    _poll?.cancel();
    _poll = null;
  }

  void dispose() {
    _unbind();
    _seekTarget = null;
  }
}
