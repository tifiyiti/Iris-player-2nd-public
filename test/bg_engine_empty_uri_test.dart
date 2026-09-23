import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/app_state.dart' show PlayerBackend;

FileItem _emptyUri(String key) =>
    FileItem(name: key, uri: '', path: [key]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  group('BackgroundPlaybackEngine empty-uri guard (P0-3)', () {
    test('empty uri publishes file + error instead of silently stalling',
        () async {
      final engine = BackgroundPlaybackEngine(
        backend: PlayerBackend.mediaKit,
        attachNative: false,
      );
      addTearDown(engine.dispose);

      // Pretend the previous file is sounding; a refused open must halt it.
      engine.isPlaying = true;
      await engine.open(_emptyUri('ghost'), autoplay: true);

      // The queue already stepped past this entry: the engine must record
      // which file failed and why, so the host can report/advance instead of
      // replaying the previous file forever with no error.
      expect(engine.file?.name, 'ghost');
      expect(engine.isInitializing, isFalse);
      expect(engine.errorText, isNotNull);
      expect(engine.errorText, isNotEmpty);
      expect(engine.isPlaying, isFalse,
          reason: 'a refused open must stop the previous ghost audio');

      // The autoplay path re-invokes play() after the open resolves; with the
      // runtime unloaded this must stay a no-op instead of resuming the
      // previous (ghost) media.
      engine.play();
      await Future<void>.delayed(Duration.zero);
      expect(engine.isPlaying, isFalse,
          reason: 'play() must not resurrect the unloaded ghost runtime');
    });
  });
}
