import 'package:flutter/material.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_editor_models.dart';

/// Responsible ONLY for computing regions & validating lines.
/// This keeps math out of the UI.
class GestureEditorController {
  /// Turn lines into a grid of normalized rectangles.
  List<Rect> computeRegions(List<EditableLine> lines) {
    final v = lines.where((l) => l.axis == LineAxis.vertical).toList()..sort((a, b) => a.value.compareTo(b.value));

    final h = lines.where((l) => l.axis == LineAxis.horizontal).toList()..sort((a, b) => a.value.compareTo(b.value));

    final xs = [0.0, ...v.map((e) => e.value), 1.0];
    final ys = [0.0, ...h.map((e) => e.value), 1.0];

    final regions = <Rect>[];
    for (var y = 0; y < ys.length - 1; y++) {
      for (var x = 0; x < xs.length - 1; x++) {
        regions.add(Rect.fromLTWH(
          xs[x],
          ys[y],
          xs[x + 1] - xs[x],
          ys[y + 1] - ys[y],
        ));
      }
    }
    return regions;
  }

  /// Ensure a dragged line never crosses another line and screen side
  double clampLineValue({
    required EditableLine line,
    required List<EditableLine> all,
    required double newValue,
  }) {
    final sameAxis = all.where((l) => l.axis == line.axis).toList()..sort((a, b) => a.value.compareTo(b.value));

    final index = sameAxis.indexOf(line);

    final min = index == 0 ? line.edgeGap : sameAxis[index - 1].value + line.minGap;

    final max = index == sameAxis.length - 1 ? 1.0 - line.edgeGap : sameAxis[index + 1].value - line.minGap;

    return newValue.clamp(min, max);
  }
}
