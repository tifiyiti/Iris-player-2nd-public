import 'dart:math' as math;

import 'package:flutter/widgets.dart'
    show
      Alignment,
      EdgeInsets,
      MainAxisAlignment,
      Offset,
      Rect,
      Size,
      ValueNotifier,
      WrapAlignment;
import 'package:iris/models/store/app_state.dart' show SidePanelCornerHideMode;

/// Sideway one-handed panel sizing semantics (pure functions).
///
/// The panel is anchored inside the window by the meta 9-grid anchor. Its
/// edges NOT touching the window border are draggable:
///
/// - Corner zones adjust TWO edges (width + height).
/// - Mid-edge zones adjust ONE edge; the OPPOSITE edge stays put — for
///   non-center anchors the Align itself fixes the opposite edge, for
///   center anchors the caller applies a transient shift compensation.
///
/// Width/height coupling (user-confirmed contract):
/// - WIDTH drags mainly drive the bottom button bar's line count: widening
///   collapses the wrap toward ONE line and the dial reclaims the freed
///   height ("试图占据最大高度"); narrowing keeps the dial's previous pixel
///   height while the wrap grows, so the panel's total height rises.
/// - HEIGHT drags scale the dial ratio-locked (a circle grows wider as it
///   grows taller) — the ONLY gesture that can shrink it; the bar line
///   count jumps as the widened dial forces the panel width up.

/// Which panel edges coincide with the window border for the given anchor.
/// Border edges are NOT resizable ("非窗口边框" contract).
({bool left, bool top, bool right, bool bottom}) borderEdgesForAnchor(
    Alignment anchor) {
  return (
    left: anchor.x <= -1,
    top: anchor.y <= -1,
    right: anchor.x >= 1,
    bottom: anchor.y >= 1,
  );
}

/// Resize capability of one corner zone: `w` = adjusts width, `h` =
/// adjusts height; a corner with both false is ABSENT (both its edges sit
/// on the window border). A corner inherits the union of its two edges, so
/// a single-edge corner degrades to that edge's axis.
typedef CornerAxes = ({bool w, bool h});

/// The 8-zone handle plan for an anchored panel.
class SidewayResizePlan {
  const SidewayResizePlan({
    required this.leftEdge,
    required this.rightEdge,
    required this.topEdge,
    required this.bottomEdge,
    required this.cornerTL,
    required this.cornerTR,
    required this.cornerBL,
    required this.cornerBR,
  });

  /// Mid-edge zones: true = the edge is resizable (off the window border).
  final bool leftEdge;
  final bool rightEdge;
  final bool topEdge;
  final bool bottomEdge;

  final CornerAxes? cornerTL;
  final CornerAxes? cornerTR;
  final CornerAxes? cornerBL;
  final CornerAxes? cornerBR;
}

SidewayResizePlan resizePlanForAnchor(Alignment anchor) {
  final (:left, :top, :right, :bottom) = borderEdgesForAnchor(anchor);
  CornerAxes? corner(bool withLeft, bool withTop) {
    final bool useW = withLeft ? !left : !right;
    final bool useH = withTop ? !top : !bottom;
    if (!useW && !useH) return null;
    return (w: useW, h: useH);
  }

  return SidewayResizePlan(
    leftEdge: !left,
    rightEdge: !right,
    topEdge: !top,
    bottomEdge: !bottom,
    cornerTL: corner(true, true),
    cornerTR: corner(false, true),
    cornerBL: corner(true, false),
    cornerBR: corner(false, false),
  );
}

/// Width-drag response for the dial's height share knob.
///
/// [dialPxBefore] is the dial's pixel height before this width update;
/// [barHAfter] the button-bar height at the NEW width (measured). Widening
/// reclaims the freed height up to the full span ("slider 总是试图占据最大
/// 高度"); narrowing retains the previous pixel height, capped by the span
/// (the last-resort floor when the slack is exhausted). Returns the
/// clamped height-share knob value.
double dialPctForWidthDrag({
  required bool widening,
  required double dialPxBefore,
  required double availH,
  required double gap,
  required double barHAfter,
  double minPct = 0.30,
  double maxPct = 1.00,
}) {
  final double spanAfter = math.max(0.0, availH - gap - barHAfter);
  if (spanAfter <= 0) return maxPct;
  final double wantPx = widening ? spanAfter : dialPxBefore;
  return (wantPx / spanAfter).clamp(minPct, maxPct).toDouble();
}

