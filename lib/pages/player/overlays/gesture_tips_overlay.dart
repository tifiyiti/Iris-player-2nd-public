import 'package:flutter/material.dart';
import 'package:iris/features/phone/gesture_guide/view/gesture_guide_overlay.dart';

/// Legacy mount point kept for the player Stack and both menu triggers.
/// The implementation now lives in
/// `features/phone/gesture_guide/view/gesture_guide_overlay.dart` and renders
/// the live effective layout instead of the old hardcoded picture.
class GestureTipsOverlay extends StatelessWidget {
  const GestureTipsOverlay({super.key});

  @override
  Widget build(BuildContext context) =>
      // Windows AXTree-crash mitigation (#103808 family): decorative hint
      // layer, nothing for assistive tech to announce.
      ExcludeSemantics(child: const GestureGuideOverlay());
}
