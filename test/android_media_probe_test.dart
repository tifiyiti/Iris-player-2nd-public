import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/probe/android_media_probe.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';

const MethodChannel _channel = MethodChannel('iris/media_probe');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = AndroidMediaProbeService();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('maps a full probe payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'probe');
      expect(call.arguments['target'], '/sdcard/a.mp4');
      return <String, Object?>{
        'durationMs': 42000,
        'width': 1080,
        'height': 1920,
      };
    });

    final r = await service.probeFile('/sdcard/a.mp4');
    expect(r.durationMs, 42000);
    expect(r.width, 1080);
    expect(r.height, 1920);
    expect(r.pixelCount, 1080 * 1920);
  });

  test('partial payload maps missing fields to null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async =>
            <String, Object?>{'durationMs': 1000});

    final r = await service.probeFile('content://x');
    expect(r.durationMs, 1000);
    expect(r.width, isNull);
    expect(r.height, isNull);
    expect(r.pixelCount, isNull);
  });

  test('null reply degrades to empty', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => null);

    final r = await service.probeFile('/x.mp4');
    expect(r, ProbeResult.empty);
  });

  test('PlatformException degrades to empty', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async =>
            throw PlatformException(code: 'probe_failed'));

    final r = await service.probeFile('/x.mp4');
    expect(r, ProbeResult.empty);
  });

  test('MissingPluginException degrades to empty', () async {
    final r = await service.probeFile('/x.mp4');
    expect(r, ProbeResult.empty);
  });
}
