import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/path_conv.dart';

void main() {
  group('canonicalProgressKey', () {
    test('unifies surface-dependent path forms to the same key', () {
      // Storage-browser FileItem: native uri (Windows backslashes) + rooted
      // segment path.
      final storageFile = FileItem(
        storageId: 'st1',
        name: 'a.mp4',
        uri: r'E:\Movies\a.mp4',
        path: ['E:', 'Movies', 'a.mp4'],
      );
      // Scenario-resolved media path: clean unrooted segments.
      final scenarioPath = ['E:', 'Movies', 'a.mp4'];

      expect(
        canonicalProgressKey(storageFile.storageId, storageFile.path),
        canonicalProgressKey('st1', scenarioPath),
      );
      expect(
        canonicalProgressKey(storageFile.storageId, storageFile.path),
        'st1:E:/Movies/a.mp4',
      );
    });

    test('strips Android rooted leading slash on both surfaces', () {
      // Storage-browser FileItem path is rooted on Android.
      final storageKey = canonicalProgressKey('st1',
          ['/storage/emulated/0', 'Movies', 'a.mp4']);
      // Media node path (pathConv output) is unrooted.
      final mediaKey = canonicalProgressKey(
          'st1', ['storage', 'emulated', '0', 'Movies', 'a.mp4']);
      expect(storageKey, mediaKey);
      expect(storageKey, 'st1:storage/emulated/0/Movies/a.mp4');
    });

    test('falls back to the uri when the segment path is empty', () {
      // SAF single-pick FileItems have no segment path.
      final a = canonicalProgressKey('', [], uri: 'content://picks/a');
      final b = canonicalProgressKey('', [], uri: 'content://picks/b');
      expect(a, isNot(b));
      expect(a, ':content:/picks/a');
      expect(b, ':content:/picks/b');
    });
  });

  group('canonicalDbPath', () {
    test('normalizes rooted and doubled-slash inputs', () {
      expect(canonicalDbPath('/storage/emulated/0/Movies'), 'storage/emulated/0/Movies');
      expect(canonicalDbPath('//storage/emulated/0/Movies'), 'storage/emulated/0/Movies');
      expect(canonicalDbPath(r'E:\Movies\a.mp4'), r'E:\Movies\a.mp4');
    });

    test('is idempotent', () {
      expect(
        canonicalDbPath(canonicalDbPath('/a//b/c')),
        canonicalDbPath('/a//b/c'),
      );
    });
  });
}
