import 'dart:typed_data';

/// A fixed-length bit vector with O(1) [rank] and O(log n) [select].
///
/// Backs the shared-order derived index (schema v44): a scenario's membership
/// in a shared media order is stored as a bitmap, so the scenario's base rank
/// at any global position is a [rank] call rather than a persisted permutation
/// — which is what made the old derived index cost O(rows × id width) on disk.
///
/// [rank] is EXCLUSIVE: `rank(i)` counts the set bits in `[0, i)`. That is the
/// quantity the index needs: "how many of my members come before global
/// position i".
class BitVector {
  BitVector._(this.length, this._words, this._blocks, this._count);

  /// Number of bits.
  final int length;

  /// Packed bits, LSB-first inside each 64-bit word. Bits at or beyond [length]
  /// are always zero.
  final Uint64List _words;

  /// `_blocks[b]` = popcount of every word before block `b` (block = 8 words =
  /// 512 bits), so [rank] is a table lookup plus a bounded tail popcount. Holds
  /// `numBlocks + 1` entries; the last one equals [count].
  final Uint32List _blocks;

  final int _count;

  static const int wordsPerBlock = 8;
  static const int bitsPerWord = 64;
  static const int bitsPerBlock = wordsPerBlock * bitsPerWord;

  /// Total number of set bits.
  int get count => _count;

  bool get isEmpty => _count == 0;
  bool get isNotEmpty => _count != 0;

  /// Whether bit [i] is set. [i] must be in `[0, length)`.
  bool operator [](int i) => (_words[i >> 6] & (1 << (i & 63))) != 0;

  /// Number of set bits in `[0, i)` (exclusive). Clamps out-of-range input, so
  /// `rank(0) == 0` and `rank(length) == count`.
  int rank(int i) {
    if (i <= 0) return 0;
    if (i >= length) return _count;
    final word = i >> 6;
    final block = word ~/ wordsPerBlock;
    var r = _blocks[block];
    for (var w = block * wordsPerBlock; w < word; w++) {
      r += _popcount(_words[w]);
    }
    final bit = i & 63;
    if (bit != 0) r += _popcount(_words[word] & ((1 << bit) - 1));
    return r;
  }

  /// Number of set bits in `[0, i]` (inclusive).
  int rankInclusive(int i) => rank(i + 1);

  /// Index of the (k+1)-th set bit (0-based [k]), or -1 when `k >= count`.
  int select(int k) {
    if (k < 0 || k >= _count) return -1;
    // Largest block whose cumulative prefix is <= k.
    var lo = 0;
    var hi = _blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_blocks[mid] <= k) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    var remaining = k - _blocks[lo];
    final start = lo * wordsPerBlock;
    final end = start + wordsPerBlock < _words.length
        ? start + wordsPerBlock
        : _words.length;
    for (var w = start; w < end; w++) {
      final pc = _popcount(_words[w]);
      if (remaining < pc) {
        return (w << 6) + _selectInWord(_words[w], remaining);
      }
      remaining -= pc;
    }
    return -1; // Unreachable: k < count guarantees a hit.
  }

  /// Smallest set index `>= from`, or -1 when there is none.
  int nextSetBit(int from) {
    if (from < 0) from = 0;
    if (from >= length) return -1;
    var w = from >> 6;
    var word = _words[w] & ~((1 << (from & 63)) - 1);
    while (true) {
      if (word != 0) {
        final idx = (w << 6) + _trailingZeros(word);
        return idx < length ? idx : -1;
      }
      if (++w >= _words.length) return -1;
      word = _words[w];
    }
  }

  /// Largest set index `<= from`, or -1 when there is none.
  int previousSetBit(int from) {
    if (from >= length) from = length - 1;
    if (from < 0) return -1;
    var w = from >> 6;
    final bit = from & 63;
    var word = _words[w] & (bit == 63 ? -1 : (1 << (bit + 1)) - 1);
    while (true) {
      if (word != 0) return (w << 6) + (63 - _leadingZeros(word));
      if (w == 0) return -1;
      word = _words[--w];
    }
  }

  /// Serializes the packed words (host endianness — every IRIS target is
  /// little-endian) for a BLOB column.
  Uint8List toBytes() => Uint8List.fromList(
      Uint8List.view(_words.buffer, _words.offsetInBytes, _words.lengthInBytes));

  /// Rebuilds a vector of [length] bits from [toBytes] output.
  factory BitVector.fromBytes(int length, Uint8List bytes) {
    final wordCount = (length + 63) >> 6;
    final padded = Uint8List(wordCount * 8)..setAll(0, bytes);
    final words = Uint64List.fromList(padded.buffer.asUint64List(0, wordCount));
    return BitVector._fromWords(length, words);
  }

  factory BitVector.fromBools(Iterable<bool> bits) {
    final list = bits is List<bool> ? bits : bits.toList(growable: false);
    final b = BitVectorBuilder(list.length);
    for (var i = 0; i < list.length; i++) {
      if (list[i]) b.set(i);
    }
    return b.build();
  }

  factory BitVector.fromSetBits(int length, Iterable<int> setBits) {
    final b = BitVectorBuilder(length);
    for (final i in setBits) {
      b.set(i);
    }
    return b.build();
  }

  /// All-zero vector of [length] bits.
  factory BitVector.empty(int length) => BitVectorBuilder(length).build();

  static BitVector _fromWords(int length, Uint64List words) {
    // Mask the trailing bits of the last word so the invariant holds.
    final rem = length & 63;
    if (rem != 0) words[words.length - 1] &= (1 << rem) - 1;
    var count = 0;
    for (final w in words) {
      count += _popcount(w);
    }
    final numBlocks = (words.length + wordsPerBlock - 1) ~/ wordsPerBlock;
    final blocks = Uint32List(numBlocks + 1);
    var acc = 0;
    for (var b = 0; b < numBlocks; b++) {
      blocks[b] = acc;
      final start = b * wordsPerBlock;
      final end = start + wordsPerBlock < words.length
          ? start + wordsPerBlock
          : words.length;
      for (var w = start; w < end; w++) {
        acc += _popcount(words[w]);
      }
    }
    blocks[numBlocks] = acc;
    return BitVector._(length, words, blocks, count);
  }

  @override
  String toString() => 'BitVector(length: $length, count: $_count)';
}

