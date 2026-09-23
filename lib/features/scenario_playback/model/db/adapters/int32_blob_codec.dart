import 'dart:typed_data';

/// Packs an int32 sequence into a little-endian BLOB (and back).
///
/// Explicit little-endian so the blob is portable and stable across the (all
/// little-endian) IRIS targets, independent of host `TypedData` endianness.
class Int32BlobCodec {
  const Int32BlobCodec._();

  static Uint8List encode(Int32List values) {
    final out = Uint8List(values.length * 4);
    final view = ByteData.view(out.buffer);
    for (var i = 0; i < values.length; i++) {
      view.setInt32(i * 4, values[i], Endian.little);
    }
    return out;
  }

  static Int32List decode(Uint8List bytes) {
    final n = bytes.length ~/ 4;
    final out = Int32List(n);
    final view =
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    for (var i = 0; i < n; i++) {
      out[i] = view.getInt32(i * 4, Endian.little);
    }
    return out;
  }
}