/// Maps a retained pixel height back onto the classic circle's scale knob
/// (`size = lerp(minSize, maxSize, scale)` — see ControlBarCircleSlider).
double classicScaleForRetainedPx({
  required double retainedPx,
  required double minSize,
  required double maxSize,
}) {
  final double range = math.max(1.0, maxSize - minSize);
  return ((retainedPx - minSize) / range).clamp(0.0, 1.0).toDouble();
}

/// The panel can never be narrower than its dial (ratio-locked circle) nor
/// wider than the window.
double effectivePanelWidth({
  required double draggedWidth,
  required double dialDiameter,
  required double maxWindowWidth,
}) {
  return math.min(maxWindowWidth, math.max(draggedWidth, dialDiameter));
}

/// Screen-percentage helpers (new total-panel contract: size is % of screen,
///
/// not absolute px; screen is stable so percent is the source of truth).
double clampPanelPct(double v) => v.clamp(10.0, 100.0).toDouble();

double pxForPercent(double pct, double windowSize) =>
    windowSize * clampPanelPct(pct) / 100.0;

double spanForTotalHeight(double totalH, double buttonsH, double gap) =>
    math.max(0.0, totalH - buttonsH - gap);

double dialPxForSpan({
  required double span,
  required double panelW,
  required bool isDial,
  required double ringDialHeightPct,
  required double classicScale,
  double kMinDiameter = 150,
  double kClassicMin = 100,
  double kClassicMax = 260,
  double kGap = 8,
}) {
  if (isDial) {
    final double want = span * ringDialHeightPct.clamp(0.30, 1.0);
    return math.max(kMinDiameter, math.min(want, math.min(span, panelW)));
  }
  final double effectiveMax = math.max(kClassicMin, math.min(span, kClassicMax));
  // lerp(min, max, scale) — mirrors CircleSliderLayout classic branch.
  final double v = kClassicMin + (effectiveMax - kClassicMin) * classicScale.clamp(0.0, 1.0);
  return v.clamp(kClassicMin, effectiveMax).toDouble();
}

// ── Windows rings (meta + sideway panel) ───────────────────────────────────

/// Default fixed-px inset from the origin edge (away from video, near window).
const double kDefaultRingInset = 28.0;

/// Default ring radius (visual circle); separately per axis so H/V tune
/// independently ("分别").
const double kDefaultRingRadius = 8.0;

/// Minimum clearance from the panel corner to the ring center.
const double kRingCornerMargin = 2.0;

/// Clamps a handle inset so the ring center stays inside its edge.
double clampHandleInset(double inset, double panelSize, double radius) {
  final double min = radius + kRingCornerMargin;
  final double max = math.max(min, panelSize - radius - kRingCornerMargin);
  return inset.clamp(min, max).toDouble();
}

/// Clamps a handle radius. Upper bound never exceeds half the panel's
/// shortest side minus margin ("上限不能超过宽高").
double clampHandleRadius(double radius, double panelW, double panelH) {
  final double maxByPanel = math.max(4.0, math.min(panelW, panelH) / 2 - kRingCornerMargin);
  final double max = math.min(16.0, maxByPanel);
  return radius.clamp(4.0, max).toDouble();
}

/// Per-axis clamps (convenience when only one dimension is known).
double clampHandleInsetH(double inset, double panelW, double radiusH) =>
    clampHandleInset(inset, panelW, radiusH);

double clampHandleInsetV(double inset, double panelH, double radiusV) =>
    clampHandleInset(inset, panelH, radiusV);

/// Which logical edge a ring lives on.
enum RingEdge { left, right, top, bottom }

/// One visible handle ring spec (pure geometry, no widget).
class RingSpec {
  const RingSpec({required this.edge, required this.center, required this.radius});
  final RingEdge edge;
  final Offset center;
  final double radius;

  /// Center as an [Offset] in panel-local coords.
  math.Point<double> get point => math.Point<double>(center.dx, center.dy);
  double get x => center.dx;
  double get y => center.dy;
}

/// Origin for the inset measurements (mirrors the 9-grid anchor).
bool _originIsLeft(Alignment anchor) => anchor.x <= -1;
bool _originIsTop(Alignment anchor) => anchor.y <= -1;

