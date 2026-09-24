import 'dart:io' show Directory, File, Platform;

import 'package:path/path.dart' as p;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/playback_tools/services/screenshot_paths.dart';
import 'package:iris/features/playback_tools/services/screenshot_service.dart';

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
    test('empty stored value renders the supplied default label', () {
      expect(
        displayScreenshotDir('', defaultLabel: 'Default', safFallbackLabel: 'X'),
        'Default',
      );
    });

    test('SAF URI renders the human-readable tail', () {
      expect(
        displayScreenshotDir(
          'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FMovies',
          defaultLabel: 'Default',
          safFallbackLabel: 'X',
        ),
        'Download/Movies',
      );
    });

    test('malformed SAF URI degrades to the fallback label', () {
      expect(
        displayScreenshotDir('content://x', defaultLabel: 'D', safFallbackLabel: 'X'),
        'X',
      );
    });

    test('plain path renders verbatim', () {
      expect(
        displayScreenshotDir(p.normalize('/a/b'),
            defaultLabel: 'D', safFallbackLabel: 'X'),
        p.normalize('/a/b'),
      );
    });
  });

  group('safTreeUriToPlainPath', () {
    // Expected values use `p.join` so the map is host-separator aware.
    test('primary volume maps under the primary root', () {
      expect(
        safTreeUriToPlainPath(
          'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FMovies',
          primaryRoot: p.join('/storage', 'emulated', '0'),
        ),
        p.join('/storage', 'emulated', '0', 'Download', 'Movies'),
      );
    });

    test('picker document shape (/tree/<id>/document/<id>) still maps', () {
      expect(
        safTreeUriToPlainPath(
          'content://com.android.externalstorage.documents/tree/primary%3ADownload/document/primary%3ADownload',
          primaryRoot: p.join('/storage', 'emulated', '0'),
        ),
        p.join('/storage', 'emulated', '0', 'Download'),
      );
    });

    test('primary volume with no root cannot be mapped', () {
      expect(
        safTreeUriToPlainPath(
          'content://com.android.externalstorage.documents/tree/primary%3ADownload',
          primaryRoot: null,
        ),
        isNull,
      );
    });

    test('non-primary volume maps to /storage/<volume>', () {
      expect(
        safTreeUriToPlainPath(
          'content://com.android.externalstorage.documents/tree/1234-5678%3AMovies',
          primaryRoot: p.join('/storage', 'emulated', '0'),
        ),
        p.join('/storage', '1234-5678', 'Movies'),
      );
    });

    test('non-SAF and unmappable shapes return null', () {
      expect(
        safTreeUriToPlainPath('/storage/emulated/0/Pictures', primaryRoot: '/x'),
        isNull,
      );
      expect(
        safTreeUriToPlainPath(
          'content://com.google.android.apps.docs.storage/tree/abc',
          primaryRoot: '/x',
        ),
        isNull,
      );
    });
  });

  group('isDirWritable', () {
    test('a real writable directory probes true and leaves no probe file',
        () async {
      final dir = await Directory.systemTemp.createTemp('iris_writable');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      expect(await isDirWritable(dir.path), isTrue);
      // The probe file must be cleaned up, so the directory stays empty.
      expect(await dir.list().toList(), isEmpty);
    });

    test('creates a missing directory and reports writable', () async {
      final base = await Directory.systemTemp.createTemp('iris_missing');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });
      final target = p.join(base.path, 'nested', 'shots');

      expect(await isDirWritable(target), isTrue);
      expect(await Directory(target).exists(), isTrue);
    });

    test('an unwritable path reports false without throwing', () async {
      // A path under an existing FILE can never become a directory.
      final file = File(
          p.join((await Directory.systemTemp.createTemp('iris_file')).path, 'f'));
      await file.writeAsString('');
      addTearDown(() async {
        if (await file.parent.exists()) {
          await file.parent.delete(recursive: true);
        }
      });

      expect(await isDirWritable(p.join(file.path, 'sub')), isFalse);
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
