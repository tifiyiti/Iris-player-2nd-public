import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:iris/features/playback_tools/services/screenshot_service.dart';
import 'package:path/path.dart' as p;

void main() {
  final sep = Platform.pathSeparator;
  final now = DateTime(2026, 8, 29, 10, 20, 30);
  // Real PNG bytes: the capture core guarantees PNG content before writing,
  // so the fallback-chain tests below must feed it decodable frames.
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 2, height: 2)),
  );
  const docs = 'docs-root';
  final defDir = p.join('default-shots', '');

  Future<ScreenshotResult> capture({
    required Uint8List? Function() frame,
    String? Function()? localPath,
    String customDir = '',
    String defaultDir = '',
    required Future<void> Function(String, Uint8List) write,
  }) {
    return captureFrameCore(
      isMediaKit: true,
      frameSource: () async => frame(),
      resolveLocalVideoPath: localPath ?? () => null,
      customDirPath: customDir,
      defaultDirPath: defaultDir.isEmpty ? defDir : defaultDir,
      documentsDirPath: docs,
      now: now,
      writeBytes: write,
      ensureDir: (_) async {},
      notifyGalleryVisible: (_) async {},
      skipPermission: true,
    );
  }

  group('captureFrameCore', () {
    test('non-mediaKit backend → unsupported with backend name', () async {
      final result = await captureFrameCore(
        isMediaKit: false,
        frameSource: () async => bytes,
        resolveLocalVideoPath: () => null,
        customDirPath: '',
        defaultDirPath: defDir,
        documentsDirPath: docs,
        now: now,
        writeBytes: (_, __) async {},
        skipPermission: true,
      );

      expect(result, isA<ScreenshotUnsupported>());
      expect((result as ScreenshotUnsupported).backend, 'fvp');
    });

    test('null frame → failure', () async {
      final result = await capture(frame: () => null, write: (_, __) async {});

      expect(result, isA<ScreenshotFailure>());
    });

    test('empty frame → failure', () async {
      final result =
          await capture(frame: () => Uint8List(0), write: (_, __) async {});

      expect(result, isA<ScreenshotFailure>());
    });

    test('frame source throws → failure with reason', () async {
      final result = await capture(
        frame: () => throw StateError('mpv boom'),
        write: (_, __) async {},
      );

      expect(result, isA<ScreenshotFailure>());
      expect((result as ScreenshotFailure).reason, contains('mpv boom'));
    });

    test('local video + write ok → success in the default dir', () async {
      final written = <String>[];
      final result = await capture(
        frame: () => bytes,
        localPath: () => '${sep}movies${sep}BBB.mp4',
        write: (path, _) async => written.add(path),
      );

      expect(result, isA<ScreenshotSuccess>());
      expect(
        (result as ScreenshotSuccess).path,
        p.join(defDir, 'BBB_102030.png'),
      );
      expect(written, hasLength(1));
    });

    test('custom dir wins over the default', () async {
      final written = <String>[];
      final result = await capture(
        frame: () => bytes,
        localPath: () => '${sep}movies${sep}BBB.mp4',
        customDir: p.join('my', 'shots'),
        write: (path, _) async => written.add(path),
      );

      expect(result, isA<ScreenshotSuccess>());
      expect(
        (result as ScreenshotSuccess).path,
        p.join(p.join('my', 'shots'), 'BBB_102030.png'),
      );
      expect(written, hasLength(1));
    });

    test('custom write fails → default still succeeds', () async {
      var calls = 0;
      late final String successPath;
      final result = await capture(
        frame: () => bytes,
        customDir: p.join('pulled', 'usb'),
        write: (path, _) async {
          calls++;
          if (calls == 1) throw StateError('drive gone');
          successPath = path;
        },
      );

      expect(result, isA<ScreenshotSuccess>());
      expect(successPath, p.join(defDir, 'iris_102030.png'));
    });

    test('default write fails → documents fallback still succeeds', () async {
      var calls = 0;
      late final String fallbackPath;
      final result = await capture(
        frame: () => bytes,
        defaultDir: p.join('denied', 'dir'),
        write: (path, _) async {
          calls++;
          if (calls == 1) throw StateError('scoped storage denied');
          fallbackPath = path;
        },
      );

      expect(result, isA<ScreenshotSuccess>());
      expect(fallbackPath, 'docs-root${sep}iris_102030.png');
    });

    test('SAF custom dir is skipped, never passed to File', () async {
      final written = <String>[];
      final result = await capture(
        frame: () => bytes,
        customDir:
            'content://com.android.externalstorage.documents/tree/primary%3ADownload',
        write: (path, _) async => written.add(path),
      );

      expect(result, isA<ScreenshotSuccess>());
      expect(written, hasLength(1));
      expect(written.single, startsWith(defDir));
      expect(written.single, isNot(contains('content://')));
    });

    test('every write fails → failure', () async {
      final result = await capture(
        frame: () => bytes,
        localPath: () => '${sep}movies${sep}BBB.mp4',
        write: (_, __) async => throw StateError('disk full'),
      );

      expect(result, isA<ScreenshotFailure>());
      expect((result as ScreenshotFailure).reason, contains('disk full'));
    });
  });
}