/// Applies a tangential delta to an inset, inverting when the origin is on
/// the far side so dragging right/down always moves the ring right/down
/// visually.
double applyInsetHDelta({
  required Alignment anchor,
  required double insetH,
  required double deltaDx,
  required double panelW,
  required double radiusH,
}) {
  final bool leftOrigin = _originIsLeft(anchor);
  final double raw = leftOrigin ? insetH + deltaDx : insetH - deltaDx;
  return clampHandleInset(raw, panelW, radiusH);
}

double applyInsetVDelta({
  required Alignment anchor,
  required double insetV,
  required double deltaDy,
  required double panelH,
  required double radiusV,
}) {
  final bool topOrigin = _originIsTop(anchor);
  final double raw = topOrigin ? insetV + deltaDy : insetV - deltaDy;
  return clampHandleInset(raw, panelH, radiusV);
}

/// Minimum rendered panel size on phone (px). The percent slider must never
/// let the user drag below these floors, or the thumb moves while the panel
/// stays pinned (a dead zone that no longer matches the shown value).
const double kPanelMinPxW = 200;
const double kPanelMinPxH = 160;

/// Lowest meaningful panel percent on phone for a given window extent, derived
/// from the [kPanelMinPxW]/[kPanelMinPxH] floor so a slider bound matches what
/// [panelSizeForWindow] actually renders.
double phonePanelMinPct({required double windowExtent, required double minPx}) {
  // Degenerate window (extent below the floor itself): nothing can fit, pin to
  // 100 so callers can detect the empty range and disable the slider.
  if (windowExtent <= 0) return 100;
  return (minPx / windowExtent * 100).clamp(10.0, 100.0).toDouble();
}

/// Total panel size as rendered by [CircleSliderLayout] (shared with
/// [ControlsOverlay] to compute the hide translation without duplication).
///
/// Mirrors `circle_slider_layout.dart:97-108` exactly: phone = screen %,
/// desktop = absolute px clamped to window*0.8.
({double panelW, double panelH}) panelSizeForWindow({
  required double windowW,
  required double windowH,
  required bool isPhone,
  required double widthPct,
  required double heightPct,
  required double widthPx,
  required double heightPx,
}) {
  double totalW, totalH;
  if (isPhone) {
    totalW = pxForPercent(widthPct, windowW);
    totalH = pxForPercent(heightPct, windowH);
    totalW = totalW.clamp(kPanelMinPxW, math.max(kPanelMinPxW, windowW - 16));
    totalH = totalH.clamp(kPanelMinPxH, math.max(kPanelMinPxH, windowH - 16));
  } else {
    totalW = widthPx.clamp(260, math.max(260, windowW * 0.8));
    totalH = heightPx.clamp(320, math.max(320, windowH * 0.8));
  }
  return (panelW: totalW, panelH: totalH);
}

/// Screen-space rect of the one-handed side panel (the side-type control
/// slider) as laid out by `CircleSliderLayout`. Mirrors the anchor + size
/// contract so the settings dialog can avoid it.
Rect sidePanelRectForWindow({
  required Size windowSize,
  required Alignment anchor,
  required bool isPhone,
  required double widthPct,
  required double heightPct,
  required double widthPx,
  required double heightPx,
}) {
  final ({double panelW, double panelH}) panel = panelSizeForWindow(
    windowW: windowSize.width,
    windowH: windowSize.height,
    isPhone: isPhone,
    widthPct: widthPct,
    heightPct: heightPct,
    widthPx: widthPx,
    heightPx: heightPx,
  );
  final double px = anchor.x <= -1
      ? 0
      : anchor.x >= 1
          ? windowSize.width - panel.panelW
          : (windowSize.width - panel.panelW) / 2;
  final double py = anchor.y <= -1
      ? 0
      : anchor.y >= 1
          ? windowSize.height - panel.panelH
          : (windowSize.height - panel.panelH) / 2;
  return Rect.fromLTWH(px, py, panel.panelW, panel.panelH);
}

