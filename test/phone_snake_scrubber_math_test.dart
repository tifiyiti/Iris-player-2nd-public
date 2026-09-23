import 'dart:math' as m;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_scrubber_live_seek_throttle.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_snake_scrubber_math.dart';

void main() {
  const Duration dur60 = Duration(seconds: 60);

  // Canonical test panel: trackLeft=0, axisW=200, fittedTracksH=200.
  // => axisH=40, connector radius r=20.
  // Bar centers y: 20, 60, 100, 140, 180.
  // Path: bar0(L→R,y20) arc0(right,c(200,40)) bar1(R→L,y60) arc1(left,c(0,80))
  //       bar2(L→R,y100) arc2(right,c(200,120)) bar3(R→L,y140) arc3(left,c(0,160))
  //       bar4(L→R,y180)
  const double trackLeft = 0, axisW = 200, fittedH = 200;
  final double r = fittedH / 5 / 2; // 20
  final double arcLen = m.pi * r; // ~62.83
  final double total = 5 * axisW + 4 * arcLen;

  final SerpentineGeometry geo =
      PhoneSnakeScrubberMath.buildSerpentine(trackLeft: trackLeft, axisW: axisW, fittedTracksH: fittedH);

  group('serpentine geometry construction', () {
    test('has 9 elements alternating bar/arc', () {
      expect(geo.segments.length, 9);
      for (int i = 0; i < 9; i++) {
        expect(geo.segments[i].isArc, i.isOdd);
      }
    });

    test('bars are parallel horizontals at 10%..90% heights, alternating direction', () {
      for (int k = 0; k < 5; k++) {
        final SnakePathSegment bar = geo.segments[2 * k];
        expect(bar.isArc, false);
        expect(bar.start.dy, closeTo(fittedH * (k * 2 + 1) / 10, 1e-9));
        expect(bar.end.dy, bar.start.dy);
        if (k.isEven) {
          expect(bar.start.dx, trackLeft);
          expect(bar.end.dx, trackLeft + axisW);
        } else {
          expect(bar.start.dx, trackLeft + axisW);
          expect(bar.end.dx, trackLeft);
        }
      }
    });

    test('arcs are true semicircles bulging outward at alternating ends', () {
      for (int c = 0; c < 4; c++) {
        final SnakePathSegment arc = geo.segments[2 * c + 1];
        expect(arc.isArc, true);
        expect(arc.radius, closeTo(r, 1e-9));
        expect(arc.length, closeTo(m.pi * r, 1e-9));
        // Endpoints connect the adjacent bar ends exactly (antipodal points).
        final Offset depEnd = geo.segments[2 * c].end;
        final Offset arrStart = geo.segments[2 * c + 2].start;
        expect(arc.pointAt(0), depEnd);
        expect(arc.pointAt(1), arrStart);
        // Bulge side: even connectors right, odd left.
        final Offset apex = arc.pointAt(0.5);
        final bool bulgesRight = c.isEven;
        expect(apex.dy, closeTo(depEnd.dy + r, 1e-6));
        if (bulgesRight) {
          expect(arc.center.dx, closeTo(trackLeft + axisW, 1e-9));
          expect(apex.dx, greaterThan(trackLeft + axisW));
        } else {
          expect(arc.center.dx, closeTo(trackLeft, 1e-9));
          expect(apex.dx, lessThan(trackLeft));
        }
      }
    });

    test('total length counts arcs (circles occupy progress)', () {
      expect(geo.totalLength, closeTo(total, 1e-6));
      expect(geo.totalLength, greaterThan(5 * axisW));
    });
  });

  group('arc-length parameterization', () {
    test('positionForU endpoints', () {
      expect(geo.positionForU(0), const Offset(0, 20));
      expect(geo.positionForU(1), const Offset(axisW, 180));
    });

    test('element junctions are continuous', () {
      expect(geo.positionForU(axisW / total), const Offset(axisW, 20)); // bar0 end
      expect(geo.positionForU((axisW + arcLen) / total), const Offset(axisW, 60)); // arc0 end
      expect(geo.positionForU((2 * axisW + arcLen) / total), const Offset(0, 60)); // bar1 end
    });

    test('mid-arc lands on bulge apex', () {
      final Offset apexRight = geo.positionForU((axisW + arcLen / 2) / total);
      expect(apexRight.dx, closeTo(axisW + r, 1e-6));
      expect(apexRight.dy, closeTo(40, 1e-6));
      final Offset apexLeft = geo.positionForU((2 * axisW + arcLen + arcLen / 2) / total);
      expect(apexLeft.dx, closeTo(-r, 1e-6));
      expect(apexLeft.dy, closeTo(80, 1e-6));
    });

    test('segForU/fracForSegU/uForSegFrac round-trip', () {
      for (final double u in <double>[0.02, 0.08, 0.17, 0.185, 0.3, 0.5, 0.66, 0.83, 0.99]) {
        final int seg = geo.segForU(u);
        final double frac = geo.fracForSegU(seg, u);
        expect(geo.uForSegFrac(seg, frac), closeTo(u, 1e-9));
      }
    });

    test('barForU: arc bands belong to departure bar', () {
      expect(geo.barForU(0.01), 0);
      expect(geo.barForU((axisW + arcLen * 0.5) / total), 0); // mid arc0 → still bar0
      expect(geo.barForU((axisW + arcLen + 100) / total), 1); // mid bar1
      expect(geo.barForU(0.999), 4);
      expect(geo.barForU(1.0), 4);
    });

    test('txForBarX direction-aware with clamp', () {
      expect(geo.txForBarX(100, 0), 0.5); // forward bar
      expect(geo.txForBarX(100, 1), 0.5); // reverse bar symmetric
      expect(geo.txForBarX(-50, 0), 0.0);
      expect(geo.txForBarX(500, 0), 1.0);
      expect(geo.txForBarX(-50, 1), 1.0); // reverse bar travel starts right
      expect(geo.txForBarX(500, 1), 0.0);
    });

    test('uForBarTx lerps inside owning bar band', () {
      expect(geo.uForBarTx(0, 0.5), closeTo(100 / total, 1e-9));
      expect(geo.uForBarTx(0, 1.0), closeTo(axisW / total, 1e-9));
      expect(geo.uForBarTx(1, 0.0), closeTo((axisW + arcLen) / total, 1e-9));
      expect(geo.uForBarTx(1, 1.0), closeTo((2 * axisW + arcLen) / total, 1e-9));
      expect(geo.uForBarTx(4, 1.0), closeTo(1.0, 1e-9));
    });
  });

  group('nearestOnPath', () {
    test('point on a bar', () {
      final NearestOnPathResult hit = geo.nearest(const Offset(100, 20));
      expect(hit.seg, 0);
      expect(hit.isBar, true);
      expect(hit.barIndex, 0);
      expect(hit.frac, closeTo(0.5, 1e-9));
      expect(hit.dist, closeTo(0, 1e-9));
    });

    test('point beyond arc apex snaps onto arc', () {
      final NearestOnPathResult hit = geo.nearest(Offset(axisW + 2 * r, 40)); // 40px right of center
      expect(hit.seg, 1);
      expect(hit.isBar, false);
      expect(hit.frac, closeTo(0.5, 1e-6));
      expect(hit.dist, closeTo(r, 1e-6));
    });

    test('beyond outer X clamps to path endpoints', () {
      final NearestOnPathResult left = geo.nearest(const Offset(-300, 20));
      expect(left.seg, 0);
      expect(left.frac, closeTo(0.0, 1e-9));
      final NearestOnPathResult rightBottom = geo.nearest(const Offset(500, 180));
      expect(rightBottom.seg, 8);
      expect(rightBottom.frac, closeTo(1.0, 1e-9));
    });
  });

  group('effectiveLineWidth narrow', () {
    test('much narrower than axisH/2 so cross-axis locking engages', () {
      final double w = PhoneSnakeScrubberMath.effectiveLineWidth(fittedH / 5);
      expect(w, lessThan(fittedH / 5 / 2)); // strictly narrower than old default
      expect(w, greaterThanOrEqualTo(6.0));
      expect(w, lessThanOrEqualTo(16.0));
    });
  });

  group('session updateZPath on-line vs off-line', () {
    final double lineW = PhoneSnakeScrubberMath.effectiveLineWidth(fittedH / 5);

    test('on-line free follow traverses whole serpentine incl. arcs', () {
      final sess = PhoneSnakeScrubSession(duration: dur60, wFine: const Duration(seconds: 30));
      sess.resetForZ(geometry: geo, lockedBar: 0, anchor: Duration.zero);
      int lastMs = -1;
      // Walk down the serpentine: bar0 → arc0 apex → bar1 → … → bar4 end.
      final List<Offset> waypoints = <Offset>[
        const Offset(100, 20),
        Offset(axisW + r, 40), // arc apex
        const Offset(100, 60),
        Offset(-r, 80), // left apex
        const Offset(100, 100),
        Offset(axisW + r, 120),
        const Offset(100, 140),
        Offset(-r, 160),
        const Offset(100, 180),
        const Offset(500, 180),
      ];
      for (final Offset wp in waypoints) {
        final Duration t = sess.updateZPath(p: wp, lineWidth: lineW);
        expect(t.inMilliseconds >= lastMs, true, reason: 'monotonic at $wp');
        lastMs = t.inMilliseconds;
      }
      expect(sess.target, dur60);
    });

    test('off-line locks to current bar band and never jumps axes', () {
      final sess = PhoneSnakeScrubSession(duration: dur60, wFine: const Duration(seconds: 30));
      sess.resetForZ(geometry: geo, lockedBar: 0, anchor: const Duration(seconds: 4));
      // Far off-line point: projects back onto bar0 horizontal, clamped.
      final Duration t = sess.updateZPath(p: const Offset(500, -60), lineWidth: lineW);
      final double expectedU = geo.uForBarTx(0, geo.txForBarX(500, 0));
      expect(t.inMilliseconds, closeTo(expectedU * 60000, 2));
      // Sliding further right off-line stays clamped at bar0 band end (< 12s).
      final Duration t2 = sess.updateZPath(p: const Offset(900, -60), lineWidth: lineW);
      expect(t2.inMilliseconds, closeTo((axisW / total) * 60000, 2));
      expect(t2.inSeconds, lessThan(12));
    });
  });

  group('session hold-on state machine', () {
    test('enterHoldOn shows hold state without changing mode/target', () {
      final sess = _zSession(anchorSec: 4);
      sess.enterHoldOn(touchPos: const Offset(100, 20));
      expect(sess.holdOn, true);
      expect(sess.active, SnakeActiveMode.z);
      expect(sess.target, const Duration(seconds: 4));
    });

    test('hold-on + dominant vertical move switches to floating anchored at target', () {
      final sess = _zSession(anchorSec: 4);
      sess.enterHoldOn(touchPos: const Offset(100, 20));
      sess.moveFromHoldOn(touchPos: const Offset(103, 45), verticalSpan: 200);
      expect(sess.holdOn, false);
      expect(sess.active, SnakeActiveMode.floating);
      expect(sess.anchor, const Duration(seconds: 4));
    });

    test('floating after hold-on actually responds (regression: was dead)', () {
      final sess = _zSession(anchorSec: 15); // u=0.25 ⇒ forward ratio > 0
      sess.enterHoldOn(touchPos: const Offset(100, 60));
      sess.moveFromHoldOn(touchPos: const Offset(100, 84), verticalSpan: 200);
      expect(sess.active, SnakeActiveMode.floating);
      final Duration t = sess.updateFloating(touchY: 84 + 200, verticalSpan: 200);
      expect(t.inMilliseconds, greaterThan(const Duration(seconds: 15).inMilliseconds));
    });

    test('hold-on + dominant horizontal move cancels back to z', () {
      final sess = _zSession(anchorSec: 4);
      sess.enterHoldOn(touchPos: const Offset(100, 20));
      sess.moveFromHoldOn(touchPos: const Offset(130, 22), verticalSpan: 200);
      expect(sess.holdOn, false);
      expect(sess.active, SnakeActiveMode.z);
    });

    test('small jitter while holding keeps hold-on', () {
      final sess = _zSession(anchorSec: 4);
      sess.enterHoldOn(touchPos: const Offset(100, 20));
      sess.moveFromHoldOn(touchPos: const Offset(102, 21), verticalSpan: 200);
      expect(sess.holdOn, true);
      expect(sess.active, SnakeActiveMode.z);
    });
  });

  group('live seek throttle', () {
    test('allows first, gates inside interval, releases after interval', () {
      final th = PhoneScrubberLiveSeekThrottle();
      final DateTime t0 = DateTime(2026, 1, 1);
      expect(th.allow(t0), true);
      expect(th.allow(t0.add(const Duration(milliseconds: 50))), false);
      expect(th.allow(t0.add(const Duration(milliseconds: 119))), false);
      expect(th.allow(t0.add(const Duration(milliseconds: 120))), true);
      expect(th.allow(t0.add(const Duration(milliseconds: 200))), false);
    });

    test('reset re-arms immediately', () {
      final th = PhoneScrubberLiveSeekThrottle();
      final DateTime t0 = DateTime(2026, 1, 1);
      expect(th.allow(t0), true);
      th.reset();
      expect(th.allow(t0.add(const Duration(milliseconds: 1))), true);
    });
  });

  group('vertical fine mapping (unchanged semantics)', () {
    test('axis5 up → toward 0% (negative)', () {
      final d = PhoneSnakeScrubberMath.deltaForVertical(raw: -1, u: 0.9, wFine: const Duration(seconds: 30), duration: dur60);
      expect(d.inMilliseconds < 0, true);
    });
    test('axis1 down → toward 100% (positive)', () {
      final d = PhoneSnakeScrubberMath.deltaForVertical(raw: 1, u: 0.3, wFine: const Duration(seconds: 30), duration: dur60);
      expect(d.inMilliseconds > 0, true);
    });
    test('full span = wFine/2 at 50/50', () {
      final d = PhoneSnakeScrubberMath.deltaForVertical(raw: 1, u: 0.6, wFine: const Duration(seconds: 60), duration: dur60);
      expect(d.inMilliseconds, 30000);
    });
  });
}

PhoneSnakeScrubSession _zSession({required int anchorSec}) {
  final geo = PhoneSnakeScrubberMath.buildSerpentine(trackLeft: 0, axisW: 200, fittedTracksH: 200);
  final sess = PhoneSnakeScrubSession(duration: const Duration(seconds: 60), wFine: const Duration(seconds: 30));
  sess.resetForZ(geometry: geo, lockedBar: 0, anchor: Duration(seconds: anchorSec));
  return sess;
}