/// Mutable builder for [BitVector] — the efficient construction path when the
/// bits arrive from a scan (no intermediate `List<bool>`).
class BitVectorBuilder {
  BitVectorBuilder(this.length)
      : assert(length >= 0),
        _words = Uint64List((length + 63) >> 6);

  final int length;
  final Uint64List _words;

  /// Sets bit [i] (no-op if already set). [i] must be in `[0, length)`.
  void set(int i) => _words[i >> 6] |= 1 << (i & 63);

  /// Sets every index in [indices].
  void setAll(Iterable<int> indices) {
    for (final i in indices) {
      set(i);
    }
  }

  /// Clears bit [i].
  void clear(int i) => _words[i >> 6] &= ~(1 << (i & 63));

  BitVector build() => BitVector._fromWords(length, _words);
}

// ── Bit twiddling (64-bit two's-complement safe) ──

/// Population count of a 64-bit word.
int _popcount(int x) {
  x -= (x >> 1) & 0x5555555555555555;
  x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
  x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0f;
  return ((x * 0x0101010101010101) >> 56) & 0xff;
}

/// Index of the lowest set bit of [word] ([word] must be non-zero).
int _trailingZeros(int word) {
  var x = word;
  var n = 0;
  if (x & 0xffffffff == 0) {
    n += 32;
    x = x >>> 32;
  }
  if (x & 0xffff == 0) {
    n += 16;
    x = x >>> 16;
  }
  if (x & 0xff == 0) {
    n += 8;
    x = x >>> 8;
  }
  if (x & 0xf == 0) {
    n += 4;
    x = x >>> 4;
  }
  if (x & 0x3 == 0) {
    n += 2;
    x = x >>> 2;
  }
  if (x & 0x1 == 0) n += 1;
  return n;
}

/// Number of leading zero bits of [word] ([word] must be non-zero).
int _leadingZeros(int word) {
  var x = word;
  var n = 0;
  if (x >>> 32 == 0) {
    n += 32;
    x <<= 32;
  }
  if (x >>> 48 == 0) {
    n += 16;
    x <<= 16;
  }
  if (x >>> 56 == 0) {
    n += 8;
    x <<= 8;
  }
  if (x >>> 60 == 0) {
    n += 4;
    x <<= 4;
  }
  if (x >>> 62 == 0) {
    n += 2;
    x <<= 2;
  }
  if (x >>> 63 == 0) n += 1;
  return n;
}

/// Index of the ([k]+1)-th set bit inside [word].
int _selectInWord(int word, int k) {
  var x = word;
  var r = k;
  while (r > 0) {
    x &= x - 1; // Clear the lowest set bit.
    r--;
  }
  return _trailingZeros(x);
}
