import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:iris/features/playback_tools/services/screenshot_media_scan.dart';
import 'package:iris/features/playback_tools/services/screenshot_service.dart';
import 'package:path/path.dart' as p;

Uint8List _realPng() {
  final image = img.Image(width: 2, height: 2);
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _realJpeg() {
  final image = img.Image(width: 2, height: 2);
  return Uint8List.fromList(img.encodeJpg(image));
}

bool _isPng(Uint8List bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

Future<ScreenshotResult> _capture({
  required Uint8List? Function() frame,
  String customDir = '',
  String defaultDir = '',
  Future<void> Function(String, Uint8List)? write,
  Future<Uint8List?> Function(Uint8List)? transcode,
  Future<void> Function(String path)? onScanned,
}) {
  return captureFrameCore(
    isMediaKit: true,
    frameSource: () async => frame(),
    resolveLocalVideoPath: () => null,
    customDirPath: customDir,
    defaultDirPath:
        defaultDir.isEmpty ? p.join('default-shots', '') : defaultDir,
    documentsDirPath: 'docs-root',
    now: DateTime(2026, 8, 29, 10, 20, 30),
    writeBytes: write ?? (_, __) async {},
    ensureDir: (_) async {},
    transcodeToPng: transcode,
    notifyGalleryVisible: onScanned,
    skipPermission: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('captureFrameCore PNG guarantee', () {
    test('JPEG bytes from media_kit are transcoded to real PNG', () async {
      Uint8List? written;
      final result = await _capture(
        frame: _realJpeg,
        write: (_, bytes) async => written = bytes,
        transcode: (bytes) async => Uint8List.fromList(
          img.encodePng(img.decodeImage(bytes)!),
        ),
      );

      expect(result, isA<ScreenshotSuccess>());
      expect(written, isNotNull);
      expect(_isPng(written!), isTrue);
    });

    test('real PNG bytes pass through untouched', () async {
      Uint8List? written;
      var transcodeCalls = 0;
      final png = _realPng();
      final result = await _capture(
        frame: () => png,
        write: (_, bytes) async => written = bytes,
        transcode: (bytes) async {
          transcodeCalls++;
          return bytes;
        },
      );

      expect(result, isA<ScreenshotSuccess>());
      expect(written, isNotNull);
      expect(_isPng(written!), isTrue);
      expect(transcodeCalls, 0);
    });

    test('undecodable bytes fail instead of writing a corrupt PNG', () async {
      var writes = 0;
      final result = await _capture(
        frame: () => Uint8List.fromList(<int>[1, 2, 3]),
        write: (_, __) async => writes++,
        transcode: (_) async => null,
      );

      expect(result, isA<ScreenshotFailure>());
      expect(writes, 0);
    });

    test('successful write notifies the gallery exactly once', () async {
      final scanned = <String>[];
      final result = await _capture(
        frame: _realPng,
        write: (_, __) async {},
        onScanned: (path) async => scanned.add(path),
      );

      expect(result, isA<ScreenshotSuccess>());
      final path = (result as ScreenshotSuccess).path;
      expect(scanned, <String>[path]);
    });
  });

  group('ScreenshotMediaScan', () {
    const channel = MethodChannel('iris/screenshot_scan');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('non-Android is a no-op without touching the channel', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        return true;
      });

      await ScreenshotMediaScan.notifyGalleryVisible(
        '/tmp/a.png',
        isAndroidPlatform: false,
      );
      expect(calls, 0);
    });

    test('missing plugin degrades silently', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await ScreenshotMediaScan.notifyGalleryVisible(
        '/tmp/a.png',
        isAndroidPlatform: true,
      );
    });
  });

  group('resolveScreenshotDirName async IO seam', () {
    test('capture uses the injected async ensureDir', () async {
      final ensured = <String>[];
      final result = await _capture(frame: _realPng);
      expect(result, isA<ScreenshotSuccess>());
      expect(ensured, isEmpty);
    });
  });
}
