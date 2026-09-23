import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';

/// Regression guard for "点击能跳，拖动不行": a DRAG must always resolve to a band
/// (nearest-band fallback), while taps keep their richer classification. The
/// old drag path returned silently for a press outside the bands, which
/// swallowed the whole gesture even though a tap on the same spot acted.
void main() {
  // Reference dial: 210px square → outerR 101, innerR 79.5, innerHitHalf 5.
  final RingDialGeometry g =
      PhoneRingDialMath.dialGeometry(size: const Size.square(210));

  group('resolveDragBand (chunkInner: progress=outer, chunk=inner)', () {
    RingDialDragBand band(double dist) => PhoneRingDialMath.resolveDragBand(
          dist: dist,
          geometry: g,
          chunkIsOuter: false,
          chunkVisible: true,
        );

    test('progress band centre hits progress', () {
      expect(band(g.outerR), RingDialDragBand.progress);
    });

    test('chunk band centre hits chunk', () {
      expect(band(g.innerR), RingDialDragBand.chunk);
    });

    test('progress band inner/outer slack still hits progress', () {
      expect(band(g.outerR - PhoneRingDialMath.kProgressHitInnerSlack),
          RingDialDragBand.progress);
      expect(band(g.outerR + PhoneRingDialMath.kProgressHitOuterSlack),
          RingDialDragBand.progress);
    });

    test('chunk band slack still hits chunk', () {
      expect(band(g.innerR + g.innerHitHalf), RingDialDragBand.chunk);
      expect(band(g.innerR - g.innerHitHalf), RingDialDragBand.chunk);
    });

    test('centre press falls back to the NEAREST band (never empty)', () {
      expect(band(0), RingDialDragBand.chunk);
    });

    test('press far outside every band still resolves', () {
      // 130 is 29px off the progress band and 50px off the chunk band.
      expect(band(130), RingDialDragBand.progress);
      expect(band(30), RingDialDragBand.chunk);
    });

    test('hidden chunk band never answers a drag', () {
      final RingDialDragBand b = PhoneRingDialMath.resolveDragBand(
        dist: g.innerR,
        geometry: g,
        chunkIsOuter: false,
        chunkVisible: false,
      );
      expect(b, RingDialDragBand.progress);
    });
  });

  group('resolveDragBand (outerChunk: progress=inner, chunk=outer)', () {
    RingDialDragBand band(double dist) => PhoneRingDialMath.resolveDragBand(
          dist: dist,
          geometry: g,
          chunkIsOuter: true,
          chunkVisible: true,
        );

    test('outer ring is the chunk band', () {
      expect(band(g.outerR), RingDialDragBand.chunk);
    });

    test('inner ring is the progress band', () {
      expect(band(g.innerR), RingDialDragBand.progress);
    });

    test('centre press falls back to the nearest (progress) band', () {
      expect(band(0), RingDialDragBand.progress);
    });
  });

  group('tap/drag parity', () {
    RingDialDragBand drag(double dist) => PhoneRingDialMath.resolveDragBand(
          dist: dist,
          geometry: g,
          chunkIsOuter: false,
          chunkVisible: true,
        );

    test('every progress-band TAP also resolves to progress for a DRAG', () {
      for (final double d in <double>[
        g.outerR - PhoneRingDialMath.kProgressHitInnerSlack,
        g.outerR,
        g.outerR + PhoneRingDialMath.kProgressHitOuterSlack,
      ]) {
        expect(PhoneRingDialMath.progressBandHit(d, g.outerR), isTrue,
            reason: 'tap must hit at dist=$d');
        expect(drag(d), RingDialDragBand.progress, reason: 'drag at dist=$d');
      }
    });

    test('every chunk-band TAP also resolves to chunk for a DRAG', () {
      for (final double d in <double>[
        g.innerR - g.innerHitHalf,
        g.innerR,
        g.innerR + g.innerHitHalf,
      ]) {
        expect(PhoneRingDialMath.chunkBandHit(d, g.innerR, g), isTrue,
            reason: 'tap must hit at dist=$d');
        expect(drag(d), RingDialDragBand.chunk, reason: 'drag at dist=$d');
      }
    });

    test('drag is a superset of tap (fallback never loses to a tap miss)', () {
      // Just outside the progress band: the tap misses, the drag still answers.
      const double d =
          101.0 + PhoneRingDialMath.kProgressHitOuterSlack + 4;
      expect(PhoneRingDialMath.progressBandHit(d, g.outerR), isFalse);
      expect(drag(d), RingDialDragBand.progress);
    });
  });
}
