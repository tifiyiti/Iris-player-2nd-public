import 'package:flutter/cupertino.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/gesture/gesture_layouts_left.dart';
import 'package:iris/models/store/gesture/gesture_layouts_right.dart';
import 'package:iris/models/store/gesture_region.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_editor_models.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_settings_entry.dart';

String _actionAt(
  Map<GestureIntent, GestureLayout> layouts,
  GestureIntent intent,
  double x,
  double y,
) {
  final layout = layouts[intent]!;
  final region = layout.regions.firstWhere(
    (r) => r.normalizedRect.contains(Offset(x, y)),
  );
  return region.action.type.name;
}

void main() {
  group('side tap restores 6-grid with none zones', () {
    test('leftSide tap: upper-left two cells none, rest toggle', () {
      final layout = leftSideGestureLayouts[GestureIntent.tap]!;
      expect(layout.regions, hasLength(6));
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.tap, 0.25, 0.1), 'none');
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.tap, 0.25, 0.5), 'none');
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.tap, 0.25, 0.85), 'toggleControls');
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.tap, 0.75, 0.1), 'toggleControls');
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.tap, 0.75, 0.5), 'toggleControls');
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.tap, 0.75, 0.85), 'toggleControls');
    });

    test('rightSide tap: mirrored — upper-right two cells none', () {
      final layout = rightSideGestureLayouts[GestureIntent.tap]!;
      expect(layout.regions, hasLength(6));
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.tap, 0.75, 0.1), 'none');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.tap, 0.75, 0.5), 'none');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.tap, 0.75, 0.85), 'toggleControls');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.tap, 0.25, 0.1), 'toggleControls');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.tap, 0.25, 0.5), 'toggleControls');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.tap, 0.25, 0.85), 'toggleControls');
    });

    test('tap allows none again', () {
      expect(
        getAllowedActions(GestureIntent.tap),
        contains(GestureActionType.none),
      );
    });
  });

  group('side tap bands are 25 / 30 / 45', () {
    test('bottom toggle band starts at 0.55 (was 0.70)', () {
      // Holding-side upper cells stay dead zones; the bottom 45% toggles.
      expect(
          _actionAt(leftSideGestureLayouts, GestureIntent.tap, 0.25, 0.6),
          'toggleControls');
      expect(
          _actionAt(rightSideGestureLayouts, GestureIntent.tap, 0.75, 0.6),
          'toggleControls');
      // Mid band (0.25–0.55) on the holding side is still a dead zone.
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.tap, 0.25, 0.3),
          'none');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.tap, 0.75, 0.3),
          'none');
    });

    test('band rects are 25 / 30 / 45', () {
      Rect rectAt(Map<GestureIntent, GestureLayout> layouts, double x, double y) =>
          layouts[GestureIntent.tap]!
              .regions
              .firstWhere((r) => r.normalizedRect.contains(Offset(x, y)))
              .normalizedRect;

      expect(rectAt(leftSideGestureLayouts, 0.25, 0.1),
          const Rect.fromLTWH(0.0, 0.00, 0.5, 0.25));
      expect(rectAt(leftSideGestureLayouts, 0.25, 0.4),
          const Rect.fromLTWH(0.0, 0.25, 0.5, 0.30));
      expect(rectAt(leftSideGestureLayouts, 0.25, 0.8),
          const Rect.fromLTWH(0.0, 0.55, 0.5, 0.45));
    });
  });

  group('side doubleTap restores top tag strip', () {
    test('leftSide doubleTap: 8 cells, top two open tags', () {
      final layout = leftSideGestureLayouts[GestureIntent.doubleTap]!;
      expect(layout.regions, hasLength(8));
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.doubleTap, 0.25, 0.05), 'openTagPlaySheet');
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.doubleTap, 0.75, 0.05), 'openTagPlaySheet');
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.doubleTap, 0.25, 0.3), 'seekForward');
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.doubleTap, 0.25, 0.6), 'seekBackward');
      expect(_actionAt(leftSideGestureLayouts, GestureIntent.doubleTap, 0.25, 0.9), 'playPause');
    });

    test('rightSide doubleTap: 8 cells, top two open tags', () {
      final layout = rightSideGestureLayouts[GestureIntent.doubleTap]!;
      expect(layout.regions, hasLength(8));
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.doubleTap, 0.25, 0.05), 'openTagPlaySheet');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.doubleTap, 0.75, 0.05), 'openTagPlaySheet');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.doubleTap, 0.75, 0.3), 'seekForward');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.doubleTap, 0.75, 0.6), 'seekBackward');
      expect(_actionAt(rightSideGestureLayouts, GestureIntent.doubleTap, 0.75, 0.9), 'playPause');
    });
  });

  group('tapLayoutHasToggle', () {
    test('all-none tap fails', () {
      final layout = GestureLayout(
        intent: GestureIntent.tap,
        regions: const [
          GestureRegion(
            normalizedRect: Rect.fromLTWH(0, 0, 0.5, 1),
            action: GestureAction(type: GestureActionType.none),
          ),
          GestureRegion(
            normalizedRect: Rect.fromLTWH(0.5, 0, 0.5, 1),
            action: GestureAction(type: GestureActionType.none),
          ),
        ],
      );
      expect(tapLayoutHasToggle(layout), isFalse);
    });

    test('single toggle passes', () {
      final layout = GestureLayout(
        intent: GestureIntent.tap,
        regions: const [
          GestureRegion(
            normalizedRect: Rect.fromLTWH(0, 0, 0.5, 1),
            action: GestureAction(type: GestureActionType.none),
          ),
          GestureRegion(
            normalizedRect: Rect.fromLTWH(0.5, 0, 0.5, 1),
            action: GestureAction(type: GestureActionType.toggleControls),
          ),
        ],
      );
      expect(tapLayoutHasToggle(layout), isTrue);
    });

    test('restored side tap layouts pass', () {
      expect(tapLayoutHasToggle(leftSideGestureLayouts[GestureIntent.tap]!), isTrue);
      expect(tapLayoutHasToggle(rightSideGestureLayouts[GestureIntent.tap]!), isTrue);
    });
  });

  group('restored side layouts stay grid-conformant', () {
    test('side tap and doubleTap pass the grid invariant', () {
      expect(isGridConformantLayout(leftSideGestureLayouts[GestureIntent.tap]!), isTrue);
      expect(isGridConformantLayout(leftSideGestureLayouts[GestureIntent.doubleTap]!), isTrue);
      expect(isGridConformantLayout(rightSideGestureLayouts[GestureIntent.tap]!), isTrue);
      expect(isGridConformantLayout(rightSideGestureLayouts[GestureIntent.doubleTap]!), isTrue);
    });
  });

  group('resolveTapHit three-state hit test', () {
    test('leftSide tap dead zone (upper-left cells) resolves to none', () {
      // kLeftTop25 covers (0..0.5, 0..0.25); kLeftMid30 covers (0..0.5, 0.25..0.55).
      expect(resolveTapHit(leftSideGestureLayouts[GestureIntent.tap], const Offset(0.25, 0.1)),
          TapHitKind.none);
      expect(resolveTapHit(leftSideGestureLayouts[GestureIntent.tap], const Offset(0.25, 0.5)),
          TapHitKind.none);
    });

    test('rightSide tap dead zone (upper-right cells) resolves to none', () {
      expect(resolveTapHit(rightSideGestureLayouts[GestureIntent.tap], const Offset(0.75, 0.1)),
          TapHitKind.none);
      expect(resolveTapHit(rightSideGestureLayouts[GestureIntent.tap], const Offset(0.75, 0.5)),
          TapHitKind.none);
    });

    test('a toggle cell resolves to action', () {
      expect(resolveTapHit(leftSideGestureLayouts[GestureIntent.tap], const Offset(0.75, 0.1)),
          TapHitKind.action);
      expect(resolveTapHit(rightSideGestureLayouts[GestureIntent.tap], const Offset(0.25, 0.1)),
          TapHitKind.action);
      // Bottom half on either side is also toggle.
      expect(resolveTapHit(leftSideGestureLayouts[GestureIntent.tap], const Offset(0.25, 0.9)),
          TapHitKind.action);
    });

    test('a point outside every region resolves to outside (fallback kept)', () {
      // Any interior point is covered by a full 2x3 grid, so craft a gappy layout.
      const gappy = GestureLayout(
        intent: GestureIntent.tap,
        regions: [
          GestureRegion(
            normalizedRect: Rect.fromLTWH(0, 0, 0.5, 0.5),
            action: GestureAction(type: GestureActionType.toggleControls),
          ),
        ],
      );
      expect(resolveTapHit(gappy, const Offset(0.9, 0.9)), TapHitKind.outside);
    });

    test('a missing layout resolves to outside', () {
      expect(resolveTapHit(null, const Offset(0.5, 0.5)), TapHitKind.outside);
    });
  });
}
