import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/actions/scenario_resolved_actions.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/scenario_playback/playback/scenario_playback_provider.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/features/virtual_media/service/vm_overlay_service.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Cold-start resume of a VM session must honour the PERSISTED occurrence.
///
/// The scenario allows duplicates, so `A/sub/dup.mp4` enters the effective
/// stream twice (occurrence 0/1) and both copies merge into ONE virtual body.
/// Parking the session on occurrence 1 and resuming must re-open
/// `segmentIndex == 1`; the resume path used to drop `PlaybackEntry`'s
/// occurrence, so the bookmark collapsed to the first copy
/// (`indexOfSegmentKey` with no occurrence).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;
  late String scenarioId;

  VirtualMediaRule buildRule() => VirtualMediaRule(
        id: 'r1',
        name: 'R',
        matchMode: VmMatchMode.specifiedDirRecursive,
        paths: const ['A'],
        boundary: VmBoundaryMode.ignoreDirs,
        useDurationCap: false,
        useCountCap: true,
        maxItemCount: 100,
        skipSingleSegment: false,
        enabled: true,
      );

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
    useAppStore();
    await useAppStore().initialized;
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    for (final t in const [
      'media_nodes',
      'scenario',
      'scenario_sources',
      'scenario_explicit_items',
      'scenario_excludes',
      'scenario_state',
      'vm_rules',
      'virtual_media_states',
      'vm_progress',
    ]) {
      await db.customStatement('DELETE FROM $t');
    }
    useAppStore().set(useAppStore().state.copyWith(
          useMetadataSettings: true,
          useLegacyStoragePersistence: false,
          useScenarioDrivenPlayback: true,
        ));
    VirtualMediaService.instance.invalidate();
    useVmPlaybackStore().replace(const VmPlaybackState());
    final sys = await usePlaybackScenarioStore().ensureSystemPlayingScenario();
    await usePlaybackScenarioStore().setActiveScenario(sys.id);
    scenarioId = sys.id;
  });

  tearDown(() async {
    useVmPlaybackStore().replace(const VmPlaybackState());
  });

  test('resume opens the PERSISTED duplicate occurrence, not the first copy',
      () async {
    // Two overlapping recursive sources expose `A/sub/dup.mp4` twice, creating
    // occurrences 0 and 1 of the same physical file (allowDuplicate default).
    await DbModule.scenarioRepo.addSource(
      scenarioId: scenarioId,
      storageId: 'st1',
      path: 'A',
      recursive: true,
    );
    await DbModule.scenarioRepo.addSource(
      scenarioId: scenarioId,
      storageId: 'st1',
      path: 'A/sub',
      recursive: true,
    );
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'A/sub/dup.mp4',
      storageId: 'st1',
      path: const ['A', 'sub', 'dup.mp4'],
      parentPath: 'A/sub',
      name: 'dup.mp4',
      mediaType: MediaType.video,
      durationMs: 60000,
    ));
    await DbModule.virtualMediaRepo.saveRule(buildRule());
    VirtualMediaService.instance.invalidate();

    final store = usePlaybackScenarioStore();
    // Park the session on the SECOND occurrence of the duplicated file.
    await store.setCurrentItem(
      occurrence: const PlaybackOccurrenceId(
        storageId: 'st1',
        path: 'A/sub/dup.mp4',
        occurrenceIndex: 1,
      ),
    );

    // Force the resume through `current()` (which preserves the occurrence)
    // instead of the located-index path that re-derives the overlay rep.
    await ScenarioResolvedActions.resumeScenarioPlayback(
      store: store,
      provider: _OccurrenceResumeProvider(store),
    );

    final ctrl = VirtualMediaController.instance;
    final session = ctrl.state.item;
    expect(session, isNotNull, reason: 'the merged row must start a VM session');
    expect(session!.segments, hasLength(2),
        reason: 'both duplicate copies must live in one merged body');
    expect(ctrl.state.segmentIndex, 1,
        reason: 'resume must land on occurrence 1, not collapse to the first');

    await ctrl.stop();
  });
}

/// Resumes via the `current()` fallback so the persisted occurrence index is
/// carried into [PlaybackEntry] (the located-index path maps to the overlay
/// representative, which only keeps the first copy's occurrence).
class _OccurrenceResumeProvider extends ScenarioPlaybackProvider {
  _OccurrenceResumeProvider(PlaybackScenarioStore store) : super(store: store);

  @override
  Future<int?> establishCurrentPosition() async => null;
}
