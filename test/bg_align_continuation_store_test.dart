import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/actions/background_playback_actions.dart';
import 'package:iris/features/background_playback/model/enum/bg_apply_scope.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/file.dart';

FileItem _f(String key) =>
    FileItem(name: key, uri: 'file:///$key', path: [key]);

/// Session invariants of the alignment offset and the cross-file continuation
/// one-shot, plus the「仅当前」anchor surviving a candidate refresh.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late BackgroundPlaybackStore store;

  setUp(() async {
    store = BackgroundPlaybackStore();
    await store.initialized;
  });

  tearDown(() => store.dispose());

  test('refresh keeps the 仅当前 anchor (startWithCandidates replace)', () async {
    await store.enableWithQueue(
      [_f('a')],
      applyScope: BgApplyScope.currentOnly,
      anchorKey: 'a',
    );
    expect(store.state.scopeAnchorKey, 'a');

    await BackgroundPlaybackActions.startWithCandidates(
      [_f('a'), _f('b')],
      replace: true,
    );

    expect(store.state.scopeAnchorKey, 'a',
        reason: 'a refresh must not silently drop the run anchor');
  });

  test('setAlignOffset records and clears the authoritative offset', () async {
    await store.enableWithQueue([_f('a')]);
    expect(store.state.alignOffsetMs, isNull);

    store.setAlignOffset(4200);
    expect(store.state.alignOffsetMs, 4200);

    store.setAlignOffset(null);
    expect(store.state.alignOffsetMs, isNull);
  });

  test('requestBgContinuation bumps the seq and carries the cause', () async {
    await store.enableWithQueue([_f('a')]);
    final before = store.state.bgContinuationSeq;

    store.requestBgContinuation(fromAlign: true);
    expect(store.state.bgContinuationSeq, before + 1);
    expect(store.state.bgContinuationFromAlign, isTrue);

    store.requestBgContinuation(fromAlign: false);
    expect(store.state.bgContinuationSeq, before + 2);
    expect(store.state.bgContinuationFromAlign, isFalse);
  });

  test('disable clears the alignment offset', () async {
    await store.enableWithQueue([_f('a')]);
    store.setAlignOffset(1000);
    await store.disable();
    expect(store.state.alignOffsetMs, isNull);
  });
}
