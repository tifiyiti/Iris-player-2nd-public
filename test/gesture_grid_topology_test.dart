import 'package:flutter/cupertino.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/gesture/gesture_layouts_default.dart';
import 'package:iris/models/store/gesture/gesture_region_layout.dart';
import 'package:iris/models/store/gesture_region.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_editor_models.dart';

/// Requirement #3: every gesture layout MUST be a strict n×m grid — regions
/// are exactly the cells carved by the interior split lines (no straddling
/// rects, no overlap). The old default doubleTap violated this (the tag strip
/// halves straddled the x=0.25/0.75 lines), which corrupted every editor /
/// guide edit round-trip.
void main() {
  group('grid invariant over all default profiles', () {
    test('every default profile layout is a strict grid', () {
      final violations = <String>[];
      defaultGestureLayoutProfiles.forEach((profileKey, layouts) {
        layouts.forEach((intent, layout) {
          if (!isGridConformantLayout(layout)) {
            violations.add('$profileKey/${intent.name}');
          }
        });
      });
      expect(violations, isEmpty, reason: 'non-grid layouts: $violations');
    });

    test('default doubleTap is the 3×3 spec (2 vertical × 2 horizontal)',
        () {
      final layout = defaultGestureLayouts[GestureIntent.doubleTap]!;
      final lines = LayoutTopology.computeEditableLines(layout);
      final vertical =
          lines.where((l) => l.axis == LineAxis.vertical).toList();
      final horizontal =
          lines.where((l) => l.axis == LineAxis.horizontal).toList();
      expect(vertical.map((l) => l.value), unorderedEquals(<double>[0.33, 0.67]));
      expect(horizontal.map((l) => l.value), unorderedEquals(<double>[0.20, 0.80]));
      // (n+1)×(m+1) cells, all nine present.
      expect(layout.regions, hasLength(9));
    });

    test('default doubleTap keeps legacy semantics per cell', () {
      final layout = defaultGestureLayouts[GestureIntent.doubleTap]!;
      String actionAt(double x, double y) {
        final region = layout.regions.firstWhere(
          (r) => r.normalizedRect.contains(Offset(x, y)),
        );
        return region.action.type.name;
      }

      // Top row: seekB | playPause | seekF.
      expect(actionAt(0.1, 0.1), 'seekBackward');
      expect(actionAt(0.5, 0.1), 'playPause');
      expect(actionAt(0.9, 0.1), 'seekForward');
      // Middle row: seekB | playPause | seekF.
      expect(actionAt(0.1, 0.5), 'seekBackward');
      expect(actionAt(0.5, 0.5), 'playPause');
      expect(actionAt(0.9, 0.5), 'seekForward');
      // Bottom row: seekB | openTags | seekF.
      expect(actionAt(0.1, 0.9), 'seekBackward');
      expect(actionAt(0.5, 0.9), 'openTagPlaySheet');
      expect(actionAt(0.9, 0.9), 'seekForward');
    });
  });

  group('dropNonGridLayouts (stored-profile cleanup)', () {
    test('non-grid stored layout falls back to the default grid', () {
      final legacySixCell = GestureLayout(
        intent: GestureIntent.doubleTap,
        regions: const [
          GestureRegion(
            normalizedRect: Rect.fromLTWH(0, 0, 0.5, 0.15),
            action: GestureAction(type: GestureActionType.openTagPlaySheet),
          ),
          GestureRegion(
            normalizedRect: Rect.fromLTWH(0, 0.15, 0.25, 0.85),
            action: GestureAction(type: GestureActionType.seekBackward),
          ),
          GestureRegion(
            normalizedRect: Rect.fromLTWH(0.25, 0.15, 0.5, 0.55),
            action: GestureAction(type: GestureActionType.playPause),
          ),
          GestureRegion(
            normalizedRect: Rect.fromLTWH(0.25, 0.70, 0.5, 0.30),
            action: GestureAction(type: GestureActionType.openTagPlaySheet),
          ),
        ],
      );
      final profiles = <String, Map<GestureIntent, GestureLayout>>{
        kLayoutRegion: {GestureIntent.doubleTap: legacySixCell},
      };

      final cleaned = dropNonGridLayouts(
        profiles: profiles,
        defaults: defaultGestureLayoutProfiles,
      );

      expect(
        cleaned[kLayoutRegion]![GestureIntent.doubleTap],
        same(defaultGestureLayouts[GestureIntent.doubleTap]),
      );
    });

    test('conformant stored layout survives untouched', () {
      final stored = defaultGestureLayouts[GestureIntent.panVertical]!;
      final profiles = <String, Map<GestureIntent, GestureLayout>>{
        kLayoutRegion: {GestureIntent.panVertical: stored},
      };

      final cleaned = dropNonGridLayouts(
        profiles: profiles,
        defaults: defaultGestureLayoutProfiles,
      );

      expect(cleaned[kLayoutRegion]![GestureIntent.panVertical], same(stored));
    });
  });

  group('migrateEmptyLongPressPanVertical (legacy empty vertical pan)', () {
    test('empty stored vertical pan fills from defaults', () {
      final stored = <GestureIntent, GestureLayout>{
        GestureIntent.longPressPanVertical: layout(
          GestureIntent.longPressPanVertical,
          const [],
        ),
      };
      final out = migrateEmptyLongPressPanVertical(
        stored,
        defaultGestureLayouts,
      );
      expect(
        out[GestureIntent.longPressPanVertical],
        same(defaultGestureLayouts[GestureIntent.longPressPanVertical]),
      );
    });

    test('non-empty stored vertical pan survives untouched', () {
      final stored = <GestureIntent, GestureLayout>{
        GestureIntent.longPressPanVertical:
            defaultGestureLayouts[GestureIntent.panVertical]!,
      };
      final out = migrateEmptyLongPressPanVertical(
        stored,
        defaultGestureLayouts,
      );
      expect(
        out[GestureIntent.longPressPanVertical],
        same(defaultGestureLayouts[GestureIntent.panVertical]),
      );
    });
  });
}
