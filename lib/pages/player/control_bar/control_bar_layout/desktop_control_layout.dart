import 'package:flutter/material.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';

class DesktopControlLayout extends StatelessWidget {
  const DesktopControlLayout({super.key, required this.controls});

  final ControlBarControls controls;

  @override
  Widget build(BuildContext context) {
    // Button ordering lives in the shared left/right groups so the stacked
    // desktop layout renders the exact same arrangement.
    //
    // 副音 quick row (问题 5): the one-line bar has no "between the slider and
    // the bar" slot, so the row goes ABOVE the main row instead.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        controls.backgroundQuickBar,
        Row(
          children: [
            ...controls.desktopLeftButtons,
            Expanded(child: controls.slider),
            ...controls.desktopRightButtons,
          ],
        ),
      ],
    );
  }
}
