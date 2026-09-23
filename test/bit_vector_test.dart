import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/resolver/bit_vector.dart';

/// The bit vector is the storage primitive of the shared-order index, so it is
/// checked exhaustively against a naive `List<bool>` oracle: every bit, every
/// exclusive rank, every select, and both neighbour searches.
void main() {
  /// Asserts [bv] agrees with [naive] everywhere.
  void checkAgainstNaive(BitVector bv, List<bool> naive) {
    final len = naive.length;
    final expectedCount = naive.where((b) => b).length;
    expect(bv.length, len);
    expect(bv.count, expectedCount);
    expect(bv.isEmpty, expectedCount == 0);

    for (var i = 0; i < len; i++) {
      expect(bv[i], naive[i], reason: 'bit[$i] (len $len)');
    }

    var acc = 0;
    for (var i = 0; i <= len; i++) {
      expect(bv.rank(i), acc, reason: 'rank($i) (len $len)');
      if (i < len && naive[i]) acc++;
    }
    expect(bv.rank(-5), 0);
    expect(bv.rank(len + 100), expectedCount);
    expect(bv.rankInclusive(len - 1), expectedCount);

    var k = 0;
    for (var i = 0; i < len; i++) {
      if (naive[i]) {
        expect(bv.select(k), i, reason: 'select($k) (len $len)');
        k++;
      }
    }
    expect(bv.select(expectedCount), -1);
    expect(bv.select(-1), -1);

    for (var i = 0; i < len; i++) {
      expect(bv.nextSetBit(i), naive.indexOf(true, i),
          reason: 'nextSetBit($i) (len $len)');
      expect(bv.previousSetBit(i), naive.lastIndexOf(true, i),
          reason: 'previousSetBit($i) (len $len)');
    }
    expect(bv.nextSetBit(-3), naive.indexOf(true, 0));
    expect(bv.nextSetBit(len + 5), -1);
    expect(bv.previousSetBit(len + 5), naive.lastIndexOf(true, len - 1));
    expect(bv.previousSetBit(-1), -1);
  }

  group('BitVector vs naive oracle', () {
    test('random patterns across word/block boundaries', () {
      final rng = Random(20260922);
      // 0,1,2 and every boundary around 64 (word) and 512 (rank block).
      const lengths = <int>[
        0, 1, 2, 3, 63, 64, 65, 127, 128, 129,
        511, 512, 513, 1023, 1024, 1025, 4096, 4097,
      ];
      for (final len in lengths) {
        for (var trial = 0; trial < 4; trial++) {
          // Mix densities so runs of zeros and runs of ones both occur.
          final p = const [0.0, 0.03, 0.5, 0.97, 1.0][trial % 5];
          final naive = List<bool>.generate(len, (_) => rng.nextDouble() < p);
          checkAgainstNaive(BitVector.fromBools(naive), naive);
        }
      }
    });

    test('sparse large vector (select is the hot path)', () {
      final rng = Random(7);
      const len = 200000;
      final set = <int>{for (var i = 0; i < 500; i++) rng.nextInt(len)};
      final naive = List<bool>.filled(len, false);
      for (final i in set) {
        naive[i] = true;
      }
      final bv = BitVector.fromSetBits(len, set);
      expect(bv.count, set.length);
      final sorted = set.toList()..sort();
      for (var k = 0; k < sorted.length; k++) {
        expect(bv.select(k), sorted[k]);
      }
      // Spot-check rank/next/previous.
      for (final probe in const [0, 1, 999, 100000, 199998, 199999]) {
        expect(bv.rank(probe), naive.take(probe).where((b) => b).length);
        expect(bv.nextSetBit(probe), naive.indexOf(true, probe));
        expect(bv.previousSetBit(probe), naive.lastIndexOf(true, probe));
      }
    });
  });

  group('construction and serialization', () {
    test('builder set/clear matches fromBools', () {
      final b = BitVectorBuilder(200);
      for (final i in const [0, 5, 63, 64, 127, 128, 199]) {
        b.set(i);
      }
      b.set(64); // idempotent
      b.clear(5);
      final naive = List<bool>.filled(200, false);
      for (final i in const [0, 63, 64, 127, 128, 199]) {
        naive[i] = true;
      }
      checkAgainstNaive(b.build(), naive);
    });

    test('empty and all-ones edges', () {
      checkAgainstNaive(BitVector.empty(0), const <bool>[]);
      checkAgainstNaive(BitVector.empty(130), List<bool>.filled(130, false));
      checkAgainstNaive(
          BitVector.fromBools(List<bool>.filled(130, true)),
          List<bool>.filled(130, true));
    });

    test('bytes round-trip preserves bits, count and rank table', () {
      final rng = Random(99);
      for (final len in const [0, 1, 64, 65, 512, 513, 4097]) {
        final naive = List<bool>.generate(len, (_) => rng.nextBool());
        final bv = BitVector.fromBools(naive);
        final restored = BitVector.fromBytes(len, bv.toBytes());
        checkAgainstNaive(restored, naive);
        expect(restored.toBytes(), bv.toBytes());
      }
    });

    test('fromBytes masks bits past the declared length', () {
      // A full word of ones declared as only 5 bits.
      final bytes = Uint8List(8)..fillRange(0, 8, 0xff);
      final bv = BitVector.fromBytes(5, bytes);
      expect(bv.length, 5);
      expect(bv.count, 5);
      for (var i = 0; i < 5; i++) {
        expect(bv[i], true);
      }
      expect(bv.rank(5), 5);
      expect(bv.select(4), 4);
      expect(bv.select(5), -1);
    });
  });
}
