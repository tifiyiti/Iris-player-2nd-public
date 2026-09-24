import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/player.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:provider/provider.dart';

/// Frame-step button shared by the phone frame-tools panel.
///
/// Tap = single frame step (the player hook pauses first — PotPlayer parity,
/// identical on desktop via D/F). Long-press = fast frame playback: once the
/// long-press threshold is reached the first step fires, then a repeating
/// timer keeps stepping until release. The timer skips a tick while the
/// previous step is still in flight so a slow backend cannot pile up commands.
class FrameStepButton extends HookWidget {
  const FrameStepButton({
    super.key,
    required this.forward,
    required this.tooltip,
    required this.icon,
    this.color,
  });

  final bool forward;
  final String tooltip;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final timer = useRef<Timer?>(null);
    // Guards the repeating timer against overlapping steps: a tick is dropped
    // when the previous `stepOnce` has not resolved yet.
    final stepping = useRef(false);

    Future<void> stepOnce() async {
      if (stepping.value) return;
      stepping.value = true;
      try {
        final player = context.read<MediaPlayer>();
        if (forward) {
          await player.stepForward();
        } else {
          await player.stepBackward();
        }
      } finally {
        stepping.value = false;
      }
    }

    void startRepeating() {
      timer.value?.cancel();
      stepOnce();
      timer.value =
          Timer.periodic(const Duration(milliseconds: 140), (_) => stepOnce());
    }

    void stop() {
      timer.value?.cancel();
      timer.value = null;
    }

    useEffect(() => stop, const []);

    // AXTree stability (#182444): tap-only tooltip while a UIA client is
    // attached, so the OverlayPortal never grafts mid-playback. The long-press
    // trigger is disabled here so it cannot compete with fast frame playback.
    return a11yTooltip(
      context: context,
      message: tooltip,
      longPressPassthrough: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: stepOnce,
        onLongPressStart: (_) => startRepeating(),
        onLongPressEnd: (_) => stop(),
        onLongPressCancel: stop,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
