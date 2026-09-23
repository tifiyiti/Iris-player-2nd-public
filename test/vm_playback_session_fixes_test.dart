import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/virtual_media/interaction/interfaces/buttons/vm_button_handler.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/features/virtual_media/vm_l10n.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart' show Repeat;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

import 'helpers/sqlite3_loader.dart';

/// H2 — user next/prev navigation must keep the play queue + autoplay (the
/// replacement feed overwrites both), never run the heavy `stop`.
/// H3 — `stopToFirst` must operate on the LIVE body: a cross-body feed that
/// settles during the awaited prelude must not make it clear/park the WRONG
/// body's progress.
/// H4 — Repeat.one on a multi-segment virtual item loops the WHOLE merged item
/// (wrap within it), not just the current physical segment.
VirtualMediaItem _item(String scope, List<String> names) => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: scope,
      rootPath: 'd',
      displayIndex: 1,
      displayName: scope,
      segments: [
        for (final n in names)
          VirtualSegment(
            mediaKey: 's:$n',
            storageId: 's',
            path: [n],
            name: n,
            parentPath: '',
            durationMs: 60000,
          ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late String scenarioId;

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    final sys = await usePlaybackScenarioStore().ensureSystemPlayingScenario();
    await usePlaybackScenarioStore().refreshScenarios();
    await usePlaybackScenarioStore().setActiveScenario(sys.id);
    scenarioId = sys.id;
    // Mirrors main.dart: the scenario playback path needs the provider
    // registered (registry.step resolves through it).
    PlaybackProviderRegistry.init();
    useAppStore();
    await useAppStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
  });

  setUp(() async {
    await usePlaybackScenarioStore().setRepeat(Repeat.none);
    useVmPlaybackStore().replace(const VmPlaybackState());
    await usePlayQueueStore().clear();
    await useAppStore().updateAutoPlay(false);
    await DbModule.virtualMediaRepo.clearAllVmProgress();
    await DbModule.virtualMediaRepo.clearAnchors();
  });

  Future<void> seed(String name) async {
    await DbModule.mediaNodesDao.deleteNode('s', name);
    await DbModule.mediaNodesDao.insertNode(
      MediaNode.file(
        id: 'f:s:$name',
        storageId: 's',
        path: [name],
        name: name,
        mediaType: MediaType.video,
      ),
    );
  }

  test('H2: next/prev navigation keeps the play queue and autoplay', () async {
    await seed('a0.mp4');
    final a = _item('rA|d|#1', ['a0.mp4']);
    final ctrl = VirtualMediaController.instance;
    await ctrl.startSession(queue: [a], queueIndex: 0);
    expect(ctrl.isActive, isTrue);
    expect(usePlayQueueStore().state.playQueue, hasLength(1));
    expect(useAppStore().state.autoPlay, isTrue);

    await VmButtonHandler.nextPrev(forward: true);

    // Lightweight deactivation: the next feed overwrites the single synthetic
    // entry, so an empty-queue flash + autoplay off/on toggle must NOT happen.
    expect(usePlayQueueStore().state.playQueue, hasLength(1));
    expect(useAppStore().state.autoPlay, isTrue);
    expect(ctrl.state.item, isNull);

    await ctrl.deactivateForNavigation();
  });

  test('H3: a cross-body feed during stop lands the stop on the LIVE body',
      () async {
    await seed('a0.mp4');
    await seed('a1.mp4');
    await seed('b0.mp4');
    final a = _item('rA|d|#1', ['a0.mp4', 'a1.mp4']);
    final b = _item('rB|d|#1', ['b0.mp4']);
    // Seed each body's scoped progress; only the body the stop actually
    // targets may be cleared.
    await DbModule.virtualMediaRepo.saveVmProgress(
      scenarioId: scenarioId,
      tagId: '',
      ruleId: 'rA',
      scopeKey: a.scopeKey,
      segmentKey: 's:a1.mp4',
      localPositionMs: 4321,
    );
    await DbModule.virtualMediaRepo.saveVmProgress(
      scenarioId: scenarioId,
      tagId: '',
      ruleId: 'rB',
      scopeKey: b.scopeKey,
      segmentKey: 's:b0.mp4',
      localPositionMs: 1234,
    );

    final ctrl = VirtualMediaController.instance;
    final fA = ctrl.startSession(queue: [a], queueIndex: 0);
    // B starts while A's feed is still in flight; B's body swap settles the
    // instant A's feed completes — BEFORE stopToFirst's continuation resumes.
    final fB = ctrl.startSession(queue: [b], queueIndex: 0);
    // The user hits stop; the pre-await body captured here is A.
    final fStop = ctrl.stopToFirst();

    await Future.wait([fA, fB, fStop]);

    final rowA = await DbModule.virtualMediaRepo.progressDao
        .get(scenarioId, '', a.scopeKey);
    expect(rowA, isNotNull);
    expect(rowA!.segmentKey, 's:a1.mp4');
    final rowB = await DbModule.virtualMediaRepo.progressDao
        .get(scenarioId, '', b.scopeKey);
    expect(rowB, isNull);

    await ctrl.deactivateForNavigation();
  });

  test('H4: Repeat.one loops the WHOLE multi-segment item', () async {
    await seed('a0.mp4');
    await seed('a1.mp4');
    final a = _item('rA|d|#1', ['a0.mp4', 'a1.mp4']);
    await usePlaybackScenarioStore().setRepeat(Repeat.one);

    final ctrl = VirtualMediaController.instance;
    await ctrl.startSession(queue: [a], queueIndex: 0);
    expect(ctrl.isActive, isTrue);
    expect(ctrl.state.segmentIndex, 0);

    expect(await ctrl.maybeHandleCompleted(), isTrue);
    expect(ctrl.state.segmentIndex, 1);

    // The last segment completes: wrap to the item head instead of handing the
    // completion to the backend's single-physical-file loop.
    expect(await ctrl.maybeHandleCompleted(), isTrue);
    expect(ctrl.state.segmentIndex, 0);
    expect(ctrl.state.item, isNotNull);

    await ctrl.deactivateForNavigation();
  });

  test('H1: a thrown feed lookup skips the broken segment (session survives)',
      () async {
    await seed('a0.mp4');
    await seed('a1.mp4');
    await seed('b0.mp4');
    final a = _item('rA|d|#1', ['a0.mp4', 'a1.mp4']);
    final b = _item('rB|d|#1', ['b0.mp4']);
    final ctrl = VirtualMediaController.instance;
    ctrl.debugNodeLoaderOverride = (storageId, path) async {
      if (path.last == 'a1.mp4') throw Exception('db down');
      return DbModule.mediaNodeRepo
          .getNodeByPath(storageId: storageId, path: path);
    };
    addTearDown(() => ctrl.debugNodeLoaderOverride = null);

    await ctrl.startSession(queue: [a, b], queueIndex: 0);
    expect(ctrl.isActive, isTrue);
    expect(ctrl.state.segmentIndex, 0);

    // Natural completion advances into the broken a1; the failed lookup must
    // route through handleSegmentError, which skips it and feeds B.
    expect(await ctrl.maybeHandleCompleted(), isTrue);
    await pumpEventQueue();
    await pumpEventQueue();

    expect(ctrl.isActive, isTrue,
        reason: 'recovery must not null the expected segment key');
    expect(ctrl.state.item?.scopeKey, b.scopeKey);
    expect(ctrl.state.segmentIndex, 0);

    await ctrl.deactivateForNavigation();
  });

  test('H5: stopToFirst lands paused — never flips autoPlay on', () async {
    await seed('a0.mp4');
    await seed('a1.mp4');
    final a = _item('rA|d|#1', ['a0.mp4', 'a1.mp4']);
    final ctrl = VirtualMediaController.instance;
    await ctrl.startSession(queue: [a], queueIndex: 0);
    expect(ctrl.isActive, isTrue);

    await useAppStore().updateAutoPlay(false);
    final seen = <bool>[];
    final sub = useAppStore().stream.listen((s) => seen.add(s.autoPlay));
    addTearDown(sub.cancel);

    await ctrl.stopToFirst();
    await pumpEventQueue();

    expect(seen, isNot(contains(true)),
        reason: 'the stop feed must open paused, not autoplay then stop');
    expect(useAppStore().state.autoPlay, isFalse);
    expect(ctrl.state.segmentIndex, 0);

    await ctrl.deactivateForNavigation();
  });

  test('H6: a broken LAST segment ends the session with a visible error',
      () async {
    await seed('a0.mp4');
    await seed('a1.mp4');
    final a = _item('rA|d|#1', ['a0.mp4', 'a1.mp4']);
    final ctrl = VirtualMediaController.instance;
    ctrl.debugNodeLoaderOverride = (storageId, path) async {
      if (path.last == 'a1.mp4') throw Exception('db down');
      return DbModule.mediaNodeRepo
          .getNodeByPath(storageId: storageId, path: path);
    };
    addTearDown(() => ctrl.debugNodeLoaderOverride = null);

    await ctrl.startSession(queue: [a], queueIndex: 0);
    expect(ctrl.isActive, isTrue);

    // Advance into the broken final segment; there is no feasible successor,
    // so the session ends. That must be VISIBLE (localized lastError), never a
    // silent stop.
    await ctrl.maybeHandleCompleted();
    await pumpEventQueue();
    await pumpEventQueue();

    expect(ctrl.state.item, isNull);
    expect(ctrl.state.lastError,
        vmLocalizations().vm_error_segment_unplayable);
  });
}
