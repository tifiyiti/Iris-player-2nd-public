import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/playback/playback_progress.dart';

void main() {
  group('shouldFlushSuppressedCompletion', () {
    test('advances when released while still completed', () {
      expect(
        shouldFlushSuppressedCompletion(
          pendingCompleted: true,
          holding: false,
          completed: true,
        ),
        isTrue,
      );
    });

    test('drops the latch when a seek carried playback off the end', () {
      // Drag touched 100% (completed latched), then returned to 50% and
      // released: the seek reset `completed`, so the stale latch must not
      // advance to the next segment/file.
      expect(
        shouldFlushSuppressedCompletion(
          pendingCompleted: true,
          holding: false,
          completed: false,
        ),
        isFalse,
      );
    });

    test('does not flush while the drag is still held', () {
      expect(
        shouldFlushSuppressedCompletion(
          pendingCompleted: true,
          holding: true,
          completed: true,
        ),
        isFalse,
      );
    });

    test('does nothing without a pending completion', () {
      expect(
        shouldFlushSuppressedCompletion(
          pendingCompleted: false,
          holding: false,
          completed: true,
        ),
        isFalse,
      );
    });
  });
}
