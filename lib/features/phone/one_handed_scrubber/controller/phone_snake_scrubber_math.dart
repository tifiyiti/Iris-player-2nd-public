import 'dart:math' as m;

import 'package:flutter/material.dart';

/// Serpentine 5-axis scrubber math.
///
/// Geometry: 5 parallel horizontal bars stacked at 10%/30%/50%/70%/90% of
/// fittedTracksH with alternating travel direction (even L→R, odd R→L),
/// joined by 4 semicircular connectors bulging outward at alternating ends
/// (even connectors on the right, odd on the left). No sharp corners.
///
/// Progress is parameterized uniformly along total path arc length, so the
/// connectors occupy playback progress too: each bar's time share equals its
/// arc-length share, not exactly 1/5.
///
/// Drag behavior ("on-line free follow, off-line lock"):
/// - Within effectiveLineWidth of the serpentine: project finger onto the
///   whole path → free follow 0→100% through bars and arcs.
/// - Beyond it: lock to the current bar and scrub only inside that bar's
///   u-band; cross-axis switching requires re-touching the line.
///
/// Vertical fine (floating/fixed) via Wfine asymmetric lerp is orthogonal.
class PhoneSnakeScrubberMath {
  const PhoneSnakeScrubberMath._();

  static const int kAxisCount = 5;

  static SerpentineGeometry buildSerpentine({
    required double trackLeft,
    required double axisW,
    required double fittedTracksH,
  }) {
    return SerpentineGeometry(trackLeft: trackLeft, axisW: axisW, fittedTracksH: fittedTracksH);
  }

  /// Narrow on-line detection band. Deliberately much smaller than half the
  /// inter-axis gap so that leaving the line is a real, reachable state and
  /// cross-axis locking actually engages.
  static double effectiveLineWidth(double axisH) => (axisH * 0.25).clamp(6.0, 16.0).toDouble();

  /// Uniform progress u = t/D 0..1.
  static double uForPosition(Duration position, Duration duration) {
    if (duration.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }

  /// Duration for uniform progress u.
  static Duration durationForU(double u, Duration duration) {
    final double v = u.clamp(0.0, 1.0).toDouble();
    return _clampDuration(duration, Duration(milliseconds: (v * duration.inMilliseconds).round()));
  }

  /// Asymmetric forward ratio for u. Maps to forward/backward share.
  static double forwardRatioForU(double u) {
    final double v = u.clamp(0.0, 1.0).toDouble();
    if (v < 0.2) return 0.0;
    if (v < 0.6) {
      return ((v - 0.2) / 0.4) * 0.5;
    }
    return 0.5 + ((v - 0.6) / 0.4) * 0.5;
  }

  /// Vertical delta mapping for floating fine axis.
  static Duration deltaForVertical({
    required double raw,
    required double u,
    required Duration wFine,
    required Duration duration,
  }) {
    final double f = forwardRatioForU(u);
    final double b = 1 - f;
    final double factor = raw > 0 ? raw * f : raw * b;
    final double ms = factor * wFine.inMilliseconds;
    return Duration(milliseconds: ms.round());
  }

  /// Fixed inner strip 50/50.
  static Duration deltaForFixedInner({
    required double v,
    required Duration wFine,
  }) {
    final double ms = v * wFine.inMilliseconds / 2;
    return Duration(milliseconds: ms.round());
  }
}

/// One element of the serpentine path: a horizontal bar or a semicircular
/// connector. [index] is the owning bar index for bars, and the departure-bar
/// index for arcs (an arc belongs to the bar it leaves).
class SnakePathSegment {
  SnakePathSegment.bar({
    required this.index,
    required this.start,
    required this.end,
  })  : isArc = false,
        center = Offset.zero,
        radius = 0,
        startAngle = 0,
        sweep = 0;

  SnakePathSegment.arc({
    required this.index,
    required this.center,
    required this.radius,
    required this.startAngle,
    required this.sweep,
    required this.start,
    required this.end,
  }) : isArc = true;

  final bool isArc;
  final int index;
  final Offset start;
  final Offset end;
  final Offset center;
  final double radius;

  /// Arc start angle in screen atan2 space (y down), radians.
  final double startAngle;

  /// Signed sweep; positive passes through angle 0 (right bulge), negative
  /// through ±π (left bulge).
  final double sweep;

  double get length => isArc ? radius * sweep.abs() : (end - start).distance;

