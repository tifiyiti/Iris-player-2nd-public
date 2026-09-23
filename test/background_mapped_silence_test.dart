import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/file.dart';

FileItem _f(String key) => FileItem(name: key, uri: 'file:///$key', path: [key]);

/// B5 regression: crossing from a playMedia segment into a `silence` segment
/// must pause in place — the natural queue index stays put. Advancing belongs
/// to the play → gap path ([exitMappedNatural]) only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  group('leaving a mapped segment for silence', () {
    late BackgroundPlaybackStore store;

    setUp(() async {
      store = BackgroundPlaybackStore();
      await store.initialized;
      await store.enableWithQueue([_f('a'), _f('b'), _f('c')]);
      store.set(store.state
          .copyWith(shuffle: false, queue: [_f('a'), _f('b'), _f('c')]));
    });

    tearDown(() => store.dispose());

    test('exitMappedInPlace drops the override without advancing', () async {
      await store.enterMappedSegment(_f('x'), targetMs: 0, rate: 1.0);
      final idx = store.state.currentIndex;

      await store.exitMappedInPlace();

      expect(store.state.currentIndex, idx);
      expect(store.state.mappedFile, isNull);
      expect(store.state.mappedRate, isNull);
      // Abort latch: the scope will not re-enter — or step on — exit.
      expect(store.state.mappedExitAdvanced, isTrue);
      // Transport untouched: the silence driver pauses via silenceHold.
      expect(store.state.bgAutoPlay, isTrue);
    });

    test('silence then resume keeps the same natural file', () async {
      await store.enterMappedSegment(_f('x'), targetMs: 0, rate: 1.0);
      final idx = store.state.currentIndex;

      await store.exitMappedInPlace();
      await store.silenceHold();
      expect(store.state.mappedSilenceOn, isTrue);
      expect(store.state.bgAutoPlay, isFalse);
      await store.resumeNatural();

      expect(store.state.currentIndex, idx);
      expect(store.state.mappedSilenceOn, isFalse);
      expect(store.state.bgAutoPlay, isTrue);
    });
  });
}
