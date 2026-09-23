import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_arc_scrubber.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_ring_dial_scrubber.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_snake_scrubber.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_time_lens_scrubber.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

/// Hosts the selected one-handed scrubber design persisted via AppState.
class PhoneOneHandedScrubber extends HookWidget {
  const PhoneOneHandedScrubber({
    super.key,
    required this.showControl,
    required this.color,
    required this.isLeftHanded,
    this.availableSpan,
    this.dialHeightPx,
  });

  final VoidCallback showControl;
  final Color? color;
  final bool isLeftHanded;

  /// Vertical span (px) between the screen top and the button-bar top, as
  /// measured by the hosting panel. Only the ring dial consumes it — its
  /// height share is defined against THIS span (bottom edge flush against
  /// the buttons, top edge free).
  final double? availableSpan;

  /// Explicit dial box height (px) from the sideway panel's sticky-height
  /// contract (see CircleSliderLayout). Only the ring dial consumes it;
  /// null falls back to [availableSpan] × the height-share knob.
  final double? dialHeightPx;

  @override
  Widget build(BuildContext context) {
    final PhoneOneHandedScrubberKind kind =
        useAppStore().select(context, (state) => state.phoneOneHandedScrubberKind);

    final Widget scrubber = switch (kind) {
      PhoneOneHandedScrubberKind.arc => PhoneArcScrubber(
          showControl: showControl,
          color: color,
          isLeftHanded: isLeftHanded,
        ),
      PhoneOneHandedScrubberKind.timeLens => PhoneTimeLensScrubber(
          showControl: showControl,
          color: color,
          isLeftHanded: isLeftHanded,
        ),
      PhoneOneHandedScrubberKind.snake => PhoneSnakeScrubber(
          showControl: showControl,
          color: color,
          isLeftHanded: isLeftHanded,
        ),
      PhoneOneHandedScrubberKind.dial => PhoneRingDialScrubber(
          showControl: showControl,
          color: color,
          isLeftHanded: isLeftHanded,
          availableSpan: availableSpan,
          dialHeightPx: dialHeightPx,
        ),
      // Unreachable through resolveScrubberSlot (classic always resolves to
      // the legacy circle slider slot); kept for an exhaustive switch.
      PhoneOneHandedScrubberKind.classic => const SizedBox.shrink(),
    };

    return scrubber;
  }
}
