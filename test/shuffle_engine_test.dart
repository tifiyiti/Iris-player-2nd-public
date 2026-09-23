import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/play_queue/engine/shuffle_engine.dart';

void main() {
  // Sizes covering every Feistel regime: powers of two, powers of four,
  // odd-t bands (collisions in the old engine) and even-t-but-not-power-of-4
  // bands (dropped items in the old engine), plus large counts.
  const sizes = [1, 2, 3, 4, 5, 8, 9, 15, 16, 17, 31, 32, 33, 64, 100, 1000];
  const seeds = [1, 42, 12345, 987654321];

  group('FeistelShuffle', () {
    for (final n in sizes) {
      test('N=$n forward is a permutation of [0,N) and inverse is its mirror',
          () {
        for (final seed in seeds) {
          final engine = FeistelShuffle(seed, n);
          final forward = [for (var i = 0; i < n; i++) engine.forward(i)];

          // Full permutation: every real index exactly once, none dropped.
          expect(forward.toSet(), {for (var i = 0; i < n; i++) i},
              reason: 'seed=$seed forward=$forward');

          // inverse is the exact inverse on both sides.
          for (var i = 0; i < n; i++) {
            expect(engine.inverse(engine.forward(i)), i, reason: 'seed=$seed i=$i');
            expect(engine.forward(engine.inverse(i)), i, reason: 'seed=$seed i=$i');
          }
        }
      });
    }

    test('deterministic for the same seed', () {
      const n = 33;
      final a = FeistelShuffle(20260806, n);
      final b = FeistelShuffle(20260806, n);
      expect([for (var i = 0; i < n; i++) a.forward(i)],
          [for (var i = 0; i < n; i++) b.forward(i)]);
    });
  });
}
