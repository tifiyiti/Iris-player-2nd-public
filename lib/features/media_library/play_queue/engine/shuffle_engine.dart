class FeistelShuffle {
  final int seed;
  final int totalCount;

  /// Feistel permutation domain: a power of four (2^(2*halfBits)) that is
  /// always >= [totalCount], so the permutation covers every real index.
  final int domainSize;
  final int halfBits;
  final int halfMask;

  FeistelShuffle(this.seed, this.totalCount)
      : halfBits = _halfBitsFor(totalCount),
        domainSize = 1 << (2 * _halfBitsFor(totalCount)),
        halfMask = (1 << _halfBitsFor(totalCount)) - 1;

  /// Maps a virtual (shuffled) position to the real (original) position.
  ///
  /// [_feistel] is a bijection on [0, domainSize); cycle-walking rejects every
  /// result >= [totalCount], which yields a true permutation of [0, totalCount)
  /// for ANY queue size (no collisions, no dropped items).
  int forward(int virtualPos) {
    if (totalCount <= 1) return totalCount == 0 ? 0 : virtualPos.clamp(0, 0);
    int x = virtualPos;
    do {
      x = _feistel(x);
    } while (x >= totalCount);
    return x;
  }

  /// Maps a real (original) position back to the virtual (shuffled) position.
  ///
  /// Symmetric to [forward]: walks the inverse Feistel orbit, rejecting results
  /// >= [totalCount], so `inverse(forward(i)) == i` holds for every valid i.
  int inverse(int originalPos) {
    if (totalCount <= 1) return totalCount == 0 ? 0 : originalPos.clamp(0, 0);
    int x = originalPos;
    do {
      x = _inverseFeistel(x);
    } while (x >= totalCount);
    return x;
  }

  int _feistel(int x) {
    int l = (x >> halfBits) & halfMask;
    int r = x & halfMask;
    for (int round = 0; round < 4; round++) {
      final int newL = r;
      final int newR = l ^ _roundFunction(r, round);
      l = newL;
      r = newR;
    }
    return ((l & halfMask) << halfBits) | (r & halfMask);
  }

  int _inverseFeistel(int x) {
    int l = (x >> halfBits) & halfMask;
    int r = x & halfMask;
    for (int round = 3; round >= 0; round--) {
      final int newR = l;
      final int newL = r ^ _roundFunction(l, round);
      l = newL;
      r = newR;
    }
    return ((l & halfMask) << halfBits) | (r & halfMask);
  }

  int _roundFunction(int value, int round) {
    final hashInput = '${seed}_${round}_$value';
    final hash = _simpleHash(hashInput);
    return hash & halfMask;
  }

  static int _simpleHash(String input) {
    int hash = 5381;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) + input.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF;
    }
    return hash;
  }

  static int _nextPowerOf2(int n) {
    if (n <= 1) return 1;
    int power = 1;
    while (power < n) {
      power <<= 1;
    }
    return power;
  }

  static int _log2(int n) {
    int result = 0;
    while (n > 1) {
      n >>= 1;
      result++;
    }
    return result;
  }

  /// Smallest half-width whose Feistel domain (2^(2*halfBits)) covers
  /// [totalCount]. ceil(ceilLog2(totalCount) / 2).
  static int _halfBitsFor(int totalCount) =>
      (_log2(_nextPowerOf2(totalCount)) + 1) ~/ 2;
}
