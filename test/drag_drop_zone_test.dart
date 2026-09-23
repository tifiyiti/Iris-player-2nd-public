import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/actions/drag_drop_play_handler.dart';

void main() {
  group('clampDropAppendPercent', () {
    test('missing value degrades to the 30% default', () {
      expect(clampDropAppendPercent(null), 30);
    });

    test('hard-clamps to 10–90 regardless of the configured value', () {
      expect(clampDropAppendPercent(5), 10);
      expect(clampDropAppendPercent(95), 90);
      expect(clampDropAppendPercent(45), 45);
    });
  });

  group('resolveDropZone', () {
    const height = 100.0;
    const percent = 30.0;

    test('above the split line appends (PotPlayer top strip)', () {
      expect(
        resolveDropZone(
            localY: 29, boxHeight: height, appendPercent: percent),
        DragDropZone.append,
      );
      expect(
        resolveDropZone(
            localY: 0, boxHeight: height, appendPercent: percent),
        DragDropZone.append,
      );
    });

    test('on/after the split line overrides and plays', () {
      expect(
        resolveDropZone(
            localY: 30, boxHeight: height, appendPercent: percent),
        DragDropZone.override,
      );
      expect(
        resolveDropZone(
            localY: 90, boxHeight: height, appendPercent: percent),
        DragDropZone.override,
      );
    });

    test('the configured split is clamped before comparing', () {
      // 5 → clamped to 10, so 9 still appends while 10 overrides.
      expect(
        resolveDropZone(localY: 9, boxHeight: height, appendPercent: 5),
        DragDropZone.append,
      );
      expect(
        resolveDropZone(localY: 10, boxHeight: height, appendPercent: 5),
        DragDropZone.override,
      );
      // 95 → clamped to 90.
      expect(
        resolveDropZone(localY: 89, boxHeight: height, appendPercent: 95),
        DragDropZone.append,
      );
      expect(
        resolveDropZone(localY: 90, boxHeight: height, appendPercent: 95),
        DragDropZone.override,
      );
    });

    test('unknown height degrades to override (play)', () {
      expect(
        resolveDropZone(localY: 0, boxHeight: 0, appendPercent: percent),
        DragDropZone.override,
      );
    });
  });
}
