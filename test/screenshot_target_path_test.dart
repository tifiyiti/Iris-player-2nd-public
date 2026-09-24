import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/playback_tools/services/screenshot_service.dart';
import 'package:path/path.dart' as p;

void main() {
  String join(String a, String b) => p.join(a, b);
  final now = DateTime(2026, 8, 25, 9, 7, 33);
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}'
      '_${two(now.hour)}${two(now.minute)}${two(now.second)}'
      '_${three(now.millisecond)}';

  group('resolveScreenshotTargetPath', () {
    test('custom dir wins; local stem kept, no beside-video write', () {
      final path = resolveScreenshotTargetPath(
        localVideoPath: join('movies', 'Big Buck Bunny.mp4'),
        customDirPath: join('custom', 'shots'),
        defaultDirPath: join('default', 'shots'),
        now: now,
      );
      expect(
        path,
        join(join('custom', 'shots'), 'Big Buck Bunny_$stamp.png'),
      );
    });

    test('blank custom dir falls back to the platform default', () {
      final path = resolveScreenshotTargetPath(
        localVideoPath: null,
        customDirPath: '  ',
        defaultDirPath: join('default', 'shots'),
        now: now,
      );
      expect(
        path,
        join(join('default', 'shots'), 'iris_$stamp.png'),
      );
    });

    test('local video no longer saves beside itself', () {
      final path = resolveScreenshotTargetPath(
        localVideoPath: join('movies', 'BBB.mp4'),
        customDirPath: '',
        defaultDirPath: join('default', 'shots'),
        now: now,
      );
      expect(
        path,
        join(join('default', 'shots'), 'BBB_$stamp.png'),
      );
    });

    test('name without extension keeps the full base', () {
      final path = resolveScreenshotTargetPath(
        localVideoPath: join('movies', 'rawfootage'),
        customDirPath: '',
        defaultDirPath: join('default', 'shots'),
        now: now,
      );
      expect(
        path,
        join(join('default', 'shots'), 'rawfootage_$stamp.png'),
      );
    });

    test('date + millisecond stamp prevents cross-day overwrite', () {
      final a = resolveScreenshotTargetPath(
        localVideoPath: join('movies', 'BBB.mp4'),
        customDirPath: '',
        defaultDirPath: join('default', 'shots'),
        now: DateTime(2026, 8, 25, 9, 7, 33, 1),
      );
      final b = resolveScreenshotTargetPath(
        localVideoPath: join('movies', 'BBB.mp4'),
        customDirPath: '',
        defaultDirPath: join('default', 'shots'),
        now: DateTime(2026, 8, 26, 9, 7, 33, 1),
      );
      expect(a, isNot(b));
    });
  });
}
