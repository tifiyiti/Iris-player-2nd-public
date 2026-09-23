import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/queue/paged_scenario_media_data_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// A2: a merged virtual representative must be gated out of the scenario
/// queue's bulk (multi-select AND keyboard) remove/exclude targets.
///
/// Symptom: "Exclude selected" on a merged row degraded the group to its FIRST
/// segment, because `_excludeRule` builds a single-file rule out of the
/// representative's own identity — documented on
/// [EffectivePlaybackItem.virtualMerged] as "first segment's identity".
EffectivePlaybackItem _virtualRep(String path, String name) =>
    EffectivePlaybackItem(
      media: MediaNode.file(
        id: 'st1:$path',
        storageId: 'st1',
        path: path.split('/'),
        name: name,
        mediaType: MediaType.video,
      ),
      scenarioId: 's1',
      virtualMerged: true,
      virtualIndex: 0,
      occurrenceId: PlaybackOccurrenceId(
        storageId: 'st1',
        path: path,
        occurrenceIndex: 0,
      ),
    );

EffectivePlaybackItem _ordinary(String path, String name,
        {bool available = true}) =>
    EffectivePlaybackItem(
      media: MediaNode.file(
        id: 'st1:$path',
        storageId: 'st1',
        path: path.split('/'),
        name: name,
        mediaType: MediaType.video,
      ),
      scenarioId: 's1',
      available: available,
      virtualIndex: 0,
      occurrenceId: PlaybackOccurrenceId(
        storageId: 'st1',
        path: path,
        occurrenceIndex: 0,
      ),
    );

void main() {
  late AppDatabase db;
  late PagedScenarioMediaDataSource ds;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
    useAppStore();
    await useAppStore().initialized;
    final sys = await usePlaybackScenarioStore().ensureSystemPlayingScenario();
    ds = PagedScenarioMediaDataSource(scenarioId: sys.id);
  });

  tearDownAll(() async {
    ds.dispose();
    await db.close();
  });

  test('a merged representative is NOT selectable — the bulk-op gate', () {
    expect(
      ds.isItemSelectable(_virtualRep('A/1.mp4', '1.mp4')),
      isFalse,
      reason: 'the gate documented on virtualMerged ("non-selectable in '
          'scenario search") must also hold in the scenario queue, where the '
          'bulk actions can otherwise degrade the group to its first segment',
    );
  });

  test('ordinary rows stay selectable (no blanket ban)', () {
    expect(ds.isItemSelectable(_ordinary('A/9.mp4', '9.mp4')), isTrue);
  });

  // The keyboard bulk-removes build their target list straight from `_items`,
  // so they never consult the multi-select set and must run through the same
  // gate. `isSelectable: ds.isItemSelectable` keeps the gate and the UI in
  // lockstep; only the predicate differs per action.
  group('resolveKeyboardRemoveTargets', () {
    test('remove-UNSELECTED skips merged reps (they are never "selected")', () {
      final merged = _virtualRep('A/1.mp4', '1.mp4');
      final ordinary = _ordinary('A/9.mp4', '9.mp4');
      final selectedIds = {ds.getItemId(ordinary)};

      final targets = resolveKeyboardRemoveTargets(
        pageItems: [merged, ordinary],
        isSelectable: ds.isItemSelectable,
        predicate: (i) => !selectedIds.contains(ds.getItemId(i)),
      );

      expect(targets, isEmpty,
          reason: 'the only unselected row is the merged rep; excluding it '
              'would degrade the whole group to its first segment');
    });

    test('remove-SELECTED ignores a merged id (defensive)', () {
      final merged = _virtualRep('A/1.mp4', '1.mp4');
      final ordinary = _ordinary('A/9.mp4', '9.mp4');
      final selectedIds = {ds.getItemId(merged), ds.getItemId(ordinary)};

      final targets = resolveKeyboardRemoveTargets(
        pageItems: [merged, ordinary],
        isSelectable: ds.isItemSelectable,
        predicate: (i) => selectedIds.contains(ds.getItemId(i)),
      );

      expect(targets, [ordinary],
          reason: 'a merged id must never widen a bulk remove, even if some '
              'path manages to put it in the selection');
    });

    test('remove-MISSING still collects unavailable ordinary rows', () {
      final mergedMissing = _virtualRep('A/1.mp4', '1.mp4');
      final ordinaryMissing = _ordinary('A/9.mp4', '9.mp4', available: false);
      final ordinaryOk = _ordinary('A/8.mp4', '8.mp4');

      final targets = resolveKeyboardRemoveTargets(
        pageItems: [mergedMissing, ordinaryOk, ordinaryMissing],
        isSelectable: ds.isItemSelectable,
        predicate: (i) => !i.available,
      );

      expect(targets, [ordinaryMissing],
          reason: 'unavailable ordinary rows are the action\'s job; merged '
              'rows are out of scope even when unavailable');
    });
  });
}