  /// Point at fraction [frac] along travel direction. Endpoints are returned
  /// verbatim so adjacent elements join exactly.
  Offset pointAt(double frac) {
    final double t = frac.clamp(0.0, 1.0).toDouble();
    if (!isArc) {
      return Offset(start.dx + (end.dx - start.dx) * t, start.dy + (end.dy - start.dy) * t);
    }
    if (t <= 0) return start;
    if (t >= 1) return end;
    final double angle = startAngle + sweep * t;
    return Offset(center.dx + radius * m.cos(angle), center.dy + radius * m.sin(angle));
  }
}

class NearestOnPathResult {
  const NearestOnPathResult({
    required this.seg,
    required this.barIndex,
    required this.frac,
    required this.dist,
    required this.point,
  });

  /// Path element index 0..8 (bars at even indices, arcs at odd).
  final int seg;

  /// Owning bar index when projected onto a bar element, otherwise -1.
  final int barIndex;

  /// Fraction along that element's travel direction.
  final double frac;
  final double dist;
  final Offset point;

  bool get isBar => barIndex >= 0;
}

/// Immutable serpentine layout plus all position/progress mappings over it.
class SerpentineGeometry {
  SerpentineGeometry({
    required this.trackLeft,
    required this.axisW,
    required this.fittedTracksH,
  }) {
    _build();
  }

  final double trackLeft;
  final double axisW;
  final double fittedTracksH;

  late final List<SnakePathSegment> segments;
  late final List<double> cumulative;
  late final double totalLength;

  void _build() {
    final double axisH = fittedTracksH / PhoneSnakeScrubberMath.kAxisCount;
    final double r = axisH / 2;
    final List<SnakePathSegment> segs = <SnakePathSegment>[];
    for (int k = 0; k < PhoneSnakeScrubberMath.kAxisCount; k++) {
      final double y = axisH * (k + 0.5);
      final Offset begin = Offset(k.isEven ? trackLeft : trackLeft + axisW, y);
      final Offset finish = Offset(k.isEven ? trackLeft + axisW : trackLeft, y);
      segs.add(SnakePathSegment.bar(index: k, start: begin, end: finish));
      if (k < PhoneSnakeScrubberMath.kAxisCount - 1) {
        final bool bulgeRight = k.isEven;
        // Circle center sits on the shared bar-end line at mid height between
        // the two bar centers, making both endpoints antipodal → true half turn.
        final Offset center = Offset(bulgeRight ? trackLeft + axisW : trackLeft, y + r);
        final Offset arrivalBegin = Offset((k + 1).isEven ? trackLeft : trackLeft + axisW, y + axisH);
        segs.add(SnakePathSegment.arc(
          index: k,
          center: center,
          radius: r,
          startAngle: -m.pi / 2,
          sweep: bulgeRight ? m.pi : -m.pi,
          start: finish,
          end: arrivalBegin,
        ));
      }
    }
    segments = List<SnakePathSegment>.unmodifiable(segs);
    final List<double> cum = <double>[0];
    for (final SnakePathSegment s in segments) {
      cum.add(cum.last + s.length);
    }
    cumulative = List<double>.unmodifiable(cum);
    totalLength = cum.last;
  }

  /// Containing element for uniform progress [u].
  int segForU(double u) {
    final double s = u.clamp(0.0, 1.0).toDouble() * totalLength;
    for (int i = 0; i < segments.length - 1; i++) {
      if (s < cumulative[i + 1]) return i;
    }
    return segments.length - 1;
  }

  /// Inverse of [uForSegFrac] within one element.
  double fracForSegU(int seg, double u) {
    final int i = seg.clamp(0, segments.length - 1);
    final double len = segments[i].length;
    if (len <= 0) return 0;
    final double local = (u.clamp(0.0, 1.0).toDouble() * totalLength - cumulative[i]).clamp(0.0, len);
    return local / len;
  }

  /// Uniform u from element index and local fraction.
  double uForSegFrac(int seg, double frac) {
    final int i = seg.clamp(0, segments.length - 1);
    final double v = (cumulative[i] + frac.clamp(0.0, 1.0) * segments[i].length) / totalLength;
    return v.clamp(0.0, 1.0).toDouble();
  }

  /// Bar owning the band containing [u]; arc bands belong to their departure bar.
  int barForU(double u) {
    return segments[segForU(u)].index;
  }

  /// Direction-aware horizontal projection onto bar [bar], clamped to 0..1
  /// along its travel direction.
  double txForBarX(double x, int bar) {
    final int b = bar.clamp(0, PhoneSnakeScrubberMath.kAxisCount - 1);
    final double xc = x.clamp(trackLeft, trackLeft + axisW).toDouble();
    final double raw = (xc - trackLeft) / axisW;
    return (b.isEven ? raw : 1 - raw).clamp(0.0, 1.0).toDouble();
  }

