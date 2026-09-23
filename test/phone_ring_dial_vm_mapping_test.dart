import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';

/// RED tests for the VM dial-ring mapping fix.
///
/// Dial contract under virtual merge (user-confirmed):
/// - chunk ring: equal division by file count (index space).
/// - progress ring: current file's real duration, file-local 0-100%.
///
/// The painter already draws this way, but tap/drag still compute on the
/// duration-weighted (equal-split total/count) axis, so tap lands and drag
/// deltas are off by up to a whole slot for unequal files.
VirtualMediaItem vmItemOf(List<(String, int)> segs) => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|k|1',
      rootPath: 'k',
      displayIndex: 1,
      displayName: 'k',
      segments: [
        for (final (name, dur) in segs)
          VirtualSegment(
            mediaKey: 'st1:k/$name',
            storageId: 'st1',
            path: ['k', name],
            name: name,
            parentPath: 'k',
            durationMs: dur,
          ),
      ],
    );

void main() {
  // Unequal files: 60s + 659178ms + 30s. Equal-split blockMs would be
  // total/3 ≈ 249726ms; real segDur(1) = 659178ms. Any mapping that
  // confuses the two is off by ~2.6x on file 1.
  final item = vmItemOf([
    ('1.mp4', 60000),
    ('2.mp4', 659178),
    ('3.mp4', 30000),
  ]);
  final total = item.totalDurationMs; // 749178

  group('vm progress-ring tap is the inverse of the painter', () {
    test('outer fraction maps onto the real file span, not total/count', () {
      // File 1 spans [60000, 719178). Its midpoint fraction 0.5 must land at
      // 60000 + 659178/2 = 389589, NOT at equal-split (1*total/3 + 0.5*total/3).
      final got = PhoneRingDialMath.vmVirtualForOuterFraction(
        item: item,
        index: 1,
        fraction: 0.5,
      );
      expect(got, 60000 + 659178 ~/ 2);
      expect(got, isNot(1497356 ~/ 2),
          reason: 'must not use the equal-split axis');
    });

    test('round-trip: paint f -> tap f_angle returns the same virtual pos', () {
      for (final idx in <int>[0, 1, 2]) {
        // f=1.0 sits exactly on the next file's head: locate() awards
        // boundaries to the later segment (translator contract), so the
        // round-trip pivots there by design.
        for (final f in <double>[0.0, 0.25, 0.5, 0.75]) {
          final virtualMs = PhoneRingDialMath.vmVirtualForOuterFraction(
            item: item,
            index: idx,
            fraction: f,
          );
          final back = PhoneRingDialMath.vmFractionForVirtual(item, virtualMs);
          expect(back.$1, idx, reason: 'idx=$idx f=$f stays in file');
          expect(back.$2, closeTo(f, 1e-6), reason: 'idx=$idx f=$f round-trips');
        }
      }
    });
  });

  group('vm chunk ring lives in equal-division index space', () {
    test('equal fraction of virtual pos divides by file count', () {
      // Virtual pos at file-1 midpoint: equalF must be (1 + 0.5)/3 = 0.5,
      // NOT the duration-weighted 389589/749178 ≈ 0.52.
      final eq = PhoneRingDialMath.vmEqualFraction(item, 389589);
      expect(eq.$1, 1);
      expect(eq.$3, closeTo(0.5, 1e-9));
    });

    test('equal fraction inverts: sector i always resolves to file i', () {
      for (var i = 0; i < 3; i++) {
        final virtualMs = PhoneRingDialMath.vmVirtualForEqualFraction(
          item,
          (i + 0.5) / 3,
        );
        final (idx, _) = item.locate(virtualMs);
        expect(idx, i, reason: 'sector $i must land in file $i');
      }
    });

    test('chunk tap lands in the tapped file, not the equal-split span', () {
      for (var i = 0; i < 3; i++) {
        final got = PhoneRingDialMath.vmVirtualForChunkTap(
          item: item,
          sector: i,
          sectorFraction: 0.5,
        );
        final (idx, _) = item.locate(got);
        expect(idx, i, reason: 'tapping sector $i must seek file $i');
      }
    });
  });

  group('vm progress drag rate follows the real file duration', () {
    test('full 330° revolution covers segDur, not total/count', () {
      final s = PhoneRingDialSession.vm(
        item: item,
        startVirtualMs: 60000, // file 1 head
      );
      s.update(0); // prime
      // Sweep the whole 330° arc in +33° steps.
      for (var i = 1; i <= 10; i++) {
        s.update(33.0 * i);
      }
      expect(
        s.targetVirtualMs,
        closeTo(60000 + 659178, 5.0),
        reason: 'one revolution on file 1 must span its real 659178ms, '
            'not total/3=${total ~/ 3}ms',
      );
    });
  });
}
