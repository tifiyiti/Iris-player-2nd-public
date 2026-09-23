import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/playback_tools/services/screenshot_paths.dart';

void main() {
  group('resolveScreenshotDirName', () {
    test('non-empty custom dir wins over the default', () {
      expect(
        resolveScreenshotDirName(
          customDir: '/custom/shots',
          defaultDir: '/default/shots',
        ),
        '/custom/shots',
      );
    });

    test('blank custom dir falls back to the default', () {
      expect(
        resolveScreenshotDirName(customDir: '  ', defaultDir: '/d'),
        '/d',
      );
    });
  });

  group('normalizeScreenshotInput', () {
    test('trims surrounding whitespace', () {
      expect(
        normalizeScreenshotInput('  /a/b  ', isAndroid: false),
        p.normalize('/a/b'),
      );
    });

    test('empty input means restore-default', () {
      expect(normalizeScreenshotInput('   ', isAndroid: false), '');
    });

    test('rejects traversal segments', () {
      expect(
        normalizeScreenshotInput('/a/../b', isAndroid: false),
        isNull,
      );
    });

    test('desktop rejects content:// URIs', () {
      expect(
        normalizeScreenshotInput(
          'content://com.android.externalstorage.documents/tree/primary%3ADownload',
          isAndroid: false,
        ),
        isNull,
      );
    });

    test('android keeps SAF tree URIs verbatim', () {
      const uri =
          'content://com.android.externalstorage.documents/tree/primary%3ADownload';
      expect(normalizeScreenshotInput(uri, isAndroid: true), uri);
    });

    test('android normalizes plain file paths', () {
      final sep = Platform.pathSeparator;
      expect(
        normalizeScreenshotInput('${sep}a${sep}b', isAndroid: true),
        '${sep}a${sep}b',
      );
    });
  });

  group('displayScreenshotDir', () {
    test('empty stored value renders the default label', () {
      expect(displayScreenshotDir(''), '默认目录');
    });

    test('SAF URI renders the human-readable tail', () {
      expect(
        displayScreenshotDir(
          'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FMovies',
        ),
        'Download/Movies',
      );
    });

    test('plain path renders verbatim', () {
      expect(displayScreenshotDir(p.normalize('/a/b')), p.normalize('/a/b'));
    });
  });

  group('defaultScreenshotSubdir', () {
    test('portable desktop resolves under the portable root', () {
      final sep = Platform.pathSeparator;
      expect(
        defaultScreenshotSubdir(
          isAndroid: false,
          isPortable: true,
          portableRoot: '${sep}exe${sep}userdata',
          picturesDir: '${sep}pic',
        ),
        '${sep}exe${sep}userdata${sep}screenshots',
      );
    });

    test('portable requested but no root degrades to the pictures dir', () {
      final sep = Platform.pathSeparator;
      expect(
        defaultScreenshotSubdir(
          isAndroid: false,
          isPortable: true,
          portableRoot: null,
          picturesDir: '${sep}pic',
        ),
        '${sep}pic${sep}IRIS',
      );
    });

    test('installed desktop resolves under the pictures dir', () {
      final sep = Platform.pathSeparator;
      expect(
        defaultScreenshotSubdir(
          isAndroid: false,
          isPortable: false,
          portableRoot: '${sep}exe${sep}userdata',
          picturesDir: '${sep}pic',
        ),
        '${sep}pic${sep}IRIS',
      );
    });

    test('android resolves the public IRIS screenshots dir', () {
      final sep = Platform.pathSeparator;
      expect(
        defaultScreenshotSubdir(
          isAndroid: true,
          isPortable: false,
          portableRoot: null,
          picturesDir: '${sep}storage${sep}Pictures',
        ),
        '${sep}storage${sep}Pictures${sep}IRIS Screenshots',
      );
    });
  });
}
