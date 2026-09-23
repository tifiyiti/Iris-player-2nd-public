import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/fg_display_window.dart';
import 'package:iris/features/background_playback/resolver/segment_snap.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';
import 'package:iris/features/background_playback/view/segment_dual_ring_dial.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// The side dial's P handle sets the ALIGNMENT: it reports INCREMENTAL per-tick
/// deltas (the parent accumulates them against the gesture's reference span),
/// and every handle drag brackets the gesture with `onDragActive(true/false)`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ch = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(ch, (call) async => null);

  // Pin the ring knobs so the dial box is exactly the host square (the test
  // computes handle positions from that geometry).
  setUp(() {
    final app = useAppStore();
    app.set(app.state.copyWith(
      ringDialHeightPct: 1.0,
      ringDialRingSlotT: 0.5,
      ringDialOuterRadius: 1.0,
      ringDialInnerRadius: 0.787,
    ));
  });

  const int fgDur = 100000;
  const int bgDur = 40000;
  const span = SegmentSpan(
    fgStartMs: 30000,
    fgEndMs: 50000,
    bgOffsetMs: -30000,
  );
  const double size = 200;

  Widget host(Widget dial) => InheritedProvider<StoreLocator>.value(
        value: StoreLocator(),
        startListening:
            (InheritedContext<StoreLocator?> e, StoreLocator value) {
          final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
          return sub.cancel;
        },
        lazy: false,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: size, height: size, child: dial),
            ),
          ),
        ),
      );

  testWidgets('P drag reports incremental deltas (equal steps ⇒ equal deltas)',
      (tester) async {
    final deltas = <int>[];
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      window: const FgDisplayWindow(startMs: 0, widthMs: fgDur, fgDurMs: fgDur),
      // Foreground on the OUTER ring ⇒ the bg/APB handles live on the inner
      // ring (role-based, not a fixed radius).
      fgOnInner: false,
      onSeekFg: (_) {},
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (d) {
        if (d != 0) deltas.add(d);
      },
    )));
    await tester.pumpAndSettle();

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double r = handleRadiusFor(SegmentPoint.p, geom.innerR);
    Offset at(double clockDeg) {
      final double rad = (clockDeg - 90) * math.pi / 180;
      return geom.center + Offset(r * math.cos(rad), r * math.sin(rad));
    }

    // P sits at the window centre: 40s of 100s over the 330° sweep.
    final double centerClock = 330 * span.centerMs / fgDur;

    final gesture = await tester.startGesture(at(centerClock));
    await tester.pump();
    // Clear the touch slop first (this step's delta is discarded).
    await gesture.moveTo(at(centerClock + 40));
    await tester.pump();
    // Two EQUAL 20° steps.
    await gesture.moveTo(at(centerClock + 60));
    await tester.pump();
    await gesture.moveTo(at(centerClock + 80));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(deltas.length, greaterThanOrEqualTo(2),
        reason: 'the P handle must have been grabbed (not a body seek)');
    final tail = deltas.sublist(deltas.length - 2);
    expect(tail[0], isNot(0));
    expect(tail[1], isNot(0));
    // Equal angular steps ⇒ equal increments (an accumulated total would double).
    expect((tail[1] - tail[0]).abs(), lessThan((tail[0].abs() * 0.3).ceil()));
    // ~20° of 330° over 100s.
    expect(tail[0].abs(), greaterThan(3000));
  });

  testWidgets('a ring body drag is a throttled scrub with a clean lifecycle',
      (tester) async {
    final seeks = <int>[];
    var scrubStarts = 0;
    var scrubEnds = 0;
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      window: const FgDisplayWindow(startMs: 0, widthMs: fgDur, fgDurMs: fgDur),
      fgOnInner: false,
      onSeekFg: seeks.add,
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
      onScrubStart: () => scrubStarts++,
      onScrubEnd: () => scrubEnds++,
    )));
    await tester.pumpAndSettle();

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double rad = (250 - 90) * math.pi / 180; // far from any A/P/B handle
    final Offset start =
        geom.center + Offset(geom.outerR * math.cos(rad), geom.outerR * math.sin(rad));

    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveTo(start + const Offset(10, 6));
    await tester.pump();
    await gesture.moveTo(start + const Offset(18, 12));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(scrubStarts, 1, reason: 'armed once on touch-down');
    expect(scrubEnds, 1, reason: 'released once');
    // Throttled live seeks (at most one per interval) + ONE committed seek.
    expect(seeks, isNotEmpty);
    expect(seeks.length, lessThanOrEqualTo(3));
  });

  testWidgets('q pan reports an absolute window start and its lifecycle',
      (tester) async {
    final starts = <int>[];
    final active = <bool>[];
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      window:
          const FgDisplayWindow(startMs: 20000, widthMs: 40000, fgDurMs: fgDur),
      fgOnInner: false,
      onSeekFg: (_) {},
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
      onWindowStartChanged: (v) {
        starts.add(v);
        return v;
      },
      onWindowDragActive: active.add,
    )));
    await tester.pumpAndSettle();

    // q lives at 5 o'clock in the annulus between the fg and bg rings (it must
    // not sit on the fg playback dot's radius).
    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double qR = qHandleRadiusFor(geom.outerR, geom.innerR);
    Offset at(double clockDeg) {
      final double rad = (clockDeg - 90) * math.pi / 180;
      return geom.center + Offset(qR * math.cos(rad), qR * math.sin(rad));
    }

    final gesture = await tester.startGesture(at(150));
    await tester.pump();
    // Clear the touch slop, then pan clockwise toward 100%.
    await gesture.moveTo(at(190));
    await tester.pump();
    await gesture.moveTo(at(220));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(active, contains(true), reason: 'q touch-down arms the pan drag');
    expect(active.last, isFalse, reason: 'release clears the local drag state');
    expect(starts, isNotEmpty, reason: 'q must report pan targets');
    expect(starts.last, greaterThan(20000),
        reason: 'panning toward 100% advances the window start');
  });

  testWidgets('a tap inside the window seeks to that clock position',
      (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      window:
          const FgDisplayWindow(startMs: 20000, widthMs: 40000, fgDurMs: fgDur),
      fgOnInner: false,
      onSeekFg: seeks.add,
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
    )));
    await tester.pumpAndSettle();

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    // 90° is a quarter of the 330° sweep and clear of q (5 o'clock, 150°).
    final double rad = (90 - 90) * math.pi / 180;
    final Offset at = geom.center +
        Offset(geom.outerR * math.cos(rad), geom.outerR * math.sin(rad));

    await tester.tapAt(at);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(seeks, isNotEmpty, reason: 'a tap must seek');
    // 90° of the 330° sweep = a quarter into the 40s window: 20s + 10s ≈ 30s.
    expect(seeks.last, closeTo(30900, 4000),
        reason: 'the tap maps to the window-relative clock');
  });

  testWidgets('a handle drag reports its lifecycle (active → released)',
      (tester) async {
    final active = <bool>[];
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      window: const FgDisplayWindow(startMs: 0, widthMs: fgDur, fgDurMs: fgDur),
      fgOnInner: false,
      onSeekFg: (_) {},
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
      onDragActive: active.add,
    )));
    await tester.pumpAndSettle();

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double r = handleRadiusFor(SegmentPoint.p, geom.innerR);
    final double rad = (330 * span.centerMs / fgDur - 90) * math.pi / 180;
    final start = geom.center + Offset(r * math.cos(rad), r * math.sin(rad));

    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveTo(start + const Offset(12, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(active, contains(true));
    expect(active.last, isFalse, reason: 'release clears the local drag state');
  });

  testWidgets('q snaps back to its 5 o\'clock home after release',
      (tester) async {
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      window:
          const FgDisplayWindow(startMs: 20000, widthMs: 40000, fgDurMs: fgDur),
      fgOnInner: false,
      onSeekFg: (_) {},
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
      onWindowStartChanged: (v) => v,
      onWindowDragActive: (_) {},
    )));
    await tester.pumpAndSettle();

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double qR = qHandleRadiusFor(geom.outerR, geom.innerR);
    Offset at(double clockDeg) {
      final double rad = (clockDeg - 90) * math.pi / 180;
      return geom.center + Offset(qR * math.cos(rad), qR * math.sin(rad));
    }

    // The painter's private type exposes the public override field, so the
    // rendered q position is directly assertable (no golden needed).
    double? qOverride() {
      final CustomPaint cp = tester.widget<CustomPaint>(find
          .descendant(
            of: find.byKey(const ValueKey('segment_dual_ring')),
            matching: find.byType(CustomPaint),
          )
          .first);
      return (cp.painter as dynamic).qClockOverrideDeg as double?;
    }

    expect(qOverride(), isNull, reason: 'idle q is drawn at its home');

    final gesture = await tester.startGesture(at(150));
    await tester.pump();
    await gesture.moveTo(at(190));
    await tester.pump();
    await gesture.moveTo(at(220));
    await tester.pump();
    expect(qOverride(), isNotNull, reason: 'a drag draws q under the finger');

    await gesture.up();
    await tester.pump();
    expect(qOverride(), isNull,
        reason: 'release snaps q back to the 5 o\'clock home');
  });

  testWidgets('q is grabbable again after a pan (hit zone stays at home)',
      (tester) async {
    final starts = <int>[];
    final active = <bool>[];
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      window:
          const FgDisplayWindow(startMs: 20000, widthMs: 40000, fgDurMs: fgDur),
      fgOnInner: false,
      onSeekFg: (_) {},
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
      onWindowStartChanged: (v) {
        starts.add(v);
        return v;
      },
      onWindowDragActive: active.add,
    )));
    await tester.pumpAndSettle();

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double qR = qHandleRadiusFor(geom.outerR, geom.innerR);
    Offset at(double clockDeg) {
      final double rad = (clockDeg - 90) * math.pi / 180;
      return geom.center + Offset(qR * math.cos(rad), qR * math.sin(rad));
    }

    final first = await tester.startGesture(at(150));
    await tester.pump();
    await first.moveTo(at(190));
    await tester.pump();
    await first.moveTo(at(220));
    await tester.pump();
    await first.up();
    await tester.pump();
    final int firstStarts = starts.length;
    expect(firstStarts, greaterThan(0));
    expect(active.last, isFalse);

    // The stale-visual regression: a second grab must land on q again (not
    // fall through to a body scrub) while the dot keeps following the finger.
    final second = await tester.startGesture(at(150));
    await tester.pump();
    expect(active.last, isTrue, reason: 'q is grabbable again at its home');
    await second.moveTo(at(200));
    await tester.pump();
    await second.up();
    await tester.pump();

    expect(starts.length, greaterThan(firstStarts),
        reason: 'the second pan reports new window starts');
    expect(active.last, isFalse);
  });

  testWidgets('q hard-stops at the window boundary and reverses immediately',
      (tester) async {
    const int lo = 20000;
    const int hi = 28000;
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      window:
          const FgDisplayWindow(startMs: 20000, widthMs: 40000, fgDurMs: fgDur),
      fgOnInner: false,
      onSeekFg: (_) {},
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
      // The host is the authority on the bounds; it returns the clamped start.
      onWindowStartChanged: (v) => v.clamp(lo, hi),
      onWindowDragActive: (_) {},
    )));
    await tester.pumpAndSettle();

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double qR = qHandleRadiusFor(geom.outerR, geom.innerR);
    Offset at(double clockDeg) {
      final double rad = (clockDeg - 90) * math.pi / 180;
      return geom.center + Offset(qR * math.cos(rad), qR * math.sin(rad));
    }

    double? qOverride() {
      final CustomPaint cp = tester.widget<CustomPaint>(find
          .descendant(
            of: find.byKey(const ValueKey('segment_dual_ring')),
            matching: find.byType(CustomPaint),
          )
          .first);
      return (cp.painter as dynamic).qClockOverrideDeg as double?;
    }

    // 40000ms window, 330° sweep ⇒ 8000ms of headroom = 66°. From the 150° home
    // the reachable extreme is 216°; the finger goes to 250°.
    final gesture = await tester.startGesture(at(150));
    await tester.pump();
    await gesture.moveTo(at(190));
    await tester.pump();
    await gesture.moveTo(at(250));
    await tester.pump();
    expect(qOverride(), closeTo(216, 3),
        reason: 'q pins at the boundary instead of following the finger');

    // Reverse: no phantom overshoot to unwind, so the handle moves at once.
    await gesture.moveTo(at(220));
    await tester.pump();
    expect(qOverride(), lessThan(200),
        reason: 'reversing the finger moves q back immediately');

    await gesture.up();
    await tester.pump();
  });

  testWidgets('q is not grabbable when the zoom window is inactive',
      (tester) async {
    final active = <bool>[];
    final scrubs = <int>[];
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      // Full-duration window ⇒ zoom inactive ⇒ no q.
      window: const FgDisplayWindow(startMs: 0, widthMs: fgDur, fgDurMs: fgDur),
      fgOnInner: false,
      onSeekFg: (_) {},
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
      onWindowStartChanged: (v) => v,
      onWindowDragActive: active.add,
      onScrubStart: () => scrubs.add(1),
    )));
    await tester.pumpAndSettle();

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double qR = qHandleRadiusFor(geom.outerR, geom.innerR);
    final double rad = (150 - 90) * math.pi / 180;
    final Offset at = geom.center +
        Offset(qR * math.cos(rad), qR * math.sin(rad));

    final gesture = await tester.startGesture(at);
    await tester.pump();
    await gesture.moveTo(at + const Offset(14, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(active, isNot(contains(true)),
        reason: 'a non-zoom window exposes no q handle');
    expect(scrubs.length, 1, reason: 'the touch falls through to a body scrub');
  });

  testWidgets('q sits in the annulus, not on the fg playback-dot radius',
      (tester) async {
    final active = <bool>[];
    final scrubs = <int>[];
    await tester.pumpWidget(host(SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: fgDur,
      bgPosMs: 10000,
      bgDurMs: bgDur,
      span: span,
      window:
          const FgDisplayWindow(startMs: 20000, widthMs: 40000, fgDurMs: fgDur),
      fgOnInner: false,
      onSeekFg: (_) {},
      onChangeStart: (_) {},
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
      onWindowStartChanged: (v) => v,
      onWindowDragActive: active.add,
      onScrubStart: () => scrubs.add(1),
    )));
    await tester.pumpAndSettle();

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double rad = (150 - 90) * math.pi / 180;

    // Exactly on the fg ring (where the playback dot lives) must NOT grab q.
    final Offset onFgRing =
        geom.center + Offset(geom.outerR * math.cos(rad), geom.outerR * math.sin(rad));
    final first = await tester.startGesture(onFgRing);
    await tester.pump();
    await first.moveTo(onFgRing + const Offset(14, 0));
    await tester.pump();
    await first.up();
    await tester.pump();
    expect(active, isNot(contains(true)),
        reason: 'the fg dot radius no longer belongs to q');
    expect(scrubs.length, 1);

    // The annulus radius does.
    final double qR = qHandleRadiusFor(geom.outerR, geom.innerR);
    final Offset onAnnulus =
        geom.center + Offset(qR * math.cos(rad), qR * math.sin(rad));
    final second = await tester.startGesture(onAnnulus);
    await tester.pump();
    expect(active, contains(true), reason: 'q lives in the annulus');
    await second.up();
    await tester.pump();
  });

  testWidgets('snap walls stop A, release on tap-up, and evict by recency',
      (tester) async {
    // Saved edges become walls; the 0 / fgDur ends never do.
    final walls = SegmentSnap.wallsFromSlices(
      [
        MappingSegment(
            action: MappingAction.playMedia, fgStartMs: 20000, fgEndMs: 35000),
        MappingSegment(
            action: MappingAction.playMedia, fgStartMs: 35000, fgEndMs: 45000),
      ],
      fgDurMs: fgDur,
    );
    expect(walls, [20000, 35000, 45000]);

    await tester.pumpWidget(host(const _SnapHost()));
    await tester.pumpAndSettle();

    _SnapHostState state() =>
        tester.state<_SnapHostState>(find.byType(_SnapHost));
    SegmentDualRingDial dial() => tester.widget<SegmentDualRingDial>(
        find.byType(SegmentDualRingDial));

    final geom = PhoneRingDialMath.dialGeometry(size: const Size(size, size));
    final double r = handleRadiusFor(SegmentPoint.a, geom.innerR);
    Offset atClock(double clockDeg) {
      final rad = (clockDeg - 90) * math.pi / 180;
      return geom.center + Offset(r * math.cos(rad), r * math.sin(rad));
    }

    double clockOf(int ms) => 330 * ms / fgDur;

    // A starts at 30000 (99°). Push toward 40000: must stop at 35000.
    var g = await tester.startGesture(atClock(clockOf(30000)));
    await tester.pump();
    await g.moveTo(atClock(clockOf(40000)));
    await tester.pump();
    expect(state().span.fgStartMs, 35000,
        reason: 'A stops exactly at the saved boundary');
    // Pushing further in the same gesture stays on the wall.
    await g.moveTo(atClock(clockOf(43000)));
    await tester.pump();
    expect(state().span.fgStartMs, 35000,
        reason: 'the same gesture cannot pass the wall it hit');
    await g.up();
    await tester.pump();

    // Tap-up released the wall: the dial now treats it as passable.
    expect(dial().snapReleased, {35000});

    // A new gesture passes 35000 freely.
    g = await tester.startGesture(atClock(clockOf(35000)));
    await tester.pump();
    await g.moveTo(atClock(clockOf(40000)));
    await tester.pump();
    expect(state().span.fgStartMs, 40000,
        reason: 'the released wall passes both ways');
    await g.up();
    await tester.pump();

    // Push on to 45000: it blocks, and releasing it evicts 35000 (limit 1).
    g = await tester.startGesture(atClock(clockOf(40000)));
    await tester.pump();
    await g.moveTo(atClock(clockOf(48000)));
    await tester.pump();
    expect(state().span.fgStartMs, 45000,
        reason: 'the next live wall blocks');
    await g.up();
    await tester.pump();
    expect(dial().snapReleased, {45000});
    expect(state().memory.isReleased(35000), isFalse,
        reason: 'the older release blocks again');

    // Dragging back down stops at the re-armed 35000.
    g = await tester.startGesture(atClock(clockOf(45000)));
    await tester.pump();
    await g.moveTo(atClock(clockOf(25000)));
    await tester.pump();
    expect(state().span.fgStartMs, 35000,
        reason: 'an evicted wall blocks again');
    await g.up();
    await tester.pump();
  });
}

