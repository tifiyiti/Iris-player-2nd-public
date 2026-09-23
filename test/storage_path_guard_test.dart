import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/storage_path_guard.dart';

/// Regression lock for the over-broad traversal guard that silently broke
/// WebDAV/FTP listing: the app stores remote base paths WITH a leading slash
/// (`['/']` = root, `['/media']` = subfolder), so rejecting any segment that
/// contains `'/'` dropped every request before it was sent.
void main() {
  group('isUnsafeRemotePathSegment', () {
    test('the storage-relative root and subfolders are safe', () {
      expect(isUnsafeRemotePathSegment('/'), isFalse);
      expect(isUnsafeRemotePathSegment('/media'), isFalse);
      expect(isUnsafeRemotePathSegment('media'), isFalse);
      expect(isUnsafeRemotePathSegment('/a/b'), isFalse);
      expect(isUnsafeRemotePathSegment(''), isFalse);
      expect(isUnsafeRemotePathSegment('..hidden'), isFalse); // not a traversal
    });

    test('genuine traversal elements are rejected', () {
      expect(isUnsafeRemotePathSegment('.'), isTrue);
      expect(isUnsafeRemotePathSegment('..'), isTrue);
      expect(isUnsafeRemotePathSegment('../x'), isTrue);
      expect(isUnsafeRemotePathSegment('/..'), isTrue);
      expect(isUnsafeRemotePathSegment('/a/../b'), isTrue);
      expect(isUnsafeRemotePathSegment(r'a\b'), isTrue);
    });
  });

  group('hasUnsafeRemotePathSegment', () {
    test('the default WebDAV/FTP base paths pass', () {
      expect(hasUnsafeRemotePathSegment(<String>['/']), isFalse);
      expect(hasUnsafeRemotePathSegment(<String>['/always', 'anime']), isFalse);
    });

    test('a traversal element anywhere in the path fails', () {
      expect(hasUnsafeRemotePathSegment(<String>['/always', '..']), isTrue);
      expect(hasUnsafeRemotePathSegment(<String>['..']), isTrue);
    });

    test('an empty path is safe', () {
      expect(hasUnsafeRemotePathSegment(const <String>[]), isFalse);
    });
  });
}
