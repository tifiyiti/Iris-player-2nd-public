import 'package:flutter/widgets.dart';

/// Scrub-drag window lock: while any slider holds a drag session the desktop
/// window keeps its bounds and the video adapts inside it, instead of the
/// window refitting per segment resolution mid-drag (which reads as picture
/// size jumps + control-bar flicker).
///
/// Publish side (backends) keeps emitting decoded sizes; consumers gate here.
/// [isScrubbing]/[isHolding] come from the single-owner `ScrubDragStore`.
bool shouldSkipResizeDuringDrag({
  required bool isScrubbing,
  required bool isHolding,
}) {
  return isScrubbing || isHolding;
}

/// Video-adapts-window during a drag: 1:1 ([BoxFit.none]) would change the
/// surface size with each segment, so it degrades to [BoxFit.contain] while
/// dragging. All other fits already adapt inside a fixed window.
BoxFit resolveDraggingBoxFit(BoxFit effectiveFit, {required bool isDragging}) {
  if (isDragging && effectiveFit == BoxFit.none) return BoxFit.contain;
  return effectiveFit;
}
