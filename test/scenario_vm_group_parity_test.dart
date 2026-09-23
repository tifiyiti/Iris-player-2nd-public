import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider.dart';
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
import 'package:iris/store/use_storage_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Display/playback GROUP PARITY under non-default scenario order.
///
/// The queue overlay derives VM groups from the scenario's REAL sort / order /
/// duplicate policy. Playback must use the SAME derivation — the old
/// `collectEffectiveItems` path (base name-asc order + forced dedup) grouped
/// differently, so a merged row could feed a different segment set (wrong child
/// highlight) or degrade to ordinary single-file playback.
///
/// Fixture (one source `A`, rule covers `A` recursively, overlong exclusion ON,
/// `skipSingleSegment` OFF):
///   - `A/ep1.mp4` 60s, modifiedAt 3
///   - `A/zzz.mp4` 10min (overlong → never a candidate), modifiedAt 2
///   - `A/ep3.mp4` 60s, modifiedAt 1
///
/// The scenario streams modifiedAt desc → ep1, zzz, ep3, while the rule's own
/// candidates are ep1 + ep3, so they form ONE group regardless of where the
/// foreign file sits: a group's members are exempt from the external order, and
/// the merged row takes part in it as a whole.
///
/// Playback must open exactly that displayed body.
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
        maxItemCount: 10,
        useExcludeOverlong: true,
        maxSingleDurationMinutes: 1,
        skipSingleSegment: false,
        enabled: true,
      );

  Future<void> seedMedia(
    String path,
    int durationMs,
    DateTime modifiedAt,
  ) async {
    final parts = path.split('/');
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: path,
      storageId: 'st1',
      path: parts,
      parentPath: parts.length <= 1 ? null : parts.sublist(0, parts.length - 1).join('/'),
      name: parts.last,
      mediaType: MediaType.video,
      durationMs: durationMs,
      modifiedAt: modifiedAt,
    ));
  }

  PlaybackEntry entryOf(
      EffectivePlaybackItem item, ScenarioPlaybackProvider provider) {
    return PlaybackEntry(
      file: provider.fileOf(item.media),
      storageId: item.media.storageId,
      path: item.pathValue,
      key: item.mediaKey,
      available: item.available,
      occurrenceIndex: item.occurrenceId.occurrenceIndex,
    );
  }

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
    useAppStore();
    await useAppStore().initialized;
    useStorageStore();
    await useStorageStore().initialized;
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

  test('playback opens the SCENARIO-ORDER group the list displayed', () async {
    await DbModule.scenarioRepo.addSource(
      scenarioId: scenarioId,
      storageId: 'st1',
      path: 'A',
      recursive: true,
    );
    final scenario = (await DbModule.scenarioRepo.getScenario(scenarioId))!;
    await DbModule.scenarioRepo.updateScenario(scenario.copyWith(
      sortField: ScenarioSortField.modifiedAt,
      sortDirection: SortDirection.desc,
    ));
    await seedMedia('A/ep1.mp4', 60000, DateTime.utc(2026, 8, 3));
    await seedMedia('A/zzz.mp4', 600000, DateTime.utc(2026, 8, 2));
    await seedMedia('A/ep3.mp4', 60000, DateTime.utc(2026, 8, 1));
    await DbModule.virtualMediaRepo.saveRule(buildRule());
    VirtualMediaService.instance.invalidate();

    final store = usePlaybackScenarioStore();
    final page = await store.resolver.resolvePage(
      scenarioId: scenarioId,
      page: 0,
      pageSize: 50,
    );
    final rep = page.items.firstWhere((i) => i.mediaKey == 'st1:A/ep1.mp4');
    expect(rep.virtualMerged, isTrue,
        reason: 'rep must be a merged representative in the displayed list');
    expect(rep.vmChildren.map((c) => c.mediaKey).toList(),
        ['st1:A/ep1.mp4', 'st1:A/ep3.mp4'],
        reason: 'the group is rule-defined, so the interleaved zzz never '
            'splits it and never joins it');

    final provider = ScenarioPlaybackProvider(store: store);
    await provider.play(
      entryOf(rep, provider),
      targetFileKey: rep.vmChildren.first.mediaKey,
      targetOccurrenceIndex: rep.vmChildren.first.occurrenceIndex,
    );

    final ctrl = VirtualMediaController.instance;
    final session = ctrl.state.item;
    expect(session, isNotNull, reason: 'the merged row must start a VM session');
    expect(
      session!.segments.map((s) => s.mediaKey).toList(),
      rep.vmChildren.map((c) => c.mediaKey).toList(),
      reason: 'fed segment set must equal the displayed child list',
    );
    expect(ctrl.state.segmentIndex, 0);

    await ctrl.stop();
  });
}