/// Largest axis-aligned region that does NOT overlap [panel], clamped inside
/// [screen], inset by [safe] (system bars) and then [margin].
///
/// The side-panel settings dialog uses this so it can never cover the very
/// control slider it is editing. A full-height horizontal strip beside the
/// panel is chosen (the panel is bottom-anchored and near full-height, so the
/// vertical slice above it is unusable anyway). Falls back to the full safe
/// screen when there is no panel or the panel leaves no usable strip.
Rect regionAvoidingPanel({
  required Size screen,
  required EdgeInsets safe,
  Rect? panel,
  double margin = 8,
}) {
  final Rect full = Rect.fromLTRB(
    safe.left + margin,
    safe.top + margin,
    screen.width - safe.right - margin,
    screen.height - safe.bottom - margin,
  );
  if (panel == null || panel.isEmpty) return full;
  final Rect left = Rect.fromLTRB(full.left, full.top, panel.left, full.bottom);
  final Rect right =
      Rect.fromLTRB(panel.right, full.top, full.right, full.bottom);
  final Rect strip = left.width >= right.width ? left : right;
  if (strip.width <= 1 || strip.height <= 1) return full;
  return strip;
}

/// Hide translation for the total panel (pure, direction-aware).
///
/// - Edge middles slide to that edge (e.g. centerLeft → left).
/// - Corners obey [cornerMode]: vertical → single-axis vertical,
///   horizontal → single-axis horizontal, diagonal → diagonal.
/// - Pure center (0,0) has no edge → falls back to handedness:
///   right-handed → right, left-handed → left.
/// [margin] covers the ring overhang + shadow so the panel is fully off-screen.
Offset hideTranslateForAnchor({
  required Alignment anchor,
  required bool isLeftHanded,
  required double panelW,
  required double panelH,
  SidePanelCornerHideMode cornerMode = SidePanelCornerHideMode.vertical,
  double margin = 24,
}) {
  final (:left, :top, :right, :bottom) = borderEdgesForAnchor(anchor);
  // Four corners → per cornerMode.
  if (left && top) {
    switch (cornerMode) {
      case SidePanelCornerHideMode.vertical:
        return Offset(0, -(panelH + margin));
      case SidePanelCornerHideMode.horizontal:
        return Offset(-(panelW + margin), 0);
      case SidePanelCornerHideMode.diagonal:
        return Offset(-(panelW + margin), -(panelH + margin));
    }
  }
  if (right && top) {
    switch (cornerMode) {
      case SidePanelCornerHideMode.vertical:
        return Offset(0, -(panelH + margin));
      case SidePanelCornerHideMode.horizontal:
        return Offset(panelW + margin, 0);
      case SidePanelCornerHideMode.diagonal:
        return Offset(panelW + margin, -(panelH + margin));
    }
  }
  if (left && bottom) {
    switch (cornerMode) {
      case SidePanelCornerHideMode.vertical:
        return Offset(0, panelH + margin);
      case SidePanelCornerHideMode.horizontal:
        return Offset(-(panelW + margin), 0);
      case SidePanelCornerHideMode.diagonal:
        return Offset(-(panelW + margin), panelH + margin);
    }
  }
  if (right && bottom) {
    switch (cornerMode) {
      case SidePanelCornerHideMode.vertical:
        return Offset(0, panelH + margin);
      case SidePanelCornerHideMode.horizontal:
        return Offset(panelW + margin, 0);
      case SidePanelCornerHideMode.diagonal:
        return Offset(panelW + margin, panelH + margin);
    }
  }
  // Edge middles → single-axis.
  if (left) return Offset(-(panelW + margin), 0);
  if (right) return Offset(panelW + margin, 0);
  if (top) return Offset(0, -(panelH + margin));
  if (bottom) return Offset(0, panelH + margin);
  // Pure center (0,0) → side fallback (spec: side right→right, side left→left).
  return Offset(isLeftHanded ? -(panelW + margin) : panelW + margin, 0);
}

/// Wrap alignment of the sideway panel's bottom button rows.
///
/// The bar exists FOR the thumb, so every row hugs the panel edge that faces
/// the screen centre instead of centring inside the panel: a right-docked
/// panel aligns its rows LEFT, a left-docked one RIGHT. A centre anchor has no
/// centre-facing edge and keeps the historical centred look.
WrapAlignment sidewayButtonAlignForAnchor(Alignment anchor) => anchor.x > 0
    ? WrapAlignment.start
    : anchor.x < 0
        ? WrapAlignment.end
        : WrapAlignment.center;