  /// Uniform u for a locked-bar projection result.
  double uForBarTx(int bar, double tx) {
    return uForSegFrac(bar * 2, tx);
  }

  /// Position on the path for uniform progress [u].
  Offset positionForU(double u) {
    final double v = u.clamp(0.0, 1.0).toDouble();
    final int seg = segForU(v);
    return segments[seg].pointAt(fracForSegU(seg, v));
  }

  /// Nearest point on the whole serpentine (bars + arcs).
  ///
  /// When the finger is clearly beyond the outward bulge reach, arcs are not
  /// eligible: an exterior finger means "pull to the endpoint" and must map
  /// to the nearest bar end instead of being hijacked by a distant arc.
  NearestOnPathResult nearest(Offset p) {
    final double r = fittedTracksH / PhoneSnakeScrubberMath.kAxisCount / 2;
    // One extra radius of grab margin past the bulge tips before an exterior
    // finger counts as "pull to endpoint".
    final bool exterior = p.dx < trackLeft - 2 * r || p.dx > trackLeft + axisW + 2 * r;
    NearestOnPathResult best =
        const NearestOnPathResult(seg: 0, barIndex: 0, frac: 0, dist: double.infinity, point: Offset.zero);
    for (int i = 0; i < segments.length; i++) {
      final SnakePathSegment s = segments[i];
      if (s.isArc) {
        if (exterior) continue;
        final _ArcProjection proj = _nearestOnArc(s, p);
        if (proj.dist < best.dist) {
          best = NearestOnPathResult(seg: i, barIndex: -1, frac: proj.frac, dist: proj.dist, point: proj.point);
        }
      } else {
        final Offset dir = s.end - s.start;
        final double len2 = dir.distanceSquared;
        double t = 0;
        if (len2 > 1e-9) {
          t = ((p - s.start).dx * dir.dx + (p - s.start).dy * dir.dy) / len2;
        }
        t = t.clamp(0.0, 1.0).toDouble();
        final Offset proj = s.pointAt(t);
        final double dist = (p - proj).distance;
        if (dist < best.dist) {
          best = NearestOnPathResult(seg: i, barIndex: s.index, frac: t, dist: dist, point: proj);
        }
      }
    }
    return best;
  }

  /// Nearest point on one semicircular arc. The clamped-angle candidate can
  /// pick the wrong endpoint for exterior points, so both endpoints always
  /// compete as explicit candidates.
  _ArcProjection _nearestOnArc(SnakePathSegment arc, Offset p) {
    final double twoPi = 2 * m.pi;
    final Offset v = p - arc.center;
    double t = (m.atan2(v.dy, v.dx) - arc.startAngle) % twoPi;
    if (arc.sweep >= 0) {
      t = t.clamp(0.0, arc.sweep).toDouble();
    } else {
      if (t > m.pi) t -= twoPi;
      t = t.clamp(arc.sweep, 0.0).toDouble();
    }
    final double angle = arc.startAngle + t;
    final Offset interior =
        Offset(arc.center.dx + arc.radius * m.cos(angle), arc.center.dy + arc.radius * m.sin(angle));

    Offset bestPoint = interior;
    double bestDist = (p - interior).distance;
    double bestFrac = arc.sweep == 0 ? 0 : t / arc.sweep.abs();

    final double dStart = (p - arc.start).distance;
    if (dStart < bestDist) {
      bestDist = dStart;
      bestPoint = arc.start;
      bestFrac = 0;
    }
    final double dEnd = (p - arc.end).distance;
    if (dEnd < bestDist) {
      bestDist = dEnd;
      bestPoint = arc.end;
      bestFrac = 1;
    }
    return _ArcProjection(point: bestPoint, frac: bestFrac.clamp(0.0, 1.0).toDouble(), dist: bestDist);
  }
}

class _ArcProjection {
  const _ArcProjection({required this.point, required this.frac, required this.dist});
  final Offset point;
  final double frac;
  final double dist;
}

enum SnakeActiveMode { z, floating, fixed }

/// Mutable per-drag session. All geometry-dependent updates require the
/// [SerpentineGeometry] captured at reset time.
class PhoneSnakeScrubSession {
  PhoneSnakeScrubSession({required this.duration, required this.wFine});

  /// Vertical move threshold to leave hold-on into floating fine adjust.
  static const double kHoldOnVerticalEnterPx = 12;

  /// Horizontal move threshold that cancels hold-on back to free follow.
  static const double kHoldOnHorizontalCancelPx = 8;

  final Duration duration;
  final Duration wFine;

