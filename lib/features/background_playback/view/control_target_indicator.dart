import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';

/// Visual semantics of "you are controlling the OTHER player": a distinct
/// accent used around the shared slider/control surfaces while 副音 is the
/// control target. One constant everywhere the indicator renders.
const Color kBackgroundTargetColor = Color(0xFF3D8BFF);

/// Outlines the CONTROL BAR while the shared controls target 副音, else returns
/// [child] untouched.
///
/// The border hugs whatever it wraps, so callers must wrap ONLY the bar itself
/// (see `ControlsOverlay`) — wrapping a full-screen `Positioned.fill`/`Align`
/// draws the frame around the whole screen instead, which reads as an overlay
/// over the picture.
class BackgroundControlTargetIndicator extends HookWidget {
  const BackgroundControlTargetIndicator({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final bg = useBackgroundPlaybackStore();
    // ONE select returning a bool: the previous short-circuit (`select(enabled)
    // && select(target) == …`) skipped the second lookup on some builds, so the
    // dependency was registered inconsistently and the frame could go stale.
    final active = bg.select(context, (s) => s.bgOwnsControls);
    if (!active) return child;
    // A 2px outline with no glow: it must read as "this bar drives 副音"
    // without painting over the picture or hiding the controls beneath.
    return Container(
      key: const ValueKey('bg_control_target_indicator'),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: kBackgroundTargetColor, width: 2),
      ),
      child: child,
    );
  }
}
