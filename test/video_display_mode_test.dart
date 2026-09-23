import 'dart:ui';
import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/video_display_mode.dart';

/// Part A: per-platform video display modes (metadata-gate era).
///
/// - Desktop cycle adds the two original-size modes on top of the legacy
///   BoxFit trio; the mobile cycle keeps the legacy trio only (a phone has
///   no resizable window, so original-size semantics are meaningless there).
/// - The render resolver maps a display mode to the BoxFit the video
///   pipeline renders with, given the video's logical (DPI-scaled) size and
///   the viewport size.
void main() {
  group('desktop cycle', () {
    test('contain → fill → cover → adaptiveOriginal → forcedOriginal → contain',
        () {
      expect(
        nextDesktopVideoDisplayMode(DesktopVideoDisplayMode.contain),
        DesktopVideoDisplayMode.fill,
      );
      expect(
        nextDesktopVideoDisplayMode(DesktopVideoDisplayMode.fill),
        DesktopVideoDisplayMode.cover,
      );
      expect(
        nextDesktopVideoDisplayMode(DesktopVideoDisplayMode.cover),
        DesktopVideoDisplayMode.adaptiveOriginal,
      );
      expect(
        nextDesktopVideoDisplayMode(DesktopVideoDisplayMode.adaptiveOriginal),
        DesktopVideoDisplayMode.forcedOriginal,
      );
      expect(
        nextDesktopVideoDisplayMode(DesktopVideoDisplayMode.forcedOriginal),
        DesktopVideoDisplayMode.contain,
      );
    });
  });

  group('mobile cycle', () {
    test('contain → fill → cover → contain', () {
      expect(
        nextMobileVideoDisplayMode(MobileVideoDisplayMode.contain),
        MobileVideoDisplayMode.fill,
      );
      expect(
        nextMobileVideoDisplayMode(MobileVideoDisplayMode.fill),
        MobileVideoDisplayMode.cover,
      );
      expect(
        nextMobileVideoDisplayMode(MobileVideoDisplayMode.cover),
        MobileVideoDisplayMode.contain,
      );
    });
  });

  group('resolveDesktopDisplayBoxFit', () {
    const window16x9 = Size(1280, 720);
    final smallVideo = Size(640, 360);
    final bigVideo = Size(2560, 1440);

    test('contain / fill / cover pass through', () {
      expect(
        resolveDesktopDisplayBoxFit(
            mode: DesktopVideoDisplayMode.contain,
            videoLogicalSize: smallVideo,
            windowSize: window16x9),
        BoxFit.contain,
      );
      expect(
        resolveDesktopDisplayBoxFit(
            mode: DesktopVideoDisplayMode.fill,
            videoLogicalSize: smallVideo,
            windowSize: window16x9),
        BoxFit.fill,
      );
      expect(
        resolveDesktopDisplayBoxFit(
            mode: DesktopVideoDisplayMode.cover,
            videoLogicalSize: smallVideo,
            windowSize: window16x9),
        BoxFit.cover,
      );
    });

    test('adaptiveOriginal: smaller than window → original size (none)',
        () {
      expect(
        resolveDesktopDisplayBoxFit(
            mode: DesktopVideoDisplayMode.adaptiveOriginal,
            videoLogicalSize: smallVideo,
            windowSize: window16x9),
        BoxFit.none,
      );
    });

    test('adaptiveOriginal: larger than window → fit window (contain)', () {
      expect(
        resolveDesktopDisplayBoxFit(
            mode: DesktopVideoDisplayMode.adaptiveOriginal,
            videoLogicalSize: bigVideo,
            windowSize: window16x9),
        BoxFit.contain,
      );
    });

    test('forcedOriginal: always original size (none), truncation accepted',
        () {
      expect(
        resolveDesktopDisplayBoxFit(
            mode: DesktopVideoDisplayMode.forcedOriginal,
            videoLogicalSize: bigVideo,
            windowSize: window16x9),
        BoxFit.none,
      );
      expect(
        resolveDesktopDisplayBoxFit(
            mode: DesktopVideoDisplayMode.forcedOriginal,
            videoLogicalSize: smallVideo,
            windowSize: window16x9),
        BoxFit.none,
      );
    });

    test('unknown video dimensions degrade adaptiveOriginal to contain', () {
      expect(
        resolveDesktopDisplayBoxFit(
            mode: DesktopVideoDisplayMode.adaptiveOriginal,
            videoLogicalSize: Size.zero,
            windowSize: window16x9),
        BoxFit.contain,
      );
    });

    test('exact-size video renders original (no forced letterbox)', () {
      expect(
        resolveDesktopDisplayBoxFit(
            mode: DesktopVideoDisplayMode.adaptiveOriginal,
            videoLogicalSize: window16x9,
            windowSize: window16x9),
        BoxFit.none,
      );
    });
  });

  group('resolveMobileDisplayBoxFit', () {
    test('trio passes through; original-size modes unreachable', () {
      const window = Size(400, 800);
      expect(
        resolveMobileDisplayBoxFit(
            mode: MobileVideoDisplayMode.contain,
            videoLogicalSize: const Size(1920, 1080),
            windowSize: window),
        BoxFit.contain,
      );
      expect(
        resolveMobileDisplayBoxFit(
            mode: MobileVideoDisplayMode.fill,
            videoLogicalSize: const Size(1920, 1080),
            windowSize: window),
        BoxFit.fill,
      );
      expect(
        resolveMobileDisplayBoxFit(
            mode: MobileVideoDisplayMode.cover,
            videoLogicalSize: const Size(1920, 1080),
            windowSize: window),
        BoxFit.cover,
      );
    });
  });
}
