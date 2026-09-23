import 'dart:ui';

import 'package:iris/models/store/gesture_region.dart';

/// Axis of a draggable split line
enum LineAxis { vertical, horizontal }

/// A line that splits the screen into regions.
/// `value` is normalized (0.0 – 1.0).
class EditableLine {
  EditableLine({
    required this.axis,
    required this.value,
    this.minGap = 0.1,
    this.edgeGap = 0.1,
  });

  final LineAxis axis;
  double value;
  final double minGap;
  final double edgeGap;
}

class LayoutTopology {
  LayoutTopology({
    required this.lines,
  });

  final List<EditableLine> lines;

  /// Derives the minimal set of interior split lines from a layout's regions
  /// (deduped by axis:value at 3-decimal precision). Shared by the full-screen
  /// editor entry and the in-guide edit mode so both edit the same geometry.
  static List<EditableLine> computeEditableLines(GestureLayout layout) {
    final lines = <EditableLine>[];
    for (final r in layout.regions) {
      final rect = r.normalizedRect;
      if (rect.left > 0 && rect.left < 1) {
        lines.add(EditableLine(axis: LineAxis.vertical, value: rect.left));
      }
      if (rect.right > 0 && rect.right < 1) {
        lines.add(EditableLine(axis: LineAxis.vertical, value: rect.right));
      }
      if (rect.top > 0 && rect.top < 1) {
        lines.add(EditableLine(axis: LineAxis.horizontal, value: rect.top));
      }
      if (rect.bottom > 0 && rect.bottom < 1) {
        lines.add(EditableLine(axis: LineAxis.horizontal, value: rect.bottom));
      }
    }
    return {
      for (final l in lines) '${l.axis}:${l.value.toStringAsFixed(3)}': l,
    }.values.toList();
  }

  List<Rect> computeRegions() {
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

  GestureLayout rebuildLayoutFrom(GestureLayout oldLayout, GestureIntent intent) {
    final newRects = computeRegions();

    final rebuilt = newRects.map((r) {
      final action = _matchAction(r, oldLayout.regions);
      return GestureRegion(
        normalizedRect: r,
        action: GestureAction(type: action),
      );
    }).toList();

    return GestureLayout(intent: intent, regions: rebuilt);
  }

  GestureActionType _matchAction(Rect newRect, List<GestureRegion> oldRegions) {
    double best = 0;
    GestureActionType bestAction = GestureActionType.none;

    for (final old in oldRegions) {
      final overlap = _intersectionArea(newRect, old.normalizedRect);
      if (overlap > best) {
        best = overlap;
        bestAction = old.action.type;
      }
    }

    return bestAction;
  }

  double _intersectionArea(Rect a, Rect b) {
    final double dx = (a.right < b.left || b.right < a.left)
        ? 0
        : (a.right < b.right ? a.right : b.right) - (a.left > b.left ? a.left : b.left);

    final double dy = (a.bottom < b.top || b.bottom < a.top)
        ? 0
        : (a.bottom < b.bottom ? a.bottom : b.bottom) - (a.top > b.top ? a.top : b.top);

    return (dx > 0.0 && dy > 0.0) ? dx * dy : 0.0;
  }
}

/// Grid invariant of the region system: a layout's regions must be EXACTLY
/// the cells carved by its interior split lines ((n+1)×(m+1) cells for n
/// vertical + m horizontal lines) — no straddling rects, no overlap, no gap.
///
/// Every editor round-trip rebuilds through [LayoutTopology.computeRegions]
/// so user-edited layouts conform by construction; LEGACY blobs (e.g. the old
/// default doubleTap whose tag strip halves straddled the column lines) do
/// not and must be reset to defaults on load (see [dropNonGridLayouts]).
bool isGridConformantLayout(GestureLayout layout) {
  if (layout.regions.isEmpty) return true;
  final lines = LayoutTopology.computeEditableLines(layout);
  final cells = LayoutTopology(lines: lines).computeRegions();
  if (cells.length != layout.regions.length) return false;
  bool sameRect(Rect a, Rect b) =>
      (a.left - b.left).abs() < _kGridEpsilon &&
      (a.top - b.top).abs() < _kGridEpsilon &&
      (a.right - b.right).abs() < _kGridEpsilon &&
      (a.bottom - b.bottom).abs() < _kGridEpsilon;
  return cells.every(
    (cell) => layout.regions.any((r) => sameRect(r.normalizedRect, cell)),
  );
}

const double _kGridEpsilon = 1e-6;

/// A tap layout is only operable when at least one region keeps
/// `toggleControls` — a tap layout with zero toggles would leave the
/// control bar unreachable (the reason `none` was once removed from tap).
/// Called from the editor save path (Dialog interception) and the store
/// write guard; pure so it stays unit-testable.
bool tapLayoutHasToggle(GestureLayout layout) {
  return layout.regions.any(
    (r) => r.action.type == GestureActionType.toggleControls,
  );
}

/// Classification of a single tap point against a tap layout. Pure; the
/// runtime (`onTap`) maps each state to behavior.
enum TapHitKind {
  /// Landed on a region bound to a real action (e.g. `toggleControls`).
  action,

  /// Landed on an explicit `none` region — a single-hand dead zone meant to
  /// stay quiet while the control panel is hidden (rapid double-tap seeking
  /// must not flash the controls).
  none,

  /// Landed outside every configured region, or no layout is present.
  outside,
}

TapHitKind resolveTapHit(GestureLayout? layout, Offset normalizedPos) {
  if (layout == null) return TapHitKind.outside;
  for (final region in layout.regions) {
    if (region.normalizedRect.contains(normalizedPos)) {
      return region.action.type == GestureActionType.none
          ? TapHitKind.none
          : TapHitKind.action;
    }
  }
  return TapHitKind.outside;
}

/// Loads a stored profile map against the defaults, resetting any layout
/// that violates the grid invariant to its default (legacy blobs), while
/// keeping conformant user edits untouched. Pure; called from
/// AppStore._normalizeLoaded on BOTH persistence paths.
Map<String, Map<GestureIntent, GestureLayout>> dropNonGridLayouts({
  required Map<String, Map<GestureIntent, GestureLayout>> profiles,
  required Map<String, Map<GestureIntent, GestureLayout>> defaults,
}) {
  final cleaned = <String, Map<GestureIntent, GestureLayout>>{};
  for (final entry in profiles.entries) {
    final defaultsForProfile = defaults[entry.key];
    if (defaultsForProfile == null) continue;
    final layouts = <GestureIntent, GestureLayout>{};
    entry.value.forEach((intent, layout) {
      final fallback = defaultsForProfile[intent];
      if (fallback == null) return;
      layouts[intent] =
          isGridConformantLayout(layout) ? layout : fallback;
    });
    cleaned[entry.key] = layouts;
  }
  return cleaned;
}
