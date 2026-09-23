import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/queue/paged_scenario_media_data_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// The scenario queue's in-place refresh contract: a completed scenario-source
/// refresh bumps `sourceScanRevision` and the open queue re-fetches page 0 —
/// while a plain `playbackVersion` bump (whose call sites already fetch
/// explicitly) does NOT trigger a second re-fetch from the listener.
void main() {
  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
    useAppStore();
    await useAppStore().initialized;
  });

  tearDownAll(() => db.close());

  Future<String> workspaceWith(String folder, String name) async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.clearSources(sys.id);
    await DbModule.scenarioRepo.addSource(
      scenarioId: sys.id,
      storageId: 'st1',
      path: folder,
      recursive: true,
    );
    try {
      await DbModule.mediaNodesDao.insertNode(MediaNode.file(
        id: 'f:st1:$folder/$name',
        storageId: 'st1',
        path: [folder, name],
        name: name,
        mediaType: MediaType.video,
      ));
    } catch (_) {}
    return sys.id;
  }

  test('sourceScanRevision bump triggers an in-place page re-fetch', () async {
    final id = await workspaceWith('q1', 'a.mp4');
    final ds = PagedScenarioMediaDataSource(scenarioId: id);
    // Let the constructor's initial fetch settle.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final before = ds.totalItems;

    // A newly scanned file appears, then the refresh signals completion.
    try {
      await DbModule.mediaNodesDao.insertNode(MediaNode.file(
        id: 'f:st1:q1/b.mp4',
        storageId: 'st1',
        path: ['q1', 'b.mp4'],
        name: 'b.mp4',
        mediaType: MediaType.video,
      ));
    } catch (_) {}

    await usePlaybackScenarioStore().bumpSourceScanRevision();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(ds.totalItems, greaterThan(before),
        reason: 'the queue must re-fetch after a source scan revision bump');
    ds.dispose();
  });

  test('playbackVersion alone does not re-fetch from the listener', () async {
    final id = await workspaceWith('q2', 'a.mp4');
    final ds = PagedScenarioMediaDataSource(scenarioId: id);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    var notified = 0;
    ds.addListener(() => notified++);

    await usePlaybackScenarioStore().bumpPlaybackVersion();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notified, 0,
        reason: 'a plain playbackVersion bump must not double-resolve');
    ds.dispose();
  });
}
