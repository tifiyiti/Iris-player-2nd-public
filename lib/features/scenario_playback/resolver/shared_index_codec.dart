import 'dart:convert';
import 'dart:typed_data';

import 'package:iris/features/scenario_playback/resolver/bit_vector.dart';
import 'package:iris/features/scenario_playback/resolver/shared_row_overlay.dart';

/// Binary codec for the shared-order derived index blobs.
///
/// These blobs are the bulk of the derived storage, so the format is compact
/// and explicit (varint lengths, little-endian int32, UTF-8 strings) rather than
/// JSON. Every blob starts with a version tag so a future format change is
/// detectable instead of silently mis-parsed.
class SharedIndexCodec {
  const SharedIndexCodec._();

  static const int version = 3;

  // ── Bitmaps ──

  /// `[version][length][packed words]` — the length is needed to rebuild the
  /// vector (the byte length alone cannot express a non-multiple of 64).
  static Uint8List encodeBitmap(BitVector bitmap) {
    final w = _Writer()
      ..varint(version)
      ..varint(bitmap.length)
      ..bytes(bitmap.toBytes());
    return w.done();
  }

  static BitVector decodeBitmap(Uint8List data) {
    final r = _Reader(data);
    _checkVersion(r.varint());
    final length = r.varint();
    return BitVector.fromBytes(length, r.bytes());
  }

  // ── Slices ──

  /// One shared-order slice: the order key, the media revision the order was
  /// built against, and its membership bitmap.
  ///
  /// The revision travels WITH the slice so the read side needs no revision
  /// plumbing: it reads the order at the revision the index was built with, and
  /// a newer revision makes the order look absent (the caller falls back).
  static Uint8List encodeSlices(
      List<({String orderKey, int mediaRev, BitVector bits})> slices) {
    final w = _Writer()
      ..varint(version)
      ..varint(slices.length);
    for (final s in slices) {
      w.string(s.orderKey);
      w.varint(s.mediaRev);
      w.bytes(encodeBitmap(s.bits));
    }
    return w.done();
  }

  static List<({String orderKey, int mediaRev, BitVector bits})> decodeSlices(
      Uint8List data) {
    final r = _Reader(data);
    _checkVersion(r.varint());
    final n = r.varint();
    return [
      for (var i = 0; i < n; i++)
        (
          orderKey: r.string(),
          mediaRev: r.varint(),
          bits: decodeBitmap(r.bytes()),
        ),
    ];
  }

  // ── Group rows ──

  /// Encodes group rows with the `(ruleId, rootPath)` prefix INTERNED once per
  /// blob. A group row then costs an anchor + a dictionary index + a chunk
  /// number + its members, instead of repeating the 36-char rule id per group.
  static Uint8List encodeGroups(List<SharedGroupRow> groups) {
    final keyIndex = <String, int>{};
    final keys = <({String ruleId, String rootPath})>[];
    for (final g in groups) {
      final key = '${g.ruleId}\u0000${g.rootPath}';
      if (!keyIndex.containsKey(key)) {
        keyIndex[key] = keys.length;
        keys.add((ruleId: g.ruleId, rootPath: g.rootPath));
      }
    }

    final w = _Writer()
      ..varint(version)
      ..varint(keys.length);
    for (final k in keys) {
      w.string(k.ruleId);
      w.string(k.rootPath);
    }
    w.varint(groups.length);
    for (final g in groups) {
      w.varint(g.anchorRank);
      w.varint(keyIndex['${g.ruleId}\u0000${g.rootPath}']!);
      w.varint(g.chunkNo);
      // The VM item's own total, not a sum of the members below (see
      // `SharedGroupRow.totalDurationMs`).
      w.varint(g.totalDurationMs);
      w.varint(g.members.length);
      for (final id in g.members) {
        w.int32(id);
      }
      w.varint(g.memberOccurrence.length);
      g.memberOccurrence.forEach((position, occurrence) {
        w.varint(position);
        w.varint(occurrence);
      });
    }
    return w.done();
  }

