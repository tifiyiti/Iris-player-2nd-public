import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/resolver/fg_display_window.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';

void main() {
  const int fg10m = 600000;
  const int bg1m = 60000;

  group('FgDisplayWindowMath.isZoomActive', () {
    test('active when bg is short enough and zoom shrinks the view', () {
      expect(
        FgDisplayWindowMath.isZoomActive(
            fgDurMs: fg10m, bgDurMs: bg1m, zoom: 2),
        isTrue,
      );
    });

    test('inactive at zoom <= 1', () {
      expect(
        FgDisplayWindowMath.isZoomActive(
            fgDurMs: fg10m, bgDurMs: bg1m, zoom: 1),
        isFalse,
      );
    });

    test('inactive when the window would cover the whole fg', () {
      expect(
        FgDisplayWindowMath.isZoomActive(
            fgDurMs: fg10m, bgDurMs: bg1m, zoom: 9),
        isTrue,
      );
      expect(
        FgDisplayWindowMath.isZoomActive(
            fgDurMs: fg10m, bgDurMs: bg1m, zoom: 10),
        isFalse,
      );
    });

    test('inactive without a background duration', () {
      expect(
        FgDisplayWindowMath.isZoomActive(
            fgDurMs: fg10m, bgDurMs: 0, zoom: 2),
        isFalse,
      );
    });
  });

  group('FgDisplayWindowMath.resolve', () {
    test('degrades to the full foreground when zoom is off', () {
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 1,
        pushBg: true,
        fgPosMs: 100000,
        spanStartMs: 80000,
        spanEndMs: 200000,
        requestedStartMs: 5000,
      );
      expect(w.active, isFalse);
      expect(w.startMs, 0);
      expect(w.widthMs, fg10m);
    });

    test('forward pan is capped so A and the dot cannot pass 12 o\'clock', () {
      // W = 120000. min(fgPos=100000, spanStart=80000) = 80000 binds.
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 100000,
        spanStartMs: 80000,
        spanEndMs: 200000,
        requestedStartMs: 200000,
      );
      expect(w.widthMs, 120000);
      expect(w.startMs, 80000);
    });

    test('forward cap falls to the dot when the playhead leads A', () {
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 50000,
        spanStartMs: 80000,
        spanEndMs: 200000,
        requestedStartMs: 200000,
      );
      expect(w.startMs, 50000);
    });

    test('backward pan is capped so B and the dot cannot pass 11 o\'clock', () {
      // W = 120000. max(0, fgPos-W, spanEnd-W) = max(0,-20000,80000) = 80000.
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 100000,
        spanStartMs: 80000,
        spanEndMs: 200000,
        requestedStartMs: 0,
      );
      expect(w.startMs, 80000);
    });

    test('backward cap follows the dot when the playhead leads B', () {
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 500000,
        spanStartMs: 300000,
        spanEndMs: 400000,
        requestedStartMs: 0,
      );
      // max(0, 500000-120000) = 380000.
      expect(w.startMs, 380000);
    });

    test('requested start inside the window is honoured', () {
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: true,
        fgPosMs: 300000,
        spanStartMs: 200000,
        spanEndMs: 400000,
        requestedStartMs: 250000,
      );
      expect(w.startMs, 250000);
    });

    test('media count bounds win when no mapping constrains the window', () {
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 590000,
        spanStartMs: 0,
        spanEndMs: fg10m,
        requestedStartMs: 999999,
      );
      // fgDur - W = 480000.
      expect(w.startMs, 480000);
    });
  });

  group('FgDisplayWindowMath.resolve preferSpan (align editor)', () {
    test('playhead leading A frames the span instead of collapsing it', () {
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 50000,
        spanStartMs: 80000,
        spanEndMs: 200000,
        requestedStartMs: 200000,
        preferSpan: true,
      );
      // W = 120000; A/B bounds are [80000, 80000], so the span is framed.
      expect(w.startMs, 80000);
    });

    test('playhead past B frames the span (dot drawn at the edge)', () {
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 500000,
        spanStartMs: 300000,
        spanEndMs: 400000,
        requestedStartMs: 0,
        preferSpan: true,
      );
      // A/B bounds [280000, 300000]; requested clamps inside them.
      expect(w.startMs, 280000);
    });

    test('compatible playhead still caps the pan', () {
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 270000,
        spanStartMs: 250000,
        spanEndMs: 300000,
        requestedStartMs: 100000,
        preferSpan: true,
      );
      expect(w.startMs, 180000);
    });

    test('a span wider than the window falls back to the playhead', () {
      final w = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 100000,
        spanStartMs: 0,
        spanEndMs: 200000,
        requestedStartMs: 500000,
        preferSpan: true,
      );
      expect(w.startMs, 100000);
    });

    test('forSpan is resolve with preferSpan on', () {
      final a = FgDisplayWindowMath.forSpan(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 50000,
        spanStartMs: 80000,
        spanEndMs: 200000,
        requestedStartMs: 200000,
      );
      final b = FgDisplayWindowMath.resolve(
        fgDurMs: fg10m,
        bgDurMs: bg1m,
        zoom: 2,
        pushBg: false,
        fgPosMs: 50000,
        spanStartMs: 80000,
        spanEndMs: 200000,
        requestedStartMs: 200000,
        preferSpan: true,
      );
      expect(a, b);
    });
  });

  group('FgDisplayWindowMath.reachedWindowEnd', () {
    const win = FgDisplayWindow(
        startMs: 100000, widthMs: 120000, fgDurMs: 600000);

    test('fires only when the dot crosses the end from inside', () {
      expect(FgDisplayWindowMath.reachedWindowEnd(win, 210000, 220000), isTrue);
      expect(FgDisplayWindowMath.reachedWindowEnd(win, 100000, 220000), isTrue);
      expect(FgDisplayWindowMath.reachedWindowEnd(win, 150000, 160000), isFalse);
    });

    test('a dot already past the end never counts', () {
      expect(FgDisplayWindowMath.reachedWindowEnd(win, 230000, 240000), isFalse);
    });

    test('no previous sample or inactive window never fires', () {
      expect(FgDisplayWindowMath.reachedWindowEnd(win, null, 999999), isFalse);
      const full = FgDisplayWindow(
          startMs: 0, widthMs: 600000, fgDurMs: 600000);
      expect(
          FgDisplayWindowMath.reachedWindowEnd(full, 500000, 600000), isFalse);
    });
  });

  group('FgDisplayWindow mapping', () {
    const win = FgDisplayWindow(
        startMs: 100000, widthMs: 120000, fgDurMs: 600000);

    test('fraction maps the window ends to 0 and 1', () {
      expect(win.fractionOf(100000), 0);
      expect(win.fractionOf(220000), 1);
      expect(win.fractionOf(160000), closeTo(0.5, 1e-9));
    });

    test('fraction clamps outside the window', () {
      expect(win.fractionOf(0), 0);
      expect(win.fractionOf(600000), 1);
    });

    test('clampPlayheadMs keeps the dot inside the window', () {
      expect(win.clampPlayheadMs(50000), 100000);
      expect(win.clampPlayheadMs(300000), 220000);
      expect(win.clampPlayheadMs(160000), 160000);
    });

    test('active only when the window is narrower than the media', () {
      expect(win.active, isTrue);
      expect(
        const FgDisplayWindow(startMs: 0, widthMs: 600000, fgDurMs: 600000)
            .active,
        isFalse,
      );
    });
  });

  group('SegmentSpanMath.translateAligned', () {
    test('slides the fg window over a fixed bg window (offset absorbs it)', () {
      const span = SegmentSpan(fgStartMs: 20000, fgEndMs: 80000);
      final out = SegmentSpanMath.translateAligned(
        span,
        10000,
        fgDurMs: 600000,
        bgDurMs: 120000,
      );
      expect(out.fgStartMs, 30000);
      expect(out.fgEndMs, 90000);
      expect(out.bgStartMs, span.bgStartMs);
      expect(out.bgEndMs, span.bgEndMs);
      expect(out.bgOffsetMs, -10000);
    });

    test('a zero delta is a no-op', () {
      const span = SegmentSpan(fgStartMs: 20000, fgEndMs: 80000);
      expect(
        SegmentSpanMath.translateAligned(span, 0,
            fgDurMs: 600000, bgDurMs: 120000),
        span,
      );
    });
  });
}
