import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/storage_path_codec.dart';

/// `StoragePathCodec` maps between the absolute domain path and the storage-
/// relative DB path. Both directions must be idempotent so a path already in
/// the target form is never double-stripped or double-prepended.
void main() {
  tearDown(() => StoragePathCodec.baseResolver = (_) => null);

  group('with a Windows base', () {
    setUp(() {
      StoragePathCodec.baseResolver = (id) => id == 'sid' ? const ['D:'] : null;
    });

    test('relativize strips the base', () {
      expect(StoragePathCodec.relativize('sid', 'D:/Movies/a.mp4'),
          'Movies/a.mp4');
    });

    test('relativize maps the root to empty', () {
      expect(StoragePathCodec.relativize('sid', 'D:'), '');
    });

    test('relativize is idempotent on a relative path', () {
      expect(StoragePathCodec.relativize('sid', 'Movies/a.mp4'),
          'Movies/a.mp4');
      expect(StoragePathCodec.relativize('sid', ''), '');
    });

    test('absolutize prepends the base', () {
      expect(StoragePathCodec.absolutize('sid', 'Movies/a.mp4'),
          'D:/Movies/a.mp4');
      expect(StoragePathCodec.absolutize('sid', ''), 'D:');
    });

    test('absolutize is idempotent on an absolute path', () {
      expect(StoragePathCodec.absolutize('sid', 'D:/Movies/a.mp4'),
          'D:/Movies/a.mp4');
    });

    test('unknown storage is a no-op', () {
      expect(StoragePathCodec.relativize('other', 'D:/Movies/a.mp4'),
          'D:/Movies/a.mp4');
      expect(StoragePathCodec.absolutize('other', 'Movies/a.mp4'),
          'Movies/a.mp4');
    });
  });

  group('with an Android base', () {
    setUp(() {
      StoragePathCodec.baseResolver =
          (id) => id == 'a' ? const ['/storage/emulated/0'] : null;
    });

    test('round-trips a nested path', () {
      expect(
        StoragePathCodec.relativize('a', 'storage/emulated/0/Movies/a.mp4'),
        'Movies/a.mp4',
      );
      expect(
        StoragePathCodec.absolutize('a', 'Movies/a.mp4'),
        'storage/emulated/0/Movies/a.mp4',
      );
    });
  });

  test('a remote root base (/ ) disables conversion', () {
    StoragePathCodec.baseResolver = (id) => const ['/'];
    expect(StoragePathCodec.relativize('w', 'Movies/a.mp4'), 'Movies/a.mp4');
    expect(StoragePathCodec.absolutize('w', 'Movies/a.mp4'), 'Movies/a.mp4');
  });

  test('a SAF tree base disables conversion (stays absolute)', () {
    const tree = 'content://com.android.externalstorage.documents/tree/primary%3AMovies';
    StoragePathCodec.baseResolver = (id) => const [tree];
    final absolute = '$tree/a.mp4';
    expect(StoragePathCodec.relativize('saf', absolute), absolute);
    expect(StoragePathCodec.absolutize('saf', 'a.mp4'), 'a.mp4');
  });
}