/// Snap-mode host: applies [SegmentSnap] walls to A drags through a
/// [SnapDragSession], releases hits on tap-up, and feeds the clamped span back
/// to the dial (the panel's contract in miniature).
class _SnapHost extends StatefulWidget {
  const _SnapHost();

  @override
  State<_SnapHost> createState() => _SnapHostState();
}

class _SnapHostState extends State<_SnapHost> {
  static const _hostSpan = SegmentSpan(
    fgStartMs: 30000,
    fgEndMs: 50000,
    bgOffsetMs: -30000,
  );

  SegmentSpan span = _hostSpan;
  final SegmentSnapMemory memory = SegmentSnapMemory(1);
  SnapDragSession? session;

  static const _walls = [20000, 35000, 45000];

  void _onChangeStart(int a) {
    final s = session ??= SnapDragSession(
      walls: _walls,
      released: memory.released,
    );
    final r = s.advance(from: span.fgStartMs, desired: a);
    setState(() {
      span = SegmentSpanMath.dragStart(
        span,
        r.value,
        fgDurMs: 100000,
        bgDurMs: 40000,
        minSpanMs: 500,
      );
    });
  }

  void _onDragActive(bool active) {
    if (active) {
      session = SnapDragSession(
        walls: _walls,
        released: memory.released,
      );
    } else {
      for (final w in session?.hits ?? const <int>[]) {
        memory.release(w);
      }
      session = null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SegmentDualRingDial(
      fgPosMs: 40000,
      fgDurMs: 100000,
      bgPosMs: 10000,
      bgDurMs: 40000,
      span: span,
      window:
          const FgDisplayWindow(startMs: 0, widthMs: 100000, fgDurMs: 100000),
      fgOnInner: false,
      onSeekFg: (_) {},
      onChangeStart: _onChangeStart,
      onChangeEnd: (_) {},
      onOffsetDrag: (_) {},
      onDragActive: _onDragActive,
      snapActive: true,
      snapWalls: _walls,
      snapReleased: memory.released,
    );
  }
}
