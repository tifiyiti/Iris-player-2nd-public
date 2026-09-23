import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/drag_window_lock.dart';

void main() {
  group('shouldSkipResizeDuringDrag', () {
    test('idle does not skip', () {
      expect(
        shouldSkipResizeDuringDrag(isScrubbing: false, isHolding: false),
        isFalse,
      );
    });

    test('scrubbing skips unconditionally', () {
      expect(
        shouldSkipResizeDuringDrag(isScrubbing: true, isHolding: false),
        isTrue,
      );
    });

    test('holding skips unconditionally', () {
      expect(
        shouldSkipResizeDuringDrag(isScrubbing: false, isHolding: true),
        isTrue,
      );
    });

    test('both flags skip', () {
      expect(
        shouldSkipResizeDuringDrag(isScrubbing: true, isHolding: true),
        isTrue,
      );
    });
  });

  group('resolveDraggingBoxFit', () {
    test('idle keeps effective fit', () {
      expect(
        resolveDraggingBoxFit(BoxFit.none, isDragging: false),
        BoxFit.none,
      );
      expect(
        resolveDraggingBoxFit(BoxFit.contain, isDragging: false),
        BoxFit.contain,
      );
    });

    test('dragging degrades none to contain (video adapts window)', () {
      expect(
        resolveDraggingBoxFit(BoxFit.none, isDragging: true),
        BoxFit.contain,
      );
    });

    test('dragging keeps non-none fit', () {
      expect(
        resolveDraggingBoxFit(BoxFit.cover, isDragging: true),
        BoxFit.cover,
      );
      expect(
        resolveDraggingBoxFit(BoxFit.contain, isDragging: true),
        BoxFit.contain,
      );
    });
  });
}
