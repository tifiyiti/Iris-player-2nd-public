import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/file.dart';

FileItem _f(String key) => FileItem(name: key, uri: 'file:///$key', path: [key]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  group('mapping store commands', () {
    late BackgroundPlaybackStore store;

    setUp(() async {
      store = BackgroundPlaybackStore();
      await store.initialized;
      await store.enableWithQueue([_f('a'), _f('b')]);
      // Deterministic order for step assertions.
      store.set(store.state.copyWith(shuffle: false, queue: [_f('a'), _f('b')]));
    });

    tearDown(() => store.dispose());

    test('enterMappedSegment drives mappedFile, seek seq, rate and autoplay',
        () async {
      await store.enterMappedSegment(_f('b'), targetMs: 1200, rate: 0.75);
      expect(store.state.mappedFile, isNotNull);
      expect(store.state.bgAutoPlay, isTrue);
      expect(store.state.mappedRate, 0.75);
      expect(store.state.mappedSeekSeq, 1);
      expect(store.state.mappedSeekTargetMs, 1200);
      expect(store.state.mappedExitAdvanced, isFalse);
    });

    test('silenceHold pauses but keeps the natural index; resume restores', () async {
      final idxBefore = store.state.currentIndex;
      await store.silenceHold();
      expect(store.state.mappedSilenceOn, isTrue);
      expect(store.state.bgAutoPlay, isFalse);
      expect(store.state.currentIndex, idxBefore);
      await store.resumeNatural();
      expect(store.state.mappedSilenceOn, isFalse);
      expect(store.state.bgAutoPlay, isTrue);
    });

    test('exitMappedNatural advances once and clears the mapped override',
        () async {
      await store.enterMappedSegment(_f('a'), targetMs: 0, rate: 1.0);
      final naturalIndexBefore = store.state.currentIndex;
      await store.exitMappedNatural();
      expect(store.state.mappedFile, isNull);
      expect(store.state.mappedRate, isNull);
      expect(store.state.mappedExitAdvanced, isTrue);
      expect(store.state.bgAutoPlay, isTrue);
      // Natural index advanced past the pre-mapping position.
      expect(store.state.currentIndex, naturalIndexBefore + 1);
    });

    test('setMappingEnabled(false) exits an active mapped segment', () async {
      await store.enterMappedSegment(_f('a'), targetMs: 0, rate: 1.0);
      await store.setMappingEnabled(false);
      expect(store.state.mappingEnabled, isFalse);
      expect(store.state.mappedFile, isNull);
    });

    test('disable clears every mapping session field', () async {
      await store.enterMappedSegment(_f('b'), targetMs: 900, rate: 1.2);
      await store.disable();
      final s = store.state;
      expect(s.mappedFile, isNull);
      expect(s.mappedRate, isNull);
      expect(s.mappedSilenceOn, isFalse);
      expect(s.mappedExitAdvanced, isFalse);
      expect(s.enabled, isFalse);
      expect(s.controlTarget, ControlTarget.foreground);
    });
  });
}
