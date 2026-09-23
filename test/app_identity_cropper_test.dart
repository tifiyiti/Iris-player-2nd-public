import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:iris/features/app_identity/services/app_identity_image.dart';
import 'package:iris/features/app_identity/view/entry_image_cropper.dart';

Uint8List _makePng(int w, int h, {int r = 200, int g = 100, int b = 50}) {
  final image = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('visibleCropRect', () {
    test('identity transform on square frame == full image', () {
      // Frame 300×300, image 300×300 → frame shows the whole image.
      final rect = visibleCropRect(
        transform: Matrix4.identity(),
        frameSize: 300,
        imageWidth: 300,
        imageHeight: 300,
      );
      expect(rect.left, closeTo(0, 1e-9));
      expect(rect.top, closeTo(0, 1e-9));
      expect(rect.right, closeTo(1, 1e-9));
      expect(rect.bottom, closeTo(1, 1e-9));
    });

    test('tall image under identity shows its top portion', () {
      // Frame 300×300, image 300×600 → frame shows image y 0..300 of 600,
      // i.e. normalized y 0..0.5, full width.
      final rect = visibleCropRect(
        transform: Matrix4.identity(),
        frameSize: 300,
        imageWidth: 300,
        imageHeight: 600,
      );
      expect(rect.left, closeTo(0, 1e-9));
      expect(rect.right, closeTo(1, 1e-9));
      expect(rect.top, closeTo(0, 1e-9));
      expect(rect.bottom, closeTo(0.5, 1e-9));
    });

    test('zoom-in keeps the visible center region', () {
      // Frame 300×300, square image 300×300, scale 2 about center → shows the
      // middle half of the image.
      final m = Matrix4.identity();
      final c = 150.0;
      m.translateByDouble(c, c, 0, 1);
      m.scaleByDouble(2, 2, 2, 1);
      m.translateByDouble(-c, -c, 0, 1);
      final rect = visibleCropRect(
        transform: m,
        frameSize: 300,
        imageWidth: 300,
        imageHeight: 300,
      );
      expect(rect.left, closeTo(0.25, 1e-9));
      expect(rect.right, closeTo(0.75, 1e-9));
      expect(rect.top, closeTo(0.25, 1e-9));
      expect(rect.bottom, closeTo(0.75, 1e-9));
    });

    test('pan shifts the crop window', () {
      // Frame 300×300, square image 300×300, scale 2 about center, then
      // translate by -75 viewport px. Derivation: viewport = 2·child - 300,
      // so frame [0,300] shows child [150,300] = image [0.5, 1.0].
      final m = Matrix4.identity();
      final c = 150.0;
      m.translateByDouble(c, c, 0, 1);
      m.scaleByDouble(2, 2, 2, 1);
      m.translateByDouble(-c, -c, 0, 1);
      m.translateByDouble(-75, 0, 0, 1);
      final rect = visibleCropRect(
        transform: m,
        frameSize: 300,
        imageWidth: 300,
        imageHeight: 300,
      );
      expect(rect.left, closeTo(0.5, 1e-9));
      expect(rect.right, closeTo(1.0, 1e-9));
    });

    test('degenerate fully-panned-away falls back to center square', () {
      // Frame 300×300, tiny image far off-screen → normalized rect must
      // still be a valid non-empty square.
      final m = Matrix4.identity()
        ..translateByDouble(1000, 1000, 0, 1);
      final rect = visibleCropRect(
        transform: m,
        frameSize: 300,
        imageWidth: 300,
        imageHeight: 300,
      );
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(1));
    });
  });

  group('AppIdentityImage.cropSquareFromBytes', () {
    test('crops a full-image rect to target square', () {
      final src = _makePng(400, 400);
      final out = AppIdentityImage.cropSquareFromBytes(
        src,
        rect: ui.Rect.fromLTRB(0, 0, 1, 1),
      );
      expect(out, isNotNull);
      final decoded = img.decodePng(out!);
      expect(decoded!.width, AppIdentityImage.targetSize);
      expect(decoded.height, AppIdentityImage.targetSize);
    });

    test('crops a sub-rect and preserves its aspect', () {
      // Left half of a 400×200 image → square crop of that region is
      // 200×200 (source left half), resized to target.
      final src = _makePng(400, 200);
      final out = AppIdentityImage.cropSquareFromBytes(
        src,
        rect: ui.Rect.fromLTRB(0, 0, 0.5, 1),
      );
      expect(out, isNotNull);
      final decoded = img.decodePng(out!);
      expect(decoded!.width, AppIdentityImage.targetSize);
      expect(decoded.height, AppIdentityImage.targetSize);
    });

    test('wide rect crops the CENTERED square, not the corner', () {
      // 400×200 source split LEFT=red / RIGHT=blue. Frame rect covers the
      // full width (0..1) and middle half of the height (0.25..0.75). The
      // crop square must be the CENTERED 200×200 block (x 100..300, y
      // 50..150), so the output shows red on its left and blue on its
      // right. A corner-anchored crop (x 0..200) would be ALL red.
      final probeImg = img.Image(width: 400, height: 200);
      for (int y = 0; y < 200; y++) {
        for (int x = 0; x < 400; x++) {
          if (x < 200) {
            probeImg.setPixelRgba(x, y, 255, 0, 0, 255); // left red
          } else {
            probeImg.setPixelRgba(x, y, 0, 0, 255, 255); // right blue
          }
        }
      }
      final out = AppIdentityImage.cropSquareFromBytes(
        Uint8List.fromList(img.encodePng(probeImg)),
        rect: ui.Rect.fromLTRB(0, 0.25, 1, 0.75),
      );
      expect(out, isNotNull);
      final decoded = img.decodePng(out!);
      expect(decoded!.width, AppIdentityImage.targetSize);
      expect(decoded.height, AppIdentityImage.targetSize);

      // Left quarter of the output sits at source x=100 → red.
      final left = decoded.getPixel(decoded.width ~/ 4, decoded.height ~/ 2);
      expect(left.r.toInt(), greaterThan(200));
      expect(left.b.toInt(), lessThan(60));
      // Right quarter sits at source x=300 → blue.
      final right =
          decoded.getPixel(decoded.width * 3 ~/ 4, decoded.height ~/ 2);
      expect(right.b.toInt(), greaterThan(200));
      expect(right.r.toInt(), lessThan(60));
    });

    test('clamps out-of-range rect into bounds', () {
      final src = _makePng(100, 100);
      final out = AppIdentityImage.cropSquareFromBytes(
        src,
        rect: ui.Rect.fromLTRB(-0.5, -0.5, 1.5, 1.5),
      );
      expect(out, isNotNull);
      final decoded = img.decodePng(out!);
      expect(decoded!.width, AppIdentityImage.targetSize);
      expect(decoded.height, AppIdentityImage.targetSize);
    });

    test('returns null for undecodable bytes', () {
      final out = AppIdentityImage.cropSquareFromBytes(
        Uint8List.fromList([0, 1, 2, 3]),
        rect: ui.Rect.fromLTRB(0, 0, 1, 1),
      );
      expect(out, isNull);
    });
  });
}
