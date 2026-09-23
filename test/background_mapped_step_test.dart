import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/file.dart';

FileItem _f(String key) => FileItem(name: key, uri: 'file:///$key', path: [key]);

/// B4 regression: while a mapped playMedia segment owns the audible output,
/// a user 副音 step/jump stays legal — it swaps the 副音 track only (the
/// foreground is never touched), abandons the mapped override with the abort
/// latch (so the segment exit does NOT step a second time), and advances the
/// natural queue exactly once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  group('user step/jump during a mapped segment', () {
    late BackgroundPlaybackStore store;

    setUp(() async {
      store = BackgroundPlaybackStore();
      await store.initialized;
      await store.enableWithQueue([_f('a'), _f('b'), _f('c')]);
      // Deterministic order for step assertions.
      store.set(store.state
          .copyWith(shuffle: false, queue: [_f('a'), _f('b'), _f('c')]));
    });

    tearDown(() => store.dispose());

    test('step abandons the mapped override and advances exactly once',
        () async {
      await store.enterMappedSegment(_f('x'), targetMs: 0, rate: 1.0);
      expect(store.state.mappedFile, isNotNull);
      final seqBefore = store.state.bgStepSeq;

      final moved = await store.step(forward: true);

      expect(moved, isTrue);
      expect(store.state.currentIndex, 1);
      expect(store.state.mappedFile, isNull);
      expect(store.state.mappedRate, isNull);
      // Abort latch: the MappingScope sees it and skips its own exit step.
      expect(store.state.mappedExitAdvanced, isTrue);
      expect(store.state.bgStepSeq, seqBefore + 1);
    });

    test('a second step moves one more (no hidden double advance)', () async {
      await store.enterMappedSegment(_f('x'), targetMs: 0, rate: 1.0);
      await store.step(forward: true);
      await store.step(forward: true);
      expect(store.state.currentIndex, 2);
    });

    test('jumpTo lands directly without an extra advance', () async {
      await store.enterMappedSegment(_f('x'), targetMs: 0, rate: 1.0);
      final seqBefore = store.state.bgStepSeq;

      await store.jumpTo(2);

      expect(store.state.currentIndex, 2);
      expect(store.state.mappedFile, isNull);
      expect(store.state.mappedExitAdvanced, isTrue);
      expect(store.state.bgStepSeq, seqBefore + 1);
    });

    test('step without a mapped segment behaves as before', () async {
      final moved = await store.step(forward: true);
      expect(moved, isTrue);
      expect(store.state.currentIndex, 1);
      expect(store.state.mappedFile, isNull);
      expect(store.state.mappedExitAdvanced, isFalse);
    });
  });
}
