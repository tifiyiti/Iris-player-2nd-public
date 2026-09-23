import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/pages/player/video_layout.dart';

void main() {
  test('invalid candidate keeps the last valid video size', () {
    const previous = Size(1280, 720);

    expect(
      retainValidVideoSize(const Size(0, 0), previous),
      previous,
    );
    expect(
      retainValidVideoSize(const Size(1920, 1080), previous),
      const Size(1920, 1080),
    );
  });

  test('invalid candidate without history returns null', () {
    expect(retainValidVideoSize(const Size(0, 0), null), isNull);
  });
}