  SerpentineGeometry? _geometry;
  int _lockedBar = 0;
  Duration _anchor = Duration.zero;
  Duration _target = Duration.zero;
  SnakeActiveMode _active = SnakeActiveMode.z;
  double _originY = 0;
  bool _holdOn = false;
  Offset _holdTouchAnchor = Offset.zero;

  int get lockedBar => _lockedBar;
  Duration get anchor => _anchor;
  Duration get target => _target;
  SnakeActiveMode get active => _active;
  bool get holdOn => _holdOn;

  void resetForZ({
    required SerpentineGeometry geometry,
    required int lockedBar,
    required Duration anchor,
  }) {
    _geometry = geometry;
    _lockedBar = lockedBar.clamp(0, PhoneSnakeScrubberMath.kAxisCount - 1);
    _anchor = _clampDuration(duration, anchor);
    _target = _anchor;
    _active = SnakeActiveMode.z;
    _holdOn = false;
    _holdTouchAnchor = Offset.zero;
    _originY = 0;
  }

  /// Z-mode drag update: on-line free follow across the whole serpentine,
  /// off-line lock to [_lockedBar]'s band only.
  Duration updateZPath({
    required Offset p,
    required double lineWidth,
  }) {
    final SerpentineGeometry? geo = _geometry;
    if (geo == null) return _target;
    final NearestOnPathResult proj = geo.nearest(p);
    if (proj.dist <= lineWidth) {
      if (proj.isBar) _lockedBar = proj.barIndex;
      _target = PhoneSnakeScrubberMath.durationForU(geo.uForSegFrac(proj.seg, proj.frac), duration);
    } else {
      final double tx = geo.txForBarX(p.dx, _lockedBar);
      _target = PhoneSnakeScrubberMath.durationForU(geo.uForBarTx(_lockedBar, tx), duration);
    }
    return _target;
  }

  /// Mark "precise stop": show the floating fine axis at the current position.
  void enterHoldOn({required Offset touchPos}) {
    if (_active != SnakeActiveMode.z) return;
    _holdOn = true;
    _holdTouchAnchor = touchPos;
  }

  /// Dispatch movement while holding still. Vertical-dominant motion beyond
  /// the threshold switches into locked floating fine adjust anchored at the
  /// hold moment's target; horizontal-dominant motion cancels hold-on and
  /// resumes free follow. Small jitter keeps holding.
  void moveFromHoldOn({required Offset touchPos, required double verticalSpan}) {
    if (!_holdOn) return;
    final double dx = (touchPos.dx - _holdTouchAnchor.dx).abs();
    final double dy = (touchPos.dy - _holdTouchAnchor.dy).abs();
    verticalSpan.toString(); // span unused here; kept for API symmetry with updateFloating
    if (dy >= kHoldOnVerticalEnterPx && dy > dx) {
      resetForFloating(anchor: _target, originY: _holdTouchAnchor.dy);
      return;
    }
    if (dx >= kHoldOnHorizontalCancelPx && dx > dy) {
      _holdOn = false;
    }
  }

  void resetForFloating({
    required Duration anchor,
    required double originY,
  }) {
    _anchor = _clampDuration(duration, anchor);
    _target = _anchor;
    _active = SnakeActiveMode.floating;
    _originY = originY;
    _holdOn = false;
  }

  void resetForFixed({
    required Duration anchor,
    required double originY,
  }) {
    _anchor = _clampDuration(duration, anchor);
    _target = _anchor;
    _active = SnakeActiveMode.fixed;
    _originY = originY;
    _holdOn = false;
  }

  Duration updateFloating({
    required double touchY,
    required double verticalSpan,
  }) {
    final double raw = ((touchY - _originY) / verticalSpan).clamp(-1.0, 1.0).toDouble();
    final double u = PhoneSnakeScrubberMath.uForPosition(_anchor, duration);
    final Duration delta = PhoneSnakeScrubberMath.deltaForVertical(raw: raw, u: u, wFine: wFine, duration: duration);
    _target = _clampDuration(duration, Duration(milliseconds: _anchor.inMilliseconds + delta.inMilliseconds));
    return _target;
  }

  Duration updateFixed({
    required double touchY,
    required double verticalSpan,
  }) {
    final double v = ((touchY - _originY) / verticalSpan).clamp(-1.0, 1.0).toDouble();
    final Duration delta = PhoneSnakeScrubberMath.deltaForFixedInner(v: v, wFine: wFine);
    _target = _clampDuration(duration, Duration(milliseconds: _anchor.inMilliseconds + delta.inMilliseconds));
    return _target;
  }
}

Duration _clampDuration(Duration duration, Duration candidate) {
  final int ms = candidate.inMilliseconds.clamp(0, duration.inMilliseconds).toInt();
  return Duration(milliseconds: ms);
}
