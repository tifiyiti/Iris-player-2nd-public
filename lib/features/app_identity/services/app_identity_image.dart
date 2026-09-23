import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// Pure image helpers for app-identity icons.
///
/// All functions are side-effect free and operate on bytes so they are
/// unit-testable without filesystem or platform channels.
abstract final class AppIdentityImage {
  /// Target square size for pinned shortcuts.
  ///
  /// 192 px covers xhdpi launchers comfortably.
  static const int targetSize = 192;

  /// Decodes [bytes] with the pure-Dart codec and re-encodes as PNG.
  ///
  /// Returns null when the source cannot be decoded. Used as a display
  /// fallback when the engine codec rejects an exotic payload (e.g. from a
  /// third-party gallery).
  static Uint8List? decodeToPng(Uint8List bytes) {
    img.Image? src;
    try {
      src = img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
    if (src == null) return null;
    return Uint8List.fromList(img.encodePng(src));
  }

  /// Crops [bytes] by a normalized rectangle (all components 0..1, relative
  /// to the source image), then resizes the crop to [targetSize]×[targetSize]
  /// and re-encodes as PNG.
  ///
  /// The visible crop frame is a SQUARE, so the produced square is the
  /// largest centered square INSIDE [rect] (side = min(rect.width, rect.height)
  /// in normalized terms) — never a corner-anchored sub-rectangle. This keeps
  /// "what the user framed" == "what the icon shows" even when the frame
  /// covers more width than height (or vice versa). Returns null when the
  /// source cannot be decoded.
  static Uint8List? cropSquareFromBytes(
    Uint8List bytes, {
    required Rect rect,
    int size = targetSize,
  }) {
    img.Image? src;
    try {
      src = img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
    if (src == null) return null;

    final left = (rect.left.clamp(0.0, 1.0) * src.width).round().clamp(0, src.width);
    final top = (rect.top.clamp(0.0, 1.0) * src.height).round().clamp(0, src.height);
    final right = (rect.right.clamp(0.0, 1.0) * src.width).round().clamp(0, src.width);
    final bottom = (rect.bottom.clamp(0.0, 1.0) * src.height).round().clamp(0, src.height);
    // Degenerate (fully panned away) rect → center square fallback.
    if (right <= left || bottom <= top) {
      final cw = src.width;
      final ch = src.height;
      final side = cw < ch ? cw : ch;
      final cx = (cw - side) ~/ 2;
      final cy = (ch - side) ~/ 2;
      final cropped = img.copyCrop(src, x: cx, y: cy, width: side, height: side);
      return Uint8List.fromList(img.encodePng(
        img.copyResize(cropped, width: size, height: size, interpolation: img.Interpolation.cubic),
      ));
    }

    // Largest centered square INSIDE the framed rect.
    final w = right - left;
    final h = bottom - top;
    final side = w < h ? w : h;
    final cx = left + (w - side) ~/ 2;
    final cy = top + (h - side) ~/ 2;

    final cropped = img.copyCrop(src, x: cx, y: cy, width: side, height: side);
    final resized = img.copyResize(
      cropped,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(img.encodePng(resized));
  }
}