/// Row-based twin of [sidewayButtonAlignForAnchor] for the group-2 副音 quick
/// bar, which lays its buttons out in a single [Row] rather than a [Wrap].
/// Same rule, so the two groups cannot drift apart.
MainAxisAlignment sidewayButtonRowAlignForAnchor(Alignment anchor) =>
    anchor.x > 0
        ? MainAxisAlignment.start
        : anchor.x < 0
            ? MainAxisAlignment.end
            : MainAxisAlignment.center;

/// Horizontal offset of the sideway panel's bottom button BLOCK inside the
/// panel, as a fraction of the free space (`panelWidth - blockWidth`).
///
/// [pos] is side-relative 0..1: 0 = the block hugs the edge that faces the
/// screen centre (right-docked → left edge, left-docked → right edge), 1 = the
/// outer window edge. A centre anchor has no centre-facing edge, so it keeps
/// the historical centred block (the knob is a no-op there).
///
/// [free] is guaranteed non-negative by the caller: the button block is
/// measured and can never be wider than the panel, so `free * pos` stays in
/// `[0, free]` and the block can never overflow the panel.
double sidewayBarX({
  required Alignment anchor,
  required double pos,
  required double free,
}) {
  if (free <= 0) return 0;
  final double p = pos.clamp(0.0, 1.0);
  if (anchor.x > 0) return free * p; // right-docked: inner edge is the left
  if (anchor.x < 0) return free * (1 - p); // left-docked: inner edge is right
  return free / 2;
}

/// Produces the visible ring centers for the current anchor (Windows rings
/// mode). Each resizable edge gets ONE ring; opposite edges share the same
/// inset value (e.g. top+bottom both use insetH → they move together).
List<RingSpec> ringCentersForAnchor({
  required Alignment anchor,
  required double panelW,
  required double panelH,
  required double insetH,
  required double insetV,
  required double radiusH,
  required double radiusV,
}) {
  if (panelW <= 0 || panelH <= 0) return const <RingSpec>[];
  final SidewayResizePlan plan = resizePlanForAnchor(anchor);
  final double clampedH = clampHandleInset(insetH, panelW, radiusH);
  final double clampedV = clampHandleInset(insetV, panelH, radiusV);
  final bool leftOrigin = _originIsLeft(anchor);
  final bool topOrigin = _originIsTop(anchor);

  final double xForH = leftOrigin ? clampedH : panelW - clampedH;
  final double yForV = topOrigin ? clampedV : panelH - clampedV;

  final List<RingSpec> out = <RingSpec>[];
  if (plan.leftEdge) {
    out.add(RingSpec(edge: RingEdge.left, center: Offset(0, yForV), radius: radiusV));
  }
  if (plan.rightEdge) {
    out.add(RingSpec(edge: RingEdge.right, center: Offset(panelW, yForV), radius: radiusV));
  }
  if (plan.topEdge) {
    out.add(RingSpec(edge: RingEdge.top, center: Offset(xForH, 0), radius: radiusH));
  }
  if (plan.bottomEdge) {
    out.add(RingSpec(edge: RingEdge.bottom, center: Offset(xForH, panelH), radius: radiusH));
  }
  return out;
}

/// Fallback bottom-bar height, used ONLY before the normal panel has ever been
/// mounted (see [sidewayBarHeight]).
const double kSidewayBarSlotH = 150;

/// Live-measured height of the sideway panel's bottom bar — the ONE source of
/// truth both the normal scaffold and the APB editor read, so the editor swaps
/// its two slots (slider / bottom bar) WITHOUT changing either size.
///
/// Published by `CircleSliderLayout`'s post-frame measurement; the fallback is
/// only used before the normal panel has ever been mounted (the control bar is
/// up long before the editor can be opened).
final ValueNotifier<double> sidewayBarHeight =
    ValueNotifier<double>(kSidewayBarSlotH);

/// Height left for the dial: total − the bottom-bar slot − gap. Deliberately
/// independent of the bar's content, so replacing the bar cannot resize the
/// ring.
double dialSpanForPanel({
  required double totalH,
  double barSlotH = kSidewayBarSlotH,
  double gap = 8,
}) =>
    math.max(0, totalH - barSlotH - gap);