import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/sideway_panel_layout.dart';

void main() {
  group('borderEdgesForAnchor — which panel edges sit on the window border', () {
    test('corner anchors touch two borders', () {
      expect(borderEdgesForAnchor(Alignment.bottomRight),
          (left: false, top: false, right: true, bottom: true));
      expect(borderEdgesForAnchor(Alignment.topLeft),
          (left: true, top: true, right: false, bottom: false));
    });

    test('edge anchors touch one border', () {
      expect(borderEdgesForAnchor(Alignment.bottomCenter),
          (left: false, top: false, right: false, bottom: true));
      expect(borderEdgesForAnchor(Alignment.centerLeft),
          (left: true, top: false, right: false, bottom: false));
    });

    test('center anchor floats — no border edges', () {
      expect(borderEdgesForAnchor(Alignment.center),
          (left: false, top: false, right: false, bottom: false));
    });
  });

  group('resizePlanForAnchor — 8-zone handle availability', () {
    test('bottom-right dock: only left width / top height / TL corner full', () {
      final plan = resizePlanForAnchor(Alignment.bottomRight);
      expect(plan.leftEdge, isTrue);
      expect(plan.topEdge, isTrue);
      expect(plan.rightEdge, isFalse);
      expect(plan.bottomEdge, isFalse);
      // Corners inherit the union of their two edges; absent when neither
      // edge is resizable.
      expect(plan.cornerTL, (w: true, h: true));
      expect(plan.cornerTR, (w: false, h: true)); // top only
      expect(plan.cornerBL, (w: true, h: false)); // left only
      expect(plan.cornerBR, isNull); // both edges on the border
    });

    test('center float: every zone is live', () {
      final plan = resizePlanForAnchor(Alignment.center);
      expect(plan.leftEdge, isTrue);
      expect(plan.rightEdge, isTrue);
      expect(plan.topEdge, isTrue);
      expect(plan.bottomEdge, isTrue);
      expect(plan.cornerTL, (w: true, h: true));
      expect(plan.cornerTR, (w: true, h: true));
      expect(plan.cornerBL, (w: true, h: true));
      expect(plan.cornerBR, (w: true, h: true));
    });

    test('bottom-center dock: top edge + both top corners only', () {
      final plan = resizePlanForAnchor(Alignment.bottomCenter);
      expect(plan.topEdge, isTrue);
      expect(plan.leftEdge, isTrue);
      expect(plan.rightEdge, isTrue);
      expect(plan.bottomEdge, isFalse);
      expect(plan.cornerTL, (w: true, h: true));
      expect(plan.cornerTR, (w: true, h: true));
      expect(plan.cornerBL, (w: true, h: false));
      expect(plan.cornerBR, (w: true, h: false));
    });
  });

  group('dialPctForWidthDrag — width/height coupling', () {
    const double gap = 8;

    test('widening lets the dial reclaim the freed height (max span)', () {
      // Bar dropped from 3 lines to 1: span grew from 400 to 760.
      final pct = dialPctForWidthDrag(
        widening: true,
        dialPxBefore: 380,
        availH: 800,
        gap: gap,
        barHAfter: 32,
      );
      expect(pct, closeTo(1.0, 1e-9)); // 760/760
    });

    test('narrowing retains the dial pixel height', () {
      // Bar wrapped from 1 line (32) to 3 lines (96): span shrank 760→696.
      final pct = dialPctForWidthDrag(
        widening: false,
        dialPxBefore: 700,
        availH: 800,
        gap: gap,
        barHAfter: 96,
      );
      // 700 / (800 - 96 - 8) = 700/696 → clamps at the 1.00 ceiling.
      expect(pct, closeTo(1.0, 1e-9));
    });

    test('narrowing retains partially while slack remains', () {
      final pct = dialPctForWidthDrag(
        widening: false,
        dialPxBefore: 560,
        availH: 800,
        gap: gap,
        barHAfter: 96,
      );
      expect(pct, closeTo(560 / 696, 1e-6));
    });

    test('degenerate zero span degrades to the ceiling, never NaN', () {
      final pct = dialPctForWidthDrag(
        widening: false,
        dialPxBefore: 400,
        availH: 8,
        gap: gap,
        barHAfter: 96,
      );
      expect(pct.isFinite, isTrue);
      expect(pct, 1.0);
    });
  });

  group('retained scale for the classic circle (0..1 knob)', () {
    test('maps a retained pixel height back onto the scale knob', () {
      // min 100, max 660: retained 380 → (380-100)/(660-100) = 0.5
      expect(
          classicScaleForRetainedPx(
              retainedPx: 380, minSize: 100, maxSize: 660),
          closeTo(0.5, 1e-9));
      expect(
          classicScaleForRetainedPx(
              retainedPx: 1000, minSize: 100, maxSize: 660),
          1.0);
      expect(
          classicScaleForRetainedPx(retainedPx: 20, minSize: 100, maxSize: 660),
          0.0);
    });
  });

  group('effectivePanelWidth — width floor follows the dial', () {
    test('panel never narrower than the dial, capped by the window', () {
      expect(
          effectivePanelWidth(
              draggedWidth: 300, dialDiameter: 420, maxWindowWidth: 1000),
          420);
      expect(
          effectivePanelWidth(
              draggedWidth: 800, dialDiameter: 420, maxWindowWidth: 1000),
          800);
      expect(
          effectivePanelWidth(
              draggedWidth: 800, dialDiameter: 420, maxWindowWidth: 600),
          600);
    });
  });

  group('bottom button rows hug the edge facing the screen centre', () {
    test('right-anchored panel aligns its rows LEFT (toward the centre)', () {
      expect(sidewayButtonAlignForAnchor(Alignment.bottomRight),
          WrapAlignment.start);
      expect(sidewayButtonRowAlignForAnchor(Alignment.bottomRight),
          MainAxisAlignment.start);
    });

    test('left-anchored panel aligns its rows RIGHT (toward the centre)', () {
      expect(
          sidewayButtonAlignForAnchor(Alignment.bottomLeft), WrapAlignment.end);
      expect(sidewayButtonRowAlignForAnchor(Alignment.bottomLeft),
          MainAxisAlignment.end);
    });

    test('centre anchor stays centred', () {
      expect(sidewayButtonAlignForAnchor(Alignment.bottomCenter),
          WrapAlignment.center);
      expect(sidewayButtonRowAlignForAnchor(Alignment.bottomCenter),
          MainAxisAlignment.center);
    });
  });

  group('sidewayBarX — block position, side-relative 0..1', () {
    test('right-docked: 0 hugs the left (centre-facing) edge, 1 the right', () {
      expect(sidewayBarX(anchor: Alignment.bottomRight, pos: 0, free: 200), 0);
      expect(sidewayBarX(anchor: Alignment.bottomRight, pos: 1, free: 200), 200);
      expect(sidewayBarX(anchor: Alignment.bottomRight, pos: 0.5, free: 200),
          100);
    });

    test('left-docked mirrors: 0 hugs the right (centre-facing) edge', () {
      expect(sidewayBarX(anchor: Alignment.bottomLeft, pos: 0, free: 200), 200);
      expect(sidewayBarX(anchor: Alignment.bottomLeft, pos: 1, free: 200), 0);
      expect(sidewayBarX(anchor: Alignment.bottomLeft, pos: 0.5, free: 200),
          100);
    });

    test('centre anchor keeps the historical centred block (knob is a no-op)',
        () {
      expect(sidewayBarX(anchor: Alignment.bottomCenter, pos: 0, free: 200),
          100);
      expect(sidewayBarX(anchor: Alignment.bottomCenter, pos: 1, free: 200),
          100);
    });

    test('no free space (or out-of-range pos) never yields a negative offset',
        () {
      expect(sidewayBarX(anchor: Alignment.bottomRight, pos: 0, free: 0), 0);
      expect(sidewayBarX(anchor: Alignment.bottomRight, pos: 0, free: -40), 0);
      expect(sidewayBarX(anchor: Alignment.bottomRight, pos: 2, free: 200), 200);
      expect(sidewayBarX(anchor: Alignment.bottomRight, pos: -1, free: 200), 0);
    });
  });
}