  static List<SharedGroupRow> decodeGroups(Uint8List data) {
    final r = _Reader(data);
    _checkVersion(r.varint());
    final keyCount = r.varint();
    final keys = [
      for (var i = 0; i < keyCount; i++)
        (ruleId: r.string(), rootPath: r.string()),
    ];
    final n = r.varint();
    final out = <SharedGroupRow>[];
    for (var i = 0; i < n; i++) {
      final anchor = r.varint();
      final key = keys[r.varint()];
      final chunkNo = r.varint();
      final totalDurationMs = r.varint();
      final memberCount = r.varint();
      final members = Int32List(memberCount);
      for (var m = 0; m < memberCount; m++) {
        members[m] = r.int32();
      }
      final occCount = r.varint();
      final occurrence = <int, int>{};
      for (var o = 0; o < occCount; o++) {
        occurrence[r.varint()] = r.varint();
      }
      out.add(SharedGroupRow(
        anchorRank: anchor,
        ruleId: key.ruleId,
        rootPath: key.rootPath,
        chunkNo: chunkNo,
        members: members,
        memberOccurrence: occurrence,
        totalDurationMs: totalDurationMs,
      ));
    }
    return out;
  }

  // ── Sparse int maps (file occurrence, raw flags) ──

  static Uint8List encodeIntMap(Map<int, int> values) {
    final w = _Writer()
      ..varint(version)
      ..varint(values.length);
    final keys = values.keys.toList()..sort();
    for (final k in keys) {
      w.varint(k);
      w.varint(values[k]!);
    }
    return w.done();
  }

  static Map<int, int> decodeIntMap(Uint8List data) {
    final r = _Reader(data);
    _checkVersion(r.varint());
    final n = r.varint();
    return {for (var i = 0; i < n; i++) r.varint(): r.varint()};
  }

  // ── Placeholders ──

  static Uint8List encodePlaceholders(
      Map<int, ({String storageId, String path})> values) {
    final w = _Writer()
      ..varint(version)
      ..varint(values.length);
    final keys = values.keys.toList()..sort();
    for (final k in keys) {
      w.varint(k);
      w.string(values[k]!.storageId);
      w.string(values[k]!.path);
    }
    return w.done();
  }

  static Map<int, ({String storageId, String path})> decodePlaceholders(
      Uint8List data) {
    final r = _Reader(data);
    _checkVersion(r.varint());
    final n = r.varint();
    return {
      for (var i = 0; i < n; i++)
        r.varint(): (storageId: r.string(), path: r.string()),
    };
  }

  static void _checkVersion(int found) {
    if (found != version) {
      throw FormatException(
          'unsupported shared-index blob version $found (expected $version)');
    }
  }
}

/// LEB128 + length-prefixed bytes writer.
class _Writer {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void varint(int value) {
    assert(value >= 0, 'varint requires a non-negative value (got $value)');
    var v = value;
    while (v >= 0x80) {
      _bytes.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _bytes.addByte(v);
  }

  void int32(int value) {
    final b = ByteData(4)..setInt32(0, value, Endian.little);
    _bytes.add(b.buffer.asUint8List());
  }

  void bytes(Uint8List value) {
    varint(value.length);
    _bytes.add(value);
  }

  void string(String value) => bytes(utf8.encode(value));

  Uint8List done() => _bytes.toBytes();
}

/// Matching reader.
class _Reader {
  _Reader(this._data);

  final Uint8List _data;
  int _pos = 0;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = _data[_pos++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  int int32() {
    final value = ByteData.sublistView(_data, _pos, _pos + 4)
        .getInt32(0, Endian.little);
    _pos += 4;
    return value;
  }

  Uint8List bytes() {
    final length = varint();
    final out = Uint8List.sublistView(_data, _pos, _pos + length);
    _pos += length;
    return out;
  }

  String string() => utf8.decode(bytes());
}
